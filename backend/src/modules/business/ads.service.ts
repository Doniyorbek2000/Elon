import { createHash } from 'node:crypto';

import { Injectable } from '@nestjs/common';
import { AdDestination, AdStatus, ListingStatus, MediaPurpose, Prisma } from '@prisma/client';

import { AppError } from '../../common/errors';
import { mediaSelect, presentMedia } from '../../common/presenters';
import { apiEnum, dbEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { RedisService } from '../../infra/redis.service';
import { MonetizationConfig } from '../monetization/config.service';
import { rotate } from '../monetization/promotion.service';
import { AdsQuery, CampaignDto } from './business.dto';

const DAY = 86400_000;

/**
 * Native local advertising for businesses. Targeting is coarse (region,
 * district, category) and uses no personal profile. Events are aggregated
 * per day; a hashed viewer key lives only in Redis for 24 h to drop
 * duplicate impressions/clicks and is never persisted.
 */
@Injectable()
export class AdsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly limiter: RateLimiterService,
    private readonly config: MonetizationConfig,
  ) {}

  private async ownBusiness(userId: string) {
    const member = await this.prisma.businessMember.findFirst({ where: { userId }, select: { businessId: true } });
    if (!member) throw AppError.notFound('Business');
    return member.businessId;
  }

  /** The destination must belong to the business (no advertising others' content). */
  private async assertDestination(businessId: string, destination: AdDestination, id: string) {
    const members = (await this.prisma.businessMember.findMany({ where: { businessId }, select: { userId: true } })).map(
      (m) => m.userId,
    );
    const ok = await {
      LISTING: () => this.prisma.listing.count({ where: { id, sellerId: { in: members }, status: ListingStatus.ACTIVE, deletedAt: null } }),
      JOB: () => this.prisma.job.count({ where: { id, employerId: { in: members }, deletedAt: null } }),
      PROVIDER: () => this.prisma.serviceProvider.count({ where: { id, userId: { in: members }, deletedAt: null } }),
      BUSINESS: async () => (id === businessId ? 1 : 0),
    }[destination]();
    if (!ok) throw AppError.validation('Invalid ad destination', { field: 'destinationId' });
  }

  async create(userId: string, dto: CampaignDto) {
    if (!(await this.config.enabled('ads'))) throw AppError.featureDisabled('ads');
    const businessId = await this.ownBusiness(userId);
    const destination = dbEnum(dto.destination) as AdDestination;
    await this.assertDestination(businessId, destination, dto.destinationId);
    if (dto.imageId) {
      const media = await this.prisma.media.findFirst({
        where: { id: dto.imageId, ownerId: userId, purpose: { in: [MediaPurpose.LISTING, MediaPurpose.AVATAR] }, deletedAt: null },
      });
      if (!media) throw AppError.validation('Invalid image', { field: 'imageId' });
    }
    const campaign = await this.prisma.adCampaign.create({
      data: {
        businessId,
        createdById: userId,
        title: dto.title,
        body: dto.body,
        imageId: dto.imageId,
        destination,
        destinationId: dto.destinationId,
        regionId: dto.regionId,
        districtId: dto.districtId,
        categoryId: dto.categoryId,
        impressionLimit: dto.impressionLimit,
      },
    });
    return this.presentOwn(campaign.id);
  }

  async mine(userId: string) {
    const businessId = await this.ownBusiness(userId);
    const rows = await this.prisma.adCampaign.findMany({ where: { businessId }, orderBy: { createdAt: 'desc' }, take: 50, select: { id: true } });
    return Promise.all(rows.map((r) => this.presentOwn(r.id)));
  }

  async setPaused(userId: string, id: string, paused: boolean) {
    const businessId = await this.ownBusiness(userId);
    const { count } = await this.prisma.adCampaign.updateMany({
      where: { id, businessId, status: paused ? AdStatus.ACTIVE : AdStatus.PAUSED },
      data: { status: paused ? AdStatus.PAUSED : AdStatus.ACTIVE },
    });
    if (!count) throw AppError.invalidState('Campaign cannot change state now');
    return this.presentOwn(id);
  }

  async presentOwn(id: string) {
    const c = await this.prisma.adCampaign.findUniqueOrThrow({
      where: { id },
      include: { dailyStats: { orderBy: { day: 'asc' }, take: 90 } },
    });
    return {
      ...this.presentCreative(c, null),
      status: apiEnum(c.status),
      targeting: { regionId: c.regionId, districtId: c.districtId, categoryId: c.categoryId },
      startsAt: c.startsAt,
      endsAt: c.endsAt,
      impressionLimit: c.impressionLimit,
      stats: {
        impressions: c.impressions,
        clicks: c.clicks,
        daily: c.dailyStats.map((d) => ({ day: d.day.toISOString().slice(0, 10), impressions: d.impressions, clicks: d.clicks })),
      },
      rejectReason: c.rejectReason,
      purchaseId: c.purchaseId,
    };
  }

  private presentCreative(
    c: { id: string; title: string; body: string; destination: AdDestination; destinationId: string },
    image: Prisma.MediaGetPayload<{ select: typeof mediaSelect }> | null,
  ) {
    return {
      id: c.id,
      title: c.title,
      body: c.body,
      image: image ? presentMedia(image) : null,
      destination: apiEnum(c.destination),
      destinationId: c.destinationId,
      /** Always rendered with a visible "Reklama" label. */
      sponsored: true,
    };
  }

  /** Ads for a browsing context; unmatched targeting means "everywhere". */
  async serve(query: AdsQuery, limit = 1) {
    if (!(await this.config.enabled('ads'))) return [];
    const now = new Date();
    const rows = await this.prisma.adCampaign.findMany({
      where: {
        status: AdStatus.ACTIVE,
        startsAt: { lte: now },
        endsAt: { gt: now },
        AND: [
          { OR: [{ regionId: null }, ...(query.region ? [{ regionId: query.region }] : [])] },
          { OR: [{ districtId: null }, ...(query.district ? [{ districtId: query.district }] : [])] },
          { OR: [{ categoryId: null }, ...(query.category ? [{ categoryId: query.category }] : [])] },
        ],
      },
      take: 50,
    });
    const available = rows.filter((c) => c.impressionLimit == null || c.impressions < c.impressionLimit);
    const picked = rotate(available).slice(0, limit);
    const images = await this.prisma.media.findMany({
      where: { id: { in: picked.map((c) => c.imageId).filter((i): i is string => !!i) } },
      select: mediaSelect,
    });
    const byId = new Map(images.map((m) => [m.id, m]));
    return picked.map((c) => this.presentCreative(c, c.imageId ? byId.get(c.imageId) ?? null : null));
  }

  /** Deduplicated per viewer/campaign/day; counts only live campaigns. */
  async recordEvent(id: string, type: 'impression' | 'click', viewerKey: string) {
    await this.limiter.consume(`adevent:${viewerKey}`, 300, 3600);
    const hashed = createHash('sha256').update(viewerKey).digest('hex').slice(0, 32);
    const fresh = await this.redis.client.set(`ad:${type}:${id}:${hashed}`, '1', 'EX', 86400, 'NX');
    if (fresh !== 'OK') return { counted: false };
    const now = new Date();
    const { count } = await this.prisma.adCampaign.updateMany({
      where: { id, status: AdStatus.ACTIVE, startsAt: { lte: now }, endsAt: { gt: now } },
      data: type === 'impression' ? { impressions: { increment: 1 } } : { clicks: { increment: 1 } },
    });
    if (!count) return { counted: false };
    const day = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    await this.prisma.adDailyStat.upsert({
      where: { campaignId_day: { campaignId: id, day } },
      create: { campaignId: id, day, impressions: type === 'impression' ? 1 : 0, clicks: type === 'click' ? 1 : 0 },
      update: type === 'impression' ? { impressions: { increment: 1 } } : { clicks: { increment: 1 } },
    });
    return { counted: true };
  }

  /** Admin approval starts the paid period. */
  async approve(id: string) {
    const campaign = await this.prisma.adCampaign.findUnique({ where: { id }, include: { business: true } });
    if (!campaign || campaign.status !== AdStatus.PENDING_REVIEW || !campaign.purchaseId) {
      throw AppError.invalidState('Campaign is not awaiting review');
    }
    const purchase = await this.prisma.purchase.findUniqueOrThrow({ where: { id: campaign.purchaseId }, include: { product: true } });
    const days = purchase.product?.durationDays ?? 7;
    const now = new Date();
    return this.prisma.adCampaign.update({
      where: { id },
      data: { status: AdStatus.ACTIVE, startsAt: now, endsAt: new Date(now.getTime() + days * DAY), rejectReason: null },
    });
  }

  /** Rejection after payment requires a refund decision by finance. */
  async reject(id: string, reason: string) {
    const campaign = await this.prisma.adCampaign.findUnique({ where: { id } });
    if (!campaign || (campaign.status !== AdStatus.PENDING_REVIEW && campaign.status !== AdStatus.DRAFT)) {
      throw AppError.invalidState('Campaign cannot be rejected now');
    }
    await this.prisma.$transaction(async (tx) => {
      await tx.adCampaign.update({ where: { id }, data: { status: AdStatus.REJECTED, rejectReason: reason } });
      if (campaign.purchaseId) {
        await tx.purchase.update({ where: { id: campaign.purchaseId }, data: { status: 'NEEDS_REVIEW', failureReason: 'ad_rejected' } });
        await tx.payment.updateMany({ where: { purchaseId: campaign.purchaseId, status: 'SUCCEEDED' }, data: { needsReview: true } });
      }
    });
  }

  /** Worker: end campaigns whose period or impression cap is over. */
  async sweep(now = new Date()): Promise<number> {
    const ended = await this.prisma.adCampaign.updateMany({
      where: { status: { in: [AdStatus.ACTIVE, AdStatus.PAUSED] }, endsAt: { lte: now } },
      data: { status: AdStatus.ENDED },
    });
    const capped = await this.prisma.$executeRaw`
      UPDATE "AdCampaign" SET "status" = 'ENDED', "updatedAt" = now()
      WHERE "status" = 'ACTIVE' AND "impressionLimit" IS NOT NULL AND "impressions" >= "impressionLimit"`;
    return ended.count + capped;
  }
}
