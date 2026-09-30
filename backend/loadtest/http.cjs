'use strict';
// Read-path load test with autocannon.
//   BASE_URL=http://localhost:3000 node loadtest/http.cjs [seconds=15] [connections=100]
// Environment: P99_MS (default 800) and MAX_ERROR_RATE (default 0.001) turn the run into a pass/fail check.
const autocannon = require('autocannon');
const { API, call } = require('./lib.cjs');

const DURATION = Number(process.argv[2] || 15);
const CONNECTIONS = Number(process.argv[3] || 100);
const P99 = Number(process.env.P99_MS || 800);
const MAX_ERRORS = Number(process.env.MAX_ERROR_RATE || 0.001);

const QUERIES = ['iphone', 'samsung', 'cobalt', 'kvartira', 'divan', 'noutbuk', 'ayfon', 'кобалт'];

async function run(name, path, extra = {}) {
  const result = await autocannon({
    url: `${API}${path}`,
    connections: CONNECTIONS,
    duration: DURATION,
    ...extra,
  });
  const errors = result.errors + result.timeouts + result.non2xx;
  const total = result.requests.total || 1;
  return {
    name,
    rps: Math.round(result.requests.average),
    p50: result.latency.p50,
    p99: result.latency.p99,
    max: result.latency.max,
    errorRate: errors / total,
  };
}

async function main() {
  const feed = await call('GET', '/listings?limit=20');
  const listingId = feed[0]?.id;
  if (!listingId) throw new Error('No listings: run loadtest/seed.cjs first');
  const requests = QUERIES.map((q) => ({
    method: 'GET',
    path: `/api/v1/search?q=${encodeURIComponent(q)}&scope=listings`,
  }));

  const scenarios = [
    ['GET /config', '/config'],
    ['GET /categories', '/categories'],
    ['GET /listings (feed)', '/listings?limit=20'],
    ['GET /listings (region filter)', '/listings?region=namangan&limit=20'],
    ['GET /listings/:id', `/listings/${listingId}`],
  ];
  const results = [];
  for (const [name, path] of scenarios) results.push(await run(name, path));
  const search = await autocannon({ url: API, connections: CONNECTIONS, duration: DURATION, requests });
  results.push({
    name: 'GET /search (8 queries)',
    rps: Math.round(search.requests.average),
    p50: search.latency.p50,
    p99: search.latency.p99,
    max: search.latency.max,
    errorRate: (search.errors + search.timeouts + search.non2xx) / (search.requests.total || 1),
  });

  console.log(`\n${CONNECTIONS} connections × ${DURATION}s each\n`);
  console.log(
    'scenario'.padEnd(34),
    'req/s'.padStart(8),
    'p50 ms'.padStart(8),
    'p99 ms'.padStart(8),
    'max ms'.padStart(8),
    'errors'.padStart(8),
  );
  for (const r of results) {
    console.log(
      r.name.padEnd(34),
      String(r.rps).padStart(8),
      String(r.p50).padStart(8),
      String(r.p99).padStart(8),
      String(r.max).padStart(8),
      `${(r.errorRate * 100).toFixed(2)}%`.padStart(8),
    );
  }
  const failed = results.filter((r) => r.p99 > P99 || r.errorRate > MAX_ERRORS);
  if (failed.length) {
    console.error(
      `\nFAILED: ${failed.map((r) => r.name).join(', ')} (p99 > ${P99} ms or error rate > ${MAX_ERRORS * 100}%)`,
    );
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
