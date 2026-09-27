# Bozor.uz API

NestJS 11 + TypeScript, PostgreSQL 16 / PostGIS + pg_trgm (Prisma 6), Redis 7, BullMQ, Socket.IO (Redis adapter) and S3-compatible object storage. API contract: [`../docs/backend-contract.md`](../docs/backend-contract.md).

## Layout

```
src/
  main.ts / bootstrap.ts   HTTP app (helmet, CORS, body limits, validation, Swagger in dev, Socket.IO adapter)
  worker.ts                BullMQ consumers: media renditions, storage cleanup, push, expiry, moderation intake
  config/env.ts            zod-validated environment (refuses unsafe production config)
  common/                  errors, response envelope, cursor pagination, presenters, Uzbek text/phone normalizers, content-risk rules
  infra/                   Prisma, Redis, rate limiter, S3 storage, queues, presence, realtime emitter
  modules/                 auth, users, locations, categories, media, listings, favorites, search,
                           jobs (+applications, resumes), services (+offerings, reviews), chat, notifications, safety, health
prisma/                    schema, migrations (PostGIS generated geography columns, trigram indexes, CHECK constraints), seed
test/                      e2e suites (per-run database), helpers
```

## Run locally

```bash
# 1. Dependencies (PostgreSQL+PostGIS, Redis, SeaweedFS S3) from the repo root
docker compose up -d postgres redis storage

# 2. Configure
cd backend
cp .env.example .env
# fill JWT_ACCESS_SECRET and OTP_HASH_SECRET: openssl rand -hex 32
# for emulator sign-in without SMS set OTP_DEV_ECHO=true (development only)

# 3. Install, migrate, seed reference data, run
npm ci
npx prisma migrate deploy
npm run build
npm run db:seed          # regions/districts/localities, categories + attribute schemas, service categories
npm start                # API on :3000  (docs: http://localhost:3000/api/v1/docs)
npm run start:worker     # second process: renditions, push, expiry sweeps
```

Flutter against this server (Android emulator reaches the host at `10.0.2.2`):

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

Everything in Docker (API + worker images built from `backend/Dockerfile`):

```bash
cp backend/.env.example backend/.env.docker   # use service hostnames: postgres, redis, storage
docker compose --profile app up -d --build
curl localhost:3000/api/v1/health/ready
```

## Checks

```bash
npm run typecheck && npm run lint && npm run format:check
npm test                 # unit
npm run test:e2e         # e2e: creates a fresh bozor_e2e_* database per run, applies migrations, drops it afterwards
npm audit
```

The e2e suites need the compose dependencies running. They run the real HTTP app, Socket.IO and the BullMQ workers in-process.

## Operational notes

- **Auth**: OTP codes are HMAC-hashed in Redis with TTL, resend cooldown, attempt limit and per-phone/IP quotas. Access JWT (HS256, 15 min, `iss`/`aud` checked) + opaque single-use refresh tokens (SHA-256 stored) with reuse detection. Every request re-checks the session row, so logout/revocation is immediate.
- **Never logged**: OTP codes (only in `NODE_ENV=development` via the dev sender), tokens, `Authorization`/cookies, request bodies containing `code`/`refreshToken`/`token` (pino redaction).
- **Media**: originals are private (`originals/{owner}/{id}`); the worker auto-orients, strips metadata and writes WebP renditions (240/480/1080 px). Served through `/media/:id/:variant` or a CDN (`MEDIA_PUBLIC_BASE_URL`). Chat media is only readable by participants. Orphans are deleted after 24 h.
- **Feed/search**: parameterized SQL only (`Prisma.sql`), PostGIS `ST_DWithin` for radius, KNN for location resolve, `pg_trgm` word similarity over a normalized `searchText` (Latin/Cyrillic, apostrophes, colloquial variants). `SearchProvider` is an interface; an external engine can replace the PostgreSQL one.
- **Redis** holds only ephemeral state: rate limits, OTP challenges, presence, view dedupe, short caches, BullMQ.
- **Jobs**: all BullMQ handlers are idempotent (deterministic job ids; renditions overwrite the same keys); failures retry with exponential backoff; undecodable images are marked `failed` immediately.
- **Moderation**: risky text/prices are held in `pendingReview`; 3 distinct reports escalate to the moderation queue. Roles `MODERATOR`/`ADMIN` are set in the database only.
- **Monetization**: models and flags exist (`FEATURE_*`), all disabled; no paid feature is active.

## Credentials required for production

Nothing below is committed; configure through the environment / secret manager.

| Capability | Variables | Status in this repository |
|---|---|---|
| SMS OTP (Eskiz.uz) | `OTP_PROVIDER=eskiz`, `ESKIZ_EMAIL`, `ESKIZ_PASSWORD`, `ESKIZ_SENDER` | Implemented, **not tested** (no credentials). Production refuses to boot with the dev provider. |
| Push (FCM HTTP v1) | `PUSH_PROVIDER=fcm`, `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT` (JSON or base64) | Implemented, **not tested** against Firebase (no project). Invalid tokens are disabled automatically. |
| Object storage (S3 / Cloudflare R2 / MinIO) | `S3_ENDPOINT`, `S3_REGION` (`auto` for R2), `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_FORCE_PATH_STYLE`, optional `MEDIA_PUBLIC_BASE_URL` | Verified locally with SeaweedFS (S3 API). Real S3/R2 **not tested**. |
| Secrets | `JWT_ACCESS_SECRET`, `OTP_HASH_SECRET` (≥ 32 chars each) | Generate per environment. |
| Web | `CORS_ORIGINS` (required in production), `PUBLIC_API_URL`, `WEB_BASE_URL` | — |
| App Links / Universal Links | `assetlinks.json`, `apple-app-site-association` on `WEB_BASE_URL` | See [`../docs/deep-linking.md`](../docs/deep-linking.md). |
