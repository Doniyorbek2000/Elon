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

The app uses the pure-Dart `sentry` package (Dart errors only). Native crashes need `sentry_flutter` with symbol upload.

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
  to moderation (`duplicate_image`). Content classification (nudity, violence) is **not** implemented; it needs an external service.

## Offline behaviour

The first page of each listing feed is cached on the device and shown, with a banner, only when the network is unavailable.
Server errors are never masked by the cache.

## Known gaps

- **Languages**: the app is Uzbek (Latin) only. Russian needs about a thousand strings extracted (`gen-l10n`), Russian
  category names on the server and localized notification texts; it is not started.
- **Search**: PostgreSQL trigram/token search behind the `SearchProvider` interface; move to Meilisearch/Typesense when
  volume or typo-tolerance demands it.
- **Load testing**: none yet (chat, search, feed).
- **Device integration tests**: only widget tests and the optional live-backend test exist.
