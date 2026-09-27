import { Injectable, Logger } from '@nestjs/common';
import {
  AuthProvider,
  DevicePlatform,
  Prisma,
  UserRole,
  UserStatus,
  VerificationLevel,
} from '@prisma/client';

import { env } from '../../config/env';
import { AppError } from '../../common/errors';
import { normalizeUzPhone } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { ChatEmitter } from '../../infra/realtime.emitter';
import { DeviceDto } from './auth.dto';
import { OtpService } from './otp.service';
import { TokenService } from './token.service';

export interface RequestMeta {
  ip?: string;
  userAgent?: string;
}

export interface TokenPair {
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
  sessionId: string;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly otp: OtpService,
    private readonly realtime: ChatEmitter,
    private readonly tokens: TokenService,
  ) {}

  static phoneOrThrow(raw: string): string {
    const phone = normalizeUzPhone(raw);
    if (!phone) throw AppError.validation('Invalid Uzbek phone number', { field: 'phone' });
    return phone;
  }

  requestOtp(rawPhone: string, ip: string) {
    return this.otp.request(AuthService.phoneOrThrow(rawPhone), ip);
  }

  /** Verifies the code, creates the account on first sign-in, opens a session. */
  async verifyOtp(rawPhone: string, code: string, device: DeviceDto, meta: RequestMeta) {
    const phone = AuthService.phoneOrThrow(rawPhone);
    await this.otp.verify(phone, code);

    const now = new Date();
    const { user, created } = await this.prisma.$transaction(async (tx) => {
      const existing = await tx.user.findUnique({ where: { phone } });
      if (existing) {
        if (existing.status !== UserStatus.ACTIVE) throw AppError.forbidden('Account is not active');
        const updated = await tx.user.update({
          where: { id: existing.id },
          data: { phoneVerifiedAt: now, lastSeenAt: now },
        });
        return { user: updated, created: false };
      }
      const createdUser = await tx.user.create({
        data: {
          phone,
          phoneVerifiedAt: now,
          lastSeenAt: now,
          identities: { create: { provider: AuthProvider.PHONE_OTP, providerUserId: phone } },
          profile: {
            create: {
              displayName: `Foydalanuvchi ${phone.slice(-4)}`,
              verification: VerificationLevel.PHONE,
            },
          },
        },
      });
      return { user: createdUser, created: true };
    });

    // A phone OTP proves phone ownership — upgrade NONE → PHONE, never downgrade.
    await this.prisma.profile.updateMany({
      where: { userId: user.id, verification: VerificationLevel.NONE },
      data: { verification: VerificationLevel.PHONE },
    });

    const tokens = await this.openSession(user.id, user.role, device, meta);
    this.logger.log({ userId: user.id, sessionId: tokens.sessionId }, 'User signed in');
    return { ...tokens, userId: user.id, isNewUser: created };
  }

  private async openSession(userId: string, role: UserRole, device: DeviceDto, meta: RequestMeta) {
    const refresh = this.tokens.newRefreshToken();
    const session = await this.prisma.session.create({
      data: {
        userId,
        deviceId: device.id,
        deviceName: device.name,
        platform: device.platform.toUpperCase() as DevicePlatform,
        refreshTokenHash: refresh.hash,
        expiresAt: this.refreshExpiry(),
        ipAddress: meta.ip,
        userAgent: meta.userAgent?.slice(0, 300),
      },
    });
    const access = this.tokens.signAccess({ sub: userId, sid: session.id, role });
    return {
      accessToken: access.token,
      accessTokenExpiresIn: access.expiresIn,
      refreshToken: refresh.token,
      sessionId: session.id,
    } satisfies TokenPair;
  }

  private refreshExpiry(): Date {
    return new Date(Date.now() + env().REFRESH_TOKEN_TTL_DAYS * 24 * 3600 * 1000);
  }

  /**
   * Rotation with reuse detection: each refresh token is single-use. If an
   * already-rotated token is presented, the session is assumed stolen and
   * revoked entirely.
   */
  async refresh(refreshToken: string, meta: RequestMeta): Promise<TokenPair> {
    const hash = TokenService.hash(refreshToken);
    const session = await this.prisma.session.findUnique({
      where: { refreshTokenHash: hash },
      include: { user: true },
    });

    if (!session) {
      const reused = await this.prisma.session.findUnique({ where: { previousTokenHash: hash } });
      if (reused && !reused.revokedAt) {
        await this.prisma.session.update({
          where: { id: reused.id },
          data: { revokedAt: new Date(), revokedReason: 'refresh_token_reuse' },
        });
        this.logger.warn(
          { sessionId: reused.id, userId: reused.userId },
          'Refresh token reuse detected; session revoked',
        );
      }
      throw AppError.unauthenticated('Session is no longer valid', 'SESSION_REVOKED');
    }
    if (session.revokedAt || session.expiresAt < new Date() || session.user.status !== UserStatus.ACTIVE) {
      throw AppError.unauthenticated('Session is no longer valid', 'SESSION_REVOKED');
    }

    const next = this.tokens.newRefreshToken();
    const now = new Date();
    const updated = await this.prisma.session.updateMany({
      where: { id: session.id, refreshTokenHash: hash, revokedAt: null },
      data: {
        refreshTokenHash: next.hash,
        previousTokenHash: hash,
        rotatedAt: now,
        lastUsedAt: now,
        expiresAt: this.refreshExpiry(),
        ipAddress: meta.ip,
      },
    });
    if (updated.count !== 1) throw AppError.unauthenticated('Session is no longer valid', 'SESSION_REVOKED');
    await this.prisma.user.update({ where: { id: session.userId }, data: { lastSeenAt: now } });

    const access = this.tokens.signAccess({ sub: session.userId, sid: session.id, role: session.user.role });
    return {
      accessToken: access.token,
      accessTokenExpiresIn: access.expiresIn,
      refreshToken: next.token,
      sessionId: session.id,
    };
  }

  async logout(userId: string, sessionId: string): Promise<void> {
    await this.revoke({ id: sessionId, userId }, 'logout');
  }

  async logoutAll(userId: string): Promise<number> {
    return this.revoke({ userId }, 'logout_all');
  }

  async revokeSession(userId: string, sessionId: string): Promise<void> {
    const count = await this.revoke({ id: sessionId, userId }, 'revoked_by_user');
    if (count === 0) throw AppError.notFound('Session');
  }

  private async revoke(where: Prisma.SessionWhereInput, reason: string): Promise<number> {
    const sessions = await this.prisma.session.findMany({
      where: { ...where, revokedAt: null },
      select: { id: true },
    });
    if (sessions.length === 0) return 0;
    const ids = sessions.map((s) => s.id);
    await this.prisma.$transaction([
      this.prisma.session.updateMany({
        where: { id: { in: ids } },
        data: { revokedAt: new Date(), revokedReason: reason },
      }),
      // Push tokens belong to a device session; stop notifying signed-out devices.
      this.prisma.pushDevice.deleteMany({ where: { sessionId: { in: ids } } }),
    ]);
    this.realtime.disconnectSessions(ids);
    return ids.length;
  }

  async listSessions(userId: string, currentSessionId: string) {
    const sessions = await this.prisma.session.findMany({
      where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { lastUsedAt: 'desc' },
    });
    return sessions.map((s) => ({
      id: s.id,
      deviceName: s.deviceName,
      platform: s.platform.toLowerCase(),
      lastUsedAt: s.lastUsedAt,
      createdAt: s.createdAt,
      current: s.id === currentSessionId,
    }));
  }
}
