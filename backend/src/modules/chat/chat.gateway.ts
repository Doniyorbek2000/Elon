import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
} from '@nestjs/websockets';
import { plainToInstance } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsBoolean, IsOptional, IsUUID, validate } from 'class-validator';
import type { Server, Socket } from 'socket.io';

import { AuthUser } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { PresenceService } from '../../infra/presence.service';
import { PrismaService } from '../../infra/prisma.service';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { AuthGuard } from '../auth/auth.guard';
import { ChatEmitter } from '../../infra/realtime.emitter';
import { SendMessageDto } from './chat.dto';
import { ChatService } from './chat.service';

class ConversationRef {
  @IsUUID()
  conversationId!: string;
}

class TypingDto extends ConversationRef {
  @IsOptional()
  @IsBoolean()
  isTyping?: boolean;
}

class SendOverSocketDto extends SendMessageDto {
  @IsUUID()
  conversationId!: string;
}

class PresenceDto {
  @IsArray()
  @ArrayMaxSize(100)
  @IsUUID('all', { each: true })
  userIds!: string[];
}

interface SocketData {
  user: AuthUser;
}

type AuthedSocket = Socket<Record<string, never>, Record<string, never>, Record<string, never>, SocketData>;

type Ack<T> = { ok: true; data: T } | { ok: false; error: { code: string; message: string } };

function failure(error: unknown): Ack<never> {
  if (error instanceof AppError) return { ok: false, error: { code: error.code, message: error.message } };
  return { ok: false, error: { code: 'INTERNAL', message: 'Unexpected error' } };
}

/**
 * Validates an event payload with the same rules as REST (whitelist, no
 * unknown fields). Failures are returned in the ack instead of a separate
 * `exception` event so clients always get a response.
 */
async function parse<T extends object>(type: new () => T, body: unknown): Promise<T> {
  const instance = plainToInstance(type, body ?? {});
  const errors = await validate(instance, { whitelist: true, forbidNonWhitelisted: true });
  if (errors.length) {
    throw AppError.validation('Invalid payload', {
      fields: errors.flatMap((e) => Object.values(e.constraints ?? {})),
    });
  }
  return instance;
}

/**
 * Realtime chat channel. Identity comes exclusively from the access token in
 * the handshake (`auth.token`); nothing in event payloads can change who the
 * sender is. Each user joins a private `user:{id}` room so every device of
 * that user receives events; REST remains the source of truth for history.
 */
@WebSocketGateway({ namespace: '/chat' })
export class ChatGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(ChatGateway.name);

  constructor(
    private readonly auth: AuthGuard,
    private readonly chat: ChatService,
    private readonly emitter: ChatEmitter,
    private readonly presence: PresenceService,
    private readonly prisma: PrismaService,
    private readonly limiter: RateLimiterService,
  ) {}

  afterInit(server: Server): void {
    this.emitter.attach(server);
    // Reject unauthenticated sockets before `connection` fires.
    server.use((socket, next) => {
      const token = this.extractToken(socket);
      if (!token)
        return next(Object.assign(new Error('UNAUTHENTICATED'), { data: { code: 'UNAUTHENTICATED' } }));
      this.auth
        .authenticate(token)
        .then((user) => {
          (socket as AuthedSocket).data.user = user;
          next();
        })
        .catch((error: unknown) => {
          const code = error instanceof AppError ? error.code : 'UNAUTHENTICATED';
          next(Object.assign(new Error(code), { data: { code } }));
        });
    });
  }

  async handleConnection(socket: AuthedSocket): Promise<void> {
    const user = socket.data.user;
    if (!user) {
      socket.disconnect(true);
      return;
    }
    await socket.join([`user:${user.userId}`, `session:${user.sessionId}`]);
    const cameOnline = await this.presence.connected(user.userId);
    if (cameOnline)
      this.emitter.toRoom(`presence:${user.userId}`, 'presence', { userId: user.userId, online: true });
  }

  async handleDisconnect(socket: AuthedSocket): Promise<void> {
    const user = socket.data.user;
    if (!user) return;
    try {
      const wentOffline = await this.presence.disconnected(user.userId);
      if (wentOffline) {
        const lastSeenAt = new Date();
        await this.prisma.user.update({ where: { id: user.userId }, data: { lastSeenAt } });
        this.emitter.toRoom(`presence:${user.userId}`, 'presence', {
          userId: user.userId,
          online: false,
          lastSeenAt,
        });
      }
    } catch (error) {
      this.logger.warn(`presence cleanup failed: ${(error as Error).message}`);
    }
  }

  @SubscribeMessage('message:send')
  async send(@ConnectedSocket() socket: AuthedSocket, @MessageBody() raw: unknown): Promise<Ack<unknown>> {
    try {
      const { conversationId, ...dto } = await parse(SendOverSocketDto, raw);
      const message = await this.chat.send(socket.data.user, conversationId, dto);
      return { ok: true, data: message };
    } catch (error) {
      return failure(error);
    }
  }

  @SubscribeMessage('conversation:read')
  async read(@ConnectedSocket() socket: AuthedSocket, @MessageBody() raw: unknown): Promise<Ack<unknown>> {
    try {
      const body = await parse(ConversationRef, raw);
      return { ok: true, data: await this.chat.markRead(socket.data.user.userId, body.conversationId) };
    } catch (error) {
      return failure(error);
    }
  }

  @SubscribeMessage('conversation:delivered')
  async delivered(
    @ConnectedSocket() socket: AuthedSocket,
    @MessageBody() raw: unknown,
  ): Promise<Ack<unknown>> {
    try {
      const body = await parse(ConversationRef, raw);
      return { ok: true, data: await this.chat.markDelivered(socket.data.user.userId, body.conversationId) };
    } catch (error) {
      return failure(error);
    }
  }

  /** Typing is ephemeral: never persisted, only relayed to the other participants. */
  @SubscribeMessage('typing')
  async typing(@ConnectedSocket() socket: AuthedSocket, @MessageBody() raw: unknown): Promise<Ack<null>> {
    const userId = socket.data.user.userId;
    try {
      const body = await parse(TypingDto, raw);
      await this.limiter.consume(`typing:${userId}`, 60, 60);
      if (!(await this.chat.isParticipantCached(userId, body.conversationId)))
        throw AppError.notFound('Conversation');
      const others = await this.chat.otherParticipants(body.conversationId, userId);
      this.emitter.toUsers(others, 'typing', {
        conversationId: body.conversationId,
        userId,
        isTyping: body.isTyping ?? true,
      });
      return { ok: true, data: null };
    } catch (error) {
      return failure(error);
    }
  }

  @SubscribeMessage('presence:heartbeat')
  async heartbeat(@ConnectedSocket() socket: AuthedSocket): Promise<Ack<null>> {
    await this.presence.heartbeat(socket.data.user.userId);
    return { ok: true, data: null };
  }

  /**
   * Subscribes to presence of chat partners only: users without a shared
   * conversation (or in a block relationship) are silently filtered out so
   * presence cannot be used to stalk arbitrary accounts.
   */
  @SubscribeMessage('presence:subscribe')
  async subscribePresence(
    @ConnectedSocket() socket: AuthedSocket,
    @MessageBody() raw: unknown,
  ): Promise<Ack<unknown>> {
    try {
      const body = await parse(PresenceDto, raw);
      const allowed = await this.chatPartners(socket.data.user.userId, body.userIds);
      await socket.join(allowed.map((id) => `presence:${id}`));
      const online = await this.presence.onlineMany(allowed);
      return { ok: true, data: allowed.map((id) => ({ userId: id, online: online.has(id) })) };
    } catch (error) {
      return failure(error);
    }
  }

  @SubscribeMessage('presence:unsubscribe')
  async unsubscribePresence(
    @ConnectedSocket() socket: AuthedSocket,
    @MessageBody() raw: unknown,
  ): Promise<Ack<null>> {
    try {
      const body = await parse(PresenceDto, raw);
      for (const id of body.userIds) await socket.leave(`presence:${id}`);
      return { ok: true, data: null };
    } catch (error) {
      return failure(error);
    }
  }

  private async chatPartners(userId: string, candidates: string[]): Promise<string[]> {
    const ids = [...new Set(candidates)].filter((id) => id !== userId);
    if (!ids.length) return [];
    const rows = await this.prisma.conversationParticipant.findMany({
      where: {
        userId: { in: ids },
        conversation: { participants: { some: { userId } } },
        user: {
          blocksMade: { none: { blockedId: userId } },
          blocksReceived: { none: { blockerId: userId } },
        },
      },
      select: { userId: true },
      distinct: ['userId'],
    });
    return rows.map((r) => r.userId);
  }

  private extractToken(socket: Socket): string | undefined {
    const auth = socket.handshake.auth as { token?: unknown } | undefined;
    if (typeof auth?.token === 'string' && auth.token) return auth.token.replace(/^Bearer\s+/i, '');
    return AuthGuard.bearer(socket.handshake.headers.authorization);
  }
}
