import { Injectable } from '@nestjs/common';
import {
  Availability,
  Currency,
  MediaPurpose,
  NotificationType,
  OfferingStatus,
  PricingType,
  Prisma,
  ProviderStatus,
  ReviewStatus,
} from '@prisma/client';

import { AuthUser } from '../../common/auth.decorators';
import { assessText, hasBlocking } from '../../common/content-risk';
import { AppError } from '../../common/errors';
import { Page, decodeCursor, encodeCursor, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { presentUser, publicUserSelect } from '../../common/presenters';
import { apiEnum, buildSearchText, dbEnum, searchTokens } from '../../common/text';
import { PresenceService } from '../../infra/presence.service';
import { PrismaService } from '../../infra/prisma.service';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { LocationsService } from '../locations/locations.service';
import { MediaService } from '../media/media.service';
import { NotificationsService } from '../notifications/notifications.service';
import {
  offeringSelect,
  presentOffering,
  presentProviderCard,
  presentProviderDetail,
  providerCardSelect,
  providerDetailSelect,
} from './provider.presenter';
import { OfferingDto, PortfolioDto, ProviderDto, ProviderSearchQuery, ReviewDto } from './services.dto';

@Injectable()
export class ServicesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly locations: LocationsService,
    private readonly media: MediaService,
    private readonly presence: PresenceService,
    private readonly notifications: NotificationsService,
    private readonly limiter: RateLimiterService,
  ) {}

  async categories() {
    const rows = await this.prisma.serviceCategory.findMany({
      where: { isActive: true },
      orderBy: { sortOrder: 'asc' },
    });
    return rows.map((c) => ({ id: c.id, name: c.name, iconKey: c.iconKey, tone: c.tone }));
  }

  // ─────────────────────────────────────────────────────────── discovery

  /** Filters shared by organic results and the paid block. */
  private async providerFilters(query: ProviderSearchQuery, viewer?: AuthUser) {
    const and: Prisma.ServiceProviderWhereInput[] = [{ status: ProviderStatus.ACTIVE, deletedAt: null }];
    if (query.category) and.push({ categories: { some: { categoryId: query.category } } });

    const origin =
      query.lat != null && query.lng != null
        ? { lat: query.lat, lng: query.lng }
        : query.radius || query.sort === 'nearest'
          ? await this.locations.origin(query.region, query.district)
          : undefined;
    let distanceById = new Map<string, number>();
    if (query.radius) {
      if (!origin) throw AppError.validation('Radius search needs a region, district or coordinates');
      const rows = await this.prisma.$queryRaw<Array<{ id: string; km: number }>>`
        SELECT p."id", ST_Distance(p."geo", ST_SetSRID(ST_MakePoint(${origin.lng}, ${origin.lat}), 4326)::geography) / 1000 AS km
        FROM "ServiceProvider" p
        WHERE p."status" = 'ACTIVE' AND p."deletedAt" IS NULL
          AND ST_DWithin(p."geo", ST_SetSRID(ST_MakePoint(${origin.lng}, ${origin.lat}), 4326)::geography, ${query.radius * 1000})
        LIMIT 5000`;
      distanceById = new Map(rows.map((r) => [r.id, r.km]));
      and.push({ id: { in: [...distanceById.keys()] } });
    } else if (query.region) {
      // A provider matches an area if based there or explicitly serving it.
      const areaMatch: Prisma.ServiceAreaWhereInput = query.district
        ? { regionId: query.region, OR: [{ districtId: query.district }, { districtId: null }] }
        : { regionId: query.region };
      and.push({
        OR: [
          { regionId: query.region, ...(query.district ? { districtId: query.district } : {}) },
          { areas: { some: areaMatch } },
        ],
      });
    }
    if (query.filter === 'topRated') and.push({ ratingAvg: { gte: 4.8 }, reviewCount: { gte: 3 } });
    for (const token of searchTokens(query.q ?? '').slice(0, 6)) {
      and.push({
        OR: [
          { searchText: { contains: token } },
          {
            offerings: {
              some: { searchText: { contains: token }, status: OfferingStatus.ACTIVE, deletedAt: null },
            },
          },
        ],
      });
    }
    if (viewer) and.push({ user: { blocksReceived: { none: { blockerId: viewer.userId } } } });
    return { and, distanceById };
  }

  async search(query: ProviderSearchQuery, viewer?: AuthUser) {
    const take = pageSize(query.limit);
    const { and, distanceById } = await this.providerFilters(query, viewer);

    const offset = Number(decodeCursor<{ o: number }>(query.cursor)?.o ?? 0);
    if (!Number.isInteger(offset) || offset < 0 || offset > 2000) throw AppError.validation('Invalid cursor');
    const orderBy: Prisma.ServiceProviderOrderByWithRelationInput[] =
      query.sort === 'newest'
        ? [{ createdAt: 'desc' }, { id: 'asc' }]
        : [{ ratingAvg: 'desc' }, { reviewCount: 'desc' }, { id: 'asc' }];
    let rows = await this.prisma.serviceProvider.findMany({
      where: { AND: and },
      select: providerCardSelect,
      orderBy,
      skip: offset,
      take: take + 1,
    });
    const nextCursor = rows.length > take ? encodeCursor({ o: offset + take }) : null;
    rows = rows.slice(0, take);
    if (query.sort === 'nearest' && distanceById.size)
      rows.sort((a, b) => (distanceById.get(a.id) ?? 0) - (distanceById.get(b.id) ?? 0));

    const [online, favorites] = await Promise.all([
      this.presence.onlineMany(rows.map((r) => r.userId)),
      viewer
        ? this.prisma.favorite.findMany({
            where: { userId: viewer.userId, providerId: { in: rows.map((r) => r.id) } },
            select: { providerId: true },
          })
        : Promise.resolve([]),
    ]);
    const saved = new Set(favorites.map((f) => f.providerId));
    let items = rows.map((r) =>
      presentProviderCard(r, {
        isOnline: online.has(r.userId),
        isFavorite: saved.has(r.id),
        distanceKm: distanceById.get(r.id) ?? null,
      }),
    );
    // Presence is ephemeral (Redis), so "online" narrows the current page.
    if (query.filter === 'online') items = items.filter((i) => i.profile.isOnline);
    return new Page(items, nextCursor);
  }

  async detail(id: string, viewer?: AuthUser) {
    const provider = await this.prisma.serviceProvider.findFirst({
      where: { id, deletedAt: null },
      select: providerDetailSelect,
    });
    if (!provider) throw AppError.notFound('Provider');
    const isOwner = viewer?.userId === provider.userId;
    if (provider.status !== ProviderStatus.ACTIVE && !isOwner) throw AppError.notFound('Provider');
    const [isOnline, favorite, reviews] = await Promise.all([
      this.presence.isOnline(provider.userId),
      viewer ? this.prisma.favorite.count({ where: { userId: viewer.userId, providerId: id } }) : 0,
      this.reviews(id, undefined, 5),
    ]);
    return {
      ...presentProviderDetail(provider, {
        isOnline,
        isFavorite: favorite > 0,
        isOwner,
      }),
      reviews: reviews.items,
    };
  }

  async contact(viewer: AuthUser, id: string) {
    await this.limiter.consume(`contact:${viewer.userId}`, 40, 3600);
    const provider = await this.prisma.serviceProvider.findFirst({
      where: { id, deletedAt: null, status: ProviderStatus.ACTIVE },
      select: { user: { select: { phone: true, profile: { select: { showPhone: true } } } } },
    });
    if (!provider) throw AppError.notFound('Provider');
    if (!provider.user.profile?.showPhone) throw AppError.forbidden('The provider prefers chat');
    return { phone: provider.user.phone };
  }

  // ──────────────────────────────────────────────────── own provider profile

  private async own(userId: string) {
    const provider = await this.prisma.serviceProvider.findFirst({ where: { userId, deletedAt: null } });
    if (!provider) throw AppError.notFound('Provider profile');
    return provider;
  }

  async mine(user: AuthUser) {
    const provider = await this.prisma.serviceProvider.findFirst({
      where: { userId: user.userId, deletedAt: null },
      select: { id: true },
    });
    return provider ? this.detail(provider.id, user) : null;
  }

  async upsert(user: AuthUser, dto: ProviderDto) {
    if (hasBlocking(assessText(dto.profession, dto.description)))
      throw AppError.validation('Remove card numbers from the description');
    const categories = await this.prisma.serviceCategory.findMany({
      where: { id: { in: dto.categoryIds }, isActive: true },
    });
    if (categories.length !== new Set(dto.categoryIds).size)
      throw AppError.validation('Unknown service category', { field: 'categoryIds' });
    const place = await this.locations.resolvePlace(dto.place);
    const areas: Array<{ regionId: string; districtId: string | null }> = [];
    for (const area of dto.areas ?? []) {
      const resolved = await this.locations.resolvePlace({
        regionId: area.regionId,
        districtId: area.districtId,
      });
      areas.push({ regionId: resolved.regionId, districtId: resolved.districtId });
    }
    const data = {
      displayName: dto.displayName,
      profession: dto.profession,
      description: dto.description,
      experienceYears: dto.experienceYears ?? 0,
      availability: dto.availability ? (dbEnum(dto.availability) as Availability) : Availability.AVAILABLE,
      regionId: place.regionId,
      districtId: place.districtId,
      lat: place.lat,
      lng: place.lng,
      searchText: buildSearchText(
        dto.displayName,
        dto.profession,
        dto.description,
        categories.map((c) => c.name).join(' '),
      ),
    };
    await this.prisma.$transaction(async (tx) => {
      const provider = await tx.serviceProvider.upsert({
        where: { userId: user.userId },
        create: { ...data, userId: user.userId },
        update: { ...data, deletedAt: null },
      });
      await tx.serviceProviderCategory.deleteMany({ where: { providerId: provider.id } });
      await tx.serviceProviderCategory.createMany({
        data: dto.categoryIds.map((categoryId) => ({ providerId: provider.id, categoryId })),
      });
      await tx.serviceArea.deleteMany({ where: { providerId: provider.id } });
      const unique = new Map(areas.map((a) => [`${a.regionId}:${a.districtId ?? ''}`, a]));
      await tx.serviceArea.createMany({
        data: [...unique.values()].map((a) => ({ ...a, providerId: provider.id })),
      });
    });
    return this.mine(user);
  }

  async setStatus(user: AuthUser, status: string) {
    const provider = await this.own(user.userId);
    if (provider.status === ProviderStatus.SUSPENDED)
      throw AppError.forbidden('Provider profile is suspended');
    await this.prisma.serviceProvider.update({
      where: { id: provider.id },
      data: { status: dbEnum(status) as ProviderStatus },
    });
    return this.mine(user);
  }

  async setPortfolio(user: AuthUser, dto: PortfolioDto) {
    const provider = await this.own(user.userId);
    const ids = await this.media.assertOwned(user.userId, dto.mediaIds, [MediaPurpose.PORTFOLIO]);
    await this.prisma.$transaction([
      this.prisma.portfolioItem.deleteMany({ where: { providerId: provider.id } }),
      this.prisma.portfolioItem.createMany({
        data: ids.map((mediaId, position) => ({ providerId: provider.id, mediaId, position })),
      }),
    ]);
    return this.mine(user);
  }

  private async offeringData(user: AuthUser, dto: OfferingDto) {
    const category = await this.prisma.serviceCategory.findFirst({
      where: { id: dto.categoryId, isActive: true },
    });
    if (!category) throw AppError.validation('Unknown service category', { field: 'categoryId' });
    if (dto.priceFrom != null && dto.priceTo != null && dto.priceTo < dto.priceFrom) {
      throw AppError.validation('priceTo must be ≥ priceFrom', { field: 'priceTo' });
    }
    if (hasBlocking(assessText(dto.title, dto.description ?? '')))
      throw AppError.validation('Remove card numbers from the offering');
    const mediaIds = dto.mediaIds
      ? await this.media.assertOwned(user.userId, dto.mediaIds, [
          MediaPurpose.OFFERING,
          MediaPurpose.PORTFOLIO,
        ])
      : undefined;
    return {
      data: {
        categoryId: dto.categoryId,
        title: dto.title,
        description: dto.description,
        pricingType: dbEnum(dto.pricingType) as PricingType,
        priceFrom: dto.priceFrom ?? null,
        priceTo: dto.priceTo ?? null,
        currency: dto.currency === 'usd' ? Currency.USD : Currency.UZS,
        priceUnit: dto.priceUnit,
        status: dto.status ? (dbEnum(dto.status) as OfferingStatus) : OfferingStatus.ACTIVE,
        searchText: buildSearchText(dto.title, dto.description, category.name),
      },
      mediaIds,
    };
  }

  async createOffering(user: AuthUser, dto: OfferingDto) {
    const provider = await this.own(user.userId);
    const count = await this.prisma.serviceOffering.count({
      where: { providerId: provider.id, deletedAt: null },
    });
    if (count >= 30) throw AppError.validation('At most 30 offerings');
    const { data, mediaIds } = await this.offeringData(user, dto);
    const offering = await this.prisma.serviceOffering.create({
      data: {
        ...data,
        providerId: provider.id,
        media: { create: (mediaIds ?? []).map((mediaId, position) => ({ mediaId, position })) },
      },
      select: offeringSelect,
    });
    await this.linkCategory(provider.id, dto.categoryId);
    return presentOffering(offering);
  }

  async updateOffering(user: AuthUser, id: string, dto: OfferingDto) {
    const provider = await this.own(user.userId);
    const existing = await this.prisma.serviceOffering.findFirst({
      where: { id, providerId: provider.id, deletedAt: null },
    });
    if (!existing) throw AppError.notFound('Offering');
    const { data, mediaIds } = await this.offeringData(user, dto);
    const offering = await this.prisma.$transaction(async (tx) => {
      if (mediaIds) {
        await tx.offeringMedia.deleteMany({ where: { offeringId: id } });
        await tx.offeringMedia.createMany({
          data: mediaIds.map((mediaId, position) => ({ offeringId: id, mediaId, position })),
        });
      }
      return tx.serviceOffering.update({ where: { id }, data, select: offeringSelect });
    });
    await this.linkCategory(provider.id, dto.categoryId);
    return presentOffering(offering);
  }

  async deleteOffering(user: AuthUser, id: string): Promise<void> {
    const provider = await this.own(user.userId);
    const { count } = await this.prisma.serviceOffering.updateMany({
      where: { id, providerId: provider.id, deletedAt: null },
      data: { deletedAt: new Date(), status: OfferingStatus.ARCHIVED },
    });
    if (!count) throw AppError.notFound('Offering');
  }

  private async linkCategory(providerId: string, categoryId: string): Promise<void> {
    await this.prisma.serviceProviderCategory.upsert({
      where: { providerId_categoryId: { providerId, categoryId } },
      create: { providerId, categoryId },
      update: {},
    });
  }

  // ─────────────────────────────────────────────────────────────── reviews

  async reviews(providerId: string, cursor?: string, limit?: number) {
    const take = pageSize(limit);
    const rows = await this.prisma.review.findMany({
      where: { providerId, status: ReviewStatus.PUBLISHED, ...keysetWhere(cursor) },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      include: { author: { select: publicUserSelect } },
      take: take + 1,
    });
    const page = keysetPage(rows, take, (r) => r.createdAt);
    return new Page(
      page.items.map((r) => {
        const author = presentUser(r.author);
        return {
          id: r.id,
          authorId: author.id,
          authorName: author.name,
          authorAvatar: author.avatar,
          rating: r.rating,
          text: r.text,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
        };
      }),
      page.nextCursor,
    );
  }

  /**
   * One review per account per provider (edits replace it). Eligibility: the
   * author must have had a two-way conversation with the provider, which
   * stops drive-by rating manipulation.
   */
  async review(user: AuthUser, providerId: string, dto: ReviewDto) {
    await this.limiter.consume(`review:${user.userId}`, 20, 24 * 3600);
    const provider = await this.prisma.serviceProvider.findFirst({
      where: { id: providerId, deletedAt: null, status: ProviderStatus.ACTIVE },
    });
    if (!provider) throw AppError.notFound('Provider');
    if (provider.userId === user.userId)
      throw new AppError('NOT_ELIGIBLE', 'You cannot review yourself', 403);

    const conversation = await this.prisma.conversation.findFirst({
      where: {
        AND: [
          { participants: { some: { userId: user.userId } } },
          { participants: { some: { userId: provider.userId } } },
          { messages: { some: { senderId: user.userId } } },
          { messages: { some: { senderId: provider.userId } } },
        ],
      },
      select: { id: true },
    });
    if (!conversation) {
      throw new AppError('NOT_ELIGIBLE', 'You can review a provider after chatting with them', 403);
    }

    const review = await this.prisma.$transaction(async (tx) => {
      const saved = await tx.review.upsert({
        where: { authorId_providerId: { authorId: user.userId, providerId } },
        create: { authorId: user.userId, providerId, rating: dto.rating, text: dto.text },
        update: { rating: dto.rating, text: dto.text, status: ReviewStatus.PUBLISHED },
      });
      await this.recompute(tx, providerId);
      return saved;
    });
    await this.notifications.notify(provider.userId, {
      type: NotificationType.REVIEW_RECEIVED,
      title: 'Yangi sharh',
      body: `Sizga ${dto.rating} yulduzli sharh qoldirildi`,
      route: `/provider/${providerId}`,
      data: { providerId, reviewId: review.id },
    });
    return { id: review.id, rating: review.rating, text: review.text, status: apiEnum(review.status) };
  }

  async deleteReview(user: AuthUser, providerId: string): Promise<void> {
    await this.prisma.$transaction(async (tx) => {
      const { count } = await tx.review.deleteMany({ where: { authorId: user.userId, providerId } });
      if (!count) throw AppError.notFound('Review');
      await this.recompute(tx, providerId);
    });
  }

  private async recompute(tx: Prisma.TransactionClient, providerId: string): Promise<void> {
    const stats = await tx.review.aggregate({
      where: { providerId, status: ReviewStatus.PUBLISHED },
      _avg: { rating: true },
      _count: { _all: true },
    });
    await tx.serviceProvider.update({
      where: { id: providerId },
      data: { ratingAvg: stats._avg.rating ?? 0, reviewCount: stats._count._all },
    });
  }

  /** Account owner of a provider (used by chat context). */
  async ownerOf(providerId: string) {
    const provider = await this.prisma.serviceProvider.findFirst({
      where: { id: providerId, deletedAt: null, status: ProviderStatus.ACTIVE },
      select: { userId: true, displayName: true, profession: true, user: { select: publicUserSelect } },
    });
    if (!provider) throw AppError.notFound('Provider');
    return provider;
  }
}
