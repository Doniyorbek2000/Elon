import { existsSync } from 'node:fs';

import { z } from 'zod';

const bool = z
  .enum(['true', 'false', '1', '0'])
  .transform((value) => value === 'true' || value === '1');

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
    MEDIA_MAX_UPLOAD_BYTES: z.coerce.number().int().positive().default(15 * 1024 * 1024),

    PUSH_PROVIDER: z.enum(['fcm', 'log', 'none']).default('log'),
    FCM_PROJECT_ID: z.string().optional(),
    /** Service-account JSON (raw or base64). */
    FCM_SERVICE_ACCOUNT: z.string().optional(),

    USD_TO_UZS_RATE: z.coerce.number().positive().default(12600),
    LISTING_TTL_DAYS: z.coerce.number().int().positive().default(30),
    JOB_TTL_DAYS: z.coerce.number().int().positive().default(30),

    FEATURE_MONETIZATION: bool.default('false'),
    FEATURE_PAID_PROMOTIONS: bool.default('false'),
    FEATURE_BUSINESS_ACCOUNTS: bool.default('false'),

    SWAGGER_ENABLED: bool.default('true'),
    WEB_BASE_URL: z.string().url().default('https://bozor.uz'),
  })
  .superRefine((env, ctx) => {
    if (env.NODE_ENV !== 'production') return;
    if (env.OTP_PROVIDER === 'dev' || env.OTP_DEV_ECHO) {
      ctx.addIssue({ code: 'custom', message: 'Dev OTP provider/echo is forbidden in production', path: ['OTP_PROVIDER'] });
    }
    if (env.OTP_PROVIDER === 'eskiz' && (!env.ESKIZ_EMAIL || !env.ESKIZ_PASSWORD)) {
      ctx.addIssue({ code: 'custom', message: 'ESKIZ_EMAIL and ESKIZ_PASSWORD are required', path: ['ESKIZ_EMAIL'] });
    }
    if (env.PUSH_PROVIDER === 'fcm' && (!env.FCM_PROJECT_ID || !env.FCM_SERVICE_ACCOUNT)) {
      ctx.addIssue({ code: 'custom', message: 'FCM_PROJECT_ID and FCM_SERVICE_ACCOUNT are required', path: ['FCM_PROJECT_ID'] });
    }
    if (!env.CORS_ORIGINS) {
      ctx.addIssue({ code: 'custom', message: 'CORS_ORIGINS must be explicit in production', path: ['CORS_ORIGINS'] });
    }
  });

export type Env = z.infer<typeof schema>;

let cached: Env | undefined;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);
  if (!parsed.success) {
    const problems = parsed.error.issues.map((i) => `  - ${i.path.join('.') || 'env'}: ${i.message}`).join('\n');
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
