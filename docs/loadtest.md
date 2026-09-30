# Load testing

Scripts live in `backend/loadtest/` (plain Node; `autocannon` and `socket.io-client` are dev dependencies).

```bash
cd backend && npm run build
# 1. a throw-away database with reference data + 20 000 synthetic listings
npx prisma migrate deploy && npm run db:seed && npm run loadtest:seed -- 20000
# 2. the API with rate limiting raised and dev OTP echo (never in production)
RATE_LIMIT_PER_MINUTE=1000000 OTP_PROVIDER=dev OTP_DEV_ECHO=true npm start
# 3. read path (feed, filters, detail, search) and realtime chat
BASE_URL=http://localhost:3000 npm run loadtest:http -- 15 100      # seconds, connections
BASE_URL=http://localhost:3000 npm run loadtest:chat -- 50 20       # pairs, messages per pair
```

`loadtest:http` fails the run when p99 exceeds `P99_MS` (default 800) or the error rate exceeds `MAX_ERROR_RATE` (default 0.1 %);
`loadtest:chat` fails on any rejected message or p99 send→ack above `P99_MS` (default 500).
`.github/workflows/loadtest.yml` runs the same thing on demand.

## Measured once (this is a sandbox, not capacity planning)

Everything — load generator, API (one Node process), PostgreSQL 16, Redis, Meilisearch — shared **4 vCPUs**; 20 000 active listings;
100 connections × 10 s per scenario.

| Scenario | req/s | p50 ms | p99 ms | errors |
|---|---:|---:|---:|---:|
| `GET /config` | 1 025 | 86 | 153 | 0 % |
| `GET /categories` | 999 | 93 | 197 | 0 % |
| `GET /listings` (feed) | 309 | 310 | 1 047 | 0 % |
| `GET /listings?region=…` | 310 | 310 | 896 | 0 % |
| `GET /listings/:id` | 454 | 206 | 686 | 0 % |
| `GET /search` — PostgreSQL (pg_trgm) | 96 | 925 | 2 131 | 0 % |
| `GET /search` — Meilisearch 1.11 | 179 | 545 | 825 | 0 % |

Chat, 50 conversations × 20 messages through Socket.IO: 1 000/1 000 acknowledged and delivered, ~258 msg/s,
send→ack p50 76 ms / p99 160 ms, send→delivered p50 71 ms / p99 156 ms.

What this says: the feed and search are CPU-bound on the database at this data volume, search is the first thing to hurt
(PostgreSQL ranks every trigram match: ~19 ms per query at 1 400 matches), Meilisearch roughly doubles search throughput on the
same hardware, and a single API process holds a few hundred chat messages per second comfortably. It does **not** say how a real
deployment behaves: run it against production-shaped infrastructure (separate DB host, several API replicas behind a load balancer,
the Redis adapter for Socket.IO) before sizing anything. Feed p99 above 800 ms at 100 concurrent connections is the number to beat.
