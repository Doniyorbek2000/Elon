import { Injectable } from '@nestjs/common';
import { BillingPeriod, Plan, PlanPrice, ProductPrice, PromotionKind, PromotionProduct, PromotionTarget } from '@prisma/client';

import { apiEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { FlagKey, MonetizationConfig } from './config.service';
import { presentAmount } from './money';

export const KIND_FLAG: Record<PromotionKind, FlagKey> = {
  LISTING_TOP: 'listingTop',
  LISTING_VIP: 'listingVip',
  LISTING_BUMP: 'listingBump',
  LISTING_FEATURED: 'featuredListings',
  JOB_TOP: 'premiumJobs',
  JOB_FEATURED: 'premiumJobs',
  JOB_URGENT: 'premiumJobs',
  PROVIDER_TOP: 'featuredServices',
  PROVIDER_FEATURED: 'featuredServices',
  AD_CAMPAIGN: 'ads',
};

const priceNow = (now: Date) => ({
  validFrom: { lte: now },
  OR: [{ validUntil: null }, { validUntil: { gt: now } }],
});

export type PricedProduct = PromotionProduct & { price: ProductPrice };
export type PricedPlan = Plan & { prices: PlanPrice[] };

/**
 * Products and plans with the price valid *now*. Prices are rows with a
 * validity window, so a future price change is scheduled data, not a deploy.
 */
@Injectable()
export class CatalogService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: MonetizationConfig,
  ) {}

  async currentPrice(productId: string, now = new Date()): Promise<ProductPrice | null> {
    return this.prisma.productPrice.findFirst({
      where: { productId, ...priceNow(now) },
      orderBy: { validFrom: 'desc' },
    });
  }

  /** Sellable = active, priced now, and its feature flag switched on. */
  async sellableProduct(productId: string, now = new Date()): Promise<PricedProduct | null> {
    const product = await this.prisma.promotionProduct.findUnique({ where: { id: productId } });
    if (!product || !product.active) return null;
    if (!(await this.config.enabled(KIND_FLAG[product.kind]))) return null;
    const price = await this.currentPrice(productId, now);
    return price ? { ...product, price } : null;
  }

  async productsFor(target: PromotionTarget, now = new Date()): Promise<PricedProduct[]> {
    const products = await this.prisma.promotionProduct.findMany({
      where: { target, active: true },
      orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
      include: { prices: { where: priceNow(now), orderBy: { validFrom: 'desc' }, take: 1 } },
    });
    const flags = await this.config.flags();
    return products
      .filter((p) => flags[KIND_FLAG[p.kind]] && p.prices.length > 0)
      .map(({ prices, ...p }) => ({ ...p, price: prices[0] }));
  }

  async plans(now = new Date()): Promise<PricedPlan[]> {
    return this.prisma.plan.findMany({
      where: { active: true },
      orderBy: { sortOrder: 'asc' },
      include: {
        prices: { where: { active: true, ...priceNow(now) }, orderBy: [{ period: 'asc' }, { validFrom: 'desc' }] },
      },
    });
  }

  async sellablePlanPrice(planPriceId: string, now = new Date()) {
    if (!(await this.config.enabled('businessPlans'))) return null;
    const price = await this.prisma.planPrice.findFirst({
      where: { id: planPriceId, active: true, ...priceNow(now), plan: { active: true } },
      include: { plan: true },
    });
    if (!price) return null;
    // Only the newest valid row for this plan/period is sellable (no stale prices).
    const newest = await this.prisma.planPrice.findFirst({
      where: { planId: price.planId, period: price.period, active: true, ...priceNow(now) },
      orderBy: { validFrom: 'desc' },
      select: { id: true },
    });
    return newest?.id === price.id ? price : null;
  }

  static presentProduct(p: PricedProduct, extra: Record<string, unknown> = {}) {
    return {
      id: p.id,
      kind: apiEnum(p.kind),
      target: apiEnum(p.target),
      placement: apiEnum(p.placement),
      durationDays: p.durationDays,
      title: p.title,
      description: p.description,
      creditCost: p.creditCost,
      price: presentAmount(p.price.amountMinor, p.price.currency),
      ...extra,
    };
  }

  static presentPlan(plan: PricedPlan) {
    // One price per period (the newest valid one).
    const byPeriod = new Map<BillingPeriod, PlanPrice>();
    for (const price of plan.prices) if (!byPeriod.has(price.period)) byPeriod.set(price.period, price);
    return {
      id: plan.id,
      title: plan.title,
      description: plan.description,
      entitlements: presentEntitlements(plan),
      prices: [...byPeriod.values()].map((p) => ({
        id: p.id,
        period: apiEnum(p.period),
        ...presentAmount(p.amountMinor, p.currency),
      })),
    };
  }
}

export function presentEntitlements(plan: Plan) {
  return {
    activeListingLimit: plan.activeListingLimit,
    monthlyListingLimit: plan.monthlyListingLimit,
    photoLimit: plan.photoLimit,
    activeJobLimit: plan.activeJobLimit,
    storefront: plan.storefront,
    businessBadge: plan.businessBadge,
    analytics: apiEnum(plan.analytics),
    maxManagers: plan.maxManagers,
    monthlyPromotionCredits: plan.monthlyPromotionCredits,
    prioritySupport: plan.prioritySupport,
  };
}
