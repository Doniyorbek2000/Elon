import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { normalizeQuery, searchTokens } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';

export type SearchKind = 'listings' | 'jobs' | 'providers';

export interface SearchFilters {
  regionId?: string;
  categoryIds?: string[];
  viewerId?: string;
}

export interface SearchHit {
  id: string;
  score: number;
}

/**
 * Search engine contract. The PostgreSQL implementation reads the normalized
 * `searchText` columns; an external engine (Meilisearch/Typesense/OpenSearch)
 * implements the same interface plus index hooks, without API changes.
 */
export interface SearchProvider {
  readonly name: string;
  search(kind: SearchKind, query: string, filters: SearchFilters, limit: number): Promise<SearchHit[]>;
  suggestTitles(query: string, limit: number): Promise<string[]>;
}

export const SEARCH_PROVIDER = Symbol('SEARCH_PROVIDER');

const TABLES: Record<SearchKind, { table: Prisma.Sql; active: Prisma.Sql; owner: Prisma.Sql }> = {
  listings: { table: Prisma.sql`"Listing"`, active: Prisma.sql`t."status" = 'ACTIVE'`, owner: Prisma.sql`t."sellerId"` },
  jobs: { table: Prisma.sql`"Job"`, active: Prisma.sql`t."status" = 'ACTIVE'`, owner: Prisma.sql`t."employerId"` },
  providers: { table: Prisma.sql`"ServiceProvider"`, active: Prisma.sql`t."status" = 'ACTIVE'`, owner: Prisma.sql`t."userId"` },
};

/** pg_trgm word similarity over normalized text: typo tolerant, index-backed. */
@Injectable()
export class PostgresSearchProvider implements SearchProvider {
  readonly name = 'postgres';

  constructor(private readonly prisma: PrismaService) {}

  async search(kind: SearchKind, query: string, filters: SearchFilters, limit: number): Promise<SearchHit[]> {
    const tokens = searchTokens(query).slice(0, 6);
    if (tokens.length === 0) return [];
    const normalized = tokens.join(' ');
    const { table, active, owner } = TABLES[kind];
    const where: Prisma.Sql[] = [active, Prisma.sql`t."deletedAt" IS NULL`];
    for (const token of tokens) {
      where.push(Prisma.sql`(t."searchText" LIKE ${`%${token}%`} OR ${token} <% t."searchText")`);
    }
    if (filters.regionId) where.push(Prisma.sql`t."regionId" = ${filters.regionId}`);
    if (kind === 'listings' && filters.categoryIds?.length) where.push(Prisma.sql`t."categoryId" = ANY(${filters.categoryIds})`);
    if (filters.viewerId) {
      where.push(Prisma.sql`NOT EXISTS (SELECT 1 FROM "Block" b WHERE b."blockerId" = ${filters.viewerId}::uuid AND b."blockedId" = ${owner})`);
    }
    const rows = await this.prisma.$queryRaw<Array<{ id: string; score: number }>>`
      SELECT t."id", word_similarity(${normalized}, t."searchText") AS score
      FROM ${table} t
      WHERE ${Prisma.join(where, ' AND ')}
      ORDER BY score DESC, t."updatedAt" DESC
      LIMIT ${limit}`;
    return rows.map((r) => ({ id: r.id, score: Number(r.score) }));
  }

  async suggestTitles(query: string, limit: number): Promise<string[]> {
    const normalized = normalizeQuery(query);
    if (normalized.length < 2) return [];
    const rows = await this.prisma.$queryRaw<Array<{ title: string }>>`
      SELECT DISTINCT ON (lower(l."title")) l."title", word_similarity(${normalized}, l."searchText") AS score
      FROM "Listing" l
      WHERE l."status" = 'ACTIVE' AND l."deletedAt" IS NULL
        AND (l."searchText" LIKE ${`%${normalized}%`} OR ${normalized} <% l."searchText")
      ORDER BY lower(l."title"), score DESC
      LIMIT ${limit}`;
    return rows.map((r) => r.title);
  }
}
