/**
 * Monetization catalog *structure*. No prices are seeded: products and paid
 * plans start inactive and unpriced; an admin sets real prices and activates
 * them (see docs/monetization.md). Seeding never overwrites admin edits.
 */
import type { AnalyticsLevel, Placement, PromotionKind, PromotionTarget } from '@prisma/client';

export const PRODUCT_SEEDS: Array<{
  id: string;
  kind: PromotionKind;
  target: PromotionTarget;
  placement?: Placement;
  durationDays: number | null;
  title: string;
  description: string;
  creditCost?: number;
}> = [
  ...[1, 3, 7, 30].map((days) => ({
    id: `listing_top_${days}d`,
    kind: 'LISTING_TOP' as const,
    target: 'LISTING' as const,
    durationDays: days,
    title: 'TOP',
    description: 'Ko‘proq odamlarga ko‘rsatiladi',
    creditCost: 1,
  })),
  { id: 'listing_vip_7d', kind: 'LISTING_VIP', target: 'LISTING', durationDays: 7, title: 'VIP', description: 'Maxsus ko‘rinish va yuqori joylashuv' },
  { id: 'listing_vip_30d', kind: 'LISTING_VIP', target: 'LISTING', durationDays: 30, title: 'VIP', description: 'Maxsus ko‘rinish va yuqori joylashuv' },
  { id: 'listing_bump', kind: 'LISTING_BUMP', target: 'LISTING', durationDays: null, title: 'Ko‘tarish', description: 'E’lonni qayta yuqoriga olib chiqish', creditCost: 1 },
  { id: 'listing_featured_home_7d', kind: 'LISTING_FEATURED', target: 'LISTING', placement: 'HOME', durationDays: 7, title: 'Bosh sahifada tavsiya', description: 'Hududingizdagi bosh sahifa «Tavsiya» blokida' },
  { id: 'listing_featured_category_7d', kind: 'LISTING_FEATURED', target: 'LISTING', placement: 'CATEGORY', durationDays: 7, title: 'Kategoriyada tavsiya', description: 'Kategoriya sahifasidagi «Tavsiya» blokida' },
  { id: 'listing_featured_region_7d', kind: 'LISTING_FEATURED', target: 'LISTING', placement: 'REGION', durationDays: 7, title: 'Hududda tavsiya', description: 'Hudud bo‘yicha «Tavsiya» blokida' },
  { id: 'job_top_7d', kind: 'JOB_TOP', target: 'JOB', durationDays: 7, title: 'TOP vakansiya', description: 'Mos qidiruvlarda ajratilgan blokda' },
  { id: 'job_featured_7d', kind: 'JOB_FEATURED', target: 'JOB', placement: 'REGION', durationDays: 7, title: 'Tavsiya etilgan vakansiya', description: 'Hududdagi «Tavsiya» blokida' },
  { id: 'job_urgent_7d', kind: 'JOB_URGENT', target: 'JOB', durationDays: 7, title: 'Shoshilinch', description: '«Shoshilinch» belgisi' },
  { id: 'provider_top_7d', kind: 'PROVIDER_TOP', target: 'PROVIDER', durationDays: 7, title: 'TOP usta', description: 'Mos qidiruvlarda ajratilgan blokda' },
  { id: 'provider_featured_region_7d', kind: 'PROVIDER_FEATURED', target: 'PROVIDER', placement: 'REGION', durationDays: 7, title: 'Hududda tavsiya', description: 'Hududingizdagi «Tavsiya etilgan ustalar» blokida' },
  { id: 'provider_featured_category_7d', kind: 'PROVIDER_FEATURED', target: 'PROVIDER', placement: 'CATEGORY', durationDays: 7, title: 'Kategoriyada tavsiya', description: 'Kategoriya ichida «Tavsiya» blokida' },
  { id: 'ad_campaign_7d', kind: 'AD_CAMPAIGN', target: 'BUSINESS', durationDays: 7, title: 'Mahalliy reklama', description: 'Tanlangan hudud va kategoriyada «Reklama» belgisi bilan' },
];

export const PLAN_SEEDS: Array<{
  id: string;
  title: string;
  description: string;
  active: boolean;
  sortOrder: number;
  activeListingLimit: number | null;
  monthlyListingLimit: number | null;
  photoLimit: number;
  activeJobLimit: number | null;
  storefront: boolean;
  businessBadge: boolean;
  analytics: AnalyticsLevel;
  maxManagers: number;
  monthlyPromotionCredits: number;
  prioritySupport: boolean;
}> = [
  {
    id: 'FREE',
    title: 'Bepul',
    description: 'Ko‘rish, qidirish, chat, sevimlilar, e’lon joylash, ishga ariza — bepul.',
    active: true,
    sortOrder: 0,
    activeListingLimit: 50,
    monthlyListingLimit: 100,
    photoLimit: 12,
    activeJobLimit: 10,
    storefront: false,
    businessBadge: false,
    analytics: 'BASIC',
    maxManagers: 0,
    monthlyPromotionCredits: 0,
    prioritySupport: false,
  },
  {
    id: 'BUSINESS',
    title: 'Business',
    description: 'Do‘kon sahifasi, kengaytirilgan statistika va ko‘proq e’lonlar.',
    active: false,
    sortOrder: 1,
    activeListingLimit: 200,
    monthlyListingLimit: null,
    photoLimit: 20,
    activeJobLimit: 30,
    storefront: true,
    businessBadge: true,
    analytics: 'ADVANCED',
    maxManagers: 1,
    monthlyPromotionCredits: 0,
    prioritySupport: false,
  },
  {
    id: 'BUSINESS_PRO',
    title: 'Business Pro',
    description: 'Business imkoniyatlari, oylik TOP kreditlari va bir nechta menejer.',
    active: false,
    sortOrder: 2,
    activeListingLimit: null,
    monthlyListingLimit: null,
    photoLimit: 20,
    activeJobLimit: null,
    storefront: true,
    businessBadge: true,
    analytics: 'ADVANCED',
    maxManagers: 5,
    monthlyPromotionCredits: 5,
    prioritySupport: true,
  },
];
