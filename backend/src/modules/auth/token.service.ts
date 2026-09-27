import { Injectable } from '@nestjs/common';
import { JwtService, TokenExpiredError } from '@nestjs/jwt';
import type { UserRole } from '@prisma/client';
import { createHash, randomBytes } from 'node:crypto';

import { env } from '../../config/env';
import { AppError } from '../../common/errors';

export interface AccessClaims {
  sub: string;
  sid: string;
  role: UserRole;
}

const ISSUER = 'bozor-api';
const AUDIENCE = 'bozor-app';

@Injectable()
export class TokenService {
  constructor(private readonly jwt: JwtService) {}

  signAccess(claims: AccessClaims): { token: string; expiresIn: number } {
    const expiresIn = env().ACCESS_TOKEN_TTL_SECONDS;
    const token = this.jwt.sign(claims, {
      secret: env().JWT_ACCESS_SECRET,
      expiresIn,
      issuer: ISSUER,
      audience: AUDIENCE,
      algorithm: 'HS256',
    });
    return { token, expiresIn };
  }

  verifyAccess(token: string): AccessClaims {
    try {
      return this.jwt.verify<AccessClaims>(token, {
        secret: env().JWT_ACCESS_SECRET,
        issuer: ISSUER,
        audience: AUDIENCE,
        algorithms: ['HS256'],
      });
    } catch (error) {
      if (error instanceof TokenExpiredError) throw AppError.unauthenticated('Access token expired', 'TOKEN_EXPIRED');
      throw AppError.unauthenticated('Invalid access token');
    }
  }

  /** Opaque, high-entropy refresh token; only its SHA-256 is persisted. */
  newRefreshToken(): { token: string; hash: string } {
    const token = randomBytes(48).toString('base64url');
    return { token, hash: TokenService.hash(token) };
  }

  static hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
