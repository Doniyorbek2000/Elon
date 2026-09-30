import { Global, Injectable, Module } from '@nestjs/common';
import { JobStatus, ListingStatus } from '@prisma/client';

import { AppError } from '../../common/errors';
import { PrismaService } from '../../infra/prisma.service';

/**
 * The service is free: there are no plans, only fixed fair-use limits that
 * keep one account from flooding the marketplace.
 */
export const LIMITS = {
  activeListings: 50,
  monthlyListings: 100,
  photosPerListing: 12,
  activeJobs: 10,
  managersPerBusiness: 5,
} as const;

const COUNTED_LISTING = [ListingStatus.ACTIVE, ListingStatus.PENDING_REVIEW, ListingStatus.RESERVED];

@Injectable()
export class LimitsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Throws LIMIT_REACHED when one more active/pending listing is not allowed. */
  async assertCanActivateListing(userId: string, excludeListingId?: string): Promise<void> {
    const active = await this.prisma.listing.count({
      where: {
        sellerId: userId,
        deletedAt: null,
        status: { in: COUNTED_LISTING },
        ...(excludeListingId ? { id: { not: excludeListingId } } : {}),
      },
    });
    if (active >= LIMITS.activeListings) throw AppError.limitReached('activeListings', LIMITS.activeListings);
  }

  async assertCanCreateListing(userId: string, photoCount: number): Promise<void> {
    this.assertPhotoLimit(photoCount);
    const since = new Date(Date.now() - 30 * 24 * 3600 * 1000);
    const created = await this.prisma.listing.count({
      where: { sellerId: userId, createdAt: { gte: since } },
    });
    if (created >= LIMITS.monthlyListings)
      throw AppError.limitReached('monthlyListings', LIMITS.monthlyListings);
  }

  assertPhotoLimit(photoCount: number): void {
    if (photoCount > LIMITS.photosPerListing) throw AppError.limitReached('photos', LIMITS.photosPerListing);
  }

  async assertCanActivateJob(userId: string, excludeJobId?: string): Promise<void> {
    const active = await this.prisma.job.count({
      where: {
        employerId: userId,
        deletedAt: null,
        status: JobStatus.ACTIVE,
        ...(excludeJobId ? { id: { not: excludeJobId } } : {}),
      },
    });
    if (active >= LIMITS.activeJobs) throw AppError.limitReached('activeJobs', LIMITS.activeJobs);
  }
}

@Global()
@Module({ providers: [LimitsService], exports: [LimitsService] })
export class LimitsModule {}
