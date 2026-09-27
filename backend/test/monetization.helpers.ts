import request from 'supertest';
import type { App } from 'supertest/types';

import { PrismaService } from '../src/infra/prisma.service';
import { DevPaymentProvider } from '../src/modules/monetization/providers/dev.provider';
import { runMonetizationTick } from '../src/worker';
import { as, NAMANGAN_CHUST, signIn, TestContext, TestUser, uploadReadyPhoto } from './helpers';

let keyCounter = 0;
export const idem = () => `idem_${process.pid}_${Date.now()}_${keyCounter++}`;

export async function makeAdmin(ctx: TestContext, role: 'ADMIN' | 'FINANCE' = 'ADMIN'): Promise<TestUser> {
  const user = await signIn(ctx.http);
  await ctx.app.get(PrismaService).user.update({ where: { id: user.userId }, data: { role } });
  return user;
}

export async function setFlags(http: App, admin: TestUser, flags: Record<string, boolean>) {
  for (const [key, enabled] of Object.entries(flags)) {
    await as(http, admin).put(`/admin/monetization/flags/${key}`, { enabled }).expect(200);
  }
}

/** Price in whole so'm → minor units string. */
export const soum = (amount: number) => (BigInt(amount) * 100n).toString();

export async function priceAndActivate(http: App, admin: TestUser, productId: string, amount: number) {
  await as(http, admin)
    .post(`/admin/monetization/products/${productId}/prices`, { amountMinor: soum(amount), currency: 'uzs' })
    .expect(201);
  await as(http, admin).patch(`/admin/monetization/products/${productId}`, { active: true }).expect(200);
}

export async function createListing(http: App, user: TestUser, title = 'Samsung Galaxy S23 256GB') {
  const photo = await uploadReadyPhoto(http, user);
  const res = await as(http, user)
    .post('/listings', {
      categoryId: 'phones',
      title,
      description: 'Holati yaxshi, qutisi va hujjatlari bilan birga.',
      price: { amount: 7_000_000, currency: 'uzs' },
      condition: 'used',
      attributes: { brand: 'Samsung' },
      place: NAMANGAN_CHUST,
      mediaIds: [photo],
    })
    .expect(201);
  return res.body.data.id as string;
}

/** Sends a correctly signed dev-provider webhook (like the provider would). */
export function devWebhook(
  http: App,
  body: { eventId: string; paymentId: string; externalId?: string; status: string; amountMinor: string },
  options: { secret?: string; timestamp?: number } = {},
) {
  const raw = JSON.stringify({ externalId: `dev_${body.paymentId}`, ...body });
  const timestamp = String(options.timestamp ?? Math.floor(Date.now() / 1000));
  const signature = DevPaymentProvider.sign(
    options.secret ?? process.env.PAYMENT_DEV_SECRET!,
    timestamp,
    raw,
  );
  return request(http)
    .post('/api/v1/payments/webhooks/dev')
    .set('Content-Type', 'application/json')
    .set('x-dev-signature', signature)
    .set('x-dev-timestamp', timestamp)
    .send(raw);
}

export async function paymentOf(ctx: TestContext, purchaseId: string) {
  return ctx.app
    .get(PrismaService)
    .payment.findFirstOrThrow({ where: { purchaseId }, orderBy: { createdAt: 'desc' } });
}

/** Checkout + signed success webhook; returns the purchase id. */
export async function buy(ctx: TestContext, user: TestUser, body: Record<string, unknown>) {
  const res = await as(ctx.http, user)
    .post('/checkout', { provider: 'dev', platform: 'web', idempotencyKey: idem(), ...body })
    .expect(201);
  const purchaseId = res.body.data.id as string;
  const payment = await paymentOf(ctx, purchaseId);
  await devWebhook(ctx.http, {
    eventId: `evt_${payment.id}_ok`,
    paymentId: payment.id,
    status: 'succeeded',
    amountMinor: payment.amountMinor.toString(),
  }).expect(200);
  return purchaseId;
}

export const tick = (ctx: TestContext, now?: Date) => runMonetizationTick(ctx.app, now);
