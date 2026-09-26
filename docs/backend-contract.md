# Backend contract (v1 draft)

Base URL comes from `--dart-define=API_BASE_URL`. JSON everywhere; auth via `Authorization: Bearer <token>` (stored in Keychain/Keystore through `SecureStore`); `Accept-Language: uz`.

Errors: non-2xx with `{ "message": "...", "errors": { "field": "..." } }`. Mapping in `ApiClient.mapDioException`: 401/403 → `UnauthorizedFailure`, 404 → `NotFoundFailure`, 400/422 → `ValidationFailure(fieldErrors)`, 429 → `RateLimitFailure`, others → `ServerFailure`.

## Shared shapes

```jsonc
// MediaImage
{ "id": "img_1", "blurHash": "…", "aspectRatio": 1.33,
  "variants": { "thumbnail": "https://cdn/…?w=160", "feed": "…w=480", "detail": "…w=1080", "original": "…" } }
// Place
{ "regionId": "namangan", "regionName": "Namangan viloyati", "districtId": "chust", "districtName": "Chust tumani",
  "localityName": "Karkidon", "lat": 41.0, "lng": 71.2 }
// Money
{ "amount": 120000000, "currency": "uzs" }          // or "usd"
// PublicProfile — never contains phone numbers
{ "id": "u_1", "name": "Azizbek", "avatar": MediaImage?, "verification": "none|phone|identity|business",
  "accountType": "personal|business", "isOnline": true, "lastActiveAt": ISO8601?, "memberSince": ISO8601,
  "rating": 4.8, "reviewCount": 37, "responseRate": 0.96, "responseTimeMinutes": 15, "activeListings": 4 }
```

## Listings — `RemoteListingRepository`

| Method | Path | Notes |
|---|---|---|
| GET | `/listings?q&category&region&district&radius&priceMin&priceMax&condition&sort&seller&limit&cursor` | `{ items: Listing[], nextCursor?, total? }`; `sort ∈ newest,priceAsc,priceDesc,popular,nearest`; `category` includes descendants; with `radius`, origin = district (or region) center, results carry `distanceKm` |
| GET | `/listings?ids=a,b` | favorites hydration |
| GET | `/listings/{id}` | `Listing` |
| GET | `/listings/{id}/similar?limit` | |
| POST | `/listings/{id}/views` | fire-and-forget |
| POST | `/listings/{id}/phone` | `{ phone }` — rate-limited, logged |
| POST | `/listings` | `NewListing.toJson()`; `imageIds` from the media upload endpoint; server may return `status: pendingReview` |
| PATCH | `/listings/{id}` | `{ status }` |
| DELETE | `/listings/{id}` | |
| GET | `/users/{id}/listings` | |

`Listing`: `id, title, description, categoryId, images[], place, publishedAt, seller, price?, negotiable, condition (new|used)?, attributes[{key,label,value}], views, favorites, promotion (top|vip|bump|featured)?, status (active|pendingReview|rejected|sold|archived)`.

## Jobs — `RemoteJobRepository`

| Method | Path |
|---|---|
| GET | `/jobs?q&types=fullTime,remote&experience&salaryMin&region&district&sort=newest|salary` → `{ items: Job[] }` |
| GET | `/jobs/{id}` |
| POST | `/jobs` (`NewVacancy`) |
| GET | `/candidates?…` → `{ items: CandidateProfile[] }`, `GET /candidates/{id}` |
| POST | `/jobs/{id}/applications` `{ message? }` → `JobApplication` |
| GET | `/me/applications` → `{ items: JobApplication[] }` |
| POST | `/users/{id}/phone` → `{ phone }` |

## Still to implement server-side (client interfaces exist)

| Interface | Location | Notes |
|---|---|---|
| `AuthRepository` | `features/auth/domain/auth.dart` | SMS OTP: request code, verify → tokens + `CurrentUser`, profile update |
| `MediaUploadService` | `features/create_listing/domain/media_upload.dart` | multipart upload with progress (`ApiClient.upload`), returns media id; server builds renditions |
| `ServicesRepository` | `features/services/domain/service_provider.dart` | categories, recommended, search, provider profile, phone reveal |
| `ChatRepository` + `ChatRealtimeGateway` | `features/chat/domain/chat.dart` | REST history + WebSocket events (`MessageReceived`, `TypingChanged`, `DeliveryChanged`, `PresenceChanged`) |
| `SearchRepository` | `features/search/domain/search.dart` | server index with typo tolerance/transliteration (Meilisearch/Elasticsearch) |
| `TrustSafetyRepository` | `features/trust_safety/domain/trust_safety.dart` | reports, block/unblock |
| `NotificationsRepository` | `features/notifications/domain/app_notification.dart` | + push (FCM/APNs) with `deepLink` payloads |
| `ProfilesRepository` | `features/profile/application/profile_providers.dart` | public profiles/storefronts |
| `MonetizationRepository` | `features/monetization/application/monetization_providers.dart` | catalog + payments (Click / Payme / Uzum) |
| `ListingAssistService` | `features/create_listing/domain/media_upload.dart` | vision model → category/title/description/attributes |
