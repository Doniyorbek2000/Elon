import { Injectable, Logger } from '@nestjs/common';
import {
  ActivationSource,
  ActivationStatus,
  JobStatus,
  ListingStatus,
  NotificationType,
  Placement,
  Prisma,
  PromotionActivation,
  PromotionKind,
  PromotionProduct,
  PromotionTarget,
  ProviderStatus,
} from '@prisma/client';

import { AppError } from '../../common/errors';
import { Badge, sortBadges } from '../../common/badges';
import { PrismaService } from '../../infra/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { MonetizationConfig } from './config.service';

type Tx = Prisma.TransactionClient;

/** Ranking tier granted while a kind is active (0 = badge/placement only). */
const TIER: Partial<Record<PromotionKind, number>> = {
  LISTING_VIP: 2,
  LISTING_TOP: 1,
  JOB_TOP: 1,
  PROVIDER_TOP: 1,
};

const BADGE: Partial<Record<PromotionKind, Badge>> = {
  LISTING_VIP: 'vip',
  LISTING_TOP: 'top',
  JOB_TOP: 'top',
  PROVIDER_TOP: 'top',
  LISTING_FEATURED: 'featured',
  JOB_FEATURED: 'featured',
  PROVIDER_FEATURED: 'featured',
  JOB_URGENT: 'urgent',
};

const KIND_TARGET: Record<PromotionKind, PromotionTarget> = {
  LISTING_TOP: 'LISTING',
  LISTING_VIP: 'LISTING',
  LISTING_BUMP: 'LISTING',
  LISTING_FEATURED: 'LISTING',
  JOB_TOP: 'JOB',
  JOB_FEATURED: 'JOB',
  JOB_URGENT: 'JOB',
  PROVIDER_TOP: 'PROVIDER',
  PROVIDER_FEATURED: 'PROVIDER',
  AD_CAMPAIGN: 'BUSINESS',
};

export interface TargetInfo {
  ownerId: string;
  regionId: string | null;
  categoryId: string | null;
  eligible: boolean;
  lastBumpAt?: Date | null;
}

/**
 * Promotion lifecycle. PromotionActivation rows are the source of truth; the
 * boostTier/boostUntil/rankedAt columns on content are a ranking cache that
 * is recomputed inside the same transaction as every change (and by the
 * worker on expiry). Queries additionally check `boostUntil > now()`, so an
 * expired promotion stops ranking even before the worker runs.
 */
@Injectable()
export class PromotionService {
  private readonly logger = new Logger(PromotionService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: MonetizationConfig,
    private readonly notifications: NotificationsService,
  ) {}

  static targetOf(kind: PromotionKind): PromotionTarget {
    return KIND_TARGET[kind];
  }

  /** Owner + eligibility of the thing being promoted (ownership checked by callers). */
  async targetInfo(target: PromotionTarget, targetId: string, db: Tx | PrismaService = this.prisma): Promise<TargetInfo | null> {
    switch (target) {
      case 'LISTING': {
        const l = await db.listing.findFirst({
          where: { id: targetId, deletedAt: null },
          select: { sellerId: true, regionId: true, categoryId: true, status: true, rankedAt: true, publishedAt: true },
        });
        if (!l) return null;
        const lastBump = await db.promotionActivation.findFirst({
          where: { target: 'LISTING', targetId, kind: 'LISTING_BUMP' },
          orderBy: { startsAt: 'desc' },
          select: { startsAt: true },
        });
        return {
          ownerId: l.sellerId,
          regionId: l.regionId,
          categoryId: l.categoryId,
          eligible: l.status === ListingStatus.ACTIVE,
          lastBumpAt: lastBump?.startsAt ?? null,
        };
      }
      case 'JOB': {
        const j = await db.job.findFirst({
          where: { id: targetId, deletedAt: null },
          select: { employerId: true, regionId: true, status: true },
        });
        return j ? { ownerId: j.employerId, regionId: j.regionId, categoryId: null, eligible: j.status === JobStatus.ACTIVE } : null;
      }
      case 'PROVIDER': {
        const p = await db.serviceProvider.findFirst({
          where: { id: targetId, deletedAt: null },
          select: { userId: true, regionId: true, status: true, categories: { select: { categoryId: true }, take: 1 } },
        });
        return p
          ? {
              ownerId: p.userId,
              regionId: p.regionId,
              categoryId: p.categories[0]?.categoryId ?? null,
              eligible: p.status === ProviderStatus.ACTIVE,
            }
          : null;
      }
      case 'BUSINESS':
        return null;
    }
  }

  /** Bump abuse guard: one bump per cooldown window per listing. */
  async assertBumpAllowed(info: TargetInfo): Promise<void> {
    const { bumpCooldownHours } = await this.config.setting('ranking');
    if (info.lastBumpAt && Date.now() - info.lastBumpAt.getTime() < bumpCooldownHours * 3600_000) {
      throw AppError.invalidState(`A listing can be bumped once every ${bumpCooldownHours} hours`);
    }
  }

  /**
   * Creates the activation (inside the caller's transaction). Buying the same
   * kind again extends it: the new window starts when the current one ends.
   */
  async activate(
    tx: Tx,
    input: {
      product: PromotionProduct;
      targetId: string;
      info: TargetInfo;
      source: ActivationSource;
      purchaseId?: string;
      now?: Date;
    },
  ): Promise<PromotionActivation> {
    const now = input.now ?? new Date();
    const { product, targetId, info } = input;
    if (product.kind === 'LISTING_BUMP') {
      const activation = await tx.promotionActivation.create({
        data: {
          productId: product.id,
          kind: product.kind,
          target: product.target,
          targetId,
          ownerId: info.ownerId,
          purchaseId: input.purchaseId,
          source: input.source,
          status: ActivationStatus.EXPIRED, // instant effect, recorded for history/analytics
          startsAt: now,
          expiresAt: now,
        },
      });
      // Dedicated ranking timestamp; publishedAt/createdAt stay untouched.
      await tx.listing.update({ where: { id: targetId }, data: { rankedAt: now } });
      return activation;
    }
    if (!product.durationDays) throw new Error(`Product ${product.id} has no duration`);
    const latest = await tx.promotionActivation.findFirst({
      where: {
        target: product.target,
        targetId,
        kind: product.kind,
        status: { in: [ActivationStatus.ACTIVE, ActivationStatus.SCHEDULED] },
        expiresAt: { gt: now },
      },
      orderBy: { expiresAt: 'desc' },
      select: { expiresAt: true },
    });
    const startsAt = latest?.expiresAt && latest.expiresAt > now ? latest.expiresAt : now;
    const expiresAt = new Date(startsAt.getTime() + product.durationDays * 24 * 3600_000);
    const activation = await tx.promotionActivation.create({
      data: {
        productId: product.id,
        kind: product.kind,
        target: product.target,
        targetId,
        ownerId: info.ownerId,
        purchaseId: input.purchaseId,
        source: input.source,
        placement: product.placement,
        regionId: product.placement === Placement.CATEGORY ? null : info.regionId,
        categoryId: product.placement === Placement.CATEGORY ? info.categoryId : null,
        status: startsAt > now ? ActivationStatus.SCHEDULED : ActivationStatus.ACTIVE,
        startsAt,
        expiresAt,
      },
    });
    await this.recompute(tx, product.target, targetId, now);
    return activation;
  }

  /** Rebuilds the ranking cache of one item from its live activations. */
  async recompute(tx: Tx | PrismaService, target: PromotionTarget, targetId: string, now = new Date()): Promise<void> {
    const live = await tx.promotionActivation.findMany({
      where: {
        target,
        targetId,
        status: { in: [ActivationStatus.ACTIVE, ActivationStatus.SCHEDULED] },
        startsAt: { lte: now },
        expiresAt: { gt: now },
      },
      select: { kind: true, expiresAt: true },
    });
    let tier = 0;
    let until: Date | null = null;
    for (const a of live) {
      const t = TIER[a.kind] ?? 0;
      if (t > tier || (t === tier && t > 0 && until && a.expiresAt && a.expiresAt > until)) {
        tier = t;
        until = a.expiresAt;
      }
    }
    const data = { boostTier: tier, boostUntil: tier > 0 ? until : null };
    if (target === 'LISTING') await tx.listing.update({ where: { id: targetId }, data });
    if (target === 'JOB') await tx.job.update({ where: { id: targetId }, data });
    if (target === 'PROVIDER') await tx.serviceProvider.update({ where: { id: targetId }, data });
  }

  /** Stops an activation (refund, moderation, target removed). */
  async cancel(tx: Tx, activationId: string): Promise<void> {
    const activation = await tx.promotionActivation.update({
      where: { id: activationId },
      data: { status: ActivationStatus.CANCELLED },
    });
    if (activation.target !== 'BUSINESS') await this.recompute(tx, activation.target, activation.targetId);
  }

  /** Paid badges of a page of items, one indexed query (no N+1). */
  async badges(target: PromotionTarget, ids: string[], now = new Date()): Promise<Map<string, Badge[]>> {
    const result = new Map<string, Badge[]>();
    if (ids.length === 0) return result;
    const rows = await this.prisma.promotionActivation.findMany({
      where: {
        target,
        targetId: { in: ids },
        status: { in: [ActivationStatus.ACTIVE, ActivationStatus.SCHEDULED] },
        startsAt: { lte: now },
        expiresAt: { gt: now },
      },
      select: { targetId: true, kind: true },
    });
    const grouped = new Map<string, Badge[]>();
    for (const row of rows) {
      const badge = BADGE[row.kind];
      if (badge) grouped.set(row.targetId, [...(grouped.get(row.targetId) ?? []), badge]);
    }
    for (const id of ids) result.set(id, sortBadges(grouped.get(id) ?? []));
    return result;
  }

  /**
   * Ids featured in a placement with explicit scope rules:
   * HOME/REGION → activation region must equal the browsing region;
   * CATEGORY → activation category must be inside the requested subtree.
   * Rotation is fair and stable within an hour.
   */
  async featuredIds(
    kind: PromotionKind,
    placement: Placement,
    scope: { regionId?: string; categoryIds?: string[] },
    limit: number,
  ): Promise<string[]> {
    const now = new Date();
    const where: Prisma.Sql[] = [
      Prisma.sql`a."kind" = ${kind}::"PromotionKind"`,
      Prisma.sql`a."placement" = ${placement}::"Placement"`,
      Prisma.sql`a."status" IN ('ACTIVE', 'SCHEDULED')`,
      Prisma.sql`a."startsAt" <= ${now}`,
      Prisma.sql`a."expiresAt" > ${now}`,
    ];
    if (placement === Placement.CATEGORY) {
      if (!scope.categoryIds?.length) return [];
      where.push(Prisma.sql`a."categoryId" = ANY(${scope.categoryIds})`);
    } else if (scope.regionId) {
      where.push(Prisma.sql`a."regionId" = ${scope.regionId}`);
    }
    const rows = await this.prisma.$queryRaw<Array<{ id: string }>>`
      SELECT DISTINCT a."targetId" AS id
      FROM "PromotionActivation" a
      WHERE ${Prisma.join(where, ' AND ')}
      LIMIT 200`;
    return rotate(rows)
      .map((r) => r.id)
      .slice(0, limit);
  }

  // ─────────────────────────────────────────────────────────── worker

  /** Idempotent sweep: start scheduled, expire ended, refresh caches, notify. */
  async sweep(now = new Date()): Promise<{ started: number; expired: number; notified: number }> {
    const due = await this.prisma.promotionActivation.findMany({
      where: {
        OR: [
          { status: ActivationStatus.SCHEDULED, startsAt: { lte: now } },
          { status: { in: [ActivationStatus.ACTIVE, ActivationStatus.SCHEDULED] }, expiresAt: { lte: now } },
        ],
      },
      select: { id: true, status: true, expiresAt: true, target: true, targetId: true, kind: true, ownerId: true },
      take: 1000,
    });
    let started = 0;
    let expired = 0;
    const touched = new Map<string, { target: PromotionTarget; targetId: string }>();
    for (const a of due) {
      const ended = a.expiresAt != null && a.expiresAt <= now;
      const next = ended ? ActivationStatus.EXPIRED : ActivationStatus.ACTIVE;
      // Conditional update: concurrent sweeps cannot double-apply.
      const { count } = await this.prisma.promotionActivation.updateMany({
        where: { id: a.id, status: a.status },
        data: { status: next },
      });
      if (!count) continue;
      if (ended) expired++;
      else started++;
      if (a.target !== 'BUSINESS') touched.set(`${a.target}:${a.targetId}`, { target: a.target, targetId: a.targetId });
    }
    for (const { target, targetId } of touched.values()) {
      await this.recompute(this.prisma, target, targetId, now).catch((error: Error) =>
        this.logger.warn(`recompute ${target}:${targetId} failed: ${error.message}`),
      );
    }
    // Stale caches whose boostUntil passed (safety net).
    await this.prisma.listing.updateMany({ where: { boostTier: { gt: 0 }, boostUntil: { lte: now } }, data: { boostTier: 0, boostUntil: null } });
    await this.prisma.job.updateMany({ where: { boostTier: { gt: 0 }, boostUntil: { lte: now } }, data: { boostTier: 0, boostUntil: null } });
    await this.prisma.serviceProvider.updateMany({
      where: { boostTier: { gt: 0 }, boostUntil: { lte: now } },
      data: { boostTier: 0, boostUntil: null },
    });
    const notified = await this.notifyExpiring(now);
    return { started, expired, notified };
  }

  private async notifyExpiring(now: Date): Promise<number> {
    const { promotionExpiringHours } = await this.config.setting('notices');
    const soon = new Date(now.getTime() + promotionExpiringHours * 3600_000);
    const rows = await this.prisma.promotionActivation.findMany({
      where: { status: ActivationStatus.ACTIVE, expiresAt: { gt: now, lte: soon }, expiringNotifiedAt: null },
      include: { product: { select: { title: true } } },
      take: 500,
    });
    let sent = 0;
    for (const a of rows) {
      const { count } = await this.prisma.promotionActivation.updateMany({
        where: { id: a.id, expiringNotifiedAt: null },
        data: { expiringNotifiedAt: now },
      });
      if (!count) continue;
      await this.notifications.notify(
        a.ownerId,
        {
          type: NotificationType.PROMOTION,
          title: `${a.product.title} tugayapti`,
          body: 'Targ‘ibot muddati tez orada tugaydi.',
          route: routeFor(a.target, a.targetId),
          data: { activationId: a.id },
        },
        { dedupeKey: `promo-expiring:${a.id}` },
      );
      sent++;
    }
    return sent;
  }
}

/** Fair, stable-within-the-hour rotation of equally paid items. */
export function rotate<T extends { id: string }>(rows: T[]): T[] {
  return [...rows].sort((a, b) => hourlyRank(a.id).localeCompare(hourlyRank(b.id)));
}

function hourlyRank(id: string): string {
  const hour = Math.floor(Date.now() / 3600_000);
  let h = 2166136261;
  for (const c of `${id}:${hour}`) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0;
  return h.toString(16).padStart(8, '0');
}

export function routeFor(target: PromotionTarget, id: string): string {
  switch (target) {
    case 'LISTING':
      return `/listing/${id}`;
    case 'JOB':
      return `/job/${id}`;
    case 'PROVIDER':
      return `/provider/${id}`;
    case 'BUSINESS':
      return `/business/${id}`;
  }
}
