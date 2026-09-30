import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { JobsOptions, Queue } from 'bullmq';

import { RedisService } from './redis.service';

export const QUEUE = {
  media: 'media',
  notifications: 'notifications',
  maintenance: 'maintenance',
  moderation: 'moderation',
} as const;

export interface MediaProcessJob {
  mediaId: string;
}

export interface MediaCleanupJob {
  keys: string[];
}

export interface PushJob {
  userId: string;
  title: string;
  body: string;
  data: Record<string, string>;
  /** Idempotency: identical keys within the retention window are dropped. */
  dedupeKey: string;
}

export interface ModerationJob {
  targetType: 'LISTING' | 'MESSAGE' | 'USER' | 'JOB' | 'PROVIDER' | 'CONVERSATION' | 'REVIEW';
  targetId: string;
  reason: string;
}

const defaults: JobsOptions = {
  attempts: 5,
  backoff: { type: 'exponential', delay: 2000 },
  removeOnComplete: { age: 24 * 3600, count: 5000 },
  removeOnFail: { age: 7 * 24 * 3600 },
};

/** BullMQ reserves ':' in custom job ids; ids stay deterministic for dedupe. */
export function jobId(...parts: string[]): string {
  return parts.map((part) => part.replace(/:/g, '.')).join('__');
}

/** Producer side of BullMQ. Consumers live in the worker process. */
@Injectable()
export class QueueService implements OnModuleDestroy {
  private readonly queues = new Map<string, Queue>();

  constructor(private readonly redis: RedisService) {}

  private queue(name: string): Queue {
    let queue = this.queues.get(name);
    if (!queue) {
      queue = new Queue(name, {
        connection: this.redis.duplicate({ forBullMq: true }),
        defaultJobOptions: defaults,
      });
      this.queues.set(name, queue);
    }
    return queue;
  }

  /** `attempt` distinguishes an explicit retry from a duplicate enqueue. */
  async processMedia(job: MediaProcessJob, attempt = 'initial'): Promise<void> {
    await this.queue(QUEUE.media).add('process', job, { jobId: jobId('process', job.mediaId, attempt) });
  }

  async cleanupMedia(job: MediaCleanupJob): Promise<void> {
    await this.queue(QUEUE.media).add('cleanup', job);
  }

  async push(job: PushJob): Promise<void> {
    await this.queue(QUEUE.notifications).add('push', job, {
      jobId: jobId('push', job.dedupeKey),
      attempts: 3,
    });
  }

  async moderation(job: ModerationJob): Promise<void> {
    await this.queue(QUEUE.moderation).add('review', job, {
      jobId: jobId('moderation', job.targetType, job.targetId),
    });
  }

  async scheduleMaintenance(): Promise<void> {
    const queue = this.queue(QUEUE.maintenance);
    await queue.upsertJobScheduler('expire-content', { every: 60 * 60 * 1000 }, { name: 'expire-content' });
    await queue.upsertJobScheduler('orphan-media', { every: 6 * 60 * 60 * 1000 }, { name: 'orphan-media' });
    // External search index follows the database (no-op for the PostgreSQL engine).
    await queue.upsertJobScheduler('search-sync', { every: 60 * 1000 }, { name: 'search-sync' });
    // Paid features must expire even when no app is open.
    await queue.upsertJobScheduler(
      'monetization-tick',
      { every: 5 * 60 * 1000 },
      { name: 'monetization-tick' },
    );
  }

  async counts(): Promise<Record<string, Record<string, number>>> {
    const result: Record<string, Record<string, number>> = {};
    for (const name of Object.values(QUEUE)) {
      result[name] = await this.queue(name).getJobCounts('waiting', 'active', 'failed', 'delayed');
    }
    return result;
  }

  async onModuleDestroy(): Promise<void> {
    await Promise.allSettled([...this.queues.values()].map((q) => q.close()));
  }
}
