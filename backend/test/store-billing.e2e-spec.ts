import { createPublicKey, verify } from 'node:crypto';
import { createServer, IncomingMessage, Server, ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

import request from 'supertest';

import { resetEnvCache } from '../src/config/env';
import { PrismaService } from '../src/infra/prisma.service';
import { fromB64url } from '../src/modules/monetization/providers/jws';
import { as, signIn, startTestApp, stopTestApp, TestContext, TestUser } from './helpers';
import { createApiKey, createApplePki, createServiceAccount } from './store-fixtures';
import { createListing, idem, makeAdmin, priceAndActivate, setFlags } from './monetization.helpers';

const pki = createApplePki();
const apiKey = createApiKey();
const google = createServiceAccount();

interface FakeServer {
  url: string;
  close: () => Promise<void>;
}

function listen(
  handler: (req: IncomingMessage, res: ServerResponse, body: string) => void,
): Promise<FakeServer> {
  const server: Server = createServer((req, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => handler(req, res, body));
  });
  return new Promise((resolve) =>
    server.listen(0, '127.0.0.1', () =>
      resolve({
        url: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
        close: () => new Promise((done) => server.close(() => done())),
      }),
    ),
  );
}

const json = (res: ServerResponse, status: number, body: unknown) => {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(body));
};

describe('Store billing: App Store and Google Play', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let admin: TestUser;
  let seller: TestUser;
  let listingId: string;
  let apple: FakeServer;
  let play: FakeServer;

  /** What the fake App Store knows: transactionId → signed info overrides. */
  const appleTransactions = new Map<string, Record<string, unknown>>();
  const appleAuthHeaders: string[] = [];
  /** What the fake Play Store knows: token → purchase resource. */
  const playPurchases = new Map<string, Record<string, unknown>>();
  const playAcks: string[] = [];
  const oauthAssertions: string[] = [];

  beforeAll(async () => {
    apple = await listen((req, res) => {
      appleAuthHeaders.push(req.headers.authorization ?? '');
      const id = req.url!.split('/').pop()!;
      const info = appleTransactions.get(id);
      if (!info) return json(res, 404, { errorCode: 4040010 });
      json(res, 200, {
        signedTransactionInfo: pki.signJws({ bundleId: 'uz.bozor.app', environment: 'Production', ...info }),
      });
    });
    play = await listen((req, res, body) => {
      const url = req.url!;
      if (url.startsWith('/token')) {
        const form = new URLSearchParams(body);
        oauthAssertions.push(form.get('assertion') ?? '');
        return json(res, 200, { access_token: 'play-access-token', expires_in: 3600 });
      }
      if (req.headers.authorization !== 'Bearer play-access-token') return json(res, 401, {});
      const token = decodeURIComponent(url.split('/tokens/')[1].split(':')[0].split('?')[0]);
      const purchase = playPurchases.get(token);
      if (!purchase) return json(res, 404, {});
      if (url.endsWith(':acknowledge')) {
        playAcks.push(token);
        purchase.acknowledgementState = 1;
        return json(res, 200, {});
      }
      json(res, 200, purchase);
    });
    Object.assign(process.env, {
      APPLE_BUNDLE_ID: 'uz.bozor.app',
      APPLE_ISSUER_ID: 'issuer-1234',
      APPLE_KEY_ID: 'KEYID12345',
      APPLE_PRIVATE_KEY: Buffer.from(apiKey.privatePem).toString('base64'),
      APPLE_ROOT_CA: Buffer.from(pki.rootPem).toString('base64'),
      APPLE_API_URL: apple.url,
      APPLE_ENVIRONMENT: 'production',
      GOOGLE_PACKAGE_NAME: 'uz.bozor.app',
      GOOGLE_SERVICE_ACCOUNT: Buffer.from(
        JSON.stringify({ ...JSON.parse(google.json), token_uri: `${play.url}/token` }),
      ).toString('base64'),
      GOOGLE_API_URL: play.url,
    });
    resetEnvCache();
    ctx = await startTestApp();
    prisma = ctx.app.get(PrismaService);
    admin = await makeAdmin(ctx);
    seller = await signIn(ctx.http);
    await setFlags(ctx.http, admin, { monetization: true, listingTop: true });
    await priceAndActivate(ctx.http, admin, 'listing_top_7d', 25_000);
    listingId = await createListing(ctx.http, seller);
    for (const [provider, storeProductId] of [
      ['APPLE', 'uz.bozor.top7'],
      ['GOOGLE', 'top7'],
    ]) {
      await as(ctx.http, admin)
        .put('/admin/monetization/store-products', { provider, storeProductId, productId: 'listing_top_7d' })
        .expect(200);
    }
  });

  afterAll(async () => {
    await stopTestApp(ctx);
    await apple.close();
    await play.close();
  });

  async function buy(provider: 'apple' | 'google', platform: 'ios' | 'android') {
    const res = await as(ctx.http, seller)
      .post('/checkout', {
        provider,
        platform,
        idempotencyKey: idem(),
        productId: 'listing_top_7d',
        targetId: listingId,
      })
      .expect(201);
    const purchaseId = res.body.data.id as string;
    const payment = await prisma.payment.findFirstOrThrow({ where: { purchaseId } });
    return {
      purchaseId,
      payment,
      action: res.body.data.action as { type: string; store: string; storeProductId: string },
    };
  }

  const receipt = (purchaseId: string, value: string) =>
    as(ctx.http, seller).post(`/me/purchases/${purchaseId}/store-receipt`, { receipt: value });
  const statusOf = async (id: string) => (await prisma.purchase.findUniqueOrThrow({ where: { id } })).status;

  describe('App Store', () => {
    it('hands the app the store product to buy', async () => {
      const { action } = await buy('apple', 'ios');
      expect(action).toEqual({ type: 'store', store: 'apple', storeProductId: 'uz.bozor.top7' });
    });

    it('activates only after Apple confirms the signed transaction', async () => {
      const { purchaseId, payment } = await buy('apple', 'ios');
      const transactionId = `2000${Date.now()}`;
      // Apple does not know the transaction yet.
      const unknown = await receipt(purchaseId, transactionId).expect(422);
      expect(unknown.body.error).toMatchObject({
        code: 'RECEIPT_INVALID',
        details: { reason: 'transaction_not_found' },
      });
      expect(await statusOf(purchaseId)).toBe('AWAITING_PAYMENT');

      appleTransactions.set(transactionId, {
        transactionId,
        productId: 'uz.bozor.top7',
        appAccountToken: payment.id,
      });
      const ok = await receipt(purchaseId, transactionId).expect(200);
      expect(ok.body.data.status).toBe('fulfilled');
      expect(await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).toMatchObject({
        status: 'SUCCEEDED',
        externalId: transactionId,
      });
      expect(await prisma.promotionActivation.count({ where: { purchaseId } })).toBe(1);

      // Re-sending is harmless.
      await receipt(purchaseId, transactionId).expect(200);
      expect(await prisma.promotionActivation.count({ where: { purchaseId } })).toBe(1);

      // The API call carried a valid ES256 JWT for our key.
      const [h, p, s] = appleAuthHeaders.at(-1)!.replace('Bearer ', '').split('.');
      expect(JSON.parse(fromB64url(h).toString())).toMatchObject({ alg: 'ES256', kid: 'KEYID12345' });
      expect(JSON.parse(fromB64url(p).toString())).toMatchObject({
        iss: 'issuer-1234',
        aud: 'appstoreconnect-v1',
        bid: 'uz.bozor.app',
      });
      expect(
        verify(
          'SHA256',
          Buffer.from(`${h}.${p}`),
          { key: createPublicKey(apiKey.publicPem), dsaEncoding: 'ieee-p1363' },
          fromB64url(s),
        ),
      ).toBe(true);
    });

    it.each([
      ['another app', { bundleId: 'com.evil.app' }, 'wrong_bundle'],
      ['another product', { productId: 'uz.bozor.vip30' }, 'wrong_product'],
      ['a revoked transaction', { revocationDate: Date.now() - 1000 }, 'revoked'],
      ['the sandbox environment', { environment: 'Sandbox' }, 'wrong_environment'],
      [
        'someone else’s payment',
        { appAccountToken: '00000000-0000-4000-8000-000000000000' },
        'account_mismatch',
      ],
      ['no account binding', { appAccountToken: undefined }, 'account_mismatch'],
    ])('rejects %s', async (_name, override, reason) => {
      const { purchaseId, payment } = await buy('apple', 'ios');
      const transactionId = `3000${Date.now()}${Math.floor(Math.random() * 1000)}`;
      appleTransactions.set(transactionId, {
        transactionId,
        productId: 'uz.bozor.top7',
        appAccountToken: payment.id,
        ...override,
      });
      const res = await receipt(purchaseId, transactionId).expect(422);
      expect(res.body.error.details.reason).toBe(reason);
      expect(await statusOf(purchaseId)).toBe('AWAITING_PAYMENT');
    });

    it('a transaction can only pay once, even if another purchase claims it', async () => {
      const first = await buy('apple', 'ios');
      const transactionId = `4000${Date.now()}`;
      appleTransactions.set(transactionId, {
        transactionId,
        productId: 'uz.bozor.top7',
        appAccountToken: first.payment.id,
      });
      await receipt(first.purchaseId, transactionId).expect(200);

      const second = await buy('apple', 'ios');
      appleTransactions.set(transactionId, {
        transactionId,
        productId: 'uz.bozor.top7',
        appAccountToken: second.payment.id,
      });
      await receipt(second.purchaseId, transactionId).expect(200); // accepted by the API…
      expect(await statusOf(second.purchaseId)).toBe('AWAITING_PAYMENT'); // …but it cannot fulfill twice
    });

    it('rejects malformed receipts and other users’ purchases', async () => {
      const { purchaseId } = await buy('apple', 'ios');
      await receipt(purchaseId, 'abcdefghijk').expect(422);
      const stranger = await signIn(ctx.http);
      await as(ctx.http, stranger)
        .post(`/me/purchases/${purchaseId}/store-receipt`, { receipt: '1234567890123' })
        .expect(404);
    });

    it('a signed REFUND notification flags the payment for review; forged ones are refused', async () => {
      const { purchaseId, payment } = await buy('apple', 'ios');
      const transactionId = `5000${Date.now()}`;
      appleTransactions.set(transactionId, {
        transactionId,
        productId: 'uz.bozor.top7',
        appAccountToken: payment.id,
      });
      await receipt(purchaseId, transactionId).expect(200);

      const notification = pki.signJws({
        notificationType: 'REFUND',
        notificationUUID: `n-${Date.now()}`,
        data: {
          bundleId: 'uz.bozor.app',
          signedTransactionInfo: pki.signJws({
            transactionId,
            bundleId: 'uz.bozor.app',
            productId: 'uz.bozor.top7',
          }),
        },
      });
      await request(ctx.http)
        .post('/api/v1/payments/webhooks/apple')
        .send({ signedPayload: notification })
        .expect(200);
      expect((await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).needsReview).toBe(true);

      const other = createApplePki();
      await request(ctx.http)
        .post('/api/v1/payments/webhooks/apple')
        .send({
          signedPayload: other.signJws({
            notificationType: 'REFUND',
            notificationUUID: 'x',
            data: { bundleId: 'uz.bozor.app' },
          }),
        })
        .expect(401);
    });
  });

  describe('Google Play', () => {
    const purchase = (payment: { id: string }, extra: Record<string, unknown> = {}) => ({
      purchaseState: 0,
      acknowledgementState: 0,
      consumptionState: 0,
      orderId: `GPA.${Date.now()}.${Math.floor(Math.random() * 1e6)}`,
      obfuscatedExternalAccountId: payment.id,
      ...extra,
    });

    it('hands the app the store product to buy', async () => {
      const { action } = await buy('google', 'android');
      expect(action).toEqual({ type: 'store', store: 'google', storeProductId: 'top7' });
    });

    it('verifies with Play, acknowledges, and activates', async () => {
      const { purchaseId, payment } = await buy('google', 'android');
      const token = `token-${Date.now()}-abcdefghij`;
      playPurchases.set(token, purchase(payment));
      const ok = await receipt(purchaseId, token).expect(200);
      expect(ok.body.data.status).toBe('fulfilled');
      expect(playAcks).toContain(token);
      expect(await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).toMatchObject({
        status: 'SUCCEEDED',
      });

      // The OAuth assertion is a valid RS256 JWT of the service account.
      const [h, p, s] = oauthAssertions.at(-1)!.split('.');
      expect(JSON.parse(fromB64url(p).toString())).toMatchObject({
        iss: 'billing@bozor-test.iam.gserviceaccount.com',
        scope: 'https://www.googleapis.com/auth/androidpublisher',
      });
      expect(
        verify('RSA-SHA256', Buffer.from(`${h}.${p}`), createPublicKey(google.publicPem), fromB64url(s)),
      ).toBe(true);
    });

    it.each([
      ['a pending purchase', { purchaseState: 2 }, 'pending'],
      ['a cancelled purchase', { purchaseState: 1 }, 'not_purchased'],
      [
        'someone else’s payment',
        { obfuscatedExternalAccountId: '00000000-0000-4000-8000-000000000000' },
        'account_mismatch',
      ],
      ['a purchase without account binding', { obfuscatedExternalAccountId: undefined }, 'account_mismatch'],
    ])('rejects %s', async (_name, override, reason) => {
      const { purchaseId, payment } = await buy('google', 'android');
      const token = `bad-${Date.now()}-${Math.floor(Math.random() * 1e6)}-xxxx`;
      playPurchases.set(token, purchase(payment, override));
      const res = await receipt(purchaseId, token).expect(422);
      expect(res.body.error.details.reason).toBe(reason);
      expect(await statusOf(purchaseId)).toBe('AWAITING_PAYMENT');
    });

    it('unknown tokens are rejected', async () => {
      const { purchaseId } = await buy('google', 'android');
      const res = await receipt(purchaseId, 'this-token-does-not-exist-1234').expect(422);
      expect(res.body.error.details.reason).toBe('purchase_not_found');
    });
  });

  it('admin store product mapping needs exactly one target and a real product', async () => {
    const put = (body: object) => as(ctx.http, admin).put('/admin/monetization/store-products', body);
    await put({ provider: 'APPLE', storeProductId: 'uz.bozor.x' }).expect(422);
    await put({ provider: 'APPLE', storeProductId: 'uz.bozor.x', productId: 'missing_product' }).expect(422);
    await as(ctx.http, seller)
      .put('/admin/monetization/store-products', {
        provider: 'APPLE',
        storeProductId: 'uz.bozor.x',
        productId: 'listing_top_7d',
      })
      .expect(403);
  });

  it('unmapped products are not sold in the store', async () => {
    await prisma.storeProduct.deleteMany({ where: { provider: 'APPLE' } });
    const res = await as(ctx.http, seller)
      .post('/checkout', {
        provider: 'apple',
        platform: 'ios',
        idempotencyKey: idem(),
        productId: 'listing_top_7d',
        targetId: listingId,
      })
      .expect(422);
    expect(res.body.error.code).toBe('PAYMENT_ROUTE_UNAVAILABLE');
  });
});
