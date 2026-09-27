import { HttpStatus, Injectable } from '@nestjs/common';
import {
  ConversationContext,
  JobStatus,
  ListingStatus,
  MediaPurpose,
  MessageType,
  NotificationType,
  Prisma,
  ProviderStatus,
  ResumeVisibility,
} from '@prisma/client';

import { AuthUser } from '../../common/auth.decorators';
import { isRiskyMessage } from '../../common/content-risk';
import { AppError } from '../../common/errors';
import { Page, decodeCursor, encodeCursor, pageSize } from '../../common/pagination';
import {
  mediaSelect,
  presentMedia,
  presentMoney,
  presentUser,
  publicUserSelect,
} from '../../common/presenters';
import { apiEnum } from '../../common/text';
import { PresenceService } from '../../infra/presence.service';
import { PrismaService } from '../../infra/prisma.service';
import { QueueService } from '../../infra/queues';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { RedisService } from '../../infra/redis.service';
import { MediaService } from '../media/media.service';
import { NotificationsService } from '../notifications/notifications.service';
import { SafetyService } from '../safety/safety.module';
import { ChatEmitter } from '../../infra/realtime.emitter';
import { OpenConversationDto, SendMessageDto } from './chat.dto';

const conversationInclude = {
  participants: { include: { user: { select: publicUserSelect } } },
  listing: {
    select: {
      id: true,
      title: true,
      priceAmount: true,
      currency: true,
      negotiable: true,
      media: { orderBy: { position: 'asc' }, take: 1, select: { media: { select: mediaSelect } } },
    },
  },
  job: {
    select: {
      id: true,
      title: true,
      companyName: true,
      salaryMin: true,
      salaryMax: true,
      salaryCurrency: true,
    },
  },
  provider: {
    select: {
      id: true,
      displayName: true,
      profession: true,
      user: { select: { profile: { select: { avatar: { select: mediaSelect } } } } },
    },
  },
} satisfies Prisma.ConversationInclude;

type ConversationRow = Prisma.ConversationGetPayload<{ include: typeof conversationInclude }>;

const messageInclude = {
  attachments: { orderBy: { position: 'asc' }, select: { media: { select: mediaSelect } } },
  sharedListing: { select: { id: true, title: true, priceAmount: true, currency: true } },
} satisfies Prisma.MessageInclude;

type MessageRow = Prisma.MessageGetPayload<{ include: typeof messageInclude }>;

@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly emitter: ChatEmitter,
    private readonly safety: SafetyService,
    private readonly media: MediaService,
    private readonly notifications: NotificationsService,
    private readonly presence: PresenceService,
    private readonly limiter: RateLimiterService,
    private readonly redis: RedisService,
    private readonly queues: QueueService,
  ) {}

  // ──────────────────────────────────────────────────────────── opening

  /** Returns the existing conversation for this (context, pair) or creates it. */
  async open(user: AuthUser, dto: OpenConversationDto) {
    const { peerId, context, key } = await this.resolveContext(user.userId, dto);
    if (peerId === user.userId) throw AppError.validation('This is your own item');
    if (await this.safety.isBlockedBetween(user.userId, peerId)) {
      throw new AppError('BLOCKED', 'You cannot message this user', HttpStatus.FORBIDDEN);
    }
    const existing = await this.prisma.conversation.findUnique({
      where: { contextKey: key },
      select: { id: true },
    });
    if (!existing) {
      await this.limiter.consume(`conversation:new:${user.userId}`, 30, 3600);
      try {
        await this.prisma.conversation.create({
          data: {
            ...context,
            contextKey: key,
            participants: { create: [{ userId: user.userId }, { userId: peerId }] },
          },
        });
      } catch (error) {
        // Concurrent open by the other side: the unique key already exists.
        if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002')) throw error;
      }
    }
    const conversation = await this.prisma.conversation.findUniqueOrThrow({
      where: { contextKey: key },
      include: conversationInclude,
    });
    return this.presentConversation(conversation, user.userId);
  }

  private async resolveContext(userId: string, dto: OpenConversationDto) {
    const pair = (other: string) => [userId, other].sort().join(':');
    switch (dto.contextType) {
      case 'listing': {
        const listing = await this.prisma.listing.findFirst({
          where: {
            id: dto.contextId,
            deletedAt: null,
            status: { in: [ListingStatus.ACTIVE, ListingStatus.RESERVED] },
          },
          select: { id: true, sellerId: true },
        });
        if (!listing) throw AppError.notFound('Listing');
        return {
          peerId: listing.sellerId,
          context: { contextType: ConversationContext.LISTING, listingId: listing.id },
          key: `LISTING:${listing.id}:${pair(listing.sellerId)}`,
        };
      }
      case 'job': {
        const job = await this.prisma.job.findFirst({
          where: { id: dto.contextId, deletedAt: null, status: JobStatus.ACTIVE },
          select: { id: true, employerId: true },
        });
        if (!job) throw AppError.notFound('Job');
        return {
          peerId: job.employerId,
          context: { contextType: ConversationContext.JOB, jobId: job.id },
          key: `JOB:${job.id}:${pair(job.employerId)}`,
        };
      }
      case 'service': {
        const provider = await this.prisma.serviceProvider.findFirst({
          where: { id: dto.contextId, deletedAt: null, status: ProviderStatus.ACTIVE },
          select: { id: true, userId: true },
        });
        if (!provider) throw AppError.notFound('Provider');
        return {
          peerId: provider.userId,
          context: { contextType: ConversationContext.SERVICE, providerId: provider.id },
          key: `SERVICE:${provider.id}:${pair(provider.userId)}`,
        };
      }
      case 'candidate': {
        // Employers may contact public candidates, or candidates who applied to them.
        const resume = await this.prisma.resume.findUnique({
          where: { id: dto.contextId },
          select: { userId: true, visibility: true },
        });
        if (!resume || resume.visibility === ResumeVisibility.HIDDEN) throw AppError.notFound('Resume');
        if (resume.visibility === ResumeVisibility.APPLICATIONS_ONLY) {
          const applied = await this.prisma.jobApplication.count({
            where: { applicantId: resume.userId, job: { employerId: userId } },
          });
          if (!applied) throw AppError.notFound('Resume');
        }
        return {
          peerId: resume.userId,
          context: { contextType: ConversationContext.DIRECT },
          key: `DIRECT:${pair(resume.userId)}`,
        };
      }
      default:
        throw AppError.validation('Unknown context');
    }
  }

  // ──────────────────────────────────────────────────────────── reading

  async list(userId: string, cursor?: string, limit?: number) {
    const take = pageSize(limit);
    const keyset = decodeCursor<{ t: string; id: string }>(cursor);
    const where: Prisma.ConversationWhereInput = { participants: { some: { userId, archivedAt: null } } };
    if (keyset) {
      const t = new Date(keyset.t);
      where.OR = [{ updatedAt: { lt: t } }, { updatedAt: t, id: { lt: keyset.id } }];
    }
    const rows = await this.prisma.conversation.findMany({
      where,
      include: conversationInclude,
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
    });
    const page = rows.slice(0, take);
    const lastMessages = await this.prisma.message.findMany({
      where: { id: { in: page.map((c) => c.lastMessageId).filter((id): id is string => !!id) } },
      select: { id: true, type: true, text: true, senderId: true },
    });
    const byId = new Map(lastMessages.map((m) => [m.id, m]));
    const peers = page
      .map((c) => c.participants.find((p) => p.userId !== userId)?.userId)
      .filter((id): id is string => !!id);
    const [online, blocks] = await Promise.all([
      this.presence.onlineMany(peers),
      this.prisma.block.findMany({
        where: {
          OR: [
            { blockerId: userId, blockedId: { in: peers } },
            { blockedId: userId, blockerId: { in: peers } },
          ],
        },
        select: { blockerId: true, blockedId: true },
      }),
    ]);
    const blocked = new Set(blocks.map((b) => (b.blockerId === userId ? b.blockedId : b.blockerId)));
    const items = page.map((c) => {
      const last = c.lastMessageId ? byId.get(c.lastMessageId) : undefined;
      return this.presentConversation(c, userId, {
        online,
        blocked,
        lastMessagePreview: last ? this.preview(last.type, last.text) : null,
      });
    });
    const lastRow = page[page.length - 1];
    return new Page(
      items,
      rows.length > take && lastRow
        ? encodeCursor({ t: lastRow.updatedAt.toISOString(), id: lastRow.id })
        : null,
    );
  }

  async get(userId: string, conversationId: string) {
    await this.assertParticipant(userId, conversationId);
    const conversation = await this.prisma.conversation.findUniqueOrThrow({
      where: { id: conversationId },
      include: conversationInclude,
    });
    const peer = conversation.participants.find((p) => p.userId !== userId)?.userId;
    const [online, blocked] = await Promise.all([
      this.presence.onlineMany(peer ? [peer] : []),
      peer ? this.safety.isBlockedBetween(userId, peer) : Promise.resolve(false),
    ]);
    return this.presentConversation(conversation, userId, {
      online,
      blocked: new Set(blocked && peer ? [peer] : []),
    });
  }

  /** Newest first; `cursor` walks back in time (scrolling up loads older). */
  async messages(userId: string, conversationId: string, cursor?: string, limit?: number) {
    await this.assertParticipant(userId, conversationId);
    const take = pageSize(limit);
    const keyset = decodeCursor<{ t: string; id: string }>(cursor);
    const where: Prisma.MessageWhereInput = { conversationId, deletedAt: null };
    if (keyset) {
      const t = new Date(keyset.t);
      where.OR = [{ createdAt: { lt: t } }, { createdAt: t, id: { lt: keyset.id } }];
    }
    const [rows, participants] = await Promise.all([
      this.prisma.message.findMany({
        where,
        include: messageInclude,
        orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
        take: take + 1,
      }),
      this.prisma.conversationParticipant.findMany({ where: { conversationId } }),
    ]);
    const peer = participants.find((p) => p.userId !== userId);
    const page = rows.slice(0, take);
    const last = page[page.length - 1];
    return new Page(
      page.map((m) => this.presentMessage(m, peer)),
      rows.length > take && last ? encodeCursor({ t: last.createdAt.toISOString(), id: last.id }) : null,
    );
  }

  // ──────────────────────────────────────────────────────────── writing

  async send(user: AuthUser, conversationId: string, dto: SendMessageDto) {
    const participants = await this.assertParticipant(user.userId, conversationId);
    const peerIds = participants.filter((p) => p.userId !== user.userId).map((p) => p.userId);
    for (const peerId of peerIds) {
      if (await this.safety.isBlockedBetween(user.userId, peerId)) {
        throw new AppError('BLOCKED', 'You cannot message this user', HttpStatus.FORBIDDEN);
      }
    }
    if (dto.clientId) {
      const duplicate = await this.prisma.message.findUnique({
        where: { senderId_clientId: { senderId: user.userId, clientId: dto.clientId } },
        include: messageInclude,
      });
      if (duplicate) return this.presentMessage(duplicate, undefined);
    }
    await this.limiter.consume(`msg:${user.userId}`, 30, 60);

    const type = {
      text: MessageType.TEXT,
      image: MessageType.IMAGE,
      listingShare: MessageType.LISTING_SHARE,
    }[dto.type]!;
    if (type === MessageType.TEXT && !dto.text)
      throw AppError.validation('Text is required', { field: 'text' });
    let mediaIds: string[] = [];
    if (type === MessageType.IMAGE) {
      if (!dto.mediaIds?.length)
        throw AppError.validation('Attach at least one image', { field: 'mediaIds' });
      mediaIds = await this.media.assertOwned(user.userId, dto.mediaIds, [MediaPurpose.CHAT]);
    }
    if (type === MessageType.LISTING_SHARE) {
      const shared = dto.sharedListingId
        ? await this.prisma.listing.count({
            where: { id: dto.sharedListingId, status: ListingStatus.ACTIVE, deletedAt: null },
          })
        : 0;
      if (!shared) throw AppError.validation('Unknown listing', { field: 'sharedListingId' });
    }
    const flagged = !!dto.text && isRiskyMessage(dto.text);
    const now = new Date();

    const message = await this.prisma.$transaction(async (tx) => {
      const created = await tx.message.create({
        data: {
          conversationId,
          senderId: user.userId,
          clientId: dto.clientId,
          type,
          text: dto.text,
          sharedListingId: type === MessageType.LISTING_SHARE ? dto.sharedListingId : null,
          flagged,
          createdAt: now,
          attachments: { create: mediaIds.map((mediaId, position) => ({ mediaId, position })) },
        },
        include: messageInclude,
      });
      await tx.conversation.update({
        where: { id: conversationId },
        data: { lastMessageAt: now, lastMessageId: created.id },
      });
      await tx.conversationParticipant.updateMany({
        where: { conversationId, userId: { in: peerIds } },
        data: { unreadCount: { increment: 1 }, archivedAt: null },
      });
      await tx.conversationParticipant.update({
        where: { conversationId_userId: { conversationId, userId: user.userId } },
        data: { lastReadAt: now, unreadCount: 0, archivedAt: null },
      });
      return created;
    });

    const presented = this.presentMessage(message, undefined);
    this.emitter.toUsers([user.userId, ...peerIds], 'message:new', { conversationId, message: presented });
    if (flagged)
      await this.queues.moderation({ targetType: 'MESSAGE', targetId: message.id, reason: 'risky_content' });
    await this.notifyOffline(user.userId, peerIds, conversationId, message);
    return presented;
  }

  /** Push only to recipients without a live socket. Preview respects privacy. */
  private async notifyOffline(
    senderId: string,
    peerIds: string[],
    conversationId: string,
    message: MessageRow,
  ) {
    const online = await this.presence.onlineMany(peerIds);
    const offline = peerIds.filter((id) => !online.has(id));
    if (!offline.length) return;
    const [sender, recipients] = await Promise.all([
      this.prisma.profile.findUnique({ where: { userId: senderId }, select: { displayName: true } }),
      this.prisma.profile.findMany({
        where: { userId: { in: offline } },
        select: { userId: true, messagePreviews: true },
      }),
    ]);
    for (const recipient of recipients) {
      await this.notifications.notify(
        recipient.userId,
        {
          type: NotificationType.MESSAGE,
          title: sender?.displayName ?? 'Yangi xabar',
          body: recipient.messagePreviews
            ? this.preview(message.type, message.text)
            : 'Sizga yangi xabar keldi',
          route: `/chat/${conversationId}`,
          data: { conversationId, messageId: message.id },
        },
        { inbox: false, dedupeKey: `msg:${message.id}:${recipient.userId}` },
      );
    }
  }

  async markRead(userId: string, conversationId: string) {
    await this.assertParticipant(userId, conversationId);
    const now = new Date();
    await this.prisma.conversationParticipant.update({
      where: { conversationId_userId: { conversationId, userId } },
      data: { lastReadAt: now, lastDeliveredAt: now, unreadCount: 0 },
    });
    const others = await this.otherParticipants(conversationId, userId);
    this.emitter.toUsers(others, 'message:read', { conversationId, userId, readAt: now });
    return { readAt: now };
  }

  async markDelivered(userId: string, conversationId: string) {
    await this.assertParticipant(userId, conversationId);
    const now = new Date();
    await this.prisma.conversationParticipant.update({
      where: { conversationId_userId: { conversationId, userId } },
      data: { lastDeliveredAt: now },
    });
    const others = await this.otherParticipants(conversationId, userId);
    this.emitter.toUsers(others, 'message:delivered', { conversationId, userId, deliveredAt: now });
    return { deliveredAt: now };
  }

  async archive(userId: string, conversationId: string): Promise<void> {
    await this.assertParticipant(userId, conversationId);
    await this.prisma.conversationParticipant.update({
      where: { conversationId_userId: { conversationId, userId } },
      data: { archivedAt: new Date() },
    });
  }

  async unreadTotal(userId: string): Promise<number> {
    const result = await this.prisma.conversationParticipant.aggregate({
      where: { userId, archivedAt: null, unreadCount: { gt: 0 } },
      _count: { _all: true },
    });
    return result._count._all;
  }

  // ──────────────────────────────────────────────────────────── helpers

  /** Membership check; cached briefly in Redis for typing/read bursts. */
  async assertParticipant(userId: string, conversationId: string) {
    const participants = await this.prisma.conversationParticipant.findMany({ where: { conversationId } });
    if (!participants.some((p) => p.userId === userId)) throw AppError.notFound('Conversation');
    await this.redis.client.set(`conv:member:${conversationId}:${userId}`, '1', 'EX', 600);
    return participants;
  }

  async isParticipantCached(userId: string, conversationId: string): Promise<boolean> {
    if (await this.redis.client.exists(`conv:member:${conversationId}:${userId}`)) return true;
    try {
      await this.assertParticipant(userId, conversationId);
      return true;
    } catch {
      return false;
    }
  }

  async otherParticipants(conversationId: string, userId: string): Promise<string[]> {
    const rows = await this.prisma.conversationParticipant.findMany({
      where: { conversationId, userId: { not: userId } },
      select: { userId: true },
    });
    return rows.map((r) => r.userId);
  }

  private preview(type: MessageType, text: string | null): string {
    switch (type) {
      case MessageType.IMAGE:
        return '📷 Rasm';
      case MessageType.LISTING_SHARE:
        return '🔗 E’lon';
      default:
        return (text ?? '').slice(0, 120);
    }
  }

  private presentConversation(
    c: ConversationRow,
    userId: string,
    extra: { online?: Set<string>; blocked?: Set<string>; lastMessagePreview?: string | null } = {},
  ) {
    const me = c.participants.find((p) => p.userId === userId);
    const peer = c.participants.find((p) => p.userId !== userId);
    const subject = this.subject(c);
    return {
      id: c.id,
      contextType: apiEnum(c.contextType),
      context: subject,
      peer: peer ? presentUser(peer.user, { isOnline: extra.online?.has(peer.userId) }) : null,
      unreadCount: me?.unreadCount ?? 0,
      lastMessageAt: c.lastMessageAt,
      lastMessagePreview: extra.lastMessagePreview ?? null,
      updatedAt: c.updatedAt,
      isBlocked: peer ? (extra.blocked?.has(peer.userId) ?? false) : false,
      peerLastReadAt: peer?.lastReadAt ?? null,
      peerLastDeliveredAt: peer?.lastDeliveredAt ?? null,
    };
  }

  private subject(c: ConversationRow) {
    if (c.listing) {
      return {
        subject: 'listing',
        refId: c.listing.id,
        title: c.listing.title,
        price: presentMoney(c.listing.priceAmount, c.listing.currency),
        negotiable: c.listing.negotiable,
        image: c.listing.media[0] ? presentMedia(c.listing.media[0].media) : null,
      };
    }
    if (c.job) {
      return {
        subject: 'job',
        refId: c.job.id,
        title: c.job.title,
        subtitle: c.job.companyName,
        salaryMin: c.job.salaryMin,
        salaryMax: c.job.salaryMax,
        currency: apiEnum(c.job.salaryCurrency),
        image: null,
      };
    }
    if (c.provider) {
      const avatar = c.provider.user.profile?.avatar;
      return {
        subject: 'service',
        refId: c.provider.id,
        title: `${c.provider.displayName} — ${c.provider.profession}`,
        image: avatar ? presentMedia(avatar) : null,
      };
    }
    return { subject: 'direct', refId: c.id, title: null, image: null };
  }

  private presentMessage(m: MessageRow, peer?: { lastReadAt: Date | null; lastDeliveredAt: Date | null }) {
    let delivery = 'sent';
    if (peer?.lastReadAt && peer.lastReadAt >= m.createdAt) delivery = 'read';
    else if (peer?.lastDeliveredAt && peer.lastDeliveredAt >= m.createdAt) delivery = 'delivered';
    return {
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      clientId: m.clientId,
      type: apiEnum(m.type),
      text: m.text,
      images: m.attachments.map((a) => presentMedia(a.media)),
      sharedListing: m.sharedListing
        ? {
            id: m.sharedListing.id,
            title: m.sharedListing.title,
            price: presentMoney(m.sharedListing.priceAmount, m.sharedListing.currency),
          }
        : null,
      flagged: m.flagged,
      createdAt: m.createdAt,
      delivery,
    };
  }
}
