import { execSync } from 'node:child_process';

import { PrismaClient } from '@prisma/client';
import Redis from 'ioredis';

import { seedReferenceData } from '../prisma/seed';
import { adminUrl, databaseUrl } from './database';
import './env';

/**
 * Every run gets its own freshly created database; migrations are applied
 * with `migrate deploy`, proving they work on an empty schema. Existing
 * databases are never touched or reset.
 */
export default async function globalSetup(): Promise<void> {
  const name = `bozor_e2e_${Date.now()}_${process.pid}`;
  const admin = new PrismaClient({ datasourceUrl: adminUrl() });
  try {
    await admin.$executeRawUnsafe(`CREATE DATABASE "${name}"`);
  } finally {
    await admin.$disconnect();
  }
  process.env.E2E_DATABASE_NAME = name;
  process.env.DATABASE_URL = databaseUrl(name);

  execSync('npx prisma migrate deploy', {
    stdio: 'pipe',
    env: { ...process.env, PRISMA_HIDE_UPDATE_MESSAGE: '1' },
  });
  const prisma = new PrismaClient({ datasourceUrl: process.env.DATABASE_URL });
  try {
    await seedReferenceData(prisma);
  } finally {
    await prisma.$disconnect();
  }
  const redis = new Redis(process.env.REDIS_URL!);
  await redis.flushdb();
  await redis.quit();
}
