import { Injectable } from '@nestjs/common';
import { AnalyticsLevel, JobStatus, ListingStatus, Plan, SubscriptionStatus } from '@prisma/client';

import { AppError } from '../../common/errors';
import { PrismaService } from '../../infra/prisma.service';
import { RedisService } from '../../infra/redis.service';

export const FREE_PLAN_ID = 'FREE';

/** Used only if the FREE plan row is missing — generous, never crippling. */
const FALLBACK_FREE: Omit<Plan, 'createdAt' | 'updatedAt'> = {
  id: FREE_PLAN_ID,
  title: 'Bepul',
  description: '',
  active: true,
  sortOrder: 0,
  activeListingLimit: 50,
  monthlyListingLimit: 100,
  photoLimit: 12,
  activeJobLimit: 10,
  storefront: false,
  businessBadge: false,
  analytics: AnalyticsLevel.BASIC,
  maxManagers: 0,
  monthlyPromotionCredits: 0,
  prioritySupport: false,
};

export interface EffectivePlan {
  plan: Omit<Plan, 'createdAt' | 'updatedAt'>;
  subscriptionId: string | null;
  /** Business whose subscription grants this plan (member or owner). */
  businessId: string | null;
}

const LIVE_SUBSCRIPTION: SubscriptionStatus[] = [SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE_PERIOD];
const COUNTED_LISTING = [ListingStatus.ACTIVE, ListingStatus.PENDING_REVIEW, ListingStatus.RESERVED];
const CACHE_SECONDS = 60;

/**
 * Single place that answers "what may this account do?". Controllers and
 * services call these methods; nothing else inspects subscriptions. The
 * server-side subscription state is authoritative (period end is compared
 * with the database clock at read time, never the device clock).
 */
@Injectable()
export class EntitlementService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  private key(userId: string) {
    return `ent:${userId}`;
  }

  async invalidate(userIds: string[]): Promise<void> {
    if (userIds.length) await this.redis.client.del(...userIds.map((id) => this.key(id)));
  }

  /** After a plan edit: drop every cached entitlement (rare admin action). */
  async invalidateAll(): Promise<void> {
    let cursor = '0';
    do {
      const [next, keys] = await this.redis.client.scan(cursor, 'MATCH', 'ent:*', 'COUNT', 500);
      if (keys.length) await this.redis.client.del(...keys);
      cursor = next;
    } while (cursor !== '0');
  }

  /** Invalidate every member of a business (plan is shared). */
  async invalidateBusiness(businessId: string): Promise<void> {
    const members = await this.prisma.businessMember.findMany({
      where: { businessId },
      select: { userId: true },
    });
    await this.invalidate(members.map((m) => m.userId));
  }

  async effectivePlan(userId: string): Promise<EffectivePlan> {
    const cached = await this.redis.client.get(this.key(userId));
    if (cached) {
      const parsed = JSON.parse(cached) as EffectivePlan & { until: string | null };
      if (!parsed.until || new Date(parsed.until) > new Date()) return parsed;
    }
    const now = new Date();
    const memberships = await this.prisma.businessMember.findMany({
      where: { userId },
      select: { businessId: true },
    });
    const businessIds = memberships.map((m) => m.businessId);
    const subscription = await this.prisma.subscription.findFirst({
      where: {
        status: { in: LIVE_SUBSCRIPTION },
        OR: [
          { userId, businessId: null },
          ...(businessIds.length ? [{ businessId: { in: businessIds } }] : []),
        ],
        AND: [{ OR: [{ currentPeriodEnd: { gt: now } }, { graceUntil: { gt: now } }] }],
      },
      include: { plan: true },
      orderBy: { plan: { sortOrder: 'desc' } },
    });
    const free = (await this.prisma.plan.findUnique({ where: { id: FREE_PLAN_ID } })) ?? FALLBACK_FREE;
    const result: EffectivePlan = subscription
      ? { plan: subscription.plan, subscriptionId: subscription.id, businessId: subscription.businessId }
      : { plan: free, subscriptionId: null, businessId: null };
    const until = subscription
      ? (subscription.graceUntil && subscription.graceUntil > subscription.currentPeriodEnd
          ? subscription.graceUntil
          : subscription.currentPeriodEnd
        ).toISOString()
      : null;
    await this.redis.client.set(this.key(userId), JSON.stringify({ ...result, until }), 'EX', CACHE_SECONDS);
    return result;
  }

  async activeListingLimit(userId: string): Promise<number | null> {
    return (await this.effectivePlan(userId)).plan.activeListingLimit;
  }

  async photoLimit(userId: string): Promise<number> {
    return (await this.effectivePlan(userId)).plan.photoLimit;
  }

  /** Throws LIMIT_REACHED when one more active/pending listing is not allowed. */
  async assertCanActivateListing(userId: string, excludeListingId?: string): Promise<void> {
    const { plan } = await this.effectivePlan(userId);
    if (plan.activeListingLimit != null) {
      const active = await this.prisma.listing.count({
        where: {
          sellerId: userId,
          deletedAt: null,
          status: { in: COUNTED_LISTING },
          ...(excludeListingId ? { id: { not: excludeListingId } } : {}),
        },
      });
      if (active >= plan.activeListingLimit)
        throw AppError.limitReached('activeListings', plan.activeListingLimit);
    }
  }

  async assertCanCreateListing(userId: string, photoCount: number): Promise<void> {
    const { plan } = await this.effectivePlan(userId);
    if (photoCount > plan.photoLimit) throw AppError.limitReached('photos', plan.photoLimit);
    if (plan.monthlyListingLimit != null) {
      const since = new Date(Date.now() - 30 * 24 * 3600 * 1000);
      const created = await this.prisma.listing.count({
        where: { sellerId: userId, createdAt: { gte: since } },
      });
      if (created >= plan.monthlyListingLimit)
        throw AppError.limitReached('monthlyListings', plan.monthlyListingLimit);
    }
  }

  async assertPhotoLimit(userId: string, photoCount: number): Promise<void> {
    const limit = await this.photoLimit(userId);
    if (photoCount > limit) throw AppError.limitReached('photos', limit);
  }

  async assertCanActivateJob(userId: string, excludeJobId?: string): Promise<void> {
    const { plan } = await this.effectivePlan(userId);
    if (plan.activeJobLimit == null) return;
    const active = await this.prisma.job.count({
      where: {
        employerId: userId,
        deletedAt: null,
        status: JobStatus.ACTIVE,
        ...(excludeJobId ? { id: { not: excludeJobId } } : {}),
      },
    });
    if (active >= plan.activeJobLimit) throw AppError.limitReached('activeJobs', plan.activeJobLimit);
  }

  async canUseStorefront(userId: string): Promise<boolean> {
    return (await this.effectivePlan(userId)).plan.storefront;
  }

  async canViewAdvancedAnalytics(userId: string): Promise<boolean> {
    return (await this.effectivePlan(userId)).plan.analytics === AnalyticsLevel.ADVANCED;
  }

  async maxManagers(userId: string): Promise<number> {
    return (await this.effectivePlan(userId)).plan.maxManagers;
  }
}
