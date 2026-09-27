/**
 * E2E configuration: isolated database per run (see global-setup), Redis DB 1 and a
 * dedicated bucket. Test-only secrets are generated per run, never committed.
 */
import { randomBytes } from 'node:crypto';

import { databaseUrl } from './database';

const secret = () => randomBytes(32).toString('hex');

Object.assign(process.env, {
  NODE_ENV: 'test',
  PORT: '3999',
  PUBLIC_API_URL: 'http://localhost:3000',
  LOG_LEVEL: 'error',
  // Set by global-setup to the per-run database.
  DATABASE_URL: process.env.E2E_DATABASE_NAME
    ? databaseUrl(process.env.E2E_DATABASE_NAME)
    : process.env.DATABASE_URL,
  REDIS_URL: process.env.TEST_REDIS_URL ?? 'redis://localhost:6379/1',
  JWT_ACCESS_SECRET: process.env.JWT_ACCESS_SECRET_TEST ?? secret(),
  OTP_HASH_SECRET: process.env.OTP_HASH_SECRET_TEST ?? secret(),
  OTP_PROVIDER: 'dev',
  OTP_DEV_ECHO: 'false',
  S3_ENDPOINT: process.env.TEST_S3_ENDPOINT ?? 'http://localhost:8333',
  S3_BUCKET: 'bozor-test',
  S3_ACCESS_KEY_ID: process.env.TEST_S3_ACCESS_KEY_ID ?? 'bozor_dev_access',
  S3_SECRET_ACCESS_KEY: process.env.TEST_S3_SECRET_ACCESS_KEY ?? 'bozor_dev_secret_key',
  S3_FORCE_PATH_STYLE: 'true',
  PUSH_PROVIDER: 'log',
  PAYMENT_DEV_ENABLED: 'true',
  PAYMENT_DEV_SECRET: process.env.PAYMENT_DEV_SECRET_TEST ?? secret(),
  SWAGGER_ENABLED: 'false',
});
