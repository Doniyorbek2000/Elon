import { Inject, Injectable, Logger } from '@nestjs/common';
import { DevicePlatform, NotificationType, Prisma } from '@prisma/client';

import { AppError } from '../../common/errors';
import { Page, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { apiEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { PushJob, QueueService } from '../../infra/queues';
import { PUSH_PROVIDER, PushProvider } from './push.provider';

export interface NotifyInput {
  type: NotificationType;
  title: string;
  body: string;
  /** Deep link route inside the app, e.g. "/chat/<id>". */
  route: string;
  data?: Record<string, string>;
}

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly queues: QueueService,
    @Inject(PUSH_PROVIDER) private readonly push: PushProvider,
  ) {}

  /**
   * In-app notification + push. Chat messages use push only (the chat list
   * already has unread counters), everything else lands in the inbox too.
   */
  async notify(userId: string, input: NotifyInput, options: { inbox?: boolean; dedupeKey?: string } = {}) {
    const data = { route: input.route, type: apiEnum(input.type), ...input.data };
    let notificationId: string | undefined;
    if (options.inbox ?? input.type !== NotificationType.MESSAGE) {
      const row = await this.prisma.notification.create({
        data: { userId, type: input.type, title: input.title, body: input.body, data },
      });
      notificationId = row.id;
    }
    await this.queues.push({
      userId,
      title: input.title,
      body: input.body,
      data: { ...data, ...(notificationId ? { notificationId } : {}) },
      dedupeKey: options.dedupeKey ?? notificationId ?? `${userId}:${Date.now()}`,
    });
  }

  /** Worker: fan out to all active devices; disable dead tokens. Idempotent per job. */
  async deliverPush(job: PushJob): Promise<{ sent: number; disabled: number }> {
    const devices = await this.prisma.pushDevice.findMany({
      where: { userId: job.userId, disabledAt: null },
    });
    let sent = 0;
    let disabled = 0;
    for (const device of devices) {
      const result = await this.push.send({
        token: device.token,
        title: job.title,
        body: job.body,
        data: job.data,
      });
      if (result === 'sent') sent++;
      if (result === 'invalid_token') {
        disabled++;
        await this.prisma.pushDevice.update({ where: { id: device.id }, data: { disabledAt: new Date() } });
      }
      if (result === 'retry') throw new Error('Push provider asked to retry');
    }
    return { sent, disabled };
  }

  async list(userId: string, cursor?: string, limit?: number) {
    const take = pageSize(limit);
    const rows = await this.prisma.notification.findMany({
      where: { userId, ...keysetWhere(cursor) },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
    });
    const page = keysetPage(rows, take, (r) => r.createdAt);
    return new Page(
      page.items.map((n) => ({
        id: n.id,
        type: apiEnum(n.type),
        title: n.title,
        body: n.body,
        data: n.data,
        deepLink: (n.data as Record<string, unknown>).route ?? null,
        isRead: n.readAt != null,
        createdAt: n.createdAt,
      })),
      page.nextCursor,
      { unreadCount: await this.unreadCount(userId) },
    );
  }

  unreadCount(userId: string): Promise<number> {
    return this.prisma.notification.count({ where: { userId, readAt: null } });
  }

  async markRead(userId: string, id: string): Promise<void> {
    const result = await this.prisma.notification.updateMany({
      where: { id, userId },
      data: { readAt: new Date() },
    });
    if (result.count === 0) throw AppError.notFound('Notification');
  }

  async markAllRead(userId: string): Promise<number> {
    return (
      await this.prisma.notification.updateMany({
        where: { userId, readAt: null },
        data: { readAt: new Date() },
      })
    ).count;
  }

  /** Registers/moves an FCM token to the current user + session. */
  async registerDevice(userId: string, sessionId: string, token: string, platform: string, locale?: string) {
    const data: Prisma.PushDeviceUncheckedCreateInput = {
      userId,
      sessionId,
      token,
      platform: platform.toUpperCase() as DevicePlatform,
      locale,
      lastSeenAt: new Date(),
      disabledAt: null,
    };
    await this.prisma.pushDevice.upsert({ where: { token }, create: data, update: data });
    this.logger.debug({ userId }, 'Push device registered');
  }

  async unregisterDevice(userId: string, token: string): Promise<void> {
    await this.prisma.pushDevice.deleteMany({ where: { token, userId } });
  }
}
