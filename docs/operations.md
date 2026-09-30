# Operations and release checklist

What must be configured outside the repository before the app takes real users or real money.

## Continuous integration

`.github/workflows/app.yml` runs format check, `flutter analyze --fatal-infos`, unit + widget tests and a debug APK build.
`.github/workflows/backend.yml` runs `prisma validate`, lint, format check, build, unit tests and the e2e suite against
PostGIS, Redis and an S3-compatible store (MinIO). Make both required checks on `main`.

## Error reporting (Sentry)

Off unless a DSN is provided; nothing is sent otherwise. Request bodies, cookies, auth headers and user objects are stripped.

| Where | Configuration |
|---|---|
| App | `--dart-define=SENTRY_DSN=… [--dart-define=SENTRY_ENVIRONMENT=production] [--dart-define=APP_RELEASE=1.0.0+12]` |
| API and worker | `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `SENTRY_TRACES_SAMPLE_RATE` |

The app uses `sentry_flutter` (Dart errors plus native Android/iOS crashes). Readable native stack traces need symbol/mapping upload at
release time (`dart run sentry_dart_plugin` with `--split-debug-info`), which is a CI step you configure with your Sentry org/project/token.

## Mobile release

- **Android**: create `android/key.properties` (see the header of `android/app/build.gradle.kts`). Release tasks now fail
  without it; `ALLOW_DEBUG_SIGNED_RELEASE=true` overrides that for a local smoke test only. `POST_NOTIFICATIONS` is declared.
- **iOS**: `ios/Runner/Runner.entitlements` enables push (`aps-environment`). It needs a paid Apple Developer team and an
  APNs key uploaded to Firebase. Universal Links stay opt-in (see `docs/deep-linking.md`).

## Payments

See `docs/monetization.md`. Click and Payme are implemented against their public specifications and tested against a
simulator only: run each provider’s sandbox checks before enabling it. Apple/Google purchase verification is not implemented.

Callback URLs to enter in the provider cabinets:

- Click: `POST {PUBLIC_API_URL}/api/v1/payments/webhooks/click`
- Payme: `POST {PUBLIC_API_URL}/api/v1/payments/webhooks/payme` (account field `order_id`)

## Content safety

- Text: `backend/src/common/content-risk.ts` normalizes evasions (spelled-out digits, separators, apostrophe variants)
  before matching phones, cards (Luhn-validated), links, off-platform contact and prepayment wording.
- Photos: listing photos get a perceptual hash. A photo that matches another seller’s live listing sends the new listing
  to moderation (`duplicate_image`).
- Photo content: `IMAGE_MODERATION_PROVIDER=sightengine` (+ `SIGHTENGINE_USER`, `SIGHTENGINE_SECRET`) checks every public photo for
  nudity, gore and offensive content. Explicit/violent images are rejected (`content_policy`), borderline ones send the listing to
  moderation (`image_review`), and a provider outage marks the photo unchecked (`image_unchecked`) instead of blocking uploads.
  The adapter follows Sightengine's documented `check.json` format and is tested against a fake server only — verify it with your
  own account and tune the thresholds in `image-moderation.ts` on real data.

## Offline behaviour

The first page of each listing feed is cached on the device and shown, with a banner, only when the network is unavailable.
Server errors are never masked by the cache.

## Known gaps

- **Languages**: Uzbek (Latin) and Russian. Every UI string is written in Uzbek in the code as `tr('…')`; Russian lives in
  `tool/l10n/*.txt` (`uzbek ||| russian`) and is compiled into `lib/core/l10n/ru.dart` with `python3 tool/l10n/build.py`.
  `test/unit/l10n_test.dart` fails when a `tr()` string has no Russian entry. Demo seed data and user-generated text are not translated.
- **Search**: PostgreSQL trigram search is the default. `SEARCH_PROVIDER=meilisearch` (+ `MEILI_URL`, `MEILI_API_KEY`) switches to
  Meilisearch: typo tolerance and ranking come from the engine, the worker syncs changed rows every minute (so results lag writes
  by up to a minute), and `postgres` remains a valid fallback. Tested against Meilisearch 1.11 (`test/search-meilisearch.e2e-spec.ts`,
  enabled by `TEST_MEILI_URL`). Run a full reindex by clearing the `search:sync:*` Redis keys.
- **Load testing**: none yet (chat, search, feed).
- **Device integration tests**: only widget tests and the optional live-backend test exist.
