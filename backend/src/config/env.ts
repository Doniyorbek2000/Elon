import { existsSync } from 'node:fs';

import { z } from 'zod';

const bool = z.enum(['true', 'false', '1', '0']).transform((value) => value === 'true' || value === '1');

/**
 * Every environment variable the service reads. Validated once at startup;
 * the process refuses to boot with a clear message if anything is missing or
 * unsafe (e.g. dev OTP enabled in production).
 */
const schema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(3000),
    PUBLIC_API_URL: z.string().url().default('http://localhost:3000'),
    CORS_ORIGINS: z.string().default(''),
    LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),

    DATABASE_URL: z.string().min(1),
    REDIS_URL: z.string().min(1),

    JWT_ACCESS_SECRET: z.string().min(32, 'JWT_ACCESS_SECRET must be at least 32 characters'),
    ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().positive().default(900),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(60),

    OTP_PROVIDER: z.enum(['dev', 'eskiz', 'none']).default('dev'),
    OTP_TTL_SECONDS: z.coerce.number().int().positive().default(300),
    OTP_RESEND_COOLDOWN_SECONDS: z.coerce.number().int().positive().default(60),
    OTP_MAX_ATTEMPTS: z.coerce.number().int().positive().default(5),
    OTP_HASH_SECRET: z.string().min(32, 'OTP_HASH_SECRET must be at least 32 characters'),
    /** Dev only: echo the code in the API response so emulators can sign in. */
    OTP_DEV_ECHO: bool.default('false'),
    ESKIZ_EMAIL: z.string().optional(),
    ESKIZ_PASSWORD: z.string().optional(),
    ESKIZ_SENDER: z.string().default('4546'),

    S3_ENDPOINT: z.string().url().optional(),
    S3_REGION: z.string().default('us-east-1'),
    S3_BUCKET: z.string().min(1),
    S3_ACCESS_KEY_ID: z.string().min(1),
    S3_SECRET_ACCESS_KEY: z.string().min(1),
    S3_FORCE_PATH_STYLE: bool.default('true'),
    /** Optional CDN/public bucket base; when empty media is streamed via the API. */
    MEDIA_PUBLIC_BASE_URL: z.string().url().optional(),
    MEDIA_MAX_UPLOAD_BYTES: z.coerce
      .number()
      .int()
      .positive()
      .default(15 * 1024 * 1024),

    PUSH_PROVIDER: z.enum(['fcm', 'log', 'none']).default('log'),
    FCM_PROJECT_ID: z.string().optional(),
    /** Service-account JSON (raw or base64). */
    FCM_SERVICE_ACCOUNT: z.string().optional(),

    USD_TO_UZS_RATE: z.coerce.number().positive().default(12600),
    LISTING_TTL_DAYS: z.coerce.number().int().positive().default(30),
    JOB_TTL_DAYS: z.coerce.number().int().positive().default(30),

    /** Error reporting. Empty disables Sentry. */
    SENTRY_DSN: z.string().url().optional(),
    SENTRY_ENVIRONMENT: z.string().optional(),
    SENTRY_TRACES_SAMPLE_RATE: z.coerce.number().min(0).max(1).default(0),

    /** `postgres` (default, pg_trgm) or `meilisearch` (typo-tolerant external engine). */
    SEARCH_PROVIDER: z.enum(['postgres', 'meilisearch']).default('postgres'),
    MEILI_URL: z.string().url().optional(),
    MEILI_API_KEY: z.string().optional(),
    /** Index name prefix so several environments can share one Meilisearch. */
    MEILI_INDEX_PREFIX: z.string().default('bozor'),

    /** Automated image content check (nudity, gore, offensive). `none` disables it. */
    IMAGE_MODERATION_PROVIDER: z.enum(['none', 'sightengine']).default('none'),
    SIGHTENGINE_USER: z.string().optional(),
    SIGHTENGINE_SECRET: z.string().optional(),
    /** Override for tests / proxies. */
    SIGHTENGINE_URL: z.string().url().default('https://api.sightengine.com/1.0/check.json'),

    /** Global per-client request limit per minute (raise it only for load tests). */
    RATE_LIMIT_PER_MINUTE: z.coerce.number().int().positive().default(300),

    SWAGGER_ENABLED: bool.default('true'),
    WEB_BASE_URL: z.string().url().default('https://bozor.uz'),
  })
  .superRefine((env, ctx) => {
    if (
      env.IMAGE_MODERATION_PROVIDER === 'sightengine' &&
      !(env.SIGHTENGINE_USER && env.SIGHTENGINE_SECRET)
    ) {
      ctx.addIssue({
        code: 'custom',
        message:
          'SIGHTENGINE_USER and SIGHTENGINE_SECRET are required when IMAGE_MODERATION_PROVIDER=sightengine',
        path: ['SIGHTENGINE_USER'],
      });
    }
    if (env.SEARCH_PROVIDER === 'meilisearch' && !env.MEILI_URL) {
      ctx.addIssue({
        code: 'custom',
        message: 'MEILI_URL is required when SEARCH_PROVIDER=meilisearch',
        path: ['MEILI_URL'],
      });
    }
    if (env.NODE_ENV !== 'production') return;
    if (env.OTP_PROVIDER === 'dev' || env.OTP_DEV_ECHO) {
      ctx.addIssue({
        code: 'custom',
        message: 'Dev OTP provider/echo is forbidden in production',
        path: ['OTP_PROVIDER'],
      });
    }
    if (env.OTP_PROVIDER === 'eskiz' && (!env.ESKIZ_EMAIL || !env.ESKIZ_PASSWORD)) {
      ctx.addIssue({
        code: 'custom',
        message: 'ESKIZ_EMAIL and ESKIZ_PASSWORD are required',
        path: ['ESKIZ_EMAIL'],
      });
    }
    if (env.PUSH_PROVIDER === 'fcm' && (!env.FCM_PROJECT_ID || !env.FCM_SERVICE_ACCOUNT)) {
      ctx.addIssue({
        code: 'custom',
        message: 'FCM_PROJECT_ID and FCM_SERVICE_ACCOUNT are required',
        path: ['FCM_PROJECT_ID'],
      });
    }
    if (!env.CORS_ORIGINS) {
      ctx.addIssue({
        code: 'custom',
        message: 'CORS_ORIGINS must be explicit in production',
        path: ['CORS_ORIGINS'],
      });
    }
  });

export type Env = z.infer<typeof schema>;

let cached: Env | undefined;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  // Blank values (`KEY=` in env files) mean "not set", so defaults apply.
  const defined = Object.fromEntries(
    Object.entries(source).filter(([, value]) => value !== undefined && value.trim() !== ''),
  );
  const parsed = schema.safeParse(defined);
  if (!parsed.success) {
    const problems = parsed.error.issues
      .map((i) => `  - ${i.path.join('.') || 'env'}: ${i.message}`)
      .join('\n');
    throw new Error(`Invalid environment configuration:\n${problems}`);
  }
  return parsed.data;
}

/**
 * Local convenience: read `.env` from the working directory when present.
 * Real environment variables always win; production deployments inject
 * configuration through the environment (or a secrets manager), not files.
 */
function loadDotEnvFile(): void {
  if (process.env.NODE_ENV === 'production' || process.env.NODE_ENV === 'test') return;
  if (existsSync('.env')) process.loadEnvFile('.env');
}

export function env(): Env {
  if (!cached) loadDotEnvFile();
  cached ??= loadEnv();
  return cached;
}

/** Test hook: forget cached config after mutating process.env. */
export function resetEnvCache(): void {
  cached = undefined;
}

export const ENV = Symbol('ENV');
