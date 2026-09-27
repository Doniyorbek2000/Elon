import { Injectable } from '@nestjs/common';
import {
  AccountType,
  BusinessRole,
  BusinessStatus,
  BusinessVerification,
  JobStatus,
  ListingStatus,
  MediaPurpose,
  MediaStatus,
  ProviderStatus,
  VerificationLevel,
} from '@prisma/client';

import { AuthUser } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { Page, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { mediaSelect, presentMedia } from '../../common/presenters';
import { apiEnum, normalizeUzPhone } from '../../common/text';
import { env } from '../../config/env';
import { PrismaService } from '../../infra/prisma.service';
import { jobCardSelect, presentJobCard } from '../jobs/job.presenter';
import { listingCardSelect, presentListingCard } from '../listings/listing.presenter';
import { LocationsService } from '../locations/locations.service';
import { MonetizationConfig } from '../monetization/config.service';
import { EntitlementService } from '../monetization/entitlements.service';
import { PromotionService } from '../monetization/promotion.service';
import { presentProviderCard, providerCardSelect } from '../services/provider.presenter';
import { AddMemberDto, BusinessDto, UpdateBusinessDto } from './business.dto';

const businessInclude = {
  members: {
    select: { userId: true, role: true, user: { select: { profile: { select: { displayName: true } } } } },
  },
} as const;

/**
 * Business accounts: one business per owner, OWNER + MANAGER roles only.
 * Verification is set exclusively by admins. The public storefront is an
 * entitlement of the owner's plan.
 */
@Injectable()
export class BusinessService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly locations: LocationsService,
    private readonly entitlements: EntitlementService,
    private readonly config: MonetizationConfig,
    private readonly promotions: PromotionService,
  ) {}

  private async assertLogo(userId: string, logoId?: string) {
    if (!logoId) return;
    const media = await this.prisma.media.findFirst({
      where: {
        id: logoId,
        ownerId: userId,
        purpose: MediaPurpose.AVATAR,
        deletedAt: null,
        status: { not: MediaStatus.FAILED },
      },
    });
    if (!media) throw AppError.validation('Invalid logo', { field: 'logoId' });
  }

  async create(user: AuthUser, dto: BusinessDto) {
    if (!(await this.config.enabled('businessAccounts'))) throw AppError.featureDisabled('businessAccounts');
    // One business per person, whether as owner or as someone's manager.
    if (await this.prisma.businessMember.findFirst({ where: { userId: user.userId } })) {
      throw AppError.conflict('You already belong to a business');
    }
    await this.assertLogo(user.userId, dto.logoId);
    const place = await this.locations.resolvePlace({ regionId: dto.regionId, districtId: dto.districtId });
    const phone = dto.phone ? normalizeUzPhone(dto.phone) : null;
    if (dto.phone && !phone) throw AppError.validation('Invalid phone', { field: 'phone' });
    const business = await this.prisma.$transaction(async (tx) => {
      const business = await tx.business.create({
        data: {
          ownerId: user.userId,
          name: dto.name,
          description: dto.description ?? '',
          categoryId: dto.categoryId,
          regionId: place.regionId,
          districtId: place.districtId,
          address: dto.address,
          phone,
          website: dto.website,
          telegram: dto.telegram?.replace(/^@/, ''),
          openingHours: dto.openingHours,
          logoId: dto.logoId,
        },
      });
      await tx.businessMember.create({
        data: { businessId: business.id, userId: user.userId, role: BusinessRole.OWNER },
      });
      await tx.profile.update({
        where: { userId: user.userId },
        data: { accountType: AccountType.BUSINESS },
      });
      return business;
    });
    await this.entitlements.invalidate([user.userId]);
    return this.mine(user.userId, business.id);
  }

  private async membership(userId: string) {
    const member = await this.prisma.businessMember.findFirst({
      where: { userId },
      include: { business: true },
    });
    if (!member) throw AppError.notFound('Business');
    return member;
  }

  async mine(userId: string, businessId?: string) {
    const member = businessId
      ? await this.prisma.businessMember.findUnique({
          where: { businessId_userId: { businessId, userId } },
          include: { business: true },
        })
      : await this.prisma.businessMember.findFirst({ where: { userId }, include: { business: true } });
    if (!member) throw AppError.notFound('Business');
    const business = await this.prisma.business.findUniqueOrThrow({
      where: { id: member.businessId },
      include: businessInclude,
    });
    const effective = await this.entitlements.effectivePlan(business.ownerId);
    return {
      ...(await this.present(business)),
      myRole: apiEnum(member.role),
      members: business.members.map((m) => ({
        userId: m.userId,
        name: m.user.profile?.displayName ?? '',
        role: apiEnum(m.role),
      })),
      plan: {
        id: effective.plan.id,
        title: effective.plan.title,
        storefront: effective.plan.storefront,
        maxManagers: effective.plan.maxManagers,
      },
    };
  }

  async update(userId: string, dto: UpdateBusinessDto) {
    const member = await this.membership(userId);
    await this.assertLogo(userId, dto.logoId);
    const data: Record<string, unknown> = { ...dto };
    if (dto.regionId) {
      const place = await this.locations.resolvePlace({ regionId: dto.regionId, districtId: dto.districtId });
      data.regionId = place.regionId;
      data.districtId = place.districtId;
    }
    if (dto.phone !== undefined) {
      const phone = normalizeUzPhone(dto.phone);
      if (!phone) throw AppError.validation('Invalid phone', { field: 'phone' });
      data.phone = phone;
    }
    if (dto.telegram) data.telegram = dto.telegram.replace(/^@/, '');
    // Name/category changes of a verified business require re-verification.
    const reverify =
      member.business.verification === BusinessVerification.VERIFIED &&
      dto.name &&
      dto.name !== member.business.name;
    await this.prisma.business.update({
      where: { id: member.businessId },
      data: { ...data, ...(reverify ? { verification: BusinessVerification.PENDING } : {}) },
    });
    return this.mine(userId, member.businessId);
  }

  async requestVerification(userId: string) {
    const member = await this.membership(userId);
    if (member.role !== BusinessRole.OWNER) throw AppError.forbidden();
    if (member.business.verification === BusinessVerification.VERIFIED)
      throw AppError.invalidState('Already verified');
    await this.prisma.business.update({
      where: { id: member.businessId },
      data: { verification: BusinessVerification.PENDING },
    });
    return this.mine(userId, member.businessId);
  }

  async addManager(userId: string, dto: AddMemberDto) {
    const member = await this.membership(userId);
    if (member.role !== BusinessRole.OWNER) throw AppError.forbidden('Only the owner manages members');
    const maxManagers = await this.entitlements.maxManagers(userId);
    const managers = await this.prisma.businessMember.count({
      where: { businessId: member.businessId, role: BusinessRole.MANAGER },
    });
    if (managers >= maxManagers) throw AppError.limitReached('managers', maxManagers);
    const phone = normalizeUzPhone(dto.phone);
    const target = phone
      ? await this.prisma.user.findUnique({ where: { phone }, select: { id: true } })
      : null;
    if (!target) throw AppError.notFound('User');
    if (await this.prisma.businessMember.findFirst({ where: { userId: target.id } })) {
      throw AppError.conflict('This user already belongs to a business');
    }
    await this.prisma.businessMember.create({
      data: { businessId: member.businessId, userId: target.id, role: BusinessRole.MANAGER },
    });
    await this.entitlements.invalidate([target.id]);
    return this.mine(userId, member.businessId);
  }

  async removeManager(userId: string, managerId: string) {
    const member = await this.membership(userId);
    if (member.role !== BusinessRole.OWNER) throw AppError.forbidden('Only the owner manages members');
    const { count } = await this.prisma.businessMember.deleteMany({
      where: { businessId: member.businessId, userId: managerId, role: BusinessRole.MANAGER },
    });
    if (!count) throw AppError.notFound('Member');
    await this.entitlements.invalidate([managerId]);
    return this.mine(userId, member.businessId);
  }

  // ─────────────────────────────────────────────────────── storefront

  private async publicBusiness(id: string) {
    const business = await this.prisma.business.findFirst({
      where: { id, status: BusinessStatus.ACTIVE },
      include: businessInclude,
    });
    if (!business || !(await this.entitlements.canUseStorefront(business.ownerId)))
      throw AppError.notFound('Business');
    return business;
  }

  async storefront(id: string) {
    const business = await this.publicBusiness(id);
    const memberIds = business.members.map((m) => m.userId);
    const [listingCount, jobs, providers] = await Promise.all([
      this.prisma.listing.count({
        where: { sellerId: { in: memberIds }, status: ListingStatus.ACTIVE, deletedAt: null },
      }),
      this.prisma.job.findMany({
        where: { employerId: { in: memberIds }, status: JobStatus.ACTIVE, deletedAt: null },
        select: jobCardSelect,
        orderBy: { publishedAt: 'desc' },
        take: 10,
      }),
      this.prisma.serviceProvider.findMany({
        where: { userId: { in: memberIds }, status: ProviderStatus.ACTIVE, deletedAt: null },
        select: providerCardSelect,
        take: 5,
      }),
    ]);
    // Ratings are shown only from real reviews of the business's providers.
    const reviewed = providers.filter((p) => p.reviewCount > 0);
    const reviewCount = reviewed.reduce((sum, p) => sum + p.reviewCount, 0);
    const rating = reviewCount
      ? Math.round((reviewed.reduce((sum, p) => sum + p.ratingAvg * p.reviewCount, 0) / reviewCount) * 10) /
        10
      : null;
    return {
      ...(await this.present(business)),
      stats: { activeListings: listingCount },
      rating,
      reviewCount,
      jobs: jobs.map((j) => presentJobCard(j)),
      providers: providers.map((p) => presentProviderCard(p)),
    };
  }

  async storefrontListings(id: string, cursor?: string, limit?: number) {
    const business = await this.publicBusiness(id);
    const take = pageSize(limit);
    const rows = await this.prisma.listing.findMany({
      where: {
        sellerId: { in: business.members.map((m) => m.userId) },
        status: ListingStatus.ACTIVE,
        deletedAt: null,
        ...keysetWhere(cursor, 'rankedAt'),
      },
      select: { ...listingCardSelect, rankedAt: true },
      orderBy: [{ rankedAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
    });
    const page = keysetPage(rows, take, (r) => r.rankedAt ?? r.createdAt);
    const badges = await this.promotions.badges(
      'LISTING',
      page.items.map((r) => r.id),
    );
    return new Page(
      page.items.map((r) => presentListingCard(r, { badges: badges.get(r.id) })),
      page.nextCursor,
    );
  }

  private async present(business: {
    id: string;
    ownerId: string;
    name: string;
    description: string;
    logoId: string | null;
    categoryId: string | null;
    regionId: string;
    districtId: string | null;
    address: string | null;
    phone: string | null;
    website: string | null;
    telegram: string | null;
    openingHours: string | null;
    verification: BusinessVerification;
    createdAt: Date;
  }) {
    const [logo, region, district, effective] = await Promise.all([
      business.logoId
        ? this.prisma.media.findUnique({ where: { id: business.logoId }, select: mediaSelect })
        : null,
      this.prisma.region.findUnique({ where: { id: business.regionId }, select: { name: true } }),
      business.districtId
        ? this.prisma.district.findUnique({ where: { id: business.districtId }, select: { name: true } })
        : null,
      this.entitlements.effectivePlan(business.ownerId),
    ]);
    return {
      id: business.id,
      ownerId: business.ownerId,
      name: business.name,
      description: business.description,
      logo: logo ? presentMedia(logo) : null,
      categoryId: business.categoryId,
      place: {
        regionId: business.regionId,
        regionName: region?.name ?? '',
        districtId: business.districtId,
        districtName: district?.name ?? null,
      },
      address: business.address,
      phone: business.phone,
      website: business.website,
      telegram: business.telegram,
      openingHours: business.openingHours,
      /** Admin-verified only; never purchasable. */
      verified: business.verification === BusinessVerification.VERIFIED,
      verification: apiEnum(business.verification),
      businessBadge: effective.plan.businessBadge,
      memberSince: business.createdAt,
      shareUrl: `${env().WEB_BASE_URL}/business/${business.id}`,
    };
  }

  /** Admin: verification also marks the owner's profile as business-verified. */
  async setVerification(id: string, verification: BusinessVerification) {
    const business = await this.prisma.business.update({ where: { id }, data: { verification } });
    await this.prisma.profile.update({
      where: { userId: business.ownerId },
      data: {
        verification:
          verification === BusinessVerification.VERIFIED
            ? VerificationLevel.BUSINESS
            : VerificationLevel.PHONE,
      },
    });
    return business;
  }
}
