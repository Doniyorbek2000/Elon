import { createHash } from 'node:crypto';

import request from 'supertest';

import { resetEnvCache } from '../src/config/env';
import { PrismaService } from '../src/infra/prisma.service';
import { as, startTestApp, stopTestApp, TestContext, TestUser, signIn } from './helpers';
import {
  createListing,
  idem,
  makeAdmin,
  paymentOf,
  priceAndActivate,
  setFlags,
} from './monetization.helpers';

// Provider credentials exist only for this suite; other suites rely on them being absent.
Object.assign(process.env, {
  CLICK_SERVICE_ID: '12345',
  CLICK_MERCHANT_ID: '67890',
  CLICK_SECRET_KEY: 'click_test_secret_key',
  PAYME_MERCHANT_ID: 'payme_test_merchant',
  PAYME_KEY: 'payme_test_key_0123456789',
});
resetEnvCache(); // imports above may already have read the environment

const CLICK = { serviceId: '12345', secret: 'click_test_secret_key' };
const md5 = (value: string) => createHash('md5').update(value).digest('hex');
const prepareIdOf = (paymentId: string) => parseInt(paymentId.replace(/-/g, '').slice(0, 12), 16);

describe('Monetization: Click and Payme adapters', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let seller: TestUser;
  let listingId: string;

  beforeAll(async () => {
    ctx = await startTestApp();
    prisma = ctx.app.get(PrismaService);
    const admin = await makeAdmin(ctx);
    seller = await signIn(ctx.http);
    await setFlags(ctx.http, admin, { monetization: true, listingTop: true });
    await priceAndActivate(ctx.http, admin, 'listing_top_7d', 25_000);
    listingId = await createListing(ctx.http, seller);
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  async function buy(provider: 'click' | 'payme') {
    const res = await as(ctx.http, seller)
      .post('/checkout', {
        provider,
        platform: 'web',
        idempotencyKey: idem(),
        productId: 'listing_top_7d',
        targetId: listingId,
      })
      .expect(201);
    const purchaseId = res.body.data.id as string;
    const payment = await paymentOf(ctx, purchaseId);
    return { purchaseId, payment, action: res.body.data.action as { type: string; url: string } };
  }

  const purchaseStatus = async (id: string) =>
    (await prisma.purchase.findUniqueOrThrow({ where: { id } })).status;

  // ─────────────────────────────────────────────────────── Click

  describe('Click', () => {
    const callback = (
      action: 0 | 1,
      fields: { paymentId: string; amount: string; clickTransId: string; prepareId?: number; error?: number },
      overrides: { sign?: string; serviceId?: string } = {},
    ) => {
      const signTime = '2026-09-30 10:00:00';
      const parts =
        action === 0
          ? [
              fields.clickTransId,
              CLICK.serviceId,
              CLICK.secret,
              fields.paymentId,
              fields.amount,
              '0',
              signTime,
            ]
          : [
              fields.clickTransId,
              CLICK.serviceId,
              CLICK.secret,
              fields.paymentId,
              String(fields.prepareId ?? ''),
              fields.amount,
              '1',
              signTime,
            ];
      const form = new URLSearchParams({
        click_trans_id: fields.clickTransId,
        service_id: overrides.serviceId ?? CLICK.serviceId,
        click_paydoc_id: '999',
        merchant_trans_id: fields.paymentId,
        ...(action === 1 ? { merchant_prepare_id: String(fields.prepareId ?? '') } : {}),
        amount: fields.amount,
        action: String(action),
        error: String(fields.error ?? 0),
        error_note: 'x',
        sign_time: signTime,
        sign_string: overrides.sign ?? md5(parts.join('')),
      });
      return request(ctx.http)
        .post('/api/v1/payments/webhooks/click')
        .type('form')
        .send(form.toString())
        .expect(200);
    };

    it('builds a hosted checkout link for the payment', async () => {
      const { payment, action } = await buy('click');
      expect(action.type).toBe('redirect');
      const url = new URL(action.url);
      expect(url.origin + url.pathname).toBe('https://my.click.uz/services/pay');
      expect(url.searchParams.get('service_id')).toBe('12345');
      expect(url.searchParams.get('merchant_id')).toBe('67890');
      expect(url.searchParams.get('transaction_param')).toBe(payment.id);
      expect(url.searchParams.get('amount')).toBe('25000.00');
    });

    it('answers protocol errors with HTTP 200 and Click error codes', async () => {
      const { payment } = await buy('click');
      const base = { paymentId: payment.id, amount: '25000.00', clickTransId: '1001' };
      expect((await callback(0, base, { sign: '0'.repeat(32) })).body.error).toBe(-1);
      expect((await callback(0, base, { serviceId: '999' })).body.error).toBe(-1);
      expect((await callback(0, { ...base, amount: '100.00' })).body.error).toBe(-2);
      expect(
        (await callback(0, { ...base, paymentId: '00000000-0000-4000-8000-000000000000' })).body.error,
      ).toBe(-5);
      // Complete without a matching prepare id.
      expect((await callback(1, { ...base, prepareId: 1 })).body.error).toBe(-6);
      expect(await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).toMatchObject({
        status: 'PENDING',
      });
    });

    it('prepare → complete fulfills exactly once', async () => {
      const { purchaseId, payment } = await buy('click');
      const base = { paymentId: payment.id, amount: '25000.00', clickTransId: '2002' };
      const prepare = await callback(0, base);
      expect(prepare.body).toMatchObject({
        error: 0,
        click_trans_id: 2002,
        merchant_trans_id: payment.id,
        merchant_prepare_id: prepareIdOf(payment.id),
      });
      expect(await purchaseStatus(purchaseId)).toBe('AWAITING_PAYMENT');

      const complete = await callback(1, { ...base, prepareId: prepareIdOf(payment.id) });
      expect(complete.body).toMatchObject({ error: 0, merchant_confirm_id: prepareIdOf(payment.id) });
      expect(await purchaseStatus(purchaseId)).toBe('FULFILLED');
      expect(await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).toMatchObject({
        status: 'SUCCEEDED',
        externalId: '2002',
      });

      // A retried complete is answered "already paid" and changes nothing.
      const again = await callback(1, { ...base, prepareId: prepareIdOf(payment.id) });
      expect(again.body.error).toBe(-4);
      expect(await prisma.promotionActivation.count({ where: { purchaseId } })).toBe(1);
    });

    it('a failed complete cancels the payment and never activates', async () => {
      const { purchaseId, payment } = await buy('click');
      const base = { paymentId: payment.id, amount: '25000.00', clickTransId: '3003' };
      await callback(0, base);
      const complete = await callback(1, { ...base, prepareId: prepareIdOf(payment.id), error: -5017 });
      expect(complete.body.error).toBe(-9);
      expect(await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).toMatchObject({
        status: 'FAILED',
        failureCode: 'click_-5017',
      });
      expect(await purchaseStatus(purchaseId)).toBe('FAILED');
      expect((await callback(0, base)).body.error).toBe(-9);
    });
  });

  // ─────────────────────────────────────────────────────── Payme

  describe('Payme', () => {
    const auth = `Basic ${Buffer.from('Paycom:payme_test_key_0123456789').toString('base64')}`;
    let rpcId = 0;
    const rpc = (method: string, params: Record<string, unknown>, authorization: string | null = auth) => {
      const req = request(ctx.http).post('/api/v1/payments/webhooks/payme');
      if (authorization) req.set('Authorization', authorization);
      return req
        .send({ jsonrpc: '2.0', id: ++rpcId, method, params })
        .expect(200)
        .then(
          (res) =>
            res.body as { id: number; result?: Record<string, number | string>; error?: { code: number } },
        );
    };
    const account = (paymentId: string) => ({ order_id: paymentId });
    const txId = () => `payme${Date.now()}${rpcId++}`.padEnd(24, '0');

    it('builds the base64 checkout link', async () => {
      const { payment, action } = await buy('payme');
      const url = new URL(action.url);
      expect(url.origin).toBe('https://checkout.paycom.uz');
      const decoded = Buffer.from(url.pathname.slice(1), 'base64').toString();
      expect(decoded).toContain('m=payme_test_merchant');
      expect(decoded).toContain(`ac.order_id=${payment.id}`);
      expect(decoded).toContain('a=2500000');
    });

    it('rejects missing or wrong credentials', async () => {
      const { payment } = await buy('payme');
      const params = { amount: 2_500_000, account: account(payment.id) };
      expect((await rpc('CheckPerformTransaction', params, null)).error?.code).toBe(-32504);
      const wrong = `Basic ${Buffer.from('Paycom:nope').toString('base64')}`;
      expect((await rpc('CheckPerformTransaction', params, wrong)).error?.code).toBe(-32504);
      expect((await rpc('Unknown', {})).error?.code).toBe(-32601);
    });

    it('validates order and amount', async () => {
      const { payment } = await buy('payme');
      expect(
        (await rpc('CheckPerformTransaction', { amount: 100, account: account(payment.id) })).error?.code,
      ).toBe(-31001);
      expect(
        (
          await rpc('CheckPerformTransaction', {
            amount: 2_500_000,
            account: account('00000000-0000-4000-8000-000000000000'),
          })
        ).error?.code,
      ).toBe(-31050);
      expect((await rpc('CheckPerformTransaction', { amount: 2_500_000, account: {} })).error?.code).toBe(
        -31050,
      );
      const ok = await rpc('CheckPerformTransaction', { amount: 2_500_000, account: account(payment.id) });
      expect(ok.result).toEqual({ allow: true });
    });

    it('create → perform fulfills once; a performed transaction cannot be cancelled', async () => {
      const { purchaseId, payment } = await buy('payme');
      const id = txId();
      const params = { id, time: Date.now(), amount: 2_500_000, account: account(payment.id) };

      const created = await rpc('CreateTransaction', params);
      expect(created.result).toMatchObject({ state: 1, transaction: id });
      // Idempotent create, but a second concurrent transaction for the same order is refused.
      expect((await rpc('CreateTransaction', params)).result?.create_time).toBe(created.result?.create_time);
      expect((await rpc('CreateTransaction', { ...params, id: txId() })).error?.code).toBe(-31099);
      expect(await purchaseStatus(purchaseId)).toBe('AWAITING_PAYMENT');

      const performed = await rpc('PerformTransaction', { id });
      expect(performed.result).toMatchObject({ state: 2, transaction: id });
      expect(Number(performed.result?.perform_time)).toBeGreaterThan(0);
      expect(await purchaseStatus(purchaseId)).toBe('FULFILLED');
      const again = await rpc('PerformTransaction', { id });
      expect(again.result?.perform_time).toBe(performed.result?.perform_time);
      expect(await prisma.promotionActivation.count({ where: { purchaseId } })).toBe(1);

      expect((await rpc('CancelTransaction', { id, reason: 5 })).error?.code).toBe(-31007);
      expect((await rpc('CheckTransaction', { id })).result).toMatchObject({ state: 2, cancel_time: 0 });
      // Paid orders are no longer payable.
      expect((await rpc('CheckPerformTransaction', params)).error?.code).toBe(-31051);
    });

    it('cancelling before perform cancels the payment; statement lists transactions', async () => {
      const { purchaseId, payment } = await buy('payme');
      const id = txId();
      const from = Date.now() - 1000;
      await rpc('CreateTransaction', {
        id,
        time: Date.now(),
        amount: 2_500_000,
        account: account(payment.id),
      });
      const cancelled = await rpc('CancelTransaction', { id, reason: 3 });
      expect(cancelled.result).toMatchObject({ state: -1, transaction: id });
      expect((await rpc('CancelTransaction', { id, reason: 3 })).result?.cancel_time).toBe(
        cancelled.result?.cancel_time,
      );
      expect((await rpc('PerformTransaction', { id })).error?.code).toBe(-31008);
      expect(await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).toMatchObject({
        status: 'CANCELLED',
      });
      expect(await purchaseStatus(purchaseId)).toBe('CANCELLED');

      const statement = await rpc('GetStatement', { from, to: Date.now() + 1000 });
      const list = (statement.result as unknown as { transactions: { id: string; state: number }[] })
        .transactions;
      expect(list.find((t) => t.id === id)).toMatchObject({ state: -1 });
      expect((await rpc('CheckTransaction', { id: 'missing' })).error?.code).toBe(-31003);
    });

    it('a timed-out transaction is closed but the order stays payable', async () => {
      const { purchaseId, payment } = await buy('payme');
      const id = txId();
      await rpc('CreateTransaction', {
        id,
        time: Date.now(),
        amount: 2_500_000,
        account: account(payment.id),
      });
      await prisma.paymeTransaction.update({
        where: { id },
        data: { createTime: BigInt(Date.now() - 13 * 3600 * 1000) },
      });
      expect((await rpc('PerformTransaction', { id })).error?.code).toBe(-31008);
      expect(await prisma.paymeTransaction.findUniqueOrThrow({ where: { id } })).toMatchObject({
        state: -1,
        reason: 4,
      });
      expect(await purchaseStatus(purchaseId)).toBe('AWAITING_PAYMENT');

      // A fresh transaction for the same order succeeds.
      const next = txId();
      await rpc('CreateTransaction', {
        id: next,
        time: Date.now(),
        amount: 2_500_000,
        account: account(payment.id),
      });
      expect((await rpc('PerformTransaction', { id: next })).result?.state).toBe(2);
      expect(await purchaseStatus(purchaseId)).toBe('FULFILLED');
    });
  });
});
