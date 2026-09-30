# Architecture

## Layout

```
lib/
  main.dart                  bootstrap: error hooks, prefs, ProviderScope
  app/
    app.dart                 MaterialApp.router, themes, locale, text-scale cap
    router/                  go_router routes, guards (onboarding, auth), deep links
    shell/                   tab shell: bottom bar with raised “+”, NavigationRail ≥ 840dp
  core/
    config/                  AppConfig (--dart-define), FeatureFlags
    design/                  tokens (colors, spacing, radii, motion, breakpoints), theme, icons
    domain/                  shared value types: Money, MediaImage, Place, PublicProfile, paging
    errors/                  AppFailure sealed hierarchy
    network/                 ApiClient (Dio) + auth interceptor + error mapping
    storage/                 KeyValueStore (prefs), SecureStore (Keychain/Keystore)
    sharing/                 deep-link builder, share service, share sheet
    utils/                   formatters (uz), input formatters, clock, external actions
    widgets/                 design-system components
  data/demo/                 ALL demo content (seed + in-memory database)
  features/<feature>/
    domain/                  entities, value objects, repository interfaces, pure rules
    data/                    demo_* and remote_* repository implementations, bundled config
    application/             Riverpod providers / Notifiers (state, orchestration)
    presentation/            screens and feature widgets
```

Features: `onboarding, home, catalog, listings, create_listing, jobs, services, search, location, chat, auth, profile, saved, notifications, trust_safety, business, settings`.

## Principles

- **Widgets never contain business logic or data.** Screens read providers; controllers call repositories; repositories return typed domain objects or throw `AppFailure`.
- **One seam per backend.** Each `*RepositoryProvider` picks the demo or remote implementation from `AppConfig.useDemoData`. Replacing demo data never touches UI code.
- **Demo data lives in exactly one place:** `lib/data/demo/demo_seed.dart`. Bundled taxonomy (`catalog/data/bundled_categories.dart`), Uzbekistan location tree (`location/data/uzbekistan_locations.dart`) and service categories are real configuration, shipped for instant first paint and refreshable from a backend later.
- **No codegen.** Models are small immutable classes with hand-written `fromJson` where a remote implementation exists. Freezed/json_serializable can be introduced per feature when payloads grow; it was deliberately not added to keep the build step-free.

## State (Riverpod 3)

| Concern | Provider |
|---|---|
| Infinite feeds | `listingFeedProvider(ListingQuery)` — `AsyncNotifier` with `PagedState`, `refresh()`, `loadMore()`; auto-disposed |
| Detail pages | `FutureProvider.autoDispose.family` |
| Favorites | `savedItemsProvider` (persisted) + `isSavedProvider` selector so a card rebuilds only when its own heart flips |
| Location | `locationProvider` (persisted; GPS optional) |
| Create flow | `createListingProvider` — steps, validation, uploads, reorder/cover, debounced draft persistence, publish |
| Session | `sessionProvider` (guest allowed; posting/chat/apply gated) |
| Chat | stream providers over `ChatRepository`; transport seam `ChatRealtimeGateway` for WebSockets |

Global auto-retry is disabled (`ProviderScope(retry: …)`): every failure surfaces an explicit retry action, so offline state is never hidden.

## Navigation

`StatefulShellRoute.indexedStack` keeps each tab’s stack and scroll position; re-tapping the active tab pops to its root. Detail pages, the create flow (full-screen dialog) and account pages sit above the shell. Guards: first launch → `/welcome` only for the landing route (shared deep links open content immediately); protected routes (`/create`, `/chat/*`, `/account/listings|applications|edit`) redirect to `/verify-phone?next=…`.

## Design system

`AppPalette` (ThemeExtension) defines semantic colors for **light and a separately designed dark palette** (navy surfaces, lifted accents for AA contrast; elevation expressed through surface tone, not shadows). Tokens: `AppSpacing`, `AppRadii`, `AppIconSize`, `AppTouch` (48dp targets), `AppMotion` (durations respect OS reduce-motion), `AppBreakpoints` (compact/medium/expanded by width, never by device model), `AppShadows`.

Components (`core/widgets`): `AppImage`, `Shimmer/SkeletonBox`, `AppSearchField`, `SectionHeader`, `ToneIcon`, `SurfaceCard`, `Pressable`, `ChoiceChipsRow`, `InfoTile`, `MetaLine`, `RatingLabel`, `VerifiedBadge`, `StatusPill`, `CountBadge`, `AppAvatar`, `FavoriteButton`, `EmptyState`, `FailureView`, `LoadMoreFooter`, `SheetScaffold`/`showAppSheet`, `StickyActionBar`, `CircleIconButton`, `ExpandableText`, `SafetyTipsCard`, `DetailSection`, `ContactSheet`, `ShareSheet`, `BrandMark`, `LandscapeBackdrop`.

## Performance

- `MediaImage` carries **thumbnail / feed / detail / original** renditions; `AppImage` picks the smallest one covering *laid-out width × DPR*, decodes at that size (`memCacheWidth`) and disk-caches. Feed cards never request originals.
- Uploads are compressed at pick time (≤ 2048 px, JPEG q82); the server generates renditions.
- Slivers + builders everywhere; grid tile heights are computed from text scale so there is no intrinsic layout pass.
- One shimmer ticker per skeleton group; animations stop under reduce-motion.
- Search suggestions are debounced by disposing the provider on each keystroke.

## Accessibility

Semantic labels on cards (title, price, place, time), toggles expose `toggled`, live regions for typing/loading, 48dp targets, text scale honored up to 200 % (layouts reflow: grids drop columns, action bars stack), bottom-bar labels capped at 120 % so five slots fit on 320 pt screens. `test/widget/responsive_layout_test.dart` renders 29 routes × 4 viewports (320 pt, 130 %, 200 %, iPad) and fails on any overflow.

## Trust & safety

Client-side heuristics (`trust_safety/domain`) warn about card numbers, phone numbers in text, external links, prepayment requests and price outliers; anything above “info” publishes as *pending review*. `MessageGuard` throttles chat bursts and warns before sending risky content. Contact numbers are fetched only on explicit “Qo‘ng‘iroq” (server rate-limited). Verification badges render only server-asserted levels. Report/block exist for listings, users, jobs, providers and conversations.

## Free service

The service is free: no payments, plans, credits, coupons or paid promotion. Business profiles, storefronts, team members and listing statistics are free, with fixed fair-use limits enforced by the backend (`LimitsService`).

## Localization

UI copy is Uzbek (Latin) inline; Material widgets are localized via `GlobalMaterialLocalizations` (`uz`). Next step for Russian: extract strings to ARB (`flutter gen-l10n`).
