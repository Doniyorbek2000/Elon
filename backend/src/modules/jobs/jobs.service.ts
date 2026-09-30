import { Injectable } from '@nestjs/common';
import {
  ApplicationMode,
  Currency,
  EmploymentType,
  ExperienceLevel,
  JobStatus,
  Prisma,
  WorkFormat,
} from '@prisma/client';

import { env } from '../../config/env';
import { AuthUser } from '../../common/auth.decorators';
import { assessText, hasBlocking, requiresModeration } from '../../common/content-risk';
import { AppError } from '../../common/errors';
import { Page, decodeCursor, encodeCursor, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { buildSearchText, dbEnum, searchTokens } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { QueueService } from '../../infra/queues';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { RedisService } from '../../infra/redis.service';
import { LimitsService } from '../limits/limits.module';
import { LocationsService } from '../locations/locations.service';
import { jobCardSelect, jobDetailSelect, presentJobCard, presentJobDetail } from './job.presenter';
import { JobInputDto, JobSearchQuery, MyJobsQuery } from './jobs.dto';

const OWNER_TRANSITIONS: Record<JobStatus, JobStatus[]> = {
  DRAFT: [JobStatus.ACTIVE, JobStatus.ARCHIVED],
  ACTIVE: [JobStatus.PAUSED, JobStatus.FILLED, JobStatus.ARCHIVED],
  PAUSED: [JobStatus.ACTIVE, JobStatus.FILLED, JobStatus.ARCHIVED],
  FILLED: [JobStatus.ACTIVE, JobStatus.ARCHIVED],
  EXPIRED: [JobStatus.ACTIVE, JobStatus.ARCHIVED],
  REJECTED: [JobStatus.ARCHIVED],
  ARCHIVED: [JobStatus.ACTIVE],
};

@Injectable()
export class JobsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly locations: LocationsService,
    private readonly limiter: RateLimiterService,
    private readonly queues: QueueService,
    private readonly redis: RedisService,
    private readonly limits: LimitsService,
  ) {}

  /** Filters shared by the organic results and the paid block (same relevance). */
  private async filters(query: JobSearchQuery, viewer?: AuthUser): Promise<Prisma.JobWhereInput> {
    const where: Prisma.JobWhereInput = { status: JobStatus.ACTIVE, deletedAt: null };
    const and: Prisma.JobWhereInput[] = [];

    if (query.radius) {
      const origin =
        query.lat != null && query.lng != null
          ? { lat: query.lat, lng: query.lng }
          : await this.locations.origin(query.region, query.district);
      if (!origin) throw AppError.validation('Radius search needs a region, district or coordinates');
      const rows = await this.prisma.$queryRaw<Array<{ id: string }>>`
        SELECT j."id" FROM "Job" j
        WHERE j."status" = 'ACTIVE' AND j."deletedAt" IS NULL
          AND ST_DWithin(j."geo", ST_SetSRID(ST_MakePoint(${origin.lng}, ${origin.lat}), 4326)::geography, ${query.radius * 1000})
        LIMIT 5000`;
      and.push({ id: { in: rows.map((r) => r.id) } });
    } else {
      if (query.region) where.regionId = query.region;
      if (query.district) where.districtId = query.district;
    }
    const types = (query.types ?? '')
      .split(',')
      .map((t) => t.trim())
      .filter(Boolean)
      .map((t) => dbEnum(t) as EmploymentType)
      .filter((t) => Object.values(EmploymentType).includes(t));
    if (types.length) where.employmentType = { in: types };
    if (query.experience) where.experience = dbEnum(query.experience) as ExperienceLevel;
    if (query.workFormat) where.workFormat = dbEnum(query.workFormat) as WorkFormat;
    if (query.salaryMin != null) {
      and.push({
        OR: [
          { salaryMax: { gte: query.salaryMin } },
          { salaryMax: null, salaryMin: { gte: query.salaryMin } },
        ],
      });
    }
    for (const token of searchTokens(query.q ?? '').slice(0, 6))
      and.push({ searchText: { contains: token } });
    if (viewer) and.push({ employer: { blocksReceived: { none: { blockerId: viewer.userId } } } });
    if (and.length) where.AND = and;
    return where;
  }

  async search(query: JobSearchQuery, viewer?: AuthUser) {
    const take = pageSize(query.limit);
    const where = await this.filters(query, viewer);

    let rows;
    let nextCursor: string | null;
    if (query.sort === 'salary') {
      const offset = Number(decodeCursor<{ o: number }>(query.cursor)?.o ?? 0);
      if (!Number.isInteger(offset) || offset < 0 || offset > 2000)
        throw AppError.validation('Invalid cursor');
      rows = await this.prisma.job.findMany({
        where,
        select: jobCardSelect,
        orderBy: [
          { salaryMax: { sort: 'desc', nulls: 'last' } },
          { salaryMin: { sort: 'desc', nulls: 'last' } },
          { id: 'asc' },
        ],
        skip: offset,
        take: take + 1,
      });
      nextCursor = rows.length > take ? encodeCursor({ o: offset + take }) : null;
      rows = rows.slice(0, take);
    } else {
      const keyset = keysetWhere(query.cursor, 'publishedAt');
      const found = await this.prisma.job.findMany({
        where: keyset ? { AND: [where, keyset] } : where,
        select: jobCardSelect,
        orderBy: [{ publishedAt: 'desc' }, { id: 'desc' }],
        take: take + 1,
      });
      const page = keysetPage(found, take, (r) => r.publishedAt ?? r.createdAt);
      rows = page.items;
      nextCursor = page.nextCursor;
    }
    const favorites = viewer
      ? new Set(
          (
            await this.prisma.favorite.findMany({
              where: { userId: viewer.userId, jobId: { in: rows.map((r) => r.id) } },
              select: { jobId: true },
            })
          ).map((f) => f.jobId),
        )
      : new Set<string | null>();
    return new Page(
      rows.map((r) => presentJobCard(r, { isFavorite: favorites.has(r.id) })),
      nextCursor,
    );
  }

  async detail(id: string, viewer?: AuthUser, viewerKey?: string) {
    const job = await this.prisma.job.findFirst({ where: { id, deletedAt: null }, select: jobDetailSelect });
    if (!job) throw AppError.notFound('Job');
    const isOwner = viewer?.userId === job.employerId;
    if (job.status !== JobStatus.ACTIVE && job.status !== JobStatus.FILLED && !isOwner)
      throw AppError.notFound('Job');
    if (!isOwner && viewerKey && job.status === JobStatus.ACTIVE) {
      const fresh = await this.redis.client.set(`view:job:${id}:${viewerKey}`, '1', 'EX', 86400, 'NX');
      if (fresh === 'OK')
        await this.prisma.job.update({ where: { id }, data: { viewCount: { increment: 1 } } });
    }
    const [favorite, application] = viewer
      ? await Promise.all([
          this.prisma.favorite.count({ where: { userId: viewer.userId, jobId: id } }),
          this.prisma.jobApplication.findUnique({
            where: { jobId_applicantId: { jobId: id, applicantId: viewer.userId } },
            select: { id: true, status: true, createdAt: true },
          }),
        ])
      : [0, null];
    return presentJobDetail(job, env().WEB_BASE_URL, {
      isFavorite: favorite > 0,
      isOwner,
      myApplication: application
        ? { id: application.id, status: application.status.toLowerCase(), appliedAt: application.createdAt }
        : null,
    });
  }

  async mine(userId: string, query: MyJobsQuery) {
    const take = pageSize(query.limit);
    const rows = await this.prisma.job.findMany({
      where: {
        employerId: userId,
        deletedAt: null,
        ...(query.status ? { status: dbEnum(query.status) as JobStatus } : {}),
        ...keysetWhere(query.cursor, 'updatedAt'),
      },
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      select: { ...jobCardSelect, updatedAt: true, _count: { select: { applications: true } } },
      take: take + 1,
    });
    const page = keysetPage(rows, take, (r) => r.updatedAt);
    return new Page(
      page.items.map((r) => ({ ...presentJobCard(r), applicationCount: r._count.applications })),
      page.nextCursor,
    );
  }

  private async data(dto: JobInputDto): Promise<Prisma.JobUncheckedCreateInput> {
    if (dto.salaryMin != null && dto.salaryMax != null && dto.salaryMax < dto.salaryMin) {
      throw AppError.validation('salaryMax must be ≥ salaryMin', { field: 'salaryMax' });
    }
    const signals = assessText(dto.title, dto.description);
    if (hasBlocking(signals)) throw AppError.validation('Remove card numbers from the vacancy');
    const place = await this.locations.resolvePlace(dto.place);
    return {
      employerId: '',
      title: dto.title,
      companyName: dto.companyName,
      description: dto.description,
      requirements: (dto.requirements ?? []).map((r) => r.trim()).filter(Boolean),
      responsibilities: (dto.responsibilities ?? []).map((r) => r.trim()).filter(Boolean),
      salaryMin: dto.salaryMin ?? null,
      salaryMax: dto.salaryMax ?? null,
      salaryCurrency: dto.salaryCurrency === 'usd' ? Currency.USD : Currency.UZS,
      salaryNegotiable: dto.salaryNegotiable ?? (dto.salaryMin == null && dto.salaryMax == null),
      employmentType: dbEnum(dto.employmentType) as EmploymentType,
      workFormat: dto.workFormat ? (dbEnum(dto.workFormat) as WorkFormat) : WorkFormat.ON_SITE,
      experience: dto.experience ? (dbEnum(dto.experience) as ExperienceLevel) : ExperienceLevel.NONE,
      workSchedule: dto.workSchedule,
      applicationMode: dto.applicationMode
        ? (dbEnum(dto.applicationMode) as ApplicationMode)
        : ApplicationMode.IN_APP,
      regionId: place.regionId,
      districtId: place.districtId,
      lat: place.lat,
      lng: place.lng,
      searchText: buildSearchText(dto.title, dto.companyName, dto.description),
    };
  }

  async create(user: AuthUser, dto: JobInputDto) {
    await this.limiter.consume(`job:create:${user.userId}`, 20, 24 * 3600);
    const data = await this.data(dto);
    const publish = dto.publish !== false;
    if (publish) await this.limits.assertCanActivateJob(user.userId);
    const job = await this.prisma.job.create({
      data: {
        ...data,
        employerId: user.userId,
        status: publish ? JobStatus.ACTIVE : JobStatus.DRAFT,
        ...(publish ? this.publication() : {}),
      },
    });
    await this.postModerate(job.id, dto);
    return this.detail(job.id, user);
  }

  async update(user: AuthUser, id: string, dto: JobInputDto) {
    await this.owned(user, id);
    const { employerId: _ignored, ...data } = await this.data(dto);
    await this.prisma.job.update({ where: { id }, data });
    await this.postModerate(id, dto);
    return this.detail(id, user);
  }

  async changeStatus(user: AuthUser, id: string, status: string) {
    const job = await this.owned(user, id);
    const next = dbEnum(status) as JobStatus;
    if (!OWNER_TRANSITIONS[job.status].includes(next))
      throw AppError.invalidState(`Cannot move from ${job.status} to ${next}`);
    if (next === JobStatus.ACTIVE) await this.limits.assertCanActivateJob(user.userId, id);
    const republish = next === JobStatus.ACTIVE && job.status !== JobStatus.PAUSED;
    await this.prisma.job.update({
      where: { id },
      data: { status: next, ...(republish ? this.publication() : {}) },
    });
    return this.detail(id, user);
  }

  async remove(user: AuthUser, id: string): Promise<void> {
    await this.owned(user, id);
    await this.prisma.job.update({
      where: { id },
      data: { deletedAt: new Date(), status: JobStatus.ARCHIVED },
    });
  }

  /** Employer phone for PHONE/BOTH application modes, honoring privacy settings. */
  async contact(viewer: AuthUser, id: string) {
    await this.limiter.consume(`contact:${viewer.userId}`, 40, 3600);
    const job = await this.prisma.job.findFirst({
      where: { id, deletedAt: null, status: JobStatus.ACTIVE },
      select: {
        applicationMode: true,
        employer: { select: { phone: true, profile: { select: { showPhone: true } } } },
      },
    });
    if (!job) throw AppError.notFound('Job');
    if (job.applicationMode === ApplicationMode.IN_APP || !job.employer.profile?.showPhone) {
      throw AppError.forbidden('The employer accepts applications in the app');
    }
    return { phone: job.employer.phone };
  }

  async expireStale(): Promise<number> {
    return (
      await this.prisma.job.updateMany({
        where: { status: JobStatus.ACTIVE, expiresAt: { lt: new Date() } },
        data: { status: JobStatus.EXPIRED },
      })
    ).count;
  }

  private publication() {
    const now = new Date();
    return { publishedAt: now, expiresAt: new Date(now.getTime() + env().JOB_TTL_DAYS * 24 * 3600 * 1000) };
  }

  /** Vacancies publish immediately; suspicious ones are queued for review. */
  private async postModerate(id: string, dto: JobInputDto): Promise<void> {
    if (requiresModeration(assessText(dto.title, dto.description))) {
      await this.queues.moderation({ targetType: 'JOB', targetId: id, reason: 'content_heuristics' });
    }
  }

  private async owned(user: AuthUser, id: string) {
    const job = await this.prisma.job.findFirst({ where: { id, deletedAt: null } });
    if (!job || job.employerId !== user.userId) throw AppError.notFound('Job');
    return job;
  }
}
