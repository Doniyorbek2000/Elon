import { Injectable } from '@nestjs/common';

import { AppError, ErrorCode } from '../common/errors';
import { RedisService } from './redis.service';

/**
 * Fixed-window counters in Redis. Used for domain limits (OTP per phone,
 * messages per minute, phone reveals) on top of the global HTTP throttler.
 */
@Injectable()
export class RateLimiterService {
  constructor(private readonly redis: RedisService) {}

  /** Returns remaining allowance; throws RATE_LIMITED when exhausted. */
  async consume(
    key: string,
    limit: number,
    windowSeconds: number,
    code: ErrorCode = 'RATE_LIMITED',
  ): Promise<number> {
    const redisKey = `rl:${key}`;
    const results = await this.redis.client
      .multi()
      .incr(redisKey)
      .expire(redisKey, windowSeconds, 'NX')
      .ttl(redisKey)
      .exec();
    const count = Number(results?.[0]?.[1] ?? 0);
    const ttl = Number(results?.[2]?.[1] ?? windowSeconds);
    if (count > limit) throw AppError.rateLimited(ttl > 0 ? ttl : windowSeconds, code);
    return limit - count;
  }
}
