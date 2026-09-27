import { Controller, Delete, Get, Injectable, Module, Param, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JobStatus, ListingStatus, Prisma, ProviderStatus } from '@prisma/client';
import { IsIn, IsUUID } from 'class-validator';

import { AuthUser, CurrentUser } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { CursorQuery, Page, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { PrismaService } from '../../infra/prisma.service';
import { jobCardSelect, presentJobCard } from '../jobs/job.presenter';
import { listingCardSelect, presentListingCard } from '../listings/listing.presenter';
import { presentProviderCard, providerCardSelect } from '../services/provider.presenter';

type Kind = 'listings' | 'jobs' | 'providers';
const KINDS: Kind[] = ['listings', 'jobs', 'providers'];

class KindParam {
  @IsIn(KINDS)
  kind!: Kind;
}

class KindIdParam extends KindParam {
  @IsUUID()
  id!: string;
}

const COLUMN: Record<Kind, 'listingId' | 'jobId' | 'providerId'> = {
  listings: 'listingId',
  jobs: 'jobId',
  providers: 'providerId',
};

@Injectable()
export class FavoritesService {
  constructor(private readonly prisma: PrismaService) {}

  private async assertTarget(kind: Kind, id: string): Promise<void> {
    const count = await {
      listings: () => this.prisma.listing.count({ where: { id, deletedAt: null, status: { not: ListingStatus.DRAFT } } }),
      jobs: () => this.prisma.job.count({ where: { id, deletedAt: null } }),
      providers: () => this.prisma.serviceProvider.count({ where: { id, deletedAt: null } }),
    }[kind]();
    if (!count) throw AppError.notFound('Item');
  }

  /** Idempotent: saving twice is a no-op. Keeps listing counters consistent. */
  async add(userId: string, kind: Kind, id: string): Promise<void> {
    await this.assertTarget(kind, id);
    const column = COLUMN[kind];
    await this.prisma.$transaction(async (tx) => {
      const existing = await tx.favorite.findFirst({ where: { userId, [column]: id } });
      if (existing) return;
      await tx.favorite.create({ data: { userId, [column]: id } as Prisma.FavoriteUncheckedCreateInput });
      if (kind === 'listings') await tx.listing.update({ where: { id }, data: { favoriteCount: { increment: 1 } } });
    });
  }

  async remove(userId: string, kind: Kind, id: string): Promise<void> {
    const column = COLUMN[kind];
    await this.prisma.$transaction(async (tx) => {
      const { count } = await tx.favorite.deleteMany({ where: { userId, [column]: id } });
      if (count && kind === 'listings') {
        await tx.listing.updateMany({ where: { id, favoriteCount: { gt: 0 } }, data: { favoriteCount: { decrement: 1 } } });
      }
    });
  }

  async ids(userId: string) {
    const rows = await this.prisma.favorite.findMany({
      where: { userId },
      select: { listingId: true, jobId: true, providerId: true },
      take: 5000,
    });
    return {
      listings: rows.flatMap((r) => (r.listingId ? [r.listingId] : [])),
      jobs: rows.flatMap((r) => (r.jobId ? [r.jobId] : [])),
      providers: rows.flatMap((r) => (r.providerId ? [r.providerId] : [])),
    };
  }

  async list(userId: string, kind: Kind, cursor?: string, limit?: number) {
    const take = pageSize(limit);
    const base = { userId, ...keysetWhere(cursor) };
    const orderBy = [{ createdAt: 'desc' as const }, { id: 'desc' as const }];
    switch (kind) {
      case 'listings': {
        const rows = await this.prisma.favorite.findMany({
          where: { ...base, listing: { is: { deletedAt: null, status: { not: ListingStatus.DRAFT } } } },
          orderBy,
          take: take + 1,
          select: { id: true, createdAt: true, listing: { select: listingCardSelect } },
        });
        const page = keysetPage(rows, take, (r) => r.createdAt);
        const items = page.items.flatMap((r) =>
          r.listing ? [presentListingCard(r.listing, { isFavorite: true })] : [],
        );
        return new Page(items, page.nextCursor);
      }
      case 'jobs': {
        const rows = await this.prisma.favorite.findMany({
          where: { ...base, job: { is: { deletedAt: null, status: { not: JobStatus.DRAFT } } } },
          orderBy,
          take: take + 1,
          select: { id: true, createdAt: true, job: { select: jobCardSelect } },
        });
        const page = keysetPage(rows, take, (r) => r.createdAt);
        const items = page.items.flatMap((r) => (r.job ? [presentJobCard(r.job, { isFavorite: true })] : []));
        return new Page(items, page.nextCursor);
      }
      case 'providers': {
        const rows = await this.prisma.favorite.findMany({
          where: { ...base, provider: { is: { deletedAt: null, status: { not: ProviderStatus.SUSPENDED } } } },
          orderBy,
          take: take + 1,
          select: { id: true, createdAt: true, provider: { select: providerCardSelect } },
        });
        const page = keysetPage(rows, take, (r) => r.createdAt);
        const items = page.items.flatMap((r) =>
          r.provider ? [presentProviderCard(r.provider, { isFavorite: true })] : [],
        );
        return new Page(items, page.nextCursor);
      }
    }
  }
}

@ApiTags('favorites')
@ApiBearerAuth()
@Controller('favorites')
class FavoritesController {
  constructor(private readonly favorites: FavoritesService) {}

  @Get('ids')
  ids(@CurrentUser() user: AuthUser) {
    return this.favorites.ids(user.userId);
  }

  @Get(':kind')
  list(@CurrentUser() user: AuthUser, @Param() params: KindParam, @Query() query: CursorQuery) {
    return this.favorites.list(user.userId, params.kind, query.cursor, query.limit);
  }

  @Put(':kind/:id')
  async add(@CurrentUser() user: AuthUser, @Param() params: KindIdParam) {
    await this.favorites.add(user.userId, params.kind, params.id);
    return { saved: true };
  }

  @Delete(':kind/:id')
  async remove(@CurrentUser() user: AuthUser, @Param() params: KindIdParam) {
    await this.favorites.remove(user.userId, params.kind, params.id);
    return { saved: false };
  }
}

@Module({ controllers: [FavoritesController], providers: [FavoritesService] })
export class FavoritesModule {}
