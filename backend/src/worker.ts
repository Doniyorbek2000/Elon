import 'reflect-metadata';

import { INestApplicationContext, Logger as NestLogger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { Job, UnrecoverableError, Worker } from 'bullmq';
import { Logger } from 'nestjs-pino';

import { AppModule } from './app.module';
import { env } from './config/env';
import { PrismaService } from './infra/prisma.service';
import {
  MediaCleanupJob,
  MediaProcessJob,
  ModerationJob,
  PushJob,
  QUEUE,
  QueueService,
} from './infra/queues';
import { flushMonitoring, initMonitoring, reportError } from './infra/monitoring';
import { RedisService } from './infra/redis.service';
import { StorageService } from './infra/storage.service';
import { JobsService } from './modules/jobs/jobs.service';
import { ListingsService } from './modules/listings/listings.service';
import { MediaService } from './modules/media/media.service';
import { AdsService } from './modules/business/ads.service';
import { CreditsService } from './modules/monetization/credits.service';
import { PaymentsService } from './modules/monetization/payments.service';
import { PromotionService } from './modules/monetization/promotion.service';
import { SubscriptionsService } from './modules/monetization/subscriptions.service';
import { SEARCH_PROVIDER, SearchProvider } from './modules/search/search.provider';
import { NotificationsService } from './modules/notifications/notifications.service';

/** Errors that retrying cannot fix (corrupt/unsupported image input). */
function isPermanentImageError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : '';
  return /unsupported image format|Input buffer contains unsupported|corrupt|pixel limit|bad seek|VipsJpeg|premature end/i.test(
    message,
  );
}

function isFinalAttempt(job: Job): boolean {
  return job.attemptsMade + 1 >= (job.opts.attempts ?? 1);
}

/** Every step is idempotent (conditional updates), safe to overlap or retry. */
export async function runMonetizationTick(app: INestApplicationContext, now = new Date()) {
  const promotions = await app.get(PromotionService).sweep(now);
  const subscriptions = await app.get(SubscriptionsService).sweep(now);
  const creditsExpired = await app.get(CreditsService).sweepExpired(now);
  const ads = await app.get(AdsService).sweep(now);
  const reconciliation = await app.get(PaymentsService).reconcile(now);
  return { promotions, subscriptions, creditsExpired, ads, reconciliation };
}

/**
 * Background worker process: image renditions, storage cleanup, push
 * delivery, expiry sweeps and moderation intake. Every handler is
 * idempotent so BullMQ retries are safe.
 */
export function startWorkers(app: INestApplicationContext): Worker[] {
  const log = new NestLogger('Worker');
  const redis = app.get(RedisService);
  const media = app.get(MediaService);
  const storage = app.get(StorageService);
  const notifications = app.get(NotificationsService);
  const listings = app.get(ListingsService);
  const jobs = app.get(JobsService);
  const prisma = app.get(PrismaService);

  const connection = () => redis.duplicate({ forBullMq: true });

  const mediaWorker = new Worker(
    QUEUE.media,
    async (job: Job) => {
      if (job.name === 'process') {
        const { mediaId } = job.data as MediaProcessJob;
        try {
          await media.process(mediaId);
        } catch (error) {
          const reason = error instanceof Error ? error.message : String(error);
          if (isPermanentImageError(error)) {
            await media.markFailed(mediaId, 'Image could not be decoded');
            throw new UnrecoverableError(reason);
          }
          if (isFinalAttempt(job)) await media.markFailed(mediaId, 'Processing failed');
          throw error;
        }
        return;
      }
      if (job.name === 'cleanup') {
        await storage.deleteMany((job.data as MediaCleanupJob).keys);
        return;
      }
      throw new UnrecoverableError(`Unknown media job ${job.name}`);
    },
    { connection: connection(), concurrency: 4 },
  );

  const notificationWorker = new Worker(
    QUEUE.notifications,
    async (job: Job) => notifications.deliverPush(job.data as PushJob),
    { connection: connection(), concurrency: 8 },
  );

  const maintenanceWorker = new Worker(
    QUEUE.maintenance,
    async (job: Job) => {
      switch (job.name) {
        case 'expire-content': {
          const [expiredListings, expiredJobs] = [await listings.expireStale(), await jobs.expireStale()];
          return { expiredListings, expiredJobs };
        }
        case 'orphan-media':
          return { orphans: await media.cleanupOrphans() };
        case 'monetization-tick':
          return runMonetizationTick(app);
        case 'search-sync':
          return (await app.get<SearchProvider>(SEARCH_PROVIDER).sync?.()) ?? { indexed: 0, removed: 0 };
        default:
          throw new UnrecoverableError(`Unknown maintenance job ${job.name}`);
      }
    },
    { connection: connection(), concurrency: 1 },
  );

  /**
   * Moderation intake: the item is already flagged/held by the producing
   * service; here we record an audit trail entry for the review console.
   * Automated classifiers can be plugged in at this point.
   */
  const moderationWorker = new Worker(
    QUEUE.moderation,
    async (job: Job) => {
      const data = job.data as ModerationJob;
      log.log(`moderation queued: ${data.targetType} ${data.targetId} (${data.reason})`);
      await prisma.moderationEvent.create({
        data: {
          targetType: data.targetType,
          targetId: data.targetId,
          action: 'AUTO_FLAGGED',
          reason: data.reason.slice(0, 500),
        },
      });
    },
    { connection: connection(), concurrency: 2 },
  );

  const workers = [mediaWorker, notificationWorker, maintenanceWorker, moderationWorker];
  for (const worker of workers) {
    worker.on('failed', (job, error) => {
      log.warn(
        `${worker.name}/${job?.name ?? '?'} failed (attempt ${job?.attemptsMade ?? 0}): ${error.message}`,
      );
      if (job && isFinalAttempt(job)) reportError(error, { queue: worker.name, job: job.name });
    });
    worker.on('error', (error) => {
      log.error(`${worker.name} worker error: ${error.message}`);
      reportError(error, { queue: worker.name });
    });
  }
  return workers;
}

async function main(): Promise<void> {
  env(); // fail fast on invalid configuration
  initMonitoring('worker');
  const app = await NestFactory.createApplicationContext(AppModule, { bufferLogs: true });
  app.useLogger(app.get(Logger));
  app.enableShutdownHooks();
  await app.get(QueueService).scheduleMaintenance();
  const workers = startWorkers(app);

  const shutdown = async () => {
    await Promise.allSettled(workers.map((w) => w.close()));
    await app.close();
    await flushMonitoring();
    process.exit(0);
  };
  process.once('SIGTERM', () => void shutdown());
  process.once('SIGINT', () => void shutdown());
}

if (require.main === module) {
  main().catch((error: unknown) => {
    process.stderr.write(`Fatal worker error: ${error instanceof Error ? error.message : String(error)}\n`);
    reportError(error, { phase: 'startup' });
    void flushMonitoring().finally(() => process.exit(1));
  });
}
