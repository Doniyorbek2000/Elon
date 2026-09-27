# API contract (v1)

Implemented by `backend/` (NestJS). Interactive OpenAPI: `GET /api/v1/docs` (development only; never served when `NODE_ENV=production`).

The app's base URL is `--dart-define=API_BASE_URL=https://api.example.uz/api/v1`.

## Conventions

| Topic | Rule |
|---|---|
| Versioning | Everything under `/api/v1`. |
| Success | `{ "data": … }`; collections add `"meta": { "nextCursor": "…" \| null }`. |
| Errors | `{ "error": { "code", "message", "details"?, "requestId" } }`. `requestId` equals the `X-Request-Id` response header (send your own to correlate). |
| Pagination | Cursor based: `?limit=1..50&cursor=<opaque>`. Clients never build cursors. |
| Enums | lowerCamel on the wire (`pendingReview`, `upTo1`, `fullTime`). |
| Money | `{ "amount": 11500, "currency": "uzs" \| "usd" }` (integer units). |
| Auth | `Authorization: Bearer <access token>` (JWT, 15 min). Identity comes only from the token; `userId`/`sellerId`/`ownerId` in bodies are rejected (`422`, unknown field). |
| Validation | Unknown fields → `422 VALIDATION_FAILED` with `details.fields`. |
| Rate limits | `429 RATE_LIMITED` / `OTP_COOLDOWN` with `details.retryAfterSeconds` and `Retry-After`. |

### Error codes → Flutter failures (`ApiClient.mapErrorResponse`)

| HTTP | code(s) | Flutter |
|---|---|---|
| 401 | `UNAUTHENTICATED`, `TOKEN_EXPIRED`, `SESSION_REVOKED` | `UnauthorizedFailure` (after one transparent refresh attempt) |
| 403 | `FORBIDDEN`, `NOT_ELIGIBLE` | `ForbiddenFailure` |
| 403 | `BLOCKED` | `BlockedFailure` |
| 404 | `NOT_FOUND` (also for resources you may not see — no existence oracle) | `NotFoundFailure` |
| 409 | `CONFLICT`, `INVALID_STATE` | `ConflictFailure(code)` |
| 413 / 415 | `PAYLOAD_TOO_LARGE`, `UNSUPPORTED_MEDIA` | `ValidationFailure` |
| 422 | `VALIDATION_FAILED`, `OTP_INVALID`, `OTP_EXPIRED` | `ValidationFailure(fieldErrors, code)` |
| 429 | `RATE_LIMITED`, `OTP_COOLDOWN`, `OTP_TOO_MANY_ATTEMPTS` | `RateLimitFailure(retryAfter)` |
| 5xx | `INTERNAL`, `SERVICE_UNAVAILABLE` | `ServerFailure` |
| — | timeout / no connection | `TimeoutFailure` / `NetworkFailure` |

## Auth

| Method | Path | Notes |
|---|---|---|
| POST | `/auth/otp/request` | `{ phone }` (any Uzbek format; normalized to `998XXXXXXXXX`). → `{ expiresInSeconds, resendInSeconds }`. Cooldown, per-phone and per-IP quotas. |
| POST | `/auth/otp/verify` | `{ phone, code, device: { id, platform, name? } }` → `{ accessToken, accessTokenExpiresIn, refreshToken, sessionId, userId, isNewUser }`. Wrong codes count; the challenge locks after `OTP_MAX_ATTEMPTS`. |
| POST | `/auth/refresh` | `{ refreshToken }` → new pair. Refresh tokens are single use; replaying an old one revokes the session (theft detection). |
| POST | `/auth/logout`, `/auth/logout-all` | Revokes current / all sessions; removes their push tokens and disconnects their sockets. |
| GET/DELETE | `/auth/sessions`, `/auth/sessions/:id` | Device list and remote sign-out. |

## Resources

| Area | Endpoints |
|---|---|
| Account | `GET/PATCH /me` (name, avatarId, showPhone, messagePreviews, preferred region/district/locality/radius), `GET /users/:id` |
| Reference | `GET /categories?kind=` (tree + form schema: `text/number/boolean/select/multiSelect` fields), `GET /service-categories`, `GET /locations/tree`, `GET /locations/resolve?lat&lng` |
| Media | `POST /media` (multipart `file` + `purpose` = listing/avatar/chat/portfolio/offering; JPEG/PNG/WebP/HEIC, ≤ 15 MB) → `{ id, status: processing }`; `GET /media/:id`; `POST /media/:id/retry`; `GET /media/:id/{thumbnail,feed,detail}` (WebP, EXIF stripped; chat media only for participants); `DELETE /media/:id` |
| Listings | `GET /listings` (`q, category, region, district, locality, radius, lat, lng, priceMin, priceMax, condition, seller, sort=newest\|priceAsc\|priceDesc\|popular\|nearest`), `GET /listings/:id`, `GET /listings/:id/similar`, `POST /listings` (`publish` default true), `PATCH /listings/:id`, `POST /listings/:id/publish`, `POST /listings/:id/status` (`reserved\|sold\|archived\|active`), `DELETE /listings/:id`, `POST /listings/:id/contact` (phone reveal, rate limited, honours `showPhone`), `GET /me/listings?status=` |
| Moderation | `GET /moderation/listings`, `POST /moderation/listings/:id/approve\|reject` (MODERATOR/ADMIN role only) |
| Favorites | `GET /favorites/ids`, `GET /favorites/{listings\|jobs\|providers}`, `PUT/DELETE /favorites/:kind/:id` (idempotent) |
| Search | `GET /search?q&scope=all\|listings\|jobs\|services\|users&region&category` → `{ listings, jobs, providers, users, correctedQuery, engine }`, `GET /search/suggest?q`, `GET /search/popular` |
| Jobs | `GET /jobs` (`q, region, district, radius, lat, lng, types, workFormat, experience, salaryMin, sort=newest\|salary`), `GET /jobs/:id`, `POST /jobs`, `PUT /jobs/:id`, `POST /jobs/:id/status` (`active\|paused\|filled\|archived`), `DELETE /jobs/:id`, `POST /jobs/:id/contact`, `GET /me/jobs` |
| Applications | `POST /jobs/:id/applications` (`coverLetter?`), `GET /jobs/:id/applications` (owner only; includes phone + CV unless hidden), `PATCH /applications/:id/status` (`viewed\|shortlisted\|rejected\|accepted`), `POST /applications/:id/withdraw`, `GET /me/applications` |
| CV | `GET/PUT /me/resume` (`visibility = public\|applicationsOnly\|hidden`), `GET /candidates`, `GET /candidates/:id`, `POST /candidates/:id/contact` |
| Services | `GET /providers` (`q, category, region, district, radius, lat, lng, filter, sort`), `GET /providers/:id`, `POST /providers/:id/contact`, `GET/PUT /me/provider`, `POST /me/provider/status`, `PUT /me/provider/portfolio`, `POST/PATCH/DELETE /me/provider/offerings[/:id]` |
| Reviews | `GET /providers/:id/reviews`, `PUT/DELETE /providers/:id/reviews/mine` — one per customer; requires a two-way conversation with the provider (`403 NOT_ELIGIBLE` otherwise); no self-reviews; ratings are aggregates of real reviews only. |
| Chat | `POST /conversations` (`contextType = listing\|job\|service\|candidate`, `contextId`; the peer is derived server-side; deduplicated per context and pair), `GET /conversations`, `GET /conversations/unread-count`, `GET /conversations/:id`, `GET /conversations/:id/messages` (newest first), `POST /conversations/:id/messages` (`type = text\|image\|listingShare`, `clientId` for idempotent retries), `POST /conversations/:id/read\|delivered\|archive` |
| Notifications | `GET /notifications` (meta includes `unreadCount`), `GET /notifications/unread-count`, `POST /notifications/:id/read`, `POST /notifications/read-all`, `PUT/DELETE /push-devices` |
| Safety | `POST /reports` (idempotent per reporter+target; escalates to moderation at 3 reports), `GET /blocks`, `PUT/DELETE /blocks/:userId` |
| Health | `GET /health/live`, `GET /health/ready` (database, Redis, storage; 503 when degraded) |

## Realtime (Socket.IO)

Namespace `/chat`, path `/socket.io`, handshake `auth: { token: <access token> }`. Invalid/revoked tokens are refused at connect (`connect_error` message = error code).

| Direction | Event | Payload |
|---|---|---|
| client → server (ack) | `message:send` | `{ conversationId, type, text?, mediaIds?, sharedListingId?, clientId? }` → `{ ok, data \| error }` |
| client → server (ack) | `conversation:read`, `conversation:delivered` | `{ conversationId }` |
| client → server (ack) | `typing` | `{ conversationId, isTyping }` (never persisted) |
| client → server (ack) | `presence:heartbeat`, `presence:subscribe`, `presence:unsubscribe` | `{ userIds }` — only chat partners are returned/subscribed |
| server → client | `message:new` | `{ conversationId, message }` (to all devices of both participants) |
| server → client | `message:read`, `message:delivered` | `{ conversationId, userId, readAt \| deliveredAt }` |
| server → client | `typing` | `{ conversationId, userId, isTyping }` |
| server → client | `presence` | `{ userId, online, lastSeenAt? }` |

Recipients without a live socket get a push (`data.route = /chat/{id}`); message text is replaced by a generic line when the recipient disabled previews.

## Push payload

`data`: `{ route, type, …ids }`. Routes used today: `/chat/{id}`, `/listing/{id}`, `/provider/{id}`, `/employer/jobs/{id}/applicants`, `/account/applications`. The app routes taps to `data.route`.
