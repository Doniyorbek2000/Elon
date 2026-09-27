# Deep linking & the Telegram share loop

Every listing, vacancy, provider and seller has a canonical public URL that equals its in-app route:

| Content | URL | In-app route |
|---|---|---|
| Listing | `https://bozor.uz/listing/{id}` | `/listing/:id` |
| Vacancy | `https://bozor.uz/job/{id}` | `/job/:id` |
| Provider | `https://bozor.uz/provider/{id}` | `/provider/:id` |
| Seller profile | `https://bozor.uz/seller/{id}` | `/seller/:id` |
| Business storefront | `https://bozor.uz/business/{id}` | `/business/:id` |

Custom-scheme fallback: `bozor://app/listing/{id}`. Links are built by `DeepLinks` (`lib/core/sharing/share_service.dart`); host and scheme come from `WEB_BASE_URL` / `APP_SCHEME`.

Share flow (`showShareSheet`): preview card (image, title, price/salary, location, host) → **Telegram** (`tg://msg_url`, falling back to `https://t.me/share/url`), copy link, or the system share sheet. After publishing, the success screen puts “Telegram’da ulashish” first.

Routing rules: a deep link opens its content directly even on first launch (onboarding only gates `/`). Unknown paths show a “Sahifa topilmadi” page with a way home.

## Android App Links

Already declared in `android/app/src/main/AndroidManifest.xml` (`autoVerify="true"` for `https://bozor.uz` with the four path prefixes, plus `bozor://app`). Serve on the web host:

`https://bozor.uz/.well-known/assetlinks.json`
```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "uz.bozor.app",
    "sha256_cert_fingerprints": ["<SHA-256 of the Play App Signing key>"]
  }
}]
```

## iOS Universal Links

`FlutterDeepLinkingEnabled` and the `bozor` URL scheme are set in `ios/Runner/Info.plist`. To enable `https` links:

1. In Xcode → Runner → Signing & Capabilities add **Associated Domains** with `applinks:bozor.uz` (requires a paid Apple Developer team; this is why it is not pre-committed — it would break signing for personal teams).
2. Serve `https://bozor.uz/.well-known/apple-app-site-association` (no extension, `application/json`):

```json
{ "applinks": { "details": [{
  "appIDs": ["<TEAM_ID>.uz.bozor.app"],
  "components": [
    { "/": "/listing/*" }, { "/": "/job/*" }, { "/": "/provider/*" }, { "/": "/seller/*" }, { "/": "/business/*" }
  ]
}]}}
```

## Web landing fallback

When the app is not installed the same URL loads the website. The landing page should render Open Graph tags so Telegram shows a rich preview:

```html
<meta property="og:title" content="Cobalt 2023 — 120 000 000 so‘m">
<meta property="og:description" content="Chust, Namangan · Bozor.uz">
<meta property="og:image" content="https://cdn.bozor.uz/…?w=1080">
<meta property="og:url" content="https://bozor.uz/listing/l_cobalt_2023">
```

plus “Ilovada ochish” / store badges.

## Push notifications (FCM → Android + iOS)

The server sends pushes through FCM HTTP v1 (`backend/README.md` → credentials). Each push carries `data.route`; the app routes taps there (cold start included). Without Firebase options the app runs with in-app notifications only.

1. Create a Firebase project; add Android app `uz.bozor.app` and iOS app with your bundle id.
2. Build the app with `--dart-define=FIREBASE_API_KEY=… FIREBASE_APP_ID=… FIREBASE_SENDER_ID=… FIREBASE_PROJECT_ID=…` (+ `FIREBASE_IOS_BUNDLE_ID` for iOS). No `google-services.json` / `GoogleService-Info.plist` is committed.
3. iOS: in Xcode → Runner → Signing & Capabilities add **Push Notifications** (creates the `aps-environment` entitlement; requires a paid team) and upload an APNs auth key to Firebase. `UIBackgroundModes = remote-notification` is already in `Info.plist`.
4. Android 13+: the notification permission is requested after sign-in.
5. Server: `PUSH_PROVIDER=fcm`, `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT`.
