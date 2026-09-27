import { ItemCondition, Prisma } from '@prisma/client';

import { AppError } from '../../common/errors';
import { decodeCursor, encodeCursor } from '../../common/pagination';
import { searchTokens } from '../../common/text';
import type { ListingSort } from './listings.dto';

export interface FeedFilters {
  text?: string;
  categoryIds?: string[];
  regionId?: string;
  districtId?: string;
  localityId?: string;
  origin?: { lat: number; lng: number };
  radiusKm?: number;
  priceMin?: number;
  priceMax?: number;
  condition?: ItemCondition;
  sellerId?: string;
  viewerId?: string;
  excludeId?: string;
}

export interface FeedRow {
  id: string;
  distance_km: number | null;
}

/** Deep offset pagination is capped; clients should refine filters instead. */
const MAX_OFFSET = 2000;

/**
 * Builds the marketplace feed query. Every user value is a bound parameter via
 * Prisma.sql — no string concatenation of input. Returns ids (+ distance);
 * hydration happens separately with Prisma includes (no N+1).
 *
 * Cursors: keyset on (publishedAt, id) for "newest" (the hot path); bounded
 * offset cursors for price/popularity/distance sorts.
 */
export function buildFeedQuery(filters: FeedFilters, sort: ListingSort, cursor: string | undefined, take: number) {
  const where: Prisma.Sql[] = [Prisma.sql`l."status" = 'ACTIVE'`, Prisma.sql`l."deletedAt" IS NULL`];
  const origin = filters.origin;
  const originPoint = origin
    ? Prisma.sql`ST_SetSRID(ST_MakePoint(${origin.lng}, ${origin.lat}), 4326)::geography`
    : undefined;

  if (filters.categoryIds?.length) where.push(Prisma.sql`l."categoryId" = ANY(${filters.categoryIds})`);
  if (filters.radiusKm && originPoint) {
    where.push(Prisma.sql`ST_DWithin(l."geo", ${originPoint}, ${filters.radiusKm * 1000})`);
  } else {
    if (filters.regionId) where.push(Prisma.sql`l."regionId" = ${filters.regionId}`);
    if (filters.districtId) where.push(Prisma.sql`l."districtId" = ${filters.districtId}`);
    if (filters.localityId) where.push(Prisma.sql`l."localityId" = ${filters.localityId}`);
  }
  if (filters.priceMin != null) where.push(Prisma.sql`l."priceUzs" >= ${BigInt(filters.priceMin)}`);
  if (filters.priceMax != null) where.push(Prisma.sql`l."priceUzs" <= ${BigInt(filters.priceMax)}`);
  if (filters.condition) where.push(Prisma.sql`l."condition" = ${filters.condition}::"ItemCondition"`);
  if (filters.sellerId) where.push(Prisma.sql`l."sellerId" = ${filters.sellerId}::uuid`);
  if (filters.excludeId) where.push(Prisma.sql`l."id" <> ${filters.excludeId}::uuid`);
  if (filters.viewerId) {
    where.push(Prisma.sql`NOT EXISTS (
      SELECT 1 FROM "Block" b WHERE b."blockerId" = ${filters.viewerId}::uuid AND b."blockedId" = l."sellerId")`);
  }
  for (const token of searchTokens(filters.text ?? '').slice(0, 6)) {
    // Tokens are normalized to [a-z0-9]; trigram word similarity gives typo tolerance.
    where.push(Prisma.sql`(l."searchText" LIKE ${`%${token}%`} OR ${token} <% l."searchText")`);
  }

  const distance = originPoint ? Prisma.sql`ST_Distance(l."geo", ${originPoint}) / 1000.0` : Prisma.sql`NULL::float8`;
  let order: Prisma.Sql;
  let offset = 0;

  if (sort === 'newest') {
    const keyset = decodeCursor<{ t: string; id: string }>(cursor);
    if (keyset) {
      const t = new Date(keyset.t);
      if (Number.isNaN(t.getTime())) throw AppError.validation('Invalid cursor');
      where.push(Prisma.sql`(l."publishedAt", l."id") < (${t}, ${keyset.id}::uuid)`);
    }
    order = Prisma.sql`l."publishedAt" DESC, l."id" DESC`;
  } else {
    offset = Number(decodeCursor<{ o: number }>(cursor)?.o ?? 0);
    if (!Number.isInteger(offset) || offset < 0 || offset > MAX_OFFSET) throw AppError.validation('Invalid cursor');
    order = {
      priceAsc: Prisma.sql`l."priceUzs" ASC NULLS LAST, l."id" ASC`,
      priceDesc: Prisma.sql`l."priceUzs" DESC NULLS LAST, l."id" ASC`,
      popular: Prisma.sql`(l."viewCount" + 20 * l."favoriteCount") DESC, l."publishedAt" DESC`,
      nearest: originPoint ? Prisma.sql`l."geo" <-> ${originPoint}, l."id"` : Prisma.sql`l."publishedAt" DESC, l."id" DESC`,
    }[sort];
  }

  const sql = Prisma.sql`
    SELECT l."id", ${distance} AS distance_km, l."publishedAt" AS published_at
    FROM "Listing" l
    WHERE ${Prisma.join(where, ' AND ')}
    ORDER BY ${order}
    LIMIT ${take + 1} OFFSET ${offset}`;

  const nextCursor = (rows: Array<FeedRow & { published_at: Date }>): string | null => {
    if (rows.length <= take) return null;
    if (sort === 'newest') {
      const last = rows[take - 1]!;
      return encodeCursor({ t: last.published_at.toISOString(), id: last.id });
    }
    return offset + take > MAX_OFFSET ? null : encodeCursor({ o: offset + take });
  };

  return { sql, nextCursor };
}
