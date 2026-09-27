import { Global, Module } from '@nestjs/common';

import { PresenceService } from './presence.service';
import { PrismaService } from './prisma.service';
import { QueueService } from './queues';
import { ChatEmitter } from './realtime.emitter';
import { RateLimiterService } from './rate-limiter.service';
import { RedisService } from './redis.service';
import { StorageService } from './storage.service';

@Global()
@Module({
  providers: [
    PrismaService,
    RedisService,
    StorageService,
    RateLimiterService,
    QueueService,
    PresenceService,
    ChatEmitter,
  ],
  exports: [
    PrismaService,
    RedisService,
    StorageService,
    RateLimiterService,
    QueueService,
    PresenceService,
    ChatEmitter,
  ],
})
export class InfraModule {}
