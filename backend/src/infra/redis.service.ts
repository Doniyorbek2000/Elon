import { Injectable, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';

import { env } from '../config/env';

/**
 * Redis is used for ephemeral state only: rate limits, OTP challenges,
 * presence, short caches and BullMQ. Nothing durable lives here.
 */
@Injectable()
export class RedisService implements OnModuleDestroy {
  readonly client: Redis;
  private readonly extra: Redis[] = [];

  constructor() {
    this.client = new Redis(env().REDIS_URL, { maxRetriesPerRequest: 3, lazyConnect: false });
  }

  /** Dedicated connection (BullMQ workers, pub/sub) — closed with the module. */
  duplicate(options: { forBullMq?: boolean } = {}): Redis {
    const connection = new Redis(env().REDIS_URL, options.forBullMq ? { maxRetriesPerRequest: null } : {});
    this.extra.push(connection);
    return connection;
  }

  async onModuleDestroy(): Promise<void> {
    await Promise.allSettled([this.client, ...this.extra].map((c) => c.quit()));
  }
}
