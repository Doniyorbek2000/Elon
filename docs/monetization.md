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
- **Payme / Click**: interface + webhook routes + configuration keys only. Their merchant documentation was not reachable from the build environment, so no protocol code was written from memory. They report `NOT_CONFIGURED` until implemented against the official docs.
- **Apple / Google**: interfaces for server-side receipt/purchase verification; `NOT_CONFIGURED` until App Store Server API / Play Developer API credentials exist.
- Webhooks: signature verified first; each provider event id is stored once (replay → no-op); payment rows are locked (`SELECT … FOR UPDATE`) and moved through an explicit state machine; fulfillment is unique per purchase.
- Money: `BigInt` minor units (`amountMinor`, tiyin for UZS). No floats.

### Store-policy decision (requires confirmation before release)
Checkout routes are data (`AppSetting checkout.routes`), resolved per platform × product kind × country:

| Platform | Default route for digital products (boosts, subscriptions, ads) |
|---|---|
| iOS | `apple` only — App Review Guideline 2.5.18: “buying advertisements … (such as sales of “boosts” …) must use in-app purchase”; 3.1.1 subscriptions/features must use IAP; outside the US storefront no links/buttons to other purchase methods. |
| Android (Google Play) | `google` only — Play Payments policy: in-app features/digital goods must use Google Play’s billing system unless an exception applies. |
| Web | `payme`, `click` (when implemented); `dev` in non-production. |

Consequence today: with store billing not configured, **mobile production builds show products but no purchasable route** (clear message, no external link). Legal/commercial confirmation is needed for: (1) whether any product qualifies for an exception, (2) region-specific alternative billing programs, (3) web checkout and how (if at all) the app may reference it.

Sources: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Google Play Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738), [Understanding Google Play’s Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818).

### Future commission marketplace
Extension points only (`Purchase.kind` can gain `ORDER_COMMISSION`; `PaymentProvider` supports split/hold capabilities flags). No escrow is implemented or claimed.
