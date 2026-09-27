import { INestApplicationContext, Logger } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import Redis from 'ioredis';
import type { Server, ServerOptions } from 'socket.io';

import { env } from '../../config/env';

/**
 * Socket.IO adapter backed by Redis pub/sub so events emitted on one API
 * instance reach sockets connected to any other instance.
 */
export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor?: ReturnType<typeof createAdapter>;
  private connections: Redis[] = [];

  constructor(app: INestApplicationContext) {
    super(app);
  }

  async connectToRedis(): Promise<void> {
    const pub = new Redis(env().REDIS_URL, { lazyConnect: true });
    const sub = pub.duplicate();
    await Promise.all([pub.connect(), sub.connect()]);
    pub.on('error', (error: Error) => this.logger.error(`redis pub: ${error.message}`));
    sub.on('error', (error: Error) => this.logger.error(`redis sub: ${error.message}`));
    this.connections = [pub, sub];
    this.adapterConstructor = createAdapter(pub, sub);
  }

  override createIOServer(port: number, options?: ServerOptions): Server {
    const server = super.createIOServer(port, {
      ...options,
      path: '/socket.io',
      transports: ['websocket', 'polling'],
      pingInterval: 25_000,
      pingTimeout: 20_000,
      maxHttpBufferSize: 64 * 1024,
      cors: { origin: true, credentials: false },
    }) as Server;
    if (this.adapterConstructor) server.adapter(this.adapterConstructor);
    return server;
  }

  override async close(server: Server): Promise<void> {
    await super.close(server);
    await Promise.allSettled(this.connections.map((c) => c.quit()));
    this.connections = [];
  }
}
