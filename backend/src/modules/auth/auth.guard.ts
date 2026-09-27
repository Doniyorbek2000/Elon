import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole, UserStatus } from '@prisma/client';
import type { Request } from 'express';

import { AuthUser, IS_OPTIONAL_AUTH, IS_PUBLIC, ROLES } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { PrismaService } from '../../infra/prisma.service';
import { TokenService } from './token.service';

/**
 * Global guard. Every route requires a valid access token for a live session
 * unless marked @Public() / @OptionalAuth(). The session row is checked on each
 * request so logout and revocation take effect immediately.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly tokens: TokenService,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType() !== 'http') return true;
    const request = context.switchToHttp().getRequest<Request & { user?: AuthUser }>();
    const targets = [context.getHandler(), context.getClass()];
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, targets);
    const optional = this.reflector.getAllAndOverride<boolean>(IS_OPTIONAL_AUTH, targets);
    const token = AuthGuard.bearer(request.headers.authorization);

    if (!token) {
      if (isPublic || optional) return true;
      throw AppError.unauthenticated();
    }
    try {
      request.user = await this.authenticate(token);
    } catch (error) {
      if (isPublic) return true;
      throw error;
    }

    const roles = this.reflector.getAllAndOverride<UserRole[] | undefined>(ROLES, targets);
    if (roles?.length && !roles.includes(request.user.role)) throw AppError.forbidden();
    return true;
  }

  async authenticate(token: string): Promise<AuthUser> {
    const claims = this.tokens.verifyAccess(token);
    const session = await this.prisma.session.findUnique({
      where: { id: claims.sid },
      select: { userId: true, revokedAt: true, expiresAt: true, user: { select: { status: true, role: true } } },
    });
    if (!session || session.userId !== claims.sub || session.revokedAt || session.expiresAt < new Date()) {
      throw AppError.unauthenticated('Session is no longer valid', 'SESSION_REVOKED');
    }
    if (session.user.status !== UserStatus.ACTIVE) throw AppError.forbidden('Account is not active');
    return { userId: claims.sub, sessionId: claims.sid, role: session.user.role };
  }

  static bearer(header: string | undefined): string | undefined {
    if (!header?.startsWith('Bearer ')) return undefined;
    return header.slice(7).trim() || undefined;
  }
}
