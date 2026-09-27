import { Prisma } from '@prisma/client';

import { env } from '../../config/env';
import {
  mediaSelect,
  presentMedia,
  presentMoney,
  presentPlace,
  presentUser,
  publicUserSelect,
} from '../../common/presenters';
import { apiEnum } from '../../common/text';

export const offeringSelect = {
  id: true,
  categoryId: true,
  title: true,
  description: true,
  pricingType: true,
  priceFrom: true,
  priceTo: true,
  currency: true,
  priceUnit: true,
  status: true,
  media: { orderBy: { position: 'asc' }, select: { media: { select: mediaSelect } } },
} satisfies Prisma.ServiceOfferingSelect;

export const providerCardSelect = {
  id: true,
  userId: true,
  displayName: true,
  profession: true,
  experienceYears: true,
  status: true,
  availability: true,
  ratingAvg: true,
  reviewCount: true,
  promotionType: true,
  promotedUntil: true,
  regionId: true,
  districtId: true,
  lat: true,
  lng: true,
  createdAt: true,
  region: { select: { name: true } },
  district: { select: { name: true } },
  user: { select: publicUserSelect },
  categories: { select: { categoryId: true } },
  offerings: {
    where: { status: 'ACTIVE', deletedAt: null },
    orderBy: { priceFrom: { sort: 'asc', nulls: 'last' } },
    take: 1,
    select: { priceFrom: true, currency: true, priceUnit: true },
  },
} satisfies Prisma.ServiceProviderSelect;

export const providerDetailSelect = {
  ...providerCardSelect,
  description: true,
  areas: {
    select: {
      regionId: true,
      districtId: true,
      region: { select: { name: true } },
      district: { select: { name: true } },
    },
  },
  portfolio: { orderBy: { position: 'asc' }, select: { caption: true, media: { select: mediaSelect } } },
  offerings: { where: { deletedAt: null }, orderBy: { createdAt: 'asc' }, select: offeringSelect },
} satisfies Prisma.ServiceProviderSelect;

type CardRow = Prisma.ServiceProviderGetPayload<{ select: typeof providerCardSelect }>;
type DetailRow = Prisma.ServiceProviderGetPayload<{ select: typeof providerDetailSelect }>;
type OfferingRow = Prisma.ServiceOfferingGetPayload<{ select: typeof offeringSelect }>;

export function presentOffering(o: OfferingRow) {
  return {
    id: o.id,
    categoryId: o.categoryId,
    title: o.title,
    description: o.description,
    pricingType: apiEnum(o.pricingType),
    priceFrom: presentMoney(o.priceFrom, o.currency),
    priceTo: presentMoney(o.priceTo, o.currency),
    priceUnit: o.priceUnit,
    status: apiEnum(o.status),
    images: o.media.map((m) => presentMedia(m.media)),
  };
}

export function presentProviderCard(
  row: CardRow,
  options: { isFavorite?: boolean; isOnline?: boolean; distanceKm?: number | null } = {},
) {
  const promoted = row.promotionType && (!row.promotedUntil || row.promotedUntil > new Date());
  const cheapest = row.offerings[0];
  const profile = presentUser(row.user, { isOnline: options.isOnline });
  return {
    id: row.id,
    userId: row.userId,
    // Provider rating is the provider's own aggregate, never the account's.
    profile: {
      ...profile,
      name: row.displayName,
      rating: row.reviewCount > 0 ? Math.round(row.ratingAvg * 10) / 10 : null,
      reviewCount: row.reviewCount,
    },
    profession: row.profession,
    categoryId: row.categories[0]?.categoryId ?? null,
    categoryIds: row.categories.map((c) => c.categoryId),
    place: presentPlace(row),
    experienceYears: row.experienceYears,
    status: apiEnum(row.status),
    availability: apiEnum(row.availability),
    priceFrom: cheapest ? presentMoney(cheapest.priceFrom, cheapest.currency) : null,
    priceUnit: cheapest?.priceUnit ?? null,
    promotion: promoted ? apiEnum(row.promotionType) : null,
    isFavorite: options.isFavorite ?? false,
    distanceKm: options.distanceKm ?? null,
    description: '',
    serviceArea: [] as string[],
    portfolio: [] as unknown[],
    offerings: [] as unknown[],
  };
}

export function presentProviderDetail(
  row: DetailRow,
  options: { isFavorite?: boolean; isOnline?: boolean; isOwner?: boolean } = {},
) {
  return {
    ...presentProviderCard(row, options),
    description: row.description,
    serviceArea: row.areas.map((a) => a.district?.name ?? a.region.name),
    areas: row.areas.map((a) => ({ regionId: a.regionId, districtId: a.districtId })),
    portfolio: row.portfolio.map((p) => ({ ...presentMedia(p.media), caption: p.caption })),
    offerings: row.offerings.filter((o) => options.isOwner || o.status === 'ACTIVE').map(presentOffering),
    shareUrl: `${env().WEB_BASE_URL}/provider/${row.id}`,
  };
}
