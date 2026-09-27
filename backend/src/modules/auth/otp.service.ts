import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { createHmac, randomInt, timingSafeEqual } from 'node:crypto';

import { env } from '../../config/env';
import { AppError } from '../../common/errors';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { RedisService } from '../../infra/redis.service';
import { OTP_SENDER, OtpSender } from './otp-sender';

export interface OtpChallenge {
  expiresInSeconds: number;
  resendInSeconds: number;
  /** Present only when OTP_DEV_ECHO=true (never in production). */
  devCode?: string;
}

/**
 * Phone OTP challenges in Redis. Only an HMAC of the code is stored; codes
 * expire, have a resend cooldown, a per-challenge attempt budget, and per
 * phone/IP hourly quotas.
 */
@Injectable()
export class OtpService {
  constructor(
    private readonly redis: RedisService,
    private readonly limiter: RateLimiterService,
    @Inject(OTP_SENDER) private readonly sender: OtpSender,
  ) {}

  private hash(phone: string, code: string): string {
    return createHmac('sha256', env().OTP_HASH_SECRET).update(`${phone}:${code}`).digest('hex');
  }

  async request(phone: string, ip: string): Promise<OtpChallenge> {
    const config = env();
    const cooldownKey = `otp:cooldown:${phone}`;
    const cooling = await this.redis.client.set(cooldownKey, '1', 'EX', config.OTP_RESEND_COOLDOWN_SECONDS, 'NX');
    if (cooling !== 'OK') {
      const ttl = await this.redis.client.ttl(cooldownKey);
      throw AppError.rateLimited(Math.max(ttl, 1), 'OTP_COOLDOWN');
    }
    await this.limiter.consume(`otp:phone:${phone}`, 5, 3600);
    await this.limiter.consume(`otp:ip:${ip}`, 30, 3600);

    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    await this.redis.client
      .multi()
      .set(`otp:code:${phone}`, this.hash(phone, code), 'EX', config.OTP_TTL_SECONDS)
      .del(`otp:attempts:${phone}`)
      .exec();
    try {
      await this.sender.send(phone, code);
    } catch {
      await this.redis.client.del(`otp:code:${phone}`, cooldownKey);
      throw new AppError('SERVICE_UNAVAILABLE', 'Could not deliver the code', HttpStatus.SERVICE_UNAVAILABLE);
    }
    return {
      expiresInSeconds: config.OTP_TTL_SECONDS,
      resendInSeconds: config.OTP_RESEND_COOLDOWN_SECONDS,
      ...(config.OTP_DEV_ECHO && config.NODE_ENV !== 'production' ? { devCode: code } : {}),
    };
  }

  /** Consumes the challenge on success. */
  async verify(phone: string, code: string): Promise<void> {
    const config = env();
    const stored = await this.redis.client.get(`otp:code:${phone}`);
    if (!stored) throw new AppError('OTP_EXPIRED', 'Code expired, request a new one', HttpStatus.UNPROCESSABLE_ENTITY);

    const attempts = await this.redis.client.incr(`otp:attempts:${phone}`);
    await this.redis.client.expire(`otp:attempts:${phone}`, config.OTP_TTL_SECONDS);
    if (attempts > config.OTP_MAX_ATTEMPTS) {
      await this.redis.client.del(`otp:code:${phone}`);
      throw new AppError('OTP_TOO_MANY_ATTEMPTS', 'Too many attempts, request a new code', HttpStatus.TOO_MANY_REQUESTS);
    }

    const expected = Buffer.from(stored, 'hex');
    const actual = Buffer.from(this.hash(phone, code), 'hex');
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
      throw new AppError('OTP_INVALID', 'Incorrect code', HttpStatus.UNPROCESSABLE_ENTITY, {
        attemptsLeft: Math.max(config.OTP_MAX_ATTEMPTS - attempts, 0),
      });
    }
    await this.redis.client.del(`otp:code:${phone}`, `otp:attempts:${phone}`);
  }
}
