import { Prisma } from '@prisma/client';

import {
  mediaSelect,
  presentMedia,
  presentMoney,
  presentPlace,
  presentUser,
  publicUserSelect,
} from '../../common/presenters';
import { apiEnum } from '../../common/text';
import { CategoriesService } from '../categories/categories.service';

export const listingCardSelect = {
  id: true,
  sellerId: true,
  categoryId: true,
  title: true,
  priceAmount: true,
  currency: true,
  negotiable: true,
  condition: true,
  status: true,
  publishedAt: true,
  createdAt: true,
  viewCount: true,
  favoriteCount: true,
  promotionType: true,
  promotedUntil: true,
  regionId: true,
  districtId: true,
  lat: true,
  lng: true,
  region: { select: { name: true } },
  district: { select: { name: true } },
  locality: { select: { name: true } },
  seller: { select: publicUserSelect },
  media: { orderBy: { position: 'asc' }, take: 1, select: { media: { select: mediaSelect } } },
} satisfies Prisma.ListingSelect;

export const listingDetailSelect = {
  ...listingCardSelect,
  description: true,
  rejectReason: true,
  riskFlags: true,
  expiresAt: true,
  soldAt: true,
  updatedAt: true,
  localityId: true,
  media: { orderBy: { position: 'asc' }, select: { media: { select: mediaSelect } } },
  attributes: { include: { attribute: true } },
} satisfies Prisma.ListingSelect;

type CardRow = Prisma.ListingGetPayload<{ select: typeof listingCardSelect }>;
type DetailRow = Prisma.ListingGetPayload<{ select: typeof listingDetailSelect }>;

export interface PresentOptions {
  isFavorite?: boolean;
  distanceKm?: number | null;
  isOwner?: boolean;
  sellerOnline?: boolean;
  sellerActiveListings?: number;
}

export function presentListingCard(row: CardRow, options: PresentOptions = {}) {
  const promoted = row.promotionType && (!row.promotedUntil || row.promotedUntil > new Date());
  return {
    id: row.id,
    title: row.title,
    description: '',
    categoryId: row.categoryId,
    images: row.media.map((m) => presentMedia(m.media)),
    place: presentPlace(row),
    publishedAt: row.publishedAt ?? row.createdAt,
    seller: presentUser(row.seller, {
      isOnline: options.sellerOnline,
      activeListings: options.sellerActiveListings,
    }),
    price: presentMoney(row.priceAmount, row.currency),
    negotiable: row.negotiable,
    condition: apiEnum(row.condition),
    attributes: [] as Array<{ key: string; label: string; value: string }>,
    views: row.viewCount,
    favorites: row.favoriteCount,
    promotion: promoted ? apiEnum(row.promotionType) : null,
    status: apiEnum(row.status),
    distanceKm: options.distanceKm != null ? Math.round(options.distanceKm * 10) / 10 : null,
    isFavorite: options.isFavorite ?? false,
    shareUrl: null as string | null,
  };
}

export function presentListingDetail(row: DetailRow, webBaseUrl: string, options: PresentOptions = {}) {
  return {
    ...presentListingCard(row, options),
    description: row.description,
    attributes: CategoriesService.presentAttributes(row.attributes),
    localityId: row.localityId,
    expiresAt: row.expiresAt,
    shareUrl: `${webBaseUrl}/listing/${row.id}`,
    // Moderation details are shown to the owner only.
    ...(options.isOwner ? { rejectReason: row.rejectReason, riskFlags: row.riskFlags } : {}),
  };
}
