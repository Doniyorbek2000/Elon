import { Body, Controller, Delete, Get, Global, Injectable, Module, Param, ParseUUIDPipe, Post, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { ModerationAction, ReportReason, ReportTarget } from '@prisma/client';
import { IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

import { AuthUser, CurrentUser } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { presentUser, publicUserSelect } from '../../common/presenters';
import { dbEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { QueueService } from '../../infra/queues';
import { RateLimiterService } from '../../infra/rate-limiter.service';

/** Distinct open reports after which content is queued for moderation. */
const ESCALATION_THRESHOLD = 3;

class ReportDto {
  @IsIn(['listing', 'user', 'job', 'provider', 'conversation', 'message', 'review'])
  targetType!: string;

  @IsUUID()
  targetId!: string;

  @IsIn(['fraud', 'prohibited', 'wrongInfo', 'wrongCategory', 'duplicate', 'spam', 'offensive', 'other'])
  reason!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  comment?: string;
}

@Injectable()
export class SafetyService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly queues: QueueService,
    private readonly limiter: RateLimiterService,
  ) {}

  async block(blockerId: string, blockedId: string): Promise<void> {
    if (blockerId === blockedId) throw AppError.validation('You cannot block yourself');
    const exists = await this.prisma.user.count({ where: { id: blockedId } });
    if (!exists) throw AppError.notFound('User');
    await this.prisma.block.upsert({
      where: { blockerId_blockedId: { blockerId, blockedId } },
      create: { blockerId, blockedId },
      update: {},
    });
  }

  async unblock(blockerId: string, blockedId: string): Promise<void> {
    await this.prisma.block.deleteMany({ where: { blockerId, blockedId } });
  }

  async blocked(blockerId: string) {
    const rows = await this.prisma.block.findMany({
      where: { blockerId },
      orderBy: { createdAt: 'desc' },
      include: { blocked: { select: publicUserSelect } },
    });
    return rows.map((r) => ({ user: presentUser(r.blocked), blockedAt: r.createdAt }));
  }

  /** True if either user blocked the other. */
  async isBlockedBetween(a: string, b: string): Promise<boolean> {
    const count = await this.prisma.block.count({
      where: { OR: [{ blockerId: a, blockedId: b }, { blockerId: b, blockedId: a }] },
    });
    return count > 0;
  }

  async report(reporterId: string, dto: ReportDto) {
    await this.limiter.consume(`report:${reporterId}`, 20, 3600);
    const targetType = dbEnum(dto.targetType) as ReportTarget;
    await this.assertTargetExists(targetType, dto.targetId, reporterId);
    const reason = dbEnum(dto.reason) as ReportReason;
    const report = await this.prisma.report.upsert({
      where: { reporterId_targetType_targetId: { reporterId, targetType, targetId: dto.targetId } },
      create: { reporterId, targetType, targetId: dto.targetId, reason, comment: dto.comment },
      update: { reason, comment: dto.comment },
    });
    const open = await this.prisma.report.count({ where: { targetType, targetId: dto.targetId, status: 'OPEN' } });
    if (open >= ESCALATION_THRESHOLD) {
      await this.prisma.moderationEvent.create({
        data: { targetType, targetId: dto.targetId, action: ModerationAction.AUTO_FLAGGED, reason: `${open} reports` },
      });
      await this.queues.moderation({ targetType, targetId: dto.targetId, reason: 'report_threshold' });
    }
    return { id: report.id, status: 'open' };
  }

  private async assertTargetExists(type: ReportTarget, id: string, reporterId: string): Promise<void> {
    const found = await (async () => {
      switch (type) {
        case ReportTarget.LISTING:
          return this.prisma.listing.count({ where: { id } });
        case ReportTarget.USER:
          if (id === reporterId) throw AppError.validation('You cannot report yourself');
          return this.prisma.user.count({ where: { id } });
        case ReportTarget.JOB:
          return this.prisma.job.count({ where: { id } });
        case ReportTarget.PROVIDER:
          return this.prisma.serviceProvider.count({ where: { id } });
        case ReportTarget.REVIEW:
          return this.prisma.review.count({ where: { id } });
        case ReportTarget.CONVERSATION:
          // Only participants can report a conversation.
          return this.prisma.conversationParticipant.count({ where: { conversationId: id, userId: reporterId } });
        case ReportTarget.MESSAGE:
          return this.prisma.message.count({
            where: { id, conversation: { participants: { some: { userId: reporterId } } } },
          });
      }
    })();
    if (!found) throw AppError.notFound('Report target');
  }
}

@ApiTags('safety')
@ApiBearerAuth()
@Controller()
class SafetyController {
  constructor(private readonly safety: SafetyService) {}

  @Post('reports')
  report(@CurrentUser() user: AuthUser, @Body() dto: ReportDto) {
    return this.safety.report(user.userId, dto);
  }

  @Get('blocks')
  blocked(@CurrentUser() user: AuthUser) {
    return this.safety.blocked(user.userId);
  }

  @Put('blocks/:userId')
  async block(@CurrentUser() user: AuthUser, @Param('userId', ParseUUIDPipe) target: string) {
    await this.safety.block(user.userId, target);
    return { ok: true };
  }

  @Delete('blocks/:userId')
  async unblock(@CurrentUser() user: AuthUser, @Param('userId', ParseUUIDPipe) target: string) {
    await this.safety.unblock(user.userId, target);
    return { ok: true };
  }
}

@Global()
@Module({ controllers: [SafetyController], providers: [SafetyService], exports: [SafetyService] })
export class SafetyModule {}
