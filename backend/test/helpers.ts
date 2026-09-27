import { INestApplication } from '@nestjs/common';
import { Worker } from 'bullmq';
import sharp from 'sharp';
import { io, Socket } from 'socket.io-client';
import request from 'supertest';
import type { App } from 'supertest/types';

import { createApp } from '../src/bootstrap';
import { startWorkers } from '../src/worker';
import { RedisService } from '../src/infra/redis.service';
import { DevOtpSender } from '../src/modules/auth/otp-sender';

export interface TestContext {
  app: INestApplication;
  http: App;
  baseUrl: string;
  workers: Worker[];
}

export async function startTestApp(): Promise<TestContext> {
  const app = await createApp({ logger: false });
  await app.listen(0, '127.0.0.1');
  const address = app.getHttpServer().address() as { port: number };
  const workers = startWorkers(app);
  return { app, http: app.getHttpServer() as App, baseUrl: `http://127.0.0.1:${address.port}`, workers };
}

export async function stopTestApp(ctx: TestContext): Promise<void> {
  await Promise.allSettled(ctx.workers.map((w) => w.close()));
  await ctx.app.close();
}

/**
 * Suites share one Redis DB per run, so identities must be unique across
 * files: phones/IPs derive from the worker pid plus a counter.
 */
const suiteSeed = (process.pid * 7919 + Date.now()) % 900;
let counter = 0;

/** Each simulated device gets its own client IP (trust proxy is on). */
export const nextIp = () => {
  const n = suiteSeed * 1000 + counter++;
  return `10.${(n >> 16) & 255}.${(n >> 8) & 255}.${n & 255}`;
};

export const nextPhone = () =>
  `99890${String(suiteSeed).padStart(3, '0')}${String(counter++).padStart(4, '0')}`;

export interface TestUser {
  userId: string;
  phone: string;
  accessToken: string;
  refreshToken: string;
  sessionId: string;
  ip: string;
}

export async function signIn(
  http: App,
  phone = nextPhone(),
  deviceId = `device-${phone}`,
): Promise<TestUser> {
  const ip = nextIp();
  await request(http).post('/api/v1/auth/otp/request').set('X-Forwarded-For', ip).send({ phone }).expect(200);
  const code = DevOtpSender.outbox.get(phone);
  if (!code) throw new Error('OTP was not issued');
  const res = await request(http)
    .post('/api/v1/auth/otp/verify')
    .set('X-Forwarded-For', ip)
    .send({ phone, code, device: { id: deviceId, platform: 'android', name: 'Test device' } })
    .expect(200);
  const data = res.body.data as {
    accessToken: string;
    refreshToken: string;
    sessionId: string;
    userId: string;
  };
  return { ...data, phone, ip };
}

/** Authenticated request helpers bound to a user. */
export function as(http: App, user: TestUser) {
  const auth = (r: request.Test) =>
    r.set('Authorization', `Bearer ${user.accessToken}`).set('X-Forwarded-For', user.ip);
  return {
    get: (url: string) => auth(request(http).get(`/api/v1${url}`)),
    post: (url: string, body?: object) => auth(request(http).post(`/api/v1${url}`)).send(body ?? {}),
    put: (url: string, body?: object) => auth(request(http).put(`/api/v1${url}`)).send(body ?? {}),
    patch: (url: string, body?: object) => auth(request(http).patch(`/api/v1${url}`)).send(body ?? {}),
    delete: (url: string, body?: object) => auth(request(http).delete(`/api/v1${url}`)).send(body ?? {}),
    upload: (buffer: Buffer, purpose: string, filename = 'photo.jpg') =>
      auth(request(http).post('/api/v1/media')).field('purpose', purpose).attach('file', buffer, filename),
  };
}

export async function jpeg(width = 1600, height = 1200, color = { r: 200, g: 60, b: 40 }): Promise<Buffer> {
  return sharp({ create: { width, height, channels: 3, background: color } })
    .withMetadata({ exif: { IFD0: { Copyright: 'test', Artist: 'secret-gps-owner' } } })
    .jpeg()
    .toBuffer();
}

export async function waitFor<T>(
  probe: () => Promise<T | undefined | null | false>,
  timeoutMs = 15000,
  stepMs = 150,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await probe();
    if (value) return value;
    if (Date.now() > deadline) throw new Error('Timed out waiting for condition');
    await new Promise((resolve) => setTimeout(resolve, stepMs));
  }
}

/** Uploads a photo and waits until the worker produced renditions. */
export async function uploadReadyPhoto(http: App, user: TestUser, purpose = 'listing'): Promise<string> {
  const res = await as(http, user)
    .upload(await jpeg(), purpose)
    .expect(201);
  const id = res.body.data.id as string;
  await waitFor(async () => {
    const media = await as(http, user).get(`/media/${id}`).expect(200);
    if (media.body.data.status === 'failed') throw new Error('media failed');
    return media.body.data.status === 'ready';
  });
  return id;
}

export function connectSocket(baseUrl: string, token?: string): Socket {
  return io(`${baseUrl}/chat`, {
    path: '/socket.io',
    transports: ['websocket'],
    auth: token ? { token } : {},
    reconnection: false,
    forceNew: true,
  });
}

export function onceEvent<T>(socket: Socket, event: string, timeoutMs = 8000): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`No '${event}' within ${timeoutMs}ms`)), timeoutMs);
    socket.once(event, (payload: T) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

export function connected(socket: Socket): Promise<void> {
  return new Promise((resolve, reject) => {
    socket.once('connect', () => resolve());
    socket.once('connect_error', (error) => reject(error));
  });
}

export function emitAck<T>(socket: Socket, event: string, payload: unknown): Promise<T> {
  return socket.timeout(8000).emitWithAck(event, payload) as Promise<T>;
}

export const NAMANGAN_CHUST = { regionId: 'namangan', districtId: 'chust' };
export const TASHKENT_YUNUSOBOD = { regionId: 'tashkent_city', districtId: 'yunusobod' };

/** Lets a test sign the same phone in on another device without waiting for the resend cooldown. */
export async function clearOtpCooldown(ctx: TestContext, phone: string): Promise<void> {
  const redis = ctx.app.get(RedisService);
  const keys = await redis.client.keys(`otp:*${phone}*`);
  if (keys.length) await redis.client.del(...keys);
}
