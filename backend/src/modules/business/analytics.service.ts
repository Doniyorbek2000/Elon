import { Injectable, Logger } from '@nestjs/common';
import { ActivationStatus } from '@prisma/client';

import { AppError } from '../../common/errors';
import { PrismaService } from '../../infra/prisma.service';
import { EntitlementService } from '../monetization/entitlements.service';

export type ListingMetric = 'views' | 'favorites' | 'contacts' | 'chats' | 'shares';

const DAY = 86400_000;

function utcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

/**
 * Seller analytics from real, aggregated counters only (no viewer
 * identities are stored). Nothing is estimated or extrapolated.
 */
@Injectable()
export class AnalyticsService {
  private readonly logger = new Logger(AnalyticsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementService,
  ) {}

  /** Best effort: analytics must never break the user action being counted. */
  async bump(listingId: string, metric: ListingMetric, now = new Date()): Promise<void> {
    const day = utcDay(now);
    await this.prisma.listingDailyStat
      .upsert({
        where: { listingId_day: { listingId, day } },
        create: { listingId, day, [metric]: 1 },
        update: { [metric]: { increment: 1 } },
      })
      .catch((error: Error) => this.logger.warn(`stat ${metric} failed: ${error.message}`));
  }

  private async series(listingId: string, from: Date, to: Date) {
    const rows = await this.prisma.listingDailyStat.findMany({
      where: { listingId, day: { gte: utcDay(from), lte: utcDay(to) } },
      orderBy: { day: 'asc' },
    });
    const totals = { views: 0, favorites: 0, contacts: 0, chats: 0, shares: 0 };
    for (const r of rows) {
      totals.views += r.views;
      totals.favorites += r.favorites;
      totals.contacts += r.contacts;
      totals.chats += r.chats;
      totals.shares += r.shares;
    }
    return {
      totals,
      daily: rows.map((r) => ({
        day: r.day.toISOString().slice(0, 10),
        views: r.views,
        favorites: r.favorites,
        contacts: r.contacts,
        chats: r.chats,
        shares: r.shares,
      })),
    };
  }

  /**
   * Free plans: last 7 days, totals only. Advanced analytics (business
   * plans): up to 90 days, daily series, custom range.
   */
  async listingStats(userId: string, listingId: string, range: { days?: number; from?: Date; to?: Date }) {
    const listing = await this.prisma.listing.findFirst({
      where: { id: listingId, sellerId: userId, deletedAt: null },
      select: { id: true, viewCount: true, favoriteCount: true, publishedAt: true },
    });
    if (!listing) throw AppError.notFound('Listing');
    const advanced = await this.entitlements.canViewAdvancedAnalytics(userId);
    const now = new Date();
    let from: Date;
    let to = now;
    if (advanced && range.from) {
      from = range.from;
      to = range.to && range.to < now ? range.to : now;
    } else {
      const days = advanced ? Math.min(range.days ?? 30, 90) : 7;
      from = new Date(now.getTime() - (days - 1) * DAY);
    }
    if (from > to || to.getTime() - from.getTime() > 90 * DAY) throw AppError.validation('Invalid range');
    const { totals, daily } = await this.series(listingId, from, to);
    return {
      level: advanced ? 'advanced' : 'basic',
      from: utcDay(from).toISOString().slice(0, 10),
      to: utcDay(to).toISOString().slice(0, 10),
      totals,
      daily: advanced ? daily : [],
      lifetime: { views: listing.viewCount, favorites: listing.favoriteCount },
    };
  }

  /**
   * Results of a promotion: counters during the promotion, and — only when
   * the listing was already live for an equally long period — the same
   * counters for that preceding period. No causal claims are made.
   */
  async promotionStats(userId: string, activationId: string) {
    const activation = await this.prisma.promotionActivation.findFirst({
      where: { id: activationId, ownerId: userId },
    });
    if (!activation || activation.target !== 'LISTING') throw AppError.notFound('Promotion');
    const now = new Date();
    const start = activation.startsAt;
    const end = activation.expiresAt && activation.expiresAt < now ? activation.expiresAt : now;
    const during = await this.series(activation.targetId, start, end);
    const length = Math.max(end.getTime() - start.getTime(), DAY);
    const beforeFrom = new Date(start.getTime() - length);
    const listing = await this.prisma.listing.findUnique({
      where: { id: activation.targetId },
      select: { publishedAt: true },
    });
    const comparable =
      !!listing?.publishedAt && listing.publishedAt <= beforeFrom && activation.kind !== 'LISTING_BUMP';
    const before = comparable
      ? await this.series(activation.targetId, beforeFrom, new Date(start.getTime() - 1))
      : null;
    return {
      activationId,
      status:
        activation.status === ActivationStatus.ACTIVE && activation.expiresAt && activation.expiresAt <= now
          ? 'expired'
          : activation.status.toLowerCase(),
      startsAt: start,
      expiresAt: activation.expiresAt,
      during: during.totals,
      before: before?.totals ?? null,
      comparable,
      note: 'Figures are counted events, not predictions or guaranteed results.',
    };
  }
}
