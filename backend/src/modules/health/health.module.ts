import { Controller, Get, HttpStatus, Module, Res } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import type { Response } from 'express';

import { Public } from '../../common/auth.decorators';
import { PrismaService } from '../../infra/prisma.service';
import { RedisService } from '../../infra/redis.service';
import { StorageService } from '../../infra/storage.service';

@ApiTags('health')
@Public()
@SkipThrottle()
@Controller('health')
class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly storage: StorageService,
  ) {}

  /** Liveness: the process is up and the event loop responds. */
  @Get('live')
  live() {
    return { status: 'ok', uptimeSeconds: Math.round(process.uptime()) };
  }

  /** Readiness: dependencies reachable; 503 takes the pod out of rotation. */
  @Get('ready')
  async ready(@Res({ passthrough: true }) response: Response) {
    const check = async (fn: () => Promise<unknown>) => {
      try {
        await fn();
        return 'up';
      } catch {
        return 'down';
      }
    };
    const checks = {
      database: await check(() => this.prisma.$queryRaw`SELECT 1`),
      redis: await check(() => this.redis.client.ping()),
      storage: (await this.storage.ping()) ? 'up' : 'down',
    };
    const ok = Object.values(checks).every((v) => v === 'up');
    if (!ok) response.status(HttpStatus.SERVICE_UNAVAILABLE);
    return { status: ok ? 'ok' : 'degraded', checks };
  }
}

@Module({ controllers: [HealthController] })
export class HealthModule {}
