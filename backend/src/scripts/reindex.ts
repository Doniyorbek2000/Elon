import 'reflect-metadata';

import { NestFactory } from '@nestjs/core';

import { AppModule } from '../app.module';
import { env } from '../config/env';
import { RedisService } from '../infra/redis.service';
import { SEARCH_PROVIDER, SearchProvider } from '../modules/search/search.provider';

/**
 * Rebuilds the external search index from scratch:
 *   npm run search:reindex
 * Clears the sync watermarks, then runs the incremental sync to completion.
 */
async function main(): Promise<void> {
  if (env().SEARCH_PROVIDER === 'postgres') {
    process.stdout.write('SEARCH_PROVIDER=postgres queries the database directly: nothing to index.\n');
    return;
  }
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });
  try {
    const redis = app.get(RedisService).client;
    const keys = await redis.keys('search:sync:*');
    if (keys.length) await redis.del(...keys);
    const started = Date.now();
    const result = await app.get<SearchProvider>(SEARCH_PROVIDER).sync?.();
    process.stdout.write(
      `Reindexed ${result?.indexed ?? 0} documents (${result?.removed ?? 0} removed) in ${((Date.now() - started) / 1000).toFixed(1)}s\n`,
    );
  } finally {
    await app.close();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(`Reindex failed: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
