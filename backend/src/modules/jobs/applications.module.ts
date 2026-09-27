import { Body, Controller, Get, HttpCode, Injectable, Module, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { ApplicationMode, ApplicationStatus, JobStatus, NotificationType, ResumeVisibility } from '@prisma/client';

import { AuthUser, CurrentUser } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { CursorQuery, Page, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { presentUser, publicUserSelect } from '../../common/presenters';
import { apiEnum, dbEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { NotificationsService } from '../notifications/notifications.service';
import { SafetyService } from '../safety/safety.module';
import { jobCardSelect, presentJobCard } from './job.presenter';
import { ApplicantsQuery, ApplicationStatusDto, ApplyDto } from './jobs.dto';
import { presentResume, resumeInclude } from './resume.presenter';

const FINAL: ApplicationStatus[] = [ApplicationStatus.ACCEPTED, ApplicationStatus.REJECTED, ApplicationStatus.WITHDRAWN];

/** Employer-side transitions. */
const EMPLOYER_TRANSITIONS: Record<ApplicationStatus, ApplicationStatus[]> = {
  SUBMITTED: [ApplicationStatus.VIEWED, ApplicationStatus.SHORTLISTED, ApplicationStatus.REJECTED, ApplicationStatus.ACCEPTED],
  VIEWED: [ApplicationStatus.SHORTLISTED, ApplicationStatus.REJECTED, ApplicationStatus.ACCEPTED],
  SHORTLISTED: [ApplicationStatus.REJECTED, ApplicationStatus.ACCEPTED],
  REJECTED: [],
  ACCEPTED: [],
  WITHDRAWN: [],
};

const STATUS_COPY: Partial<Record<ApplicationStatus, string>> = {
  VIEWED: 'Arizangiz ko‘rib chiqildi',
  SHORTLISTED: 'Siz saralangan nomzodlar ro‘yxatidasiz',
  ACCEPTED: 'Arizangiz qabul qilindi',
  REJECTED: 'Arizangiz bo‘yicha javob keldi',
};

@Injectable()
export class ApplicationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly safety: SafetyService,
    private readonly limiter: RateLimiterService,
  ) {}

  private present(application: {
    id: string;
    status: ApplicationStatus;
    coverLetter: string | null;
    createdAt: Date;
    statusChangedAt: Date;
  }) {
    return {
      id: application.id,
      status: apiEnum(application.status),
      message: application.coverLetter,
      appliedAt: application.createdAt,
      statusChangedAt: application.statusChangedAt,
    };
  }

  async apply(user: AuthUser, jobId: string, dto: ApplyDto) {
    await this.limiter.consume(`apply:${user.userId}`, 50, 24 * 3600);
    const job = await this.prisma.job.findFirst({ where: { id: jobId, deletedAt: null } });
    if (!job || job.status !== JobStatus.ACTIVE) throw AppError.notFound('Job');
    if (job.employerId === user.userId) throw AppError.validation('You cannot apply to your own vacancy');
    if (job.applicationMode === ApplicationMode.PHONE) throw AppError.invalidState('This vacancy accepts phone calls only');
    if (await this.safety.isBlockedBetween(user.userId, job.employerId)) {
      throw new AppError('BLOCKED', 'You cannot apply to this employer', 403);
    }
    const existing = await this.prisma.jobApplication.findUnique({
      where: { jobId_applicantId: { jobId, applicantId: user.userId } },
    });
    if (existing && existing.status !== ApplicationStatus.WITHDRAWN) throw AppError.conflict('You have already applied');

    const application = existing
      ? await this.prisma.jobApplication.update({
          where: { id: existing.id },
          data: { status: ApplicationStatus.SUBMITTED, coverLetter: dto.coverLetter, statusChangedAt: new Date(), viewedAt: null },
        })
      : await this.prisma.jobApplication.create({
          data: { jobId, applicantId: user.userId, coverLetter: dto.coverLetter },
        });
    const applicant = await this.prisma.profile.findUnique({ where: { userId: user.userId }, select: { displayName: true } });
    await this.notifications.notify(job.employerId, {
      type: NotificationType.APPLICATION_RECEIVED,
      title: 'Yangi ariza',
      body: `${applicant?.displayName ?? 'Nomzod'} «${job.title}» vakansiyasiga ariza yubordi`,
      route: `/employer/jobs/${job.id}/applicants`,
      data: { jobId: job.id, applicationId: application.id },
    });
    return { ...this.present(application), job: { id: job.id, title: job.title } };
  }

  async mine(userId: string, cursor?: string, limit?: number) {
    const take = pageSize(limit);
    const rows = await this.prisma.jobApplication.findMany({
      where: { applicantId: userId, ...keysetWhere(cursor) },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      include: { job: { select: jobCardSelect } },
      take: take + 1,
    });
    const page = keysetPage(rows, take, (r) => r.createdAt);
    return new Page(
      page.items.map((a) => ({ ...this.present(a), job: presentJobCard(a.job) })),
      page.nextCursor,
    );
  }

  async withdraw(user: AuthUser, id: string) {
    const application = await this.prisma.jobApplication.findUnique({ where: { id } });
    if (!application || application.applicantId !== user.userId) throw AppError.notFound('Application');
    if (FINAL.includes(application.status)) throw AppError.invalidState('Application can no longer be withdrawn');
    const updated = await this.prisma.jobApplication.update({
      where: { id },
      data: { status: ApplicationStatus.WITHDRAWN, statusChangedAt: new Date() },
    });
    return this.present(updated);
  }

  /** Applicants of the caller's own vacancy. Includes contact data (consented by applying). */
  async applicants(user: AuthUser, jobId: string, query: ApplicantsQuery) {
    const job = await this.prisma.job.findFirst({ where: { id: jobId, deletedAt: null } });
    if (!job || job.employerId !== user.userId) throw AppError.notFound('Job');
    const take = pageSize(query.limit);
    const rows = await this.prisma.jobApplication.findMany({
      where: {
        jobId,
        ...(query.status ? { status: dbEnum(query.status) as ApplicationStatus } : {}),
        ...keysetWhere(query.cursor),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      include: {
        applicant: { select: { ...publicUserSelect, phone: true, resume: { include: resumeInclude } } },
      },
      take: take + 1,
    });
    const page = keysetPage(rows, take, (r) => r.createdAt);
    return new Page(
      page.items.map((a) => ({
        ...this.present(a),
        applicant: presentUser(a.applicant),
        phone: a.applicant.phone,
        resume:
          a.applicant.resume && a.applicant.resume.visibility !== ResumeVisibility.HIDDEN
            ? presentResume(a.applicant.resume, a.applicant)
            : null,
      })),
      page.nextCursor,
    );
  }

  async setStatus(user: AuthUser, id: string, dto: ApplicationStatusDto) {
    const application = await this.prisma.jobApplication.findUnique({ where: { id }, include: { job: true } });
    if (!application || application.job.employerId !== user.userId) throw AppError.notFound('Application');
    const next = dbEnum(dto.status) as ApplicationStatus;
    if (!EMPLOYER_TRANSITIONS[application.status].includes(next)) {
      throw AppError.invalidState(`Cannot move from ${application.status} to ${next}`);
    }
    const updated = await this.prisma.jobApplication.update({
      where: { id },
      data: { status: next, statusChangedAt: new Date(), viewedAt: application.viewedAt ?? new Date() },
    });
    await this.notifications.notify(application.applicantId, {
      type: NotificationType.APPLICATION_STATUS,
      title: STATUS_COPY[next] ?? 'Ariza holati yangilandi',
      body: `«${application.job.title}» — ${application.job.companyName}`,
      route: '/account/applications',
      data: { applicationId: id, jobId: application.jobId, status: apiEnum(next) },
    });
    return this.present(updated);
  }
}

@ApiTags('applications')
@ApiBearerAuth()
@Controller()
class ApplicationsController {
  constructor(private readonly applications: ApplicationsService) {}

  @Post('jobs/:id/applications')
  apply(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ApplyDto) {
    return this.applications.apply(user, id, dto);
  }

  @Get('jobs/:id/applications')
  applicants(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Query() query: ApplicantsQuery) {
    return this.applications.applicants(user, id, query);
  }

  @Get('me/applications')
  mine(@CurrentUser() user: AuthUser, @Query() query: CursorQuery) {
    return this.applications.mine(user.userId, query.cursor, query.limit);
  }

  @Post('applications/:id/withdraw')
  @HttpCode(200)
  withdraw(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.applications.withdraw(user, id);
  }

  @Patch('applications/:id/status')
  status(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ApplicationStatusDto) {
    return this.applications.setStatus(user, id, dto);
  }
}

@Module({ controllers: [ApplicationsController], providers: [ApplicationsService] })
export class ApplicationsModule {}
