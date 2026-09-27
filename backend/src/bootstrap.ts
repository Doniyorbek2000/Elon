import { INestApplication, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { Logger } from 'nestjs-pino';
import express from 'express';

import { env } from './config/env';
import { AppModule } from './app.module';
import { RedisIoAdapter } from './modules/chat/redis-io.adapter';

export const API_PREFIX = 'api/v1';

/** Shared by main.ts and e2e tests so both run the exact same pipeline. */
export async function createApp(options: { logger?: boolean } = {}): Promise<INestApplication> {
  const config = env();
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
    logger: options.logger === false ? false : undefined,
    bodyParser: false,
  });
  if (options.logger !== false) app.useLogger(app.get(Logger));

  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(express.json({ limit: '256kb' }));
  app.use(express.urlencoded({ extended: false, limit: '64kb' }));
  app.use(
    helmet({
      contentSecurityPolicy: false, // JSON API; Swagger UI needs inline assets.
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );
  const origins = config.CORS_ORIGINS.split(',').map((o) => o.trim()).filter(Boolean);
  app.enableCors({
    origin: origins.length ? origins : config.NODE_ENV !== 'production',
    credentials: false,
    maxAge: 600,
  });
  app.setGlobalPrefix(API_PREFIX);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
      stopAtFirstError: false,
      errorHttpStatusCode: 422,
    }),
  );
  app.enableShutdownHooks();

  const ioAdapter = new RedisIoAdapter(app);
  await ioAdapter.connectToRedis();
  app.useWebSocketAdapter(ioAdapter);

  if (config.SWAGGER_ENABLED && config.NODE_ENV !== 'production') {
    const document = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('Bozor.uz API')
        .setDescription('Marketplace, jobs, services and chat. Responses: { data, meta? } | { error }.')
        .setVersion('1.0')
        .addBearerAuth()
        .build(),
    );
    SwaggerModule.setup(`${API_PREFIX}/docs`, app, document);
  }
  return app;
}
