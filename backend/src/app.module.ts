import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { randomUUID } from 'node:crypto';
import { LoggerModule } from 'nestjs-pino';

import { env } from './config/env';
import { EnvelopeInterceptor } from './common/envelope.interceptor';
import { HttpExceptionFilter } from './common/http-exception.filter';
import { InfraModule } from './infra/infra.module';
import { ApplicationsModule } from './modules/jobs/applications.module';
import { AuthGuard } from './modules/auth/auth.guard';
import { AuthModule } from './modules/auth/auth.module';
import { CategoriesModule } from './modules/categories/categories.module';
import { ChatModule } from './modules/chat/chat.module';
import { FavoritesModule } from './modules/favorites/favorites.module';
import { HealthModule } from './modules/health/health.module';
import { JobsModule } from './modules/jobs/jobs.module';
import { ListingsModule } from './modules/listings/listings.module';
import { LocationsModule } from './modules/locations/locations.module';
import { MediaModule } from './modules/media/media.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { ResumesModule } from './modules/jobs/resumes.module';
import { SafetyModule } from './modules/safety/safety.module';
import { SearchModule } from './modules/search/search.module';
import { ServicesModule } from './modules/services/services.module';
import { UsersModule } from './modules/users/users.module';

export const domainModules = [
  InfraModule,
  AuthModule,
  UsersModule,
  LocationsModule,
  CategoriesModule,
  MediaModule,
  NotificationsModule,
  SafetyModule,
  ListingsModule,
  FavoritesModule,
  SearchModule,
  JobsModule,
  ApplicationsModule,
  ResumesModule,
  ServicesModule,
  ChatModule,
  HealthModule,
];

/** Human-readable logs in local development when pino-pretty is installed; JSON otherwise. */
function prettyTransport() {
  if (env().NODE_ENV !== 'development') return undefined;
  try {
    require.resolve('pino-pretty');
    return { target: 'pino-pretty', options: { singleLine: true } };
  } catch {
    return undefined;
  }
}

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        level: env().LOG_LEVEL,
        genReqId: (request, response) => {
          const incoming = request.headers['x-request-id'];
          const id = typeof incoming === 'string' && /^[\w-]{8,64}$/.test(incoming) ? incoming : randomUUID();
          response.setHeader('X-Request-Id', id);
          return id;
        },
        // Secrets never reach logs.
        redact: {
          paths: [
            'req.headers.authorization',
            'req.headers.cookie',
            'req.body.code',
            'req.body.refreshToken',
            'req.body.token',
            'res.headers["set-cookie"]',
          ],
          censor: '[redacted]',
        },
        serializers: {
          req: (req: { id: string; method: string; url: string }) => ({
            id: req.id,
            method: req.method,
            url: req.url,
          }),
        },
        autoLogging: { ignore: (req) => req.url?.startsWith('/api/v1/health') ?? false },
        transport: prettyTransport(),
      },
    }),
    ThrottlerModule.forRoot([
      { name: 'default', ttl: 60_000, limit: env().NODE_ENV === 'test' ? 10_000 : 300 },
    ]),
    ...domainModules,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useExisting: AuthGuard },
    { provide: APP_INTERCEPTOR, useClass: EnvelopeInterceptor },
    { provide: APP_FILTER, useClass: HttpExceptionFilter },
  ],
})
export class AppModule {}
