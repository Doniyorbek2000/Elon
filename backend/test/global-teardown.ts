import { PrismaClient } from '@prisma/client';

import { adminUrl } from './database';

/** Drops only the database this run created in global-setup. */
export default async function globalTeardown(): Promise<void> {
  const name = process.env.E2E_DATABASE_NAME;
  if (!name?.startsWith('bozor_e2e_') || process.env.E2E_KEEP_DATABASE === '1') return;
  const admin = new PrismaClient({ datasourceUrl: adminUrl() });
  try {
    await admin.$executeRawUnsafe(`DROP DATABASE IF EXISTS "${name}" WITH (FORCE)`);
  } finally {
    await admin.$disconnect();
  }
}
