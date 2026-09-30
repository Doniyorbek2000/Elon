# Monetization & business platform (Phase 7)

## Audit (state before Phase 7)

| Area | Found |
|---|---|
| Schema | `PromotionType` enum and never-written `promotionType/promotedUntil` columns on `Listing`, `Job`, `ServiceProvider`. `Profile.accountType` (PERSONAL/BUSINESS). No payments, plans, business or ad models. |
| Backend flags | `FEATURE_MONETIZATION/PAID_PROMOTIONS/BUSINESS_ACCOUNTS` env vars (require redeploy to change), not used anywhere. |
| Flutter | `StaticMonetizationRepository` with **hardcoded client-side prices**; flags only from `--dart-define` (need an app release to change); `_PromoteSheet` and `PlansScreen` gated off. |
| Admin | `MODERATOR/ADMIN` roles; only listing moderation endpoints. No admin app. |
| Limits | None besides DTO caps (12 photos). |

## Principles

- Core marketplace stays free: browse, search, chat, favorites, a generous number of listings, job applications, services.
- We sell **visibility, speed, business tools, promotion, convenience** — never quality signals. Payment never touches ratings or reviews.
- Server is authoritative for prices, eligibility, entitlements, payment state and activation. The app only displays them.
- Everything commercial is switchable at runtime (`FeatureFlag` table) and priced in the database (`ProductPrice`, `PlanPrice`). Seed data contains **no production prices** — products are created inactive/unpriced until an admin sets them.

## Architecture

```
catalog  ── PromotionProduct (+ProductPrice history), Plan (+PlanPrice)
config   ── FeatureFlag, AppSetting (limits, checkout routes, slots)
checkout ── Purchase (price snapshot, coupon) ─┬─ Payment ── PaymentEvent (webhook/reconciliation log, unique per provider event)
                                               │            └─ Refund
                                               └─ fulfillment (in the same DB transaction as the verified SUCCEEDED transition)
                                                    ├─ PromotionActivation ──> ranking cache on Listing/Job/ServiceProvider (boostTier, boostUntil, rankedAt)
                                                    ├─ Subscription ──> entitlements, monthly CreditLedgerEntry grants
                                                    └─ AdCampaign (pending review)
business ── Business, BusinessMember(OWNER|MANAGER) → storefront
analytics── ListingDailyStat, AdDailyStat (aggregates only, no personal data)
admin    ── /admin/monetization/* (ADMIN role) + AdminAuditLog
```

### Ranking
- Organic order is untouched; filters/relevance/location decide what is shown.
- **Bump** moves `rankedAt` (a dedicated ranking timestamp); `publishedAt`/`createdAt` never change. Cooldown between bumps.
- **TOP/VIP** set `boostTier` (VIP 2, TOP 1) until `boostUntil`. Paid items appear in a separate, labeled "TOP" block on the first page for the **same filters** (limited slots, fair rotation), not by pushing organic results away.
- **Featured** placements (home / category / region) are explicit activations with scope; shown only in labeled "Tavsiya" blocks.
- Expiry is enforced twice: every query checks `boostUntil > now()`, and a worker job clears the cache.

### Payments
- `PaymentProvider` adapters: `dev` (development/test only, HMAC-signed webhooks), `payme`, `click`, `apple`, `google`, plus internal `credits` and `free` (100 % coupon).
- **Click** (`providers/click.provider.ts`): Shop API two-phase callbacks (`Prepare`/`Complete`, MD5 `sign_string`), answered with HTTP 200 and Click error codes (`-1 … -9`). Enabled when `CLICK_SERVICE_ID`, `CLICK_MERCHANT_ID` and `CLICK_SECRET_KEY` are set. Callback URL for the Click cabinet: `POST {PUBLIC_API_URL}/api/v1/payments/webhooks/click` (both Prepare and Complete).
- **Payme** (`payme.service.ts`, `providers/payme.provider.ts`): Merchant API JSON-RPC (`CheckPerformTransaction`, `CreateTransaction`, `PerformTransaction`, `CancelTransaction`, `CheckTransaction`, `GetStatement`) with Basic auth, transaction state in `PaymeTransaction`, 12 h transaction timeout. Enabled when `PAYME_MERCHANT_ID` and `PAYME_KEY` are set (`PAYME_TEST_MODE=true` → `test.paycom.uz`). Endpoint for the Payme cabinet: `POST {PUBLIC_API_URL}/api/v1/payments/webhooks/payme`; the account field is `order_id`. A performed transaction cannot be cancelled through the API (`-31007`): refunds are handled by support.
- **Both were written from the public merchant specifications and verified against a simulator in `test/monetization-providers.e2e-spec.ts` — not against Click/Payme themselves.** Run their sandbox/test-cashbox checks before enabling either in production (field names, amount formats, and the exact error codes they expect are the usual places for surprises). Status polling and API-initiated refunds are not implemented for either.
- Provider callbacks are returned to the caller **without** the `{ data }` envelope (`RawResponse`).
- **Apple / Google**: interfaces for server-side receipt/purchase verification; `NOT_CONFIGURED` until App Store Server API / Play Developer API credentials exist.
- Webhooks: signature verified first; each provider event id is stored once (replay → no-op); payment rows are locked (`SELECT … FOR UPDATE`) and moved through an explicit state machine; fulfillment is unique per purchase.
- Money: `BigInt` minor units (`amountMinor`, tiyin for UZS). No floats.

### Store-policy decision (requires confirmation before release)
Checkout routes are data (`AppSetting` key `checkoutRoutes`, editable by admins), resolved per platform (`ios` / `android` / `web`). Per-country or per-product routing is not implemented; add it here if legal review requires it.

| Platform | Default route for digital products (boosts, subscriptions, ads) |
|---|---|
| iOS | `apple` only — App Review Guideline 2.5.18: “buying advertisements … (such as sales of “boosts” …) must use in-app purchase”; 3.1.1 subscriptions/features must use IAP; outside the US storefront no links/buttons to other purchase methods. |
| Android (Google Play) | `google` only — Play Payments policy: in-app features/digital goods must use Google Play’s billing system unless an exception applies. |
| Web | `payme`, `click` (when implemented); `dev` in non-production. |

Consequence today: with store billing not configured, **mobile production builds show products but no purchasable route** (clear message, no external link). Legal/commercial confirmation is needed for: (1) whether any product qualifies for an exception, (2) region-specific alternative billing programs, (3) web checkout and how (if at all) the app may reference it.

Sources: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738), [Understanding Google Play’s Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818).

### Client (Flutter)
- Flags and free-tier limits come from `GET /config` at start-up (`remoteConfigProvider`); if it fails, everything commercial stays hidden. The old `FF_*` build flags were removed (only `FF_AI_LISTING_ASSIST` remains).
- No prices, plans or products exist in the app. Demo builds use `UnavailableMonetizationRepository` / `EmptyPromotedRepository` (nothing for sale, no invented paid blocks).
- `CheckoutController` (not widgets) owns the flow: `POST /checkout` with a client idempotency key (reused on retry of the same attempt) → open the provider page (`redirect`) → poll `GET /me/purchases/:id` and re-check on app resume → show only what the server reports. Store actions go through `StoreBilling` (unavailable: the purchase is cancelled, nothing links out).
- Screens: “E’lonni tezroq soting” sheet (also vacancies, provider profile, ad campaigns), “TOP faollashtirildi” result, “To‘lovlar va tariflar” (plan, subscriptions, credits, receipts), “Biznes uchun” comparison, business profile + managers, public storefront `/business/:id`, listing statistics with promotion results.
- Paid blocks are separate from organic lists and always labeled (“Reklama”, TOP/VIP/Tavsiya/Shoshilinch). Failures of paid blocks hide the block, never the page.

### Launching a product (admin, no deploy)
1. `PUT /admin/monetization/flags/monetization {enabled:true}` and the product flag (e.g. `listingTop`).
2. `POST /admin/monetization/products/:id/prices {amountMinor, currency}` — whole so‘m only; `validFrom` in the future schedules a change.
3. `PATCH /admin/monetization/products/:id {active:true}` (refused without a price).
4. Plans: `POST /admin/monetization/plans/:id/prices {period}` + `PATCH …/plans/:id {active:true}`; plan limit edits apply immediately.
Every step is written to `AdminAuditLog`.

### Requires credentials / external work before real money
| Item | Status | Needed |
|---|---|---|
| Payme | Implemented (Merchant API), not verified against Payme | Merchant account + key, cabinet endpoint URL, sandbox run with Payme’s test cases; optional `fetchStatus`/refund work |
| Click | Implemented (Shop API), not verified against Click | Service/merchant ids + secret key, cabinet callback URL, sandbox run; optional status lookup/reversal |
| Apple IAP | Interface; route `ios → APPLE` | App Store Connect products, App Store Server API key; client StoreKit implementation of `StoreBilling`; receipt verification endpoint |
| Google Play Billing | Interface; route `android → GOOGLE` | Play Console products, service account for Play Developer API; client billing implementation; purchase-token verification + RTDN webhook |
| Real prices | None seeded | Business decision, entered via admin API |
| Legal/tax | Not done | Offer terms, refund policy text, fiscal receipts (OFD) requirements in Uzbekistan |

Nothing above has been sandbox-tested. Only the `dev` provider (HMAC-signed, test-only, refused in production by env validation) is exercised end-to-end in tests.

### Security review (Phase 7)
Checked: webhook signature before parsing (raw body, constant-time compare, 300 s timestamp window), event-id replay protection, row locks around payment/coupon/credit/bump state, idempotency keys, ownership checks returning 404 for others’ items, admin/finance role guards with audit log, rate limits on checkout/quote/ad events, no card data stored, no secrets in the repo or logs.
Fixed during review: (1) two bump purchases paid concurrently could both apply — fulfillment now locks the listing row and re-checks the cooldown (the loser goes to `NEEDS_REVIEW` for a refund decision); (2) a manager could open a second business — creation now requires no existing membership; (3) the dev checkout page token is compared in constant time.
Known limits: the per-process 15 s config cache means a flag change can take up to 15 s per API instance; entitlement cache is invalidated on plan edits and subscription changes.

### Future commission marketplace
Extension points only (`Purchase.kind` can gain `ORDER_COMMISSION`; `PaymentProvider` supports split/hold capabilities flags). No escrow is implemented or claimed.
