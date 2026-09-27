import {
  Body,
  Controller,
  Get,
  HttpCode,
  Injectable,
  Module,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Currency, EmploymentType, Prisma, ResumeVisibility } from '@prisma/client';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

import { AuthUser, CurrentUser, MaybeUser, OptionalAuth } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { CursorQuery, Page, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { publicUserSelect } from '../../common/presenters';
import { buildSearchText, dbEnum, searchTokens } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { LocationsService } from '../locations/locations.service';
import { EMPLOYMENT_TYPES } from './jobs.dto';
import { presentResume, resumeInclude } from './resume.presenter';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
const thisYear = new Date().getFullYear();

class ExperienceDto {
  @Transform(trim) @IsString() @Length(1, 100) company!: string;
  @Transform(trim) @IsString() @Length(1, 100) position!: string;
  @IsInt() @Min(1960) @Max(thisYear + 1) startYear!: number;
  @IsOptional() @IsInt() @Min(1960) @Max(thisYear + 1) endYear?: number | null;
  @IsOptional() @IsString() @MaxLength(500) description?: string;
}

class EducationDto {
  @Transform(trim) @IsString() @Length(1, 150) institution!: string;
  @IsOptional() @IsString() @MaxLength(100) degree?: string;
  @IsOptional() @IsInt() @Min(1960) @Max(thisYear + 8) endYear?: number | null;
}

class ResumeDto {
  @Transform(trim) @IsString() @Length(2, 100) title!: string;
  @IsOptional() @IsString() @MaxLength(2000) about?: string;
  @IsOptional() @IsInt() @Min(0) @Max(70) experienceYears?: number;
  @IsOptional() @IsString({ each: true }) @MaxLength(40, { each: true }) @ArrayMaxSize(30) skills?: string[];
  @IsOptional() @IsIn(EMPLOYMENT_TYPES, { each: true }) @ArrayMaxSize(4) employmentTypes?: string[];
  @IsOptional() @IsString() @MaxLength(64) preferredRegionId?: string | null;
  @IsOptional() @IsString() @MaxLength(64) preferredDistrictId?: string | null;
  @IsOptional() @IsInt() @Min(0) @Max(1_000_000_000) salaryExpectation?: number | null;
  @IsOptional() @IsIn(['uzs', 'usd']) salaryCurrency?: string;
  @IsIn(['public', 'applicationsOnly', 'hidden']) visibility!: string;
  @IsOptional()
  @ValidateNested({ each: true })
  @Type(() => ExperienceDto)
  @ArrayMaxSize(15)
  experiences?: ExperienceDto[];
  @IsOptional()
  @ValidateNested({ each: true })
  @Type(() => EducationDto)
  @ArrayMaxSize(10)
  educations?: EducationDto[];
}

class CandidatesQuery extends CursorQuery {
  @IsOptional() @IsString() @MaxLength(100) q?: string;
  @IsOptional() @IsString() @MaxLength(64) region?: string;
  @IsOptional() @IsString() @MaxLength(64) district?: string;
  @IsOptional() @IsString() @MaxLength(80) types?: string;
}

const candidateInclude = {
  ...resumeInclude,
  user: { select: publicUserSelect },
} satisfies Prisma.ResumeInclude;

@Injectable()
export class ResumesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly locations: LocationsService,
    private readonly limiter: RateLimiterService,
  ) {}

  private async names(regionId: string | null, districtId: string | null) {
    const [region, district] = await Promise.all([
      regionId ? this.prisma.region.findUnique({ where: { id: regionId }, select: { name: true } }) : null,
      districtId
        ? this.prisma.district.findUnique({ where: { id: districtId }, select: { name: true } })
        : null,
    ]);
    return { regionName: region?.name ?? null, districtName: district?.name ?? null };
  }

  async mine(userId: string) {
    const resume = await this.prisma.resume.findUnique({ where: { userId }, include: candidateInclude });
    if (!resume) return null;
    return presentResume(
      resume,
      resume.user,
      await this.names(resume.preferredRegionId, resume.preferredDistrictId),
    );
  }

  async upsert(userId: string, dto: ResumeDto) {
    let regionId: string | null = null;
    let districtId: string | null = null;
    if (dto.preferredRegionId) {
      const place = await this.locations.resolvePlace({
        regionId: dto.preferredRegionId,
        districtId: dto.preferredDistrictId,
      });
      regionId = place.regionId;
      districtId = place.districtId;
    }
    const data = {
      title: dto.title,
      about: dto.about,
      experienceYears: dto.experienceYears ?? 0,
      skills: (dto.skills ?? []).map((s) => s.trim()).filter(Boolean),
      employmentTypes: (dto.employmentTypes ?? []).map((t) => dbEnum(t) as EmploymentType),
      preferredRegionId: regionId,
      preferredDistrictId: districtId,
      salaryExpectation: dto.salaryExpectation ?? null,
      salaryCurrency: dto.salaryCurrency === 'usd' ? Currency.USD : Currency.UZS,
      visibility: dbEnum(dto.visibility) as ResumeVisibility,
      searchText: buildSearchText(dto.title, dto.about, (dto.skills ?? []).join(' ')),
    };
    await this.prisma.$transaction(async (tx) => {
      const resume = await tx.resume.upsert({ where: { userId }, create: { ...data, userId }, update: data });
      await tx.resumeExperience.deleteMany({ where: { resumeId: resume.id } });
      await tx.resumeEducation.deleteMany({ where: { resumeId: resume.id } });
      await tx.resumeExperience.createMany({
        data: (dto.experiences ?? []).map((e, sortOrder) => ({ ...e, resumeId: resume.id, sortOrder })),
      });
      await tx.resumeEducation.createMany({
        data: (dto.educations ?? []).map((e, sortOrder) => ({ ...e, resumeId: resume.id, sortOrder })),
      });
    });
    return this.mine(userId);
  }

  /** Public résumés only; applications-only CVs are visible via applicant lists. */
  async search(query: CandidatesQuery, viewer?: AuthUser) {
    const take = pageSize(query.limit);
    const and: Prisma.ResumeWhereInput[] = [{ visibility: ResumeVisibility.PUBLIC }];
    if (query.region) and.push({ preferredRegionId: query.region });
    if (query.district) and.push({ preferredDistrictId: query.district });
    const types = (query.types ?? '')
      .split(',')
      .filter(Boolean)
      .map((t) => dbEnum(t.trim()) as EmploymentType);
    if (types.length) and.push({ employmentTypes: { hasSome: types } });
    for (const token of searchTokens(query.q ?? '').slice(0, 6))
      and.push({ searchText: { contains: token } });
    if (viewer) and.push({ user: { blocksReceived: { none: { blockerId: viewer.userId } } } });
    const keyset = keysetWhere(query.cursor, 'updatedAt');
    if (keyset) and.push(keyset);
    const rows = await this.prisma.resume.findMany({
      where: { AND: and, user: { status: 'ACTIVE' } },
      include: candidateInclude,
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
    });
    const page = keysetPage(rows, take, (r) => r.updatedAt);
    const items = await Promise.all(
      page.items.map(async (r) =>
        presentResume(r, r.user, await this.names(r.preferredRegionId, r.preferredDistrictId)),
      ),
    );
    return new Page(items, page.nextCursor);
  }

  async get(id: string, viewer?: AuthUser) {
    const resume = await this.prisma.resume.findUnique({ where: { id }, include: candidateInclude });
    if (!resume || !(await this.canView(resume, viewer))) throw AppError.notFound('Resume');
    return presentResume(
      resume,
      resume.user,
      await this.names(resume.preferredRegionId, resume.preferredDistrictId),
    );
  }

  async contact(viewer: AuthUser, id: string) {
    await this.limiter.consume(`contact:${viewer.userId}`, 40, 3600);
    const resume = await this.prisma.resume.findUnique({
      where: { id },
      include: { user: { select: { phone: true, profile: { select: { showPhone: true } } } } },
    });
    if (!resume || !(await this.canView(resume, viewer))) throw AppError.notFound('Resume');
    if (!resume.user.profile?.showPhone) throw AppError.forbidden('The candidate prefers chat');
    return { phone: resume.user.phone };
  }

  /** Owner, anyone for PUBLIC, employers the candidate applied to for APPLICATIONS_ONLY. */
  private async canView(
    resume: { userId: string; visibility: ResumeVisibility },
    viewer?: AuthUser,
  ): Promise<boolean> {
    if (viewer?.userId === resume.userId) return true;
    if (resume.visibility === ResumeVisibility.PUBLIC) return true;
    if (resume.visibility === ResumeVisibility.HIDDEN || !viewer) return false;
    const applied = await this.prisma.jobApplication.count({
      where: { applicantId: resume.userId, job: { employerId: viewer.userId } },
    });
    return applied > 0;
  }
}

@ApiTags('resumes')
@Controller()
class ResumesController {
  constructor(private readonly resumes: ResumesService) {}

  @ApiBearerAuth()
  @Get('me/resume')
  mine(@CurrentUser() user: AuthUser) {
    return this.resumes.mine(user.userId);
  }

  @ApiBearerAuth()
  @Put('me/resume')
  upsert(@CurrentUser() user: AuthUser, @Body() dto: ResumeDto) {
    return this.resumes.upsert(user.userId, dto);
  }

  @OptionalAuth()
  @Get('candidates')
  search(@Query() query: CandidatesQuery, @MaybeUser() viewer?: AuthUser) {
    return this.resumes.search(query, viewer);
  }

  @OptionalAuth()
  @Get('candidates/:id')
  get(@Param('id', ParseUUIDPipe) id: string, @MaybeUser() viewer?: AuthUser) {
    return this.resumes.get(id, viewer);
  }

  @ApiBearerAuth()
  @Post('candidates/:id/contact')
  @HttpCode(200)
  contact(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.resumes.contact(user, id);
  }
}

@Module({ controllers: [ResumesController], providers: [ResumesService] })
export class ResumesModule {}
