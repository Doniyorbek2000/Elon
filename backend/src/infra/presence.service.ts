import { Injectable } from '@nestjs/common';

import { RedisService } from './redis.service';

const TTL_SECONDS = 70;

/**
 * Online presence lives only in Redis: a per-user counter of live sockets
 * plus a TTL key refreshed by client heartbeats. Nothing is written to
 * PostgreSQL per heartbeat; `lastSeenAt` is persisted only on disconnect.
 */
@Injectable()
export class PresenceService {
  constructor(private readonly redis: RedisService) {}

  async connected(userId: string): Promise<boolean> {
    const count = await this.redis.client.incr(`presence:conn:${userId}`);
    await this.redis.client.set(`presence:${userId}`, '1', 'EX', TTL_SECONDS);
    return count === 1;
  }

  async heartbeat(userId: string): Promise<void> {
    await this.redis.client.set(`presence:${userId}`, '1', 'EX', TTL_SECONDS);
  }

  /** Returns true when the user's last socket went away. */
  async disconnected(userId: string): Promise<boolean> {
    const count = await this.redis.client.decr(`presence:conn:${userId}`);
    if (count <= 0) {
      await this.redis.client.del(`presence:conn:${userId}`, `presence:${userId}`);
      return true;
    }
    return false;
  }

  async isOnline(userId: string): Promise<boolean> {
    return (await this.redis.client.exists(`presence:${userId}`)) === 1;
  }

  async onlineMany(userIds: string[]): Promise<Set<string>> {
    const unique = [...new Set(userIds)];
    if (unique.length === 0) return new Set();
    const values = await this.redis.client.mget(unique.map((id) => `presence:${id}`));
    return new Set(unique.filter((_, index) => values[index] != null));
  }
}
