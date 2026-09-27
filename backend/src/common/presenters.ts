import { MediaStatus, Prisma } from '@prisma/client';

import { env } from '../config/env';
import { apiEnum } from './text';

/**
 * Presenters turn Prisma rows into API JSON. Every public shape is built here
 * from explicit `select`s so private columns (phone, tokens, storage keys)
 * can never leak by accident.
 */

export const mediaSelect = {
  id: true,
  status: true,
  width: true,
  height: true,
  thumbKey: true,
  feedKey: true,
  detailKey: true,
} satisfies Prisma.MediaSelect;

export type MediaRow = Prisma.MediaGetPayload<{ select: typeof mediaSelect }>;

export interface ApiMedia {
  id: string;
  status: string;
  aspectRatio: number | null;
  variants: Partial<Record<'thumbnail' | 'feed' | 'detail' | 'original', string>>;
}

function variantUrl(
  media: MediaRow,
  variant: 'thumbnail' | 'feed' | 'detail',
  key: string | null,
): string | undefined {
  if (!key) return undefined;
  const cdn = env().MEDIA_PUBLIC_BASE_URL;
  return cdn
    ? `${cdn.replace(/\/$/, '')}/${key}`
    : `${env().PUBLIC_API_URL}/api/v1/media/${media.id}/${variant}`;
}

export function presentMedia(media: MediaRow): ApiMedia {
  const ready = media.status === MediaStatus.READY;
  const detail = ready ? variantUrl(media, 'detail', media.detailKey) : undefined;
  return {
    id: media.id,
    status: apiEnum(media.status),
    aspectRatio: media.width && media.height ? media.width / media.height : null,
    variants: ready
      ? {
          thumbnail: variantUrl(media, 'thumbnail', media.thumbKey),
          feed: variantUrl(media, 'feed', media.feedKey),
          detail,
          // Originals stay private; the largest public rendition is "detail".
          original: detail,
        }
      : {},
  };
}

export const placeSelect = {
  regionId: true,
  districtId: true,
  lat: true,
  lng: true,
  region: { select: { name: true } },
  district: { select: { name: true } },
} satisfies Prisma.ListingSelect;

export interface PlaceRow {
  regionId: string;
  districtId: string | null;
  lat: number | null;
  lng: number | null;
  region: { name: string };
  district: { name: string } | null;
  locality?: { name: string } | null;
}

export function presentPlace(row: PlaceRow) {
  return {
    regionId: row.regionId,
    regionName: row.region.name,
    districtId: row.districtId,
    districtName: row.district?.name ?? null,
    localityName: row.locality?.name ?? null,
    lat: row.lat,
    lng: row.lng,
  };
}

export const publicUserSelect = {
  id: true,
  createdAt: true,
  lastSeenAt: true,
  profile: {
    select: {
      displayName: true,
      verification: true,
      accountType: true,
      avatar: { select: mediaSelect },
    },
  },
  provider: { select: { ratingAvg: true, reviewCount: true } },
} satisfies Prisma.UserSelect;

export type PublicUserRow = Prisma.UserGetPayload<{ select: typeof publicUserSelect }>;

export function presentUser(
  user: PublicUserRow,
  extra: { isOnline?: boolean; activeListings?: number } = {},
) {
  const reviews = user.provider?.reviewCount ?? 0;
  return {
    id: user.id,
    name: user.profile?.displayName ?? 'Foydalanuvchi',
    avatar: user.profile?.avatar ? presentMedia(user.profile.avatar) : null,
    verification: apiEnum(user.profile?.verification ?? 'NONE'),
    accountType: apiEnum(user.profile?.accountType ?? 'PERSONAL'),
    isOnline: extra.isOnline ?? false,
    lastActiveAt: user.lastSeenAt,
    memberSince: user.createdAt,
    // Ratings come only from real reviews; absent until someone reviews.
    rating: reviews > 0 ? Math.round((user.provider?.ratingAvg ?? 0) * 10) / 10 : null,
    reviewCount: reviews,
    activeListings: extra.activeListings ?? 0,
  };
}

export function presentMoney(amount: bigint | number | null, currency: string) {
  return amount == null ? null : { amount: Number(amount), currency: apiEnum(currency) };
}
