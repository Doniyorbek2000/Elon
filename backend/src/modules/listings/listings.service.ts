import { Injectable, Logger } from '@nestjs/common';
import {
  CategoryKind,
  Currency,
  ItemCondition,
  ListingStatus,
  MediaPurpose,
  ModerationAction,
  NotificationType,
  Placement,
  PriceMode,
  Prisma,
  ReportTarget,
} from '@prisma/client';

import { env } from '../../config/env';
import { AuthUser } from '../../common/auth.decorators';
import { assessPrice, assessText, hasBlocking, requiresModeration } from '../../common/content-risk';
import { AppError } from '../../common/errors';
import { Page, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { buildSearchText, dbEnum } from '../../common/text';
import { PresenceService } from '../../infra/presence.service';
import { PrismaService } from '../../infra/prisma.service';
import { QueueService } from '../../infra/queues';
import { EntitlementService } from '../monetization/entitlements.service';
import { AnalyticsService } from '../business/analytics.service';
import { MonetizationConfig } from '../monetization/config.service';
import { PromotionService } from '../monetization/promotion.service';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { RedisService } from '../../infra/redis.service';
import { CategoriesService } from '../categories/categories.service';
import { LocationsService } from '../locations/locations.service';
import { MediaService } from '../media/media.service';
import { NotificationsService } from '../notifications/notifications.service';
import { FeedFilters, FeedRow, buildFeedQuery } from './listing-feed.query';
import {
  listingCardSelect,
  listingDetailSelect,
  presentListingCard,
  presentListingDetail,
} from './listing.presenter';
import {
  CreateListingDto,
  FeaturedQuery,
  FeedQuery,
  MAX_LISTING_PHOTOS,
  MoneyDto,
  MyListingsQuery,
  UpdateListingDto,
} from './listings.dto';

/** Owner-initiated transitions. Moderation transitions live in `moderate()`. */
const OWNER_TRANSITIONS: Record<ListingStatus, ListingStatus[]> = {
  DRAFT: [ListingStatus.ARCHIVED],
  PENDING_REVIEW: [ListingStatus.ARCHIVED],
  ACTIVE: [ListingStatus.RESERVED, ListingStatus.SOLD, ListingStatus.ARCHIVED],
  RESERVED: [ListingStatus.ACTIVE, ListingStatus.SOLD, ListingStatus.ARCHIVED],
  SOLD: [ListingStatus.ACTIVE, ListingStatus.ARCHIVED],
  EXPIRED: [ListingStatus.ACTIVE, ListingStatus.ARCHIVED],
  REJECTED: [ListingStatus.ARCHIVED],
  ARCHIVED: [ListingStatus.ACTIVE],
};

@Injectable()
export class ListingsService {
  private readonly logger = new Logger(ListingsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly categories: CategoriesService,
    private readonly locations: LocationsService,
    private readonly media: MediaService,
    private readonly notifications: NotificationsService,
    private readonly presence: PresenceService,
    private readonly limiter: RateLimiterService,
    private readonly redis: RedisService,
    private readonly queues: QueueService,
    private readonly entitlements: EntitlementService,
    private readonly promotions: PromotionService,
    private readonly config: MonetizationConfig,
    private readonly analytics: AnalyticsService,
  ) {}

  // ─────────────────────────────────────────────────────────────── reads

  private async feedFilters(query: FeedQuery, viewer?: AuthUser): Promise<FeedFilters> {
    const sort = query.sort ?? 'newest';
    const radiusKm = query.radius;
    let origin: { lat: number; lng: number } | undefined;
    if (query.lat != null && query.lng != null) origin = { lat: query.lat, lng: query.lng };
    else if (radiusKm || sort === 'nearest')
      origin = await this.locations.origin(query.region, query.district);
    if (radiusKm && !origin)
      throw AppError.validation('Radius search needs a region, district or coordinates');
    return {
      text: query.q,
      categoryIds: query.category ? await this.categories.subtreeIds(query.category) : undefined,
      regionId: query.region,
      districtId: query.district,
      localityId: query.locality,
      origin,
      radiusKm,
      priceMin: query.priceMin,
      priceMax: query.priceMax,
      condition: query.condition ? (dbEnum(query.condition) as ItemCondition) : undefined,
      sellerId: query.seller,
      viewerId: viewer?.userId,
    };
  }

  async feed(query: FeedQuery, viewer?: AuthUser) {
    const take = pageSize(query.limit);
    const { sql, nextCursor } = buildFeedQuery(
      await this.feedFilters(query, viewer),
      query.sort ?? 'newest',
      query.cursor,
      take,
    );
    const rows = await this.prisma.$queryRaw<Array<FeedRow & { published_at: Date }>>(sql);
    const pageRows = rows.slice(0, take);
    const items = await this.hydrate(pageRows, viewer);
    return new Page(items, nextCursor(rows));
  }

  /**
   * Paid TOP/VIP listings that match the *same* filters, for the labeled block
   * above the organic feed. Limited slots, VIP first, fair hourly rotation.
   */
  async promoted(query: FeedQuery, viewer?: AuthUser) {
    const [top, vip] = await Promise.all([
      this.config.enabled('listingTop'),
      this.config.enabled('listingVip'),
    ]);
    if (!top && !vip) return [];
    const { promotedSlots } = await this.config.setting('ranking');
    const { sql } = buildFeedQuery(
      { ...(await this.feedFilters(query, viewer)), promotedOnly: true },
      'newest',
      undefined,
      promotedSlots,
    );
    const rows = await this.prisma.$queryRaw<Array<FeedRow & { published_at: Date }>>(sql);
    return this.hydrate(rows.slice(0, promotedSlots), viewer);
  }

  /** Featured placement block (home / category / region) with explicit scope rules. */
  async featured(query: FeaturedQuery, viewer?: AuthUser) {
    if (!(await this.config.enabled('featuredListings'))) return [];
    const { featuredSlots } = await this.config.setting('ranking');
    const placement = dbEnum(query.placement) as Placement;
    const ids = await this.promotions.featuredIds(
      'LISTING_FEATURED',
      placement,
      {
        regionId: query.region,
        categoryIds: query.category ? await this.categories.subtreeIds(query.category) : undefined,
      },
      featuredSlots,
    );
    if (!ids.length) return [];
    const { sql } = buildFeedQuery(
      { onlyIds: ids, viewerId: viewer?.userId },
      'newest',
      undefined,
      featuredSlots,
    );
    const rows = await this.prisma.$queryRaw<Array<FeedRow & { published_at: Date }>>(sql);
    const order = new Map(ids.map((id, index) => [id, index]));
    rows.sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0));
    return this.hydrate(rows.slice(0, featuredSlots), viewer);
  }

  private async hydrate(rows: FeedRow[], viewer?: AuthUser) {
    if (rows.length === 0) return [];
    const ids = rows.map((r) => r.id);
    const [listings, favorites] = await Promise.all([
      this.prisma.listing.findMany({ where: { id: { in: ids } }, select: listingCardSelect }),
      viewer
        ? this.prisma.favorite.findMany({
            where: { userId: viewer.userId, listingId: { in: ids } },
            select: { listingId: true },
          })
        : Promise.resolve([]),
    ]);
    const byId = new Map(listings.map((l) => [l.id, l]));
    const favoriteIds = new Set(favorites.map((f) => f.listingId));
    const badges = await this.promotions.badges('LISTING', ids);
    return rows
      .map((row) => {
        const listing = byId.get(row.id);
        return listing
          ? presentListingCard(listing, {
              isFavorite: favoriteIds.has(row.id),
              distanceKm: row.distance_km,
              badges: badges.get(row.id),
            })
          : undefined;
      })
      .filter((x): x is ReturnType<typeof presentListingCard> => x !== undefined);
  }

  async detail(id: string, viewer?: AuthUser, viewerKey?: string) {
    const row = await this.prisma.listing.findFirst({
      where: { id, deletedAt: null },
      select: listingDetailSelect,
    });
    if (!row) throw AppError.notFound('Listing');
    const isOwner = viewer?.userId === row.sellerId;
    const publiclyVisible =
      row.status === ListingStatus.ACTIVE ||
      row.status === ListingStatus.RESERVED ||
      row.status === ListingStatus.SOLD;
    if (!publiclyVisible && !isOwner && !this.isModerator(viewer)) throw AppError.notFound('Listing');

    if (!isOwner && viewerKey && row.status === ListingStatus.ACTIVE) await this.countView(id, viewerKey);
    const [favorite, sellerOnline, sellerActiveListings, badges] = await Promise.all([
      viewer ? this.prisma.favorite.count({ where: { userId: viewer.userId, listingId: id } }) : 0,
      this.presence.isOnline(row.sellerId),
      this.prisma.listing.count({
        where: { sellerId: row.sellerId, status: ListingStatus.ACTIVE, deletedAt: null },
      }),
      this.promotions.badges('LISTING', [id]),
    ]);
    return presentListingDetail(row, env().WEB_BASE_URL, {
      badges: badges.get(id),
      isFavorite: favorite > 0,
      isOwner,
      sellerOnline,
      sellerActiveListings,
    });
  }

  /** One view per viewer per listing per day; counted without a write per request. */
  private async countView(id: string, viewerKey: string): Promise<void> {
    const fresh = await this.redis.client.set(`view:listing:${id}:${viewerKey}`, '1', 'EX', 86400, 'NX');
    if (fresh === 'OK') {
      await this.prisma.listing.update({ where: { id }, data: { viewCount: { increment: 1 } } });
      await this.analytics.bump(id, 'views');
    }
  }

  async similar(id: string, viewer?: AuthUser) {
    const listing = await this.prisma.listing.findFirst({
      where: { id, deletedAt: null },
      select: { categoryId: true, regionId: true },
    });
    if (!listing) throw AppError.notFound('Listing');
    const root = await this.categories.root(listing.categoryId);
    const { sql } = buildFeedQuery(
      {
        categoryIds: await this.categories.subtreeIds(root.id),
        regionId: listing.regionId,
        excludeId: id,
        viewerId: viewer?.userId,
      },
      'newest',
      undefined,
      8,
    );
    const rows = await this.prisma.$queryRaw<FeedRow[]>(sql);
    return this.hydrate(rows.slice(0, 8), viewer);
  }

  async mine(userId: string, query: MyListingsQuery) {
    const take = pageSize(query.limit);
    const rows = await this.prisma.listing.findMany({
      where: {
        sellerId: userId,
        deletedAt: null,
        ...(query.status ? { status: dbEnum(query.status) as ListingStatus } : {}),
        ...keysetWhere(query.cursor, 'updatedAt'),
      },
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
      select: { ...listingCardSelect, updatedAt: true },
    });
    const page = keysetPage(rows, take, (r) => r.updatedAt);
    return new Page(
      page.items.map((row) => presentListingCard(row)),
      page.nextCursor,
    );
  }

  // ────────────────────────────────────────────────────────────── writes

  async create(user: AuthUser, dto: CreateListingDto) {
    await this.limiter.consume(`listing:create:${user.userId}`, 30, 24 * 3600);
    const category = await this.categories.get(dto.categoryId);
    if (category.kind !== CategoryKind.MARKETPLACE || !(await this.categories.isLeaf(category.id))) {
      throw AppError.validation('Choose a specific marketplace category', { field: 'categoryId' });
    }
    const attributes = await this.categories.validateAttributes(dto.categoryId, dto.attributes ?? {});
    const place = await this.locations.resolvePlace(dto.place);
    const mediaIds = await this.media.assertOwned(user.userId, dto.mediaIds, [MediaPurpose.LISTING]);
    await this.entitlements.assertCanCreateListing(user.userId, mediaIds.length);
    const price = this.normalizePrice(dto.price ?? null);

    const listing = await this.prisma.listing.create({
      data: {
        sellerId: user.userId,
        categoryId: dto.categoryId,
        title: dto.title,
        description: dto.description,
        priceAmount: price.amount,
        currency: price.currency,
        priceUzs: price.uzs,
        negotiable: dto.negotiable ?? false,
        condition: dto.condition ? (dbEnum(dto.condition) as ItemCondition) : null,
        status: ListingStatus.DRAFT,
        ...place,
        searchText: buildSearchText(dto.title, dto.description, category.name),
        attributes: { create: attributes },
        media: { create: mediaIds.map((mediaId, position) => ({ mediaId, position })) },
      },
      select: { id: true },
    });
    if (dto.publish !== false) return this.publish(user, listing.id);
    return this.detail(listing.id, user);
  }

  async update(user: AuthUser, id: string, dto: UpdateListingDto) {
    const listing = await this.owned(user, id);
    if (listing.status === ListingStatus.PENDING_REVIEW)
      throw AppError.invalidState('Listing is under review');
    const categoryId = dto.categoryId ?? listing.categoryId;
    const category = await this.categories.get(categoryId);
    if (category.kind !== CategoryKind.MARKETPLACE || !(await this.categories.isLeaf(category.id))) {
      throw AppError.validation('Choose a specific marketplace category', { field: 'categoryId' });
    }

    const data: Prisma.ListingUncheckedUpdateInput = {
      categoryId,
      title: dto.title,
      description: dto.description,
      negotiable: dto.negotiable,
    };
    if (dto.condition !== undefined)
      data.condition = dto.condition ? (dbEnum(dto.condition) as ItemCondition) : null;
    if (dto.price !== undefined) {
      const price = this.normalizePrice(dto.price);
      Object.assign(data, { priceAmount: price.amount, currency: price.currency, priceUzs: price.uzs });
    }
    if (dto.place) Object.assign(data, await this.locations.resolvePlace(dto.place));
    const attributes =
      dto.attributes !== undefined || dto.categoryId !== undefined
        ? await this.categories.validateAttributes(categoryId, dto.attributes ?? {})
        : undefined;
    const mediaIds = dto.mediaIds
      ? await this.media.assertOwned(user.userId, dto.mediaIds, [MediaPurpose.LISTING])
      : undefined;
    if (mediaIds) await this.entitlements.assertPhotoLimit(user.userId, mediaIds.length);
    data.searchText = buildSearchText(
      dto.title ?? listing.title,
      dto.description ?? listing.description,
      category.name,
    );

    await this.prisma.$transaction(async (tx) => {
      await tx.listing.update({ where: { id }, data });
      if (attributes) {
        await tx.listingAttribute.deleteMany({ where: { listingId: id } });
        await tx.listingAttribute.createMany({ data: attributes.map((a) => ({ ...a, listingId: id })) });
      }
      if (mediaIds) {
        await tx.listingMedia.deleteMany({ where: { listingId: id } });
        await tx.listingMedia.createMany({
          data: mediaIds.map((mediaId, position) => ({ listingId: id, mediaId, position })),
        });
      }
    });

    // Content edits on a live listing are re-screened.
    if (listing.status === ListingStatus.ACTIVE || listing.status === ListingStatus.RESERVED) {
      const signals = await this.screen(id);
      if (requiresModeration(signals))
        await this.sendToReview(
          id,
          signals.map((s) => s.code),
        );
    }
    return this.detail(id, user);
  }

  /** DRAFT/REJECTED → ACTIVE, or PENDING_REVIEW when heuristics flag it. */
  async publish(user: AuthUser, id: string) {
    const listing = await this.owned(user, id);
    if (listing.status !== ListingStatus.DRAFT && listing.status !== ListingStatus.REJECTED) {
      throw AppError.invalidState(`Cannot publish a listing in status ${listing.status}`);
    }
    await this.entitlements.assertCanActivateListing(user.userId, id);
    await this.assertPublishable(id);
    const signals = await this.screen(id);
    if (hasBlocking(signals)) {
      throw AppError.validation('Remove card numbers from the listing', {
        riskFlags: signals.map((s) => s.code),
      });
    }
    if (requiresModeration(signals)) {
      await this.sendToReview(
        id,
        signals.map((s) => s.code),
      );
    } else {
      await this.activate(id);
    }
    return this.detail(id, user);
  }

  async changeStatus(user: AuthUser, id: string, target: string) {
    const listing = await this.owned(user, id);
    const next = dbEnum(target) as ListingStatus;
    if (!OWNER_TRANSITIONS[listing.status].includes(next)) {
      throw AppError.invalidState(`Cannot move from ${listing.status} to ${next}`);
    }
    if (next === ListingStatus.ACTIVE && listing.status !== ListingStatus.RESERVED) {
      // Re-listing (sold/expired/archived) goes through publication checks again.
      await this.entitlements.assertCanActivateListing(user.userId, id);
      await this.assertPublishable(id);
      const signals = await this.screen(id);
      if (requiresModeration(signals)) {
        await this.sendToReview(
          id,
          signals.map((s) => s.code),
        );
        return this.detail(id, user);
      }
      await this.activate(id);
      return this.detail(id, user);
    }
    await this.prisma.listing.update({
      where: { id },
      data: { status: next, soldAt: next === ListingStatus.SOLD ? new Date() : undefined },
    });
    return this.detail(id, user);
  }

  /** Share taps (deduplicated per viewer and day) for seller analytics. */
  async recordShare(id: string, viewerKey: string) {
    await this.limiter.consume(`share:${viewerKey}`, 60, 3600);
    const listing = await this.prisma.listing.findFirst({
      where: { id, deletedAt: null, status: ListingStatus.ACTIVE },
      select: { id: true },
    });
    if (!listing) throw AppError.notFound('Listing');
    const fresh = await this.redis.client.set(`share:listing:${id}:${viewerKey}`, '1', 'EX', 86400, 'NX');
    if (fresh === 'OK') await this.analytics.bump(id, 'shares');
    return { ok: true };
  }

  async remove(user: AuthUser, id: string): Promise<void> {
    await this.owned(user, id);
    await this.prisma.listing.update({
      where: { id },
      data: { deletedAt: new Date(), status: ListingStatus.ARCHIVED },
    });
  }

  /** Seller phone on explicit request only; rate-limited and respecting privacy. */
  async contact(viewer: AuthUser, id: string) {
    await this.limiter.consume(`contact:${viewer.userId}`, 40, 3600);
    const listing = await this.prisma.listing.findFirst({
      where: { id, deletedAt: null, status: { in: [ListingStatus.ACTIVE, ListingStatus.RESERVED] } },
      select: { seller: { select: { id: true, phone: true, profile: { select: { showPhone: true } } } } },
    });
    if (!listing) throw AppError.notFound('Listing');
    if (!listing.seller.profile?.showPhone) throw AppError.forbidden('The seller prefers chat');
    await this.analytics.bump(id, 'contacts');
    return { phone: listing.seller.phone };
  }

  // ─────────────────────────────────────────────────────────── moderation

  async moderationQueue(cursor?: string, limit?: number) {
    const take = pageSize(limit);
    const rows = await this.prisma.listing.findMany({
      where: { status: ListingStatus.PENDING_REVIEW, deletedAt: null, ...keysetWhere(cursor, 'updatedAt') },
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
      select: { ...listingDetailSelect, updatedAt: true },
    });
    const page = keysetPage(rows, take, (r) => r.updatedAt);
    return new Page(
      page.items.map((r) => presentListingDetail(r, env().WEB_BASE_URL, { isOwner: true })),
      page.nextCursor,
    );
  }

  async moderate(moderator: AuthUser, id: string, decision: 'approve' | 'reject', reason?: string) {
    const listing = await this.prisma.listing.findFirst({ where: { id, deletedAt: null } });
    if (!listing) throw AppError.notFound('Listing');
    if (listing.status !== ListingStatus.PENDING_REVIEW)
      throw AppError.invalidState('Listing is not awaiting review');
    if (decision === 'approve') await this.activate(id);
    else {
      await this.prisma.listing.update({
        where: { id },
        data: { status: ListingStatus.REJECTED, rejectReason: reason },
      });
    }
    await this.prisma.moderationEvent.create({
      data: {
        targetType: ReportTarget.LISTING,
        targetId: id,
        action: decision === 'approve' ? ModerationAction.APPROVED : ModerationAction.REJECTED,
        actorId: moderator.userId,
        reason,
      },
    });
    await this.notifications.notify(listing.sellerId, {
      type: NotificationType.LISTING_STATUS,
      title: decision === 'approve' ? 'E’loningiz faollashtirildi' : 'E’loningiz rad etildi',
      body:
        decision === 'approve'
          ? `«${listing.title}» endi hammaga ko‘rinadi.`
          : `«${listing.title}»: ${reason ?? 'qoidalarga mos emas'}`,
      route: `/listing/${id}`,
      data: { listingId: id },
    });
    return { id, status: decision === 'approve' ? 'active' : 'rejected' };
  }

  /** Expires listings past their TTL. Called by the maintenance worker. */
  async expireStale(): Promise<number> {
    const result = await this.prisma.listing.updateMany({
      where: { status: ListingStatus.ACTIVE, expiresAt: { lt: new Date() } },
      data: { status: ListingStatus.EXPIRED },
    });
    return result.count;
  }

  // ────────────────────────────────────────────────────────────── helpers

  private isModerator(viewer?: AuthUser): boolean {
    return viewer?.role === 'MODERATOR' || viewer?.role === 'ADMIN';
  }

  /** Loads a listing only if the caller owns it; otherwise 404 (no existence leak). */
  private async owned(user: AuthUser, id: string) {
    const listing = await this.prisma.listing.findFirst({ where: { id, deletedAt: null } });
    if (!listing || listing.sellerId !== user.userId) throw AppError.notFound('Listing');
    return listing;
  }

  private normalizePrice(price: MoneyDto | null): {
    amount: bigint | null;
    currency: Currency;
    uzs: bigint | null;
  } {
    if (!price) return { amount: null, currency: Currency.UZS, uzs: null };
    const currency = price.currency === 'usd' ? Currency.USD : Currency.UZS;
    const amount = BigInt(price.amount);
    const uzs = currency === Currency.USD ? amount * BigInt(Math.round(env().USD_TO_UZS_RATE)) : amount;
    return { amount, currency, uzs };
  }

  private async assertPublishable(id: string): Promise<void> {
    const listing = await this.prisma.listing.findUniqueOrThrow({
      where: { id },
      include: { _count: { select: { media: true } } },
    });
    const schema = await this.categories.effectiveSchema(listing.categoryId);
    const errors: Record<string, string> = {};
    if (schema.photosRequired && listing._count.media === 0)
      errors.mediaIds = 'At least one photo is required';
    if (listing._count.media > MAX_LISTING_PHOTOS) errors.mediaIds = `At most ${MAX_LISTING_PHOTOS} photos`;
    if (schema.priceMode === PriceMode.REQUIRED && listing.priceAmount == null && !listing.negotiable) {
      errors.price = 'Price is required unless negotiable';
    }
    if (listing.currency === Currency.USD && !schema.allowUsd)
      errors.price = 'This category accepts so‘m only';
    if (Object.keys(errors).length) throw AppError.validation('Listing is incomplete', { fields: errors });
  }

  private async screen(id: string) {
    const listing = await this.prisma.listing.findUniqueOrThrow({ where: { id } });
    const reference = await this.referencePrice(listing.categoryId);
    return [...assessText(listing.title, listing.description), ...assessPrice(listing.priceUzs, reference)];
  }

  /** Average active price in the category (needs ≥ 5 samples to be meaningful). */
  private async referencePrice(categoryId: string): Promise<bigint | null> {
    const stats = await this.prisma.listing.aggregate({
      where: { categoryId, status: ListingStatus.ACTIVE, priceUzs: { not: null } },
      _avg: { priceUzs: true },
      _count: { _all: true },
    });
    if (stats._count._all < 5 || stats._avg.priceUzs == null) return null;
    return BigInt(Math.round(stats._avg.priceUzs));
  }

  private async activate(id: string): Promise<void> {
    const now = new Date();
    await this.prisma.listing.update({
      where: { id },
      data: {
        status: ListingStatus.ACTIVE,
        publishedAt: now,
        rankedAt: now,
        expiresAt: new Date(now.getTime() + env().LISTING_TTL_DAYS * 24 * 3600 * 1000),
        flagged: false,
        riskFlags: [],
        rejectReason: null,
      },
    });
  }

  private async sendToReview(id: string, flags: string[]): Promise<void> {
    await this.prisma.listing.update({
      where: { id },
      data: { status: ListingStatus.PENDING_REVIEW, flagged: true, riskFlags: flags },
    });
    await this.prisma.moderationEvent.create({
      data: {
        targetType: ReportTarget.LISTING,
        targetId: id,
        action: ModerationAction.AUTO_FLAGGED,
        reason: flags.join(','),
      },
    });
    await this.queues.moderation({ targetType: 'LISTING', targetId: id, reason: flags.join(',') });
    this.logger.log({ listingId: id, flags }, 'Listing sent to moderation');
  }
}
