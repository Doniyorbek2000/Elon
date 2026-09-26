# Bozor.uz — mobile app

Local-first marketplace for Uzbekistan that combines **classifieds (E’lonlar)**, **jobs (Ish)** and **local services (Xizmatlar)** in one Flutter app for Android and iOS.

| Home | Listing | Create | Jobs | Services | Chat |
|---|---|---|---|---|---|
| ![](docs/screenshots/iphone15_01_home.jpg) | ![](docs/screenshots/iphone15_04_listing_detail.jpg) | ![](docs/screenshots/iphone15_05_create_listing.jpg) | ![](docs/screenshots/iphone15_06_jobs.jpg) | ![](docs/screenshots/iphone15_08_services.jpg) | ![](docs/screenshots/iphone15_12_conversation.jpg) |

Screenshots are rendered by the test suite with network images disabled, so photos show the category placeholder. On a device, demo listings load photos from Unsplash.

## Requirements

- Flutter **3.47.x stable** (Dart 3.13)
- Android: Android SDK (compileSdk 36, minSdk 24), JDK 17
- iOS: Xcode 16+, CocoaPods, iOS 15.0+

## Run

```bash
flutter pub get
flutter run                                   # demo data, no backend needed
flutter run --dart-define=API_BASE_URL=https://api.bozor.uz/v1   # real API for listings/jobs
```

With no `API_BASE_URL` the app runs on local demo data (`lib/data/demo/`).

### Build-time configuration (`--dart-define`)

| Key | Default | Purpose |
|---|---|---|
| `API_BASE_URL` | *(empty → demo data)* | REST backend base URL |
| `WEB_BASE_URL` | `https://bozor.uz` | Share links / App Links / Universal Links host |
| `APP_SCHEME` | `bozor` | Custom URL scheme (`bozor://app/listing/42`) |
| `SUPPORT_TELEGRAM_URL` | `https://t.me/bozoruz_support` | Help → support button. **Replace with the real account.** |
| `DEMO_LATENCY_MS` | `450` | Simulated latency for demo repositories |
| `FF_MONETIZATION`, `FF_PAID_PROMOTIONS`, `FF_SUBSCRIPTIONS`, `FF_BUSINESS_ACCOUNTS`, `FF_ADVERTISING` | `false` | Monetization switches (hidden during the free phase) |
| `FF_AI_LISTING_ASSIST` | `false` | Photo → title/description suggestions in the create flow |
| `FF_PROMOTION_BADGES` | `true` | Show TOP/VIP badges |
| `FF_REALTIME_CHAT` | `false` | Use the WebSocket chat gateway |

### Android release signing

Create `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without it, release builds fall back to debug signing (local testing only).

## Quality checks

```bash
dart format -l 120 lib test tool
flutter analyze
flutter test                                                  # 183 unit + widget + responsive tests
flutter test tool/screenshots/screens_test.dart --update-goldens   # renders all screens × 6 devices to tool/screenshots/out/
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — layers, state, design system, performance, accessibility
- [Backend contract](docs/backend-contract.md) — endpoints the remote repositories expect
- [Deep linking](docs/deep-linking.md) — App Links / Universal Links / Telegram share loop
- UI reference: `docs/reference/marketplace-ui.png`

Fonts: [Inter](https://rsms.me/inter/) (SIL OFL 1.1, `assets/fonts/OFL.txt`), subset to Latin, Latin Extended, Cyrillic and Uzbek apostrophes (ʻ ‘).
