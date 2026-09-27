import request from 'supertest';

import { DevOtpSender } from '../src/modules/auth/otp-sender';
import {
  as,
  clearOtpCooldown,
  connectSocket,
  nextIp,
  nextPhone,
  signIn,
  startTestApp,
  stopTestApp,
  TestContext,
} from './helpers';

describe('Auth (phone OTP, sessions, refresh rotation)', () => {
  let ctx: TestContext;

  beforeAll(async () => {
    ctx = await startTestApp();
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  it('normalizes phone formats and never echoes the code outside development', async () => {
    const ip = nextIp();
    const res = await request(ctx.http)
      .post('/api/v1/auth/otp/request')
      .set('X-Forwarded-For', ip)
      .send({ phone: '+998 (90) 555-44-33' })
      .expect(200);
    expect(res.body.data).toEqual(expect.objectContaining({ expiresInSeconds: 300, resendInSeconds: 60 }));
    expect(res.body.data.devCode).toBeUndefined();
    expect(DevOtpSender.outbox.get('998905554433')).toMatch(/^\d{6}$/);
  });

  it('rejects invalid phone numbers with 422', async () => {
    const res = await request(ctx.http)
      .post('/api/v1/auth/otp/request')
      .set('X-Forwarded-For', nextIp())
      .send({ phone: '12345' })
      .expect(422);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
    expect(res.body.error.requestId).toBeTruthy();
  });

  it('enforces resend cooldown with 429 + retryAfter', async () => {
    const phone = nextPhone();
    const ip = nextIp();
    await request(ctx.http)
      .post('/api/v1/auth/otp/request')
      .set('X-Forwarded-For', ip)
      .send({ phone })
      .expect(200);
    const res = await request(ctx.http)
      .post('/api/v1/auth/otp/request')
      .set('X-Forwarded-For', ip)
      .send({ phone })
      .expect(429);
    expect(res.body.error.code).toBe('OTP_COOLDOWN');
    expect(res.body.error.details.retryAfterSeconds).toBeGreaterThan(0);
  });

  it('locks the challenge after too many wrong codes', async () => {
    const phone = nextPhone();
    const ip = nextIp();
    await request(ctx.http)
      .post('/api/v1/auth/otp/request')
      .set('X-Forwarded-For', ip)
      .send({ phone })
      .expect(200);
    const real = DevOtpSender.outbox.get(phone)!;
    const wrong = real === '000000' ? '111111' : '000000';
    const device = { id: 'device-lockout', platform: 'ios' };
    for (let i = 0; i < 4; i++) {
      const res = await request(ctx.http)
        .post('/api/v1/auth/otp/verify')
        .set('X-Forwarded-For', ip)
        .send({ phone, code: wrong, device })
        .expect(422);
      expect(res.body.error.code).toBe('OTP_INVALID');
    }
    const fifth = await request(ctx.http)
      .post('/api/v1/auth/otp/verify')
      .set('X-Forwarded-For', ip)
      .send({ phone, code: wrong, device });
    expect([422, 429]).toContain(fifth.status);
    // Even the correct code no longer works once attempts are exhausted.
    const after = await request(ctx.http)
      .post('/api/v1/auth/otp/verify')
      .set('X-Forwarded-For', ip)
      .send({ phone, code: real, device });
    expect(after.status).not.toBe(200);
  });

  it('signs in, rotates refresh tokens and detects reuse', async () => {
    const user = await signIn(ctx.http);
    const me = await as(ctx.http, user).get('/me').expect(200);
    expect(me.body.data.id).toBe(user.userId);
    expect(me.body.data.verification).not.toBe('business'); // no fake verification

    const rotated = await request(ctx.http)
      .post('/api/v1/auth/refresh')
      .set('X-Forwarded-For', user.ip)
      .send({ refreshToken: user.refreshToken })
      .expect(200);
    expect(rotated.body.data.refreshToken).not.toBe(user.refreshToken);

    // Replaying the old token is treated as theft: the whole session is revoked.
    const replay = await request(ctx.http)
      .post('/api/v1/auth/refresh')
      .set('X-Forwarded-For', user.ip)
      .send({ refreshToken: user.refreshToken })
      .expect(401);
    expect(replay.body.error.code).toBe('SESSION_REVOKED');
    await request(ctx.http)
      .post('/api/v1/auth/refresh')
      .set('X-Forwarded-For', user.ip)
      .send({ refreshToken: rotated.body.data.refreshToken })
      .expect(401);
    await request(ctx.http)
      .get('/api/v1/me')
      .set('Authorization', `Bearer ${rotated.body.data.accessToken}`)
      .expect(401);
  });

  it('logout revokes the current session only; logout-all revokes every device', async () => {
    const phone = nextPhone();
    const phoneA = await signIn(ctx.http, phone, 'device-a-123');
    // Second device on the same account (test clears the per-phone resend cooldown).
    const tabletRes = await signInAfterCooldown(phone, 'device-b-456');
    const sessions = await as(ctx.http, phoneA).get('/auth/sessions').expect(200);
    expect(sessions.body.data).toHaveLength(2);

    await as(ctx.http, phoneA).post('/auth/logout').expect(200);
    await as(ctx.http, phoneA).get('/me').expect(401);
    await as(ctx.http, tabletRes).get('/me').expect(200);

    const third = await signInAfterCooldown(phone, 'device-c-789');
    const res = await as(ctx.http, third).post('/auth/logout-all').expect(200);
    expect(res.body.data.revokedSessions).toBe(2);
    await as(ctx.http, tabletRes).get('/me').expect(401);
  });

  it('rejects unauthenticated sockets and sockets with revoked sessions', async () => {
    const anonymous = connectSocket(ctx.baseUrl);
    const error = await new Promise<Error>((resolve) => anonymous.once('connect_error', resolve));
    expect(error.message).toBe('UNAUTHENTICATED');
    anonymous.close();

    const user = await signIn(ctx.http);
    await as(ctx.http, user).post('/auth/logout').expect(200);
    const revoked = connectSocket(ctx.baseUrl, user.accessToken);
    const revokedError = await new Promise<Error>((resolve) => revoked.once('connect_error', resolve));
    expect(revokedError.message).toBe('SESSION_REVOKED');
    revoked.close();
  });

  async function signInAfterCooldown(phone: string, deviceId: string) {
    await clearOtpCooldown(ctx, phone);
    return signIn(ctx.http, phone, deviceId);
  }
});
