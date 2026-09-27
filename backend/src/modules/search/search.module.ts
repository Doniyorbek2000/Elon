import { Controller, Get, Inject, Injectable, Module, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, Length, MaxLength } from 'class-validator';

import { AuthUser, MaybeUser, OptionalAuth, Public } from '../../common/auth.decorators';
import { presentUser, publicUserSelect } from '../../common/presenters';
import { normalizeQuery, normalizeText, searchTokens } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { CategoriesService } from '../categories/categories.service';
import { jobCardSelect, presentJobCard } from '../jobs/job.presenter';
import { listingCardSelect, presentListingCard } from '../listings/listing.presenter';
import { presentProviderCard, providerCardSelect } from '../services/provider.presenter';
import { PostgresSearchProvider, SEARCH_PROVIDER, SearchFilters, SearchKind, SearchProvider } from './search.provider';

class SearchQuery {
  @IsString()
  @Length(1, 100)
  q!: string;

  @IsOptional()
  @IsIn(['all', 'listings', 'jobs', 'services', 'users'])
  scope?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  region?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  category?: string;
}

class SuggestQuery {
  @IsString()
  @Length(1, 100)
  q!: string;
}

function reorder<T extends { id: string }>(rows: T[], ids: string[]): T[] {
  const byId = new Map(rows.map((r) => [r.id, r]));
  return ids.map((id) => byId.get(id)).filter((r): r is T => r !== undefined);
}

@Injectable()
export class SearchService {
  constructor(
    @Inject(SEARCH_PROVIDER) private readonly provider: SearchProvider,
    private readonly prisma: PrismaService,
    private readonly categories: CategoriesService,
  ) {}

  /** Universal search: listings, jobs, providers and users in one call. */
  async search(query: SearchQuery, viewer?: AuthUser) {
    const scope = query.scope ?? 'all';
    const limit = scope === 'all' ? 10 : 30;
    const filters: SearchFilters = {
      regionId: query.region,
      categoryIds: query.category ? await this.categories.subtreeIds(query.category) : undefined,
      viewerId: viewer?.userId,
    };
    const wants = (kind: string) => scope === 'all' || scope === kind;
    const hits = async (kind: SearchKind) => (wants(kind === 'providers' ? 'services' : kind) ? this.provider.search(kind, query.q, filters, limit) : []);
    const [listingHits, jobHits, providerHits] = await Promise.all([hits('listings'), hits('jobs'), hits('providers')]);

    const [listings, jobs, providers, users] = await Promise.all([
      this.prisma.listing.findMany({ where: { id: { in: listingHits.map((h) => h.id) } }, select: listingCardSelect }),
      this.prisma.job.findMany({ where: { id: { in: jobHits.map((h) => h.id) } }, select: jobCardSelect }),
      this.prisma.serviceProvider.findMany({ where: { id: { in: providerHits.map((h) => h.id) } }, select: providerCardSelect }),
      wants('users') ? this.users(query.q, limit, viewer) : Promise.resolve([]),
    ]);
    const normalized = normalizeText(query.q);
    const canonical = normalizeQuery(query.q);
    return {
      listings: reorder(listings, listingHits.map((h) => h.id)).map((l) => presentListingCard(l)),
      jobs: reorder(jobs, jobHits.map((h) => h.id)).map((j) => presentJobCard(j)),
      providers: reorder(providers, providerHits.map((h) => h.id)).map((p) => presentProviderCard(p)),
      users,
      correctedQuery: canonical !== normalized ? canonical : null,
      engine: this.provider.name,
    };
  }

  private async users(q: string, limit: number, viewer?: AuthUser) {
    const tokens = searchTokens(q);
    if (!tokens.length) return [];
    const rows = await this.prisma.user.findMany({
      where: {
        status: 'ACTIVE',
        deletedAt: null,
        AND: tokens.map((t) => ({ profile: { displayName: { contains: t, mode: 'insensitive' as const } } })),
        ...(viewer ? { blocksReceived: { none: { blockerId: viewer.userId } } } : {}),
        // Only people with public activity are discoverable.
        OR: [{ listings: { some: { status: 'ACTIVE' } } }, { provider: { status: 'ACTIVE' } }, { jobs: { some: { status: 'ACTIVE' } } }],
      },
      select: { ...publicUserSelect, _count: { select: { listings: { where: { status: 'ACTIVE' } } } } },
      take: limit,
    });
    return rows.map((u) => presentUser(u, { activeListings: u._count.listings }));
  }

  async suggest(q: string) {
    const tokens = searchTokens(q);
    if (!tokens.length) return [];
    const tree = (await this.categories.tree()) as Array<{ id: string; name: string; children: Array<{ id: string; name: string }> }>;
    const categoryHits = tree
      .flatMap((root) => [{ id: root.id, name: root.name, parent: null as string | null }, ...root.children.map((c) => ({ ...c, parent: root.name }))])
      .filter((c) => tokens.every((t) => normalizeText(c.name).includes(t)))
      .slice(0, 4)
      .map((c) => ({ text: c.name, kind: 'category', refId: c.id, subtitle: c.parent ?? 'Kategoriya' }));
    const services = await this.prisma.serviceCategory.findMany({ where: { isActive: true } });
    const serviceHits = services
      .filter((s) => tokens.every((t) => normalizeText(s.name).includes(t)))
      .slice(0, 3)
      .map((s) => ({ text: s.name, kind: 'serviceCategory', refId: s.id, subtitle: 'Xizmatlar' }));
    const titles = (await this.provider.suggestTitles(q, 6)).map((t) => ({ text: t, kind: 'query', refId: null, subtitle: 'E’lonlar' }));
    return [...categoryHits, ...serviceHits, ...titles].slice(0, 10);
  }

  /** Popular queries are curated until enough search analytics exist. */
  popular() {
    return ['iPhone', 'Cobalt', 'Kvartira ijaraga', 'Santexnik', 'Haydovchi kerak', 'Konditsioner', 'Sement', 'Repetitor'];
  }
}

@ApiTags('search')
@Controller('search')
class SearchController {
  constructor(private readonly search: SearchService) {}

  @OptionalAuth()
  @Get()
  run(@Query() query: SearchQuery, @MaybeUser() viewer?: AuthUser) {
    return this.search.search(query, viewer);
  }

  @Public()
  @Get('suggest')
  suggest(@Query() query: SuggestQuery) {
    return this.search.suggest(query.q);
  }

  @Public()
  @Get('popular')
  popular() {
    return this.search.popular();
  }
}

@Module({
  controllers: [SearchController],
  providers: [SearchService, { provide: SEARCH_PROVIDER, useClass: PostgresSearchProvider }],
})
export class SearchModule {}
