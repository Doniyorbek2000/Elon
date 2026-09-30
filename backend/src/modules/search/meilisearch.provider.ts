import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { normalizeQuery, searchTokens } from '../../common/text';
import { env } from '../../config/env';
import { PrismaService } from '../../infra/prisma.service';
import { RedisService } from '../../infra/redis.service';
import { SearchFilters, SearchHit, SearchKind, SearchProvider } from './search.provider';

interface IndexedDocument {
  id: string;
  title: string;
  searchText: string;
  regionId: string | null;
  categoryId: string | null;
  ownerId: string;
}

interface SourceRow extends IndexedDocument {
  status: string;
  deletedAt: Date | null;
  updatedAt: Date;
}

const KINDS: SearchKind[] = ['listings', 'jobs', 'providers'];
const BATCH = 500;
/** Rows are re-read this far behind the watermark so commits that landed out of order are not missed. */
const OVERLAP_MS = 10_000;

/** Column expressions per kind: every source is mapped to the same document shape. */
const SOURCES: Record<
  SearchKind,
  { table: Prisma.Sql; title: Prisma.Sql; owner: Prisma.Sql; category: Prisma.Sql }
> = {
  listings: {
    table: Prisma.sql`"Listing"`,
    title: Prisma.sql`t."title"`,
    owner: Prisma.sql`t."sellerId"`,
    category: Prisma.sql`t."categoryId"`,
  },
  jobs: {
    table: Prisma.sql`"Job"`,
    title: Prisma.sql`t."title"`,
    owner: Prisma.sql`t."employerId"`,
    category: Prisma.sql`NULL`,
  },
  providers: {
    table: Prisma.sql`"ServiceProvider"`,
    title: Prisma.sql`t."displayName"`,
    owner: Prisma.sql`t."userId"`,
    category: Prisma.sql`NULL`,
  },
};

/** Minimal Meilisearch REST client (Node's fetch; no SDK dependency). */
export class MeilisearchClient {
  constructor(
    private readonly baseUrl: string,
    private readonly apiKey?: string,
  ) {}

  async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const response = await fetch(`${this.baseUrl.replace(/\/$/, '')}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(this.apiKey ? { Authorization: `Bearer ${this.apiKey}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    });
    const text = await response.text();
    if (!response.ok)
      throw new Error(`Meilisearch ${method} ${path} → ${response.status}: ${text.slice(0, 300)}`);
    return (text ? JSON.parse(text) : {}) as T;
  }

  /** Waits for an asynchronous task (settings, documents) to finish. */
  async wait(taskUid: number, timeoutMs = 60_000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const task = await this.request<{ status: string; error?: { message: string } }>(
        'GET',
        `/tasks/${taskUid}`,
      );
      if (task.status === 'succeeded') return;
      if (task.status === 'failed' || task.status === 'canceled') {
        throw new Error(`Meilisearch task ${taskUid} ${task.status}: ${task.error?.message ?? ''}`);
      }
      if (Date.now() > deadline) throw new Error(`Meilisearch task ${taskUid} timed out`);
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }
}

/**
 * Meilisearch engine: typo tolerance, prefix matching and ranking come from
 * the engine; text is normalized exactly like the PostgreSQL provider
 * (Cyrillic → Latin, apostrophes, synonyms), so both index the same words.
 *
 * The index follows the database by polling `updatedAt` (worker, every
 * minute): rows that are active are upserted, everything else is removed.
 * Searches therefore lag writes by up to a minute; the database stays the
 * source of truth and `SEARCH_PROVIDER=postgres` is always a valid fallback.
 */
@Injectable()
export class MeilisearchSearchProvider implements SearchProvider {
  readonly name = 'meilisearch';
  private readonly logger = new Logger(MeilisearchSearchProvider.name);
  private readonly client: MeilisearchClient;
  private readonly prefix: string;
  private ready?: Promise<void>;

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {
    const config = env();
    this.client = new MeilisearchClient(config.MEILI_URL!, config.MEILI_API_KEY);
    this.prefix = config.MEILI_INDEX_PREFIX;
  }

  private index(kind: SearchKind): string {
    return `${this.prefix}_${kind}`;
  }

  /** Creates indexes and settings once per process. */
  private ensureIndexes(): Promise<void> {
    this.ready ??= (async () => {
      for (const kind of KINDS) {
        const uid = this.index(kind);
        try {
          await this.client.request('GET', `/indexes/${uid}`);
        } catch {
          const task = await this.client.request<{ taskUid: number }>('POST', '/indexes', {
            uid,
            primaryKey: 'id',
          });
          await this.client.wait(task.taskUid);
        }
        const settings = await this.client.request<{ taskUid: number }>('PATCH', `/indexes/${uid}/settings`, {
          searchableAttributes: ['title', 'searchText'],
          filterableAttributes: ['regionId', 'categoryId', 'ownerId'],
          displayedAttributes: ['id', 'title'],
          typoTolerance: { enabled: true, minWordSizeForTypos: { oneTypo: 4, twoTypos: 8 } },
          pagination: { maxTotalHits: 1000 },
        });
        await this.client.wait(settings.taskUid);
      }
    })().catch((error: unknown) => {
      this.ready = undefined; // retry on the next call
      throw error;
    });
    return this.ready;
  }

  async search(kind: SearchKind, query: string, filters: SearchFilters, limit: number): Promise<SearchHit[]> {
    const tokens = searchTokens(query).slice(0, 6);
    if (tokens.length === 0) return [];
    await this.ensureIndexes();
    const filter: string[] = [];
    const quote = (value: string) => JSON.stringify(value);
    if (filters.regionId) filter.push(`regionId = ${quote(filters.regionId)}`);
    if (kind === 'listings' && filters.categoryIds?.length) {
      filter.push(`categoryId IN [${filters.categoryIds.map(quote).join(', ')}]`);
    }
    if (filters.viewerId) {
      const blocked = await this.prisma.block.findMany({
        where: { blockerId: filters.viewerId },
        select: { blockedId: true },
        take: 1000,
      });
      if (blocked.length)
        filter.push(`ownerId NOT IN [${blocked.map((b) => quote(b.blockedId)).join(', ')}]`);
    }
    const result = await this.client.request<{ hits: Array<{ id: string; _rankingScore?: number }> }>(
      'POST',
      `/indexes/${this.index(kind)}/search`,
      {
        q: tokens.join(' '),
        limit,
        filter: filter.length ? filter : undefined,
        matchingStrategy: 'all',
        showRankingScore: true,
        attributesToRetrieve: ['id'],
      },
    );
    return result.hits.map((hit) => ({ id: hit.id, score: hit._rankingScore ?? 0 }));
  }

  async suggestTitles(query: string, limit: number): Promise<string[]> {
    const normalized = normalizeQuery(query);
    if (normalized.length < 2) return [];
    await this.ensureIndexes();
    const result = await this.client.request<{ hits: Array<{ title: string }> }>(
      'POST',
      `/indexes/${this.index('listings')}/search`,
      { q: normalized, limit: limit * 3, attributesToRetrieve: ['title'] },
    );
    const seen = new Set<string>();
    const titles: string[] = [];
    for (const hit of result.hits) {
      const key = hit.title.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      titles.push(hit.title);
      if (titles.length >= limit) break;
    }
    return titles;
  }

  // ─────────────────────────────────────────────────────── indexing

  async sync(): Promise<{ indexed: number; removed: number }> {
    await this.ensureIndexes();
    let indexed = 0;
    let removed = 0;
    for (const kind of KINDS) {
      const result = await this.syncKind(kind);
      indexed += result.indexed;
      removed += result.removed;
    }
    return { indexed, removed };
  }

  private async syncKind(kind: SearchKind): Promise<{ indexed: number; removed: number }> {
    const key = `search:sync:${this.index(kind)}`;
    const stored = await this.redis.client.get(key);
    let since = stored ? new Date(new Date(stored).getTime() - OVERLAP_MS) : new Date(0);
    const { table, title, owner, category } = SOURCES[kind];
    let indexed = 0;
    let removed = 0;
    for (;;) {
      const rows = await this.prisma.$queryRaw<SourceRow[]>`
        SELECT t."id"::text AS id, ${title} AS title, t."searchText" AS "searchText",
               t."regionId" AS "regionId", ${category} AS "categoryId", ${owner}::text AS "ownerId",
               t."status"::text AS status, t."deletedAt" AS "deletedAt", t."updatedAt" AS "updatedAt"
        FROM ${table} t
        WHERE t."updatedAt" >= ${since}
        ORDER BY t."updatedAt" ASC, t."id" ASC
        LIMIT ${BATCH}`;
      if (rows.length === 0) break;
      const live = rows.filter((r) => r.status === 'ACTIVE' && r.deletedAt === null);
      const dead = rows.filter((r) => !(r.status === 'ACTIVE' && r.deletedAt === null));
      if (live.length) {
        const documents: IndexedDocument[] = live.map((r) => ({
          id: r.id,
          title: r.title,
          searchText: r.searchText ?? '',
          regionId: r.regionId,
          categoryId: r.categoryId,
          ownerId: r.ownerId,
        }));
        const task = await this.client.request<{ taskUid: number }>(
          'POST',
          `/indexes/${this.index(kind)}/documents`,
          documents,
        );
        await this.client.wait(task.taskUid);
        indexed += live.length;
      }
      if (dead.length) {
        const task = await this.client.request<{ taskUid: number }>(
          'POST',
          `/indexes/${this.index(kind)}/documents/delete-batch`,
          dead.map((r) => r.id),
        );
        await this.client.wait(task.taskUid);
        removed += dead.length;
      }
      const last = rows[rows.length - 1].updatedAt;
      await this.redis.client.set(key, last.toISOString());
      if (rows.length < BATCH) break;
      // A full batch of identical timestamps would loop forever; step past it.
      since = last > since ? last : new Date(since.getTime() + 1);
    }
    if (indexed || removed) this.logger.log({ kind, indexed, removed }, 'Search index synchronized');
    return { indexed, removed };
  }
}
