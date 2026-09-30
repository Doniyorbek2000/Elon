'use strict';
// Shared helpers for the load-test scripts (plain Node, no build step except `npm run build` for seed.cjs).

const BASE = (process.env.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
const API = `${BASE}/api/v1`;

async function call(method, path, { token, body, ip } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(ip ? { 'X-Forwarded-For': ip } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${JSON.stringify(json).slice(0, 200)}`);
  return json.data;
}

/** Signs a synthetic user in. Needs the API to run with OTP_PROVIDER=dev and OTP_DEV_ECHO=true (never production). */
async function signIn(index, fixedPhone) {
  const phone = fixedPhone || `99891${String(index).padStart(7, '0')}`;
  const ip = `10.${(index >> 16) & 255}.${(index >> 8) & 255}.${index & 255}`;
  let challenge;
  for (let attempt = 0; ; attempt++) {
    try {
      challenge = await call('POST', '/auth/otp/request', { body: { phone }, ip });
      break;
    } catch (error) {
      const wait = /OTP_COOLDOWN.*"retryAfterSeconds":(\d+)/.exec(String(error.message));
      if (!wait || attempt > 2) throw error;
      await new Promise((resolve) => setTimeout(resolve, (Number(wait[1]) + 1) * 1000));
    }
  }
  if (!challenge.devCode) throw new Error('OTP_DEV_ECHO must be enabled on the load-test server');
  const session = await call('POST', '/auth/otp/verify', {
    body: {
      phone,
      code: challenge.devCode,
      device: { id: `load-${index}`, platform: 'android', name: 'load' },
    },
    ip,
  });
  return { ...session, phone, ip };
}

const percentile = (sorted, p) =>
  sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))] ?? 0;

module.exports = { BASE, API, call, signIn, percentile };
