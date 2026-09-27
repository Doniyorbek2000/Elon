import request from 'supertest';

import { PrismaService } from '../src/infra/prisma.service';
import { PaymentProviderRegistry } from '../src/modules/monetization/providers/providers.registry';
import { DevPaymentProvider } from '../src/modules/monetization/providers/dev.provider';
import { as, signIn, startTestApp, stopTestApp, TestContext, TestUser } from './helpers';
import {
  buy,
  createListing,
  devWebhook,
  idem,
  makeAdmin,
  paymentOf,
  priceAndActivate,
  setFlags,
  soum,
  tick,
} from './monetization.helpers';

describe('Monetization: promotions, payments, webhooks, coupons, credits, refunds', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let admin: TestUser;
  let finance: TestUser;
  let seller: TestUser;
  let stranger: TestUser;
  let listingId: string;

  beforeAll(async () => {
    ctx = await startTestApp();
    prisma = ctx.app.get(PrismaService);
    [admin, finance, seller, stranger] = await Promise.all([
      makeAdmin(ctx),
      makeAdmin(ctx, 'FINANCE'),
      signIn(ctx.http),
      signIn(ctx.http),
    ]);
    listingId = await createListing(ctx.http, seller);
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  const checkout = (user: TestUser, body: Record<string, unknown>) =>
    as(ctx.http, user).post('/checkout', {
      provider: 'dev',
      platform: 'web',
      idempotencyKey: idem(),
      ...body,
    });

  it('launches free: everything commercial is off and nothing can be bought', async () => {
    const config = await request(ctx.http).get('/api/v1/config').expect(200);
    expect(Object.values(config.body.data.flags).every((v) => v === false)).toBe(true);
    expect(config.body.data.freePlan.activeListingLimit).toBe(50);
    const catalog = await as(ctx.http, seller)
      .get(`/catalog/promotions?target=listing&targetId=${listingId}&platform=web`)
      .expect(200);
    expect(catalog.body.data.products).toEqual([]);
    const res = await checkout(seller, { productId: 'listing_top_7d', targetId: listingId }).expect(403);
    expect(res.body.error.code).toBe('FEATURE_DISABLED');
    // Regular users cannot reach admin controls.
    await as(ctx.http, seller).put('/admin/monetization/flags/monetization', { enabled: true }).expect(403);
  });

  it('flow G: admin sets prices and flags; clients receive them without a release', async () => {
    await setFlags(ctx.http, admin, {
      monetization: true,
      listingTop: true,
      listingVip: true,
      listingBump: true,
      coupons: true,
      promotionCredits: true,
    });
    // A product cannot be activated without a price.
    await as(ctx.http, admin)
      .patch('/admin/monetization/products/listing_top_7d', { active: true })
      .expect(409);
    await priceAndActivate(ctx.http, admin, 'listing_top_7d', 25_000);
    await priceAndActivate(ctx.http, admin, 'listing_top_1d', 6_000);
    await priceAndActivate(ctx.http, admin, 'listing_vip_7d', 50_000);
    await priceAndActivate(ctx.http, admin, 'listing_bump', 5_000);
    // Fractional so'm is rejected (no floats anywhere).
    await as(ctx.http, admin)
      .post('/admin/monetization/products/listing_top_7d/prices', { amountMinor: '2500050', currency: 'uzs' })
      .expect(422);

    let catalog = await as(ctx.http, seller)
      .get(`/catalog/promotions?target=listing&targetId=${listingId}&platform=web`)
      .expect(200);
    const top = catalog.body.data.products.find((p: { id: string }) => p.id === 'listing_top_7d');
    expect(top.price).toEqual({ amountMinor: soum(25_000), amount: 25_000, currency: 'uzs' });
    expect(catalog.body.data.providers).toContain('dev');

    // Future price change is scheduled, not applied early; an immediate change is picked up.
    const tomorrow = new Date(Date.now() + 86400_000).toISOString();
    await as(ctx.http, admin)
      .post('/admin/monetization/products/listing_top_7d/prices', {
        amountMinor: soum(99_000),
        currency: 'uzs',
        validFrom: tomorrow,
      })
      .expect(201);
    await as(ctx.http, admin)
      .post('/admin/monetization/products/listing_top_7d/prices', {
        amountMinor: soum(30_000),
        currency: 'uzs',
      })
      .expect(201);
    catalog = await as(ctx.http, seller)
      .get(`/catalog/promotions?target=listing&targetId=${listingId}&platform=web`)
      .expect(200);
    expect(
      catalog.body.data.products.find((p: { id: string }) => p.id === 'listing_top_7d').price.amount,
    ).toBe(30_000);
    const audit = await prisma.adminAuditLog.count({
      where: { actorId: admin.userId, action: 'product.price' },
    });
    expect(audit).toBeGreaterThanOrEqual(6);
  });

  it('rejects client-side price or status manipulation and foreign targets', async () => {
    const cheap = await checkout(seller, {
      productId: 'listing_top_7d',
      targetId: listingId,
      amountMinor: '100',
    }).expect(422);
    expect(cheap.body.error.code).toBe('VALIDATION_FAILED');
    await checkout(seller, { productId: 'listing_top_7d', targetId: listingId, price: { amount: 1 } }).expect(
      422,
    );
    await checkout(seller, {
      productId: 'listing_top_7d',
      targetId: listingId,
      paymentStatus: 'SUCCESS',
    }).expect(422);
    await checkout(seller, {
      productId: 'listing_top_7d',
      targetId: listingId,
      userId: stranger.userId,
    }).expect(422);
    // Someone else's listing: indistinguishable from a missing one.
    await checkout(stranger, { productId: 'listing_top_7d', targetId: listingId }).expect(404);
    // Inactive or unknown products are not sellable.
    await checkout(seller, { productId: 'listing_vip_30d', targetId: listingId }).expect(422);
    // In-app purchases route to store billing, which is not configured.
    const ios = await checkout(seller, {
      productId: 'listing_top_7d',
      targetId: listingId,
      provider: 'apple',
      platform: 'ios',
    }).expect(503);
    expect(ios.body.error.code).toBe('PROVIDER_NOT_CONFIGURED');
    await checkout(seller, { productId: 'listing_top_7d', targetId: listingId, provider: 'payme' }).expect(
      503,
    );
    // The client cannot "settle" a paid product as free.
    await checkout(seller, { productId: 'listing_top_7d', targetId: listingId, provider: 'free' }).expect(
      422,
    );
  });

  it('flow A: TOP → server payment → verified webhook → active, visible, then expires', async () => {
    const res = await checkout(seller, { productId: 'listing_top_7d', targetId: listingId }).expect(201);
    const purchaseId = res.body.data.id;
    expect(res.body.data.status).toBe('awaitingPayment');
    expect(res.body.data.total.amount).toBe(30_000); // server price, not client input
    expect(res.body.data.action.type).toBe('redirect');
    expect(res.body.data.action.url).toContain('/payments/dev/checkout/');

    // Not active before verification.
    let detail = await as(ctx.http, stranger).get(`/listings/${listingId}`).expect(200);
    expect(detail.body.data.badges).toEqual([]);
    const beforePromoted = await request(ctx.http)
      .get('/api/v1/listings/promoted?region=namangan')
      .expect(200);
    expect(beforePromoted.body.data.map((l: { id: string }) => l.id)).not.toContain(listingId);

    const payment = await paymentOf(ctx, purchaseId);
    await devWebhook(ctx.http, {
      eventId: `evt_${payment.id}_1`,
      paymentId: payment.id,
      status: 'succeeded',
      amountMinor: payment.amountMinor.toString(),
    }).expect(200);

    const done = await as(ctx.http, seller).get(`/me/purchases/${purchaseId}`).expect(200);
    expect(done.body.data.status).toBe('fulfilled');
    expect(done.body.data.payments[0].status).toBe('succeeded');
    expect(
      new Date(done.body.data.activation.expiresAt).getTime() -
        new Date(done.body.data.activation.startsAt).getTime(),
    ).toBe(7 * 86400_000);

    detail = await as(ctx.http, stranger).get(`/listings/${listingId}`).expect(200);
    expect(detail.body.data.badges).toEqual(['top']);
    expect(detail.body.data.promotion).toBe('top');
    const promoted = await request(ctx.http)
      .get('/api/v1/listings/promoted?region=namangan&district=chust')
      .expect(200);
    expect(promoted.body.data.map((l: { id: string }) => l.id)).toContain(listingId);
    // Other filters are respected: not shown for another region.
    const elsewhere = await request(ctx.http)
      .get('/api/v1/listings/promoted?region=tashkent_city')
      .expect(200);
    expect(elsewhere.body.data).toEqual([]);

    const inbox = await as(ctx.http, seller).get('/notifications').expect(200);
    expect(inbox.body.data.some((n: { type: string }) => n.type === 'promotion')).toBe(true);

    // Expiry: a paid window that ended stops ranking even before the worker runs…
    const activation = await prisma.promotionActivation.findUniqueOrThrow({ where: { purchaseId } });
    const past = new Date(Date.now() - 1000);
    await prisma.promotionActivation.update({ where: { id: activation.id }, data: { expiresAt: past } });
    await prisma.listing.update({ where: { id: listingId }, data: { boostUntil: past } });
    const afterExpiry = await request(ctx.http).get('/api/v1/listings/promoted?region=namangan').expect(200);
    expect(afterExpiry.body.data.map((l: { id: string }) => l.id)).not.toContain(listingId);
    // …and the worker marks it expired and clears the cache.
    const result = await tick(ctx);
    expect(result.promotions.expired).toBeGreaterThanOrEqual(1);
    expect(
      (await prisma.promotionActivation.findUniqueOrThrow({ where: { id: activation.id } })).status,
    ).toBe('EXPIRED');
    expect((await prisma.listing.findUniqueOrThrow({ where: { id: listingId } })).boostTier).toBe(0);
    detail = await as(ctx.http, stranger).get(`/listings/${listingId}`).expect(200);
    expect(detail.body.data.badges).toEqual([]);
  });

  it('flow B: failed and cancelled payments activate nothing', async () => {
    const failed = await checkout(seller, { productId: 'listing_top_1d', targetId: listingId }).expect(201);
    const payment = await paymentOf(ctx, failed.body.data.id);
    await devWebhook(ctx.http, {
      eventId: `evt_${payment.id}_f`,
      paymentId: payment.id,
      status: 'failed',
      amountMinor: payment.amountMinor.toString(),
    }).expect(200);
    const detail = await as(ctx.http, seller).get(`/me/purchases/${failed.body.data.id}`).expect(200);
    expect(detail.body.data.status).toBe('failed');
    expect(detail.body.data.activation).toBeNull();
    expect(await prisma.promotionActivation.count({ where: { purchaseId: failed.body.data.id } })).toBe(0);

    const cancelled = await checkout(seller, { productId: 'listing_top_1d', targetId: listingId }).expect(
      201,
    );
    await as(ctx.http, seller).post(`/me/purchases/${cancelled.body.data.id}/cancel`).expect(200);
    await as(ctx.http, stranger).post(`/me/purchases/${cancelled.body.data.id}/cancel`).expect(404);
    await as(ctx.http, stranger).get(`/me/purchases/${cancelled.body.data.id}`).expect(404); // no cross-user payment data
    expect((await as(ctx.http, seller).get(`/me/purchases/${cancelled.body.data.id}`)).body.data.status).toBe(
      'cancelled',
    );
  });

  it('flow C: duplicate, replayed, forged and mismatched webhooks never double-activate', async () => {
    const res = await checkout(seller, { productId: 'listing_top_1d', targetId: listingId }).expect(201);
    const purchaseId = res.body.data.id;
    const payment = await paymentOf(ctx, purchaseId);
    const body = {
      eventId: `evt_${payment.id}_dup`,
      paymentId: payment.id,
      status: 'succeeded',
      amountMinor: payment.amountMinor.toString(),
    };

    // Forged signature, stale timestamp (replay window) → rejected.
    const forged = await devWebhook(ctx.http, body, { secret: 'x'.repeat(64) }).expect(401);
    expect(forged.body.error.code).toBe('SIGNATURE_INVALID');
    await devWebhook(ctx.http, body, { timestamp: Math.floor(Date.now() / 1000) - 3600 }).expect(401);
    await request(ctx.http)
      .post('/api/v1/payments/webhooks/dev')
      .set('Content-Type', 'application/json')
      .send(JSON.stringify(body))
      .expect(401);
    expect(await prisma.promotionActivation.count({ where: { purchaseId } })).toBe(0);

    await devWebhook(ctx.http, body).expect(200);
    await devWebhook(ctx.http, body).expect(200); // same event id (replay)
    await devWebhook(ctx.http, { ...body, eventId: `${body.eventId}_retry` }).expect(200); // provider retry with a new id
    expect(await prisma.promotionActivation.count({ where: { purchaseId } })).toBe(1);
    const events = await prisma.paymentEvent.findMany({
      where: { paymentId: payment.id },
      orderBy: { receivedAt: 'asc' },
    });
    expect(events.map((e) => e.outcome)).toEqual(['applied', 'ignored:already_succeeded']);

    // Out-of-order failure after success is ignored.
    await devWebhook(ctx.http, { ...body, eventId: `${body.eventId}_late_fail`, status: 'failed' }).expect(
      200,
    );
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).status).toBe('SUCCEEDED');

    // Concurrent duplicate deliveries of one event: still exactly one activation.
    const other = await checkout(seller, { productId: 'listing_top_1d', targetId: listingId }).expect(201);
    const p2 = await paymentOf(ctx, other.body.data.id);
    const b2 = {
      eventId: `evt_${p2.id}_race`,
      paymentId: p2.id,
      status: 'succeeded',
      amountMinor: p2.amountMinor.toString(),
    };
    await Promise.all([
      devWebhook(ctx.http, b2),
      devWebhook(ctx.http, b2),
      devWebhook(ctx.http, { ...b2, eventId: `${b2.eventId}_x` }),
    ]);
    expect(await prisma.promotionActivation.count({ where: { purchaseId: other.body.data.id } })).toBe(1);

    // Amount mismatch: never fulfilled, flagged for review.
    const third = await checkout(seller, { productId: 'listing_top_1d', targetId: listingId }).expect(201);
    const p3 = await paymentOf(ctx, third.body.data.id);
    await devWebhook(ctx.http, {
      eventId: `evt_${p3.id}_amt`,
      paymentId: p3.id,
      status: 'succeeded',
      amountMinor: '100',
    }).expect(200);
    const p3After = await prisma.payment.findUniqueOrThrow({ where: { id: p3.id } });
    expect(p3After.status).toBe('PENDING');
    expect(p3After.needsReview).toBe(true);
    expect(await prisma.promotionActivation.count({ where: { purchaseId: third.body.data.id } })).toBe(0);
  });

  it('late success after the user cancelled is honoured and flagged for review', async () => {
    const res = await checkout(seller, { productId: 'listing_top_1d', targetId: listingId }).expect(201);
    await as(ctx.http, seller).post(`/me/purchases/${res.body.data.id}/cancel`).expect(200);
    const payment = await paymentOf(ctx, res.body.data.id);
    await devWebhook(ctx.http, {
      eventId: `evt_${payment.id}_late`,
      paymentId: payment.id,
      status: 'succeeded',
      amountMinor: payment.amountMinor.toString(),
    }).expect(200);
    const after = await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
    expect(after.status).toBe('SUCCEEDED');
    expect(after.needsReview).toBe(true);
    expect((await prisma.purchase.findUniqueOrThrow({ where: { id: res.body.data.id } })).status).toBe(
      'FULFILLED',
    );
  });

  it('idempotency keys return the same purchase and cannot be reused for another product', async () => {
    const key = idem();
    const first = await as(ctx.http, seller)
      .post('/checkout', {
        productId: 'listing_top_1d',
        targetId: listingId,
        provider: 'dev',
        platform: 'web',
        idempotencyKey: key,
      })
      .expect(201);
    const again = await as(ctx.http, seller)
      .post('/checkout', {
        productId: 'listing_top_1d',
        targetId: listingId,
        provider: 'dev',
        platform: 'web',
        idempotencyKey: key,
      })
      .expect(201);
    expect(again.body.data.id).toBe(first.body.data.id);
    expect(await prisma.payment.count({ where: { purchaseId: first.body.data.id } })).toBe(1);
    await as(ctx.http, seller)
      .post('/checkout', {
        productId: 'listing_top_7d',
        targetId: listingId,
        provider: 'dev',
        platform: 'web',
        idempotencyKey: key,
      })
      .expect(409);
  });

  it('bump moves the ranking time, keeps publishedAt, and has a cooldown', async () => {
    const before = await prisma.listing.findUniqueOrThrow({ where: { id: listingId } });
    await new Promise((r) => setTimeout(r, 20));
    await buy(ctx, seller, { productId: 'listing_bump', targetId: listingId });
    const after = await prisma.listing.findUniqueOrThrow({ where: { id: listingId } });
    expect(after.publishedAt?.getTime()).toBe(before.publishedAt?.getTime());
    expect(after.createdAt.getTime()).toBe(before.createdAt.getTime());
    expect(after.rankedAt!.getTime()).toBeGreaterThan(before.rankedAt!.getTime());
    expect(
      await prisma.promotionActivation.count({ where: { targetId: listingId, kind: 'LISTING_BUMP' } }),
    ).toBe(1);
    const again = await checkout(seller, { productId: 'listing_bump', targetId: listingId }).expect(409);
    expect(again.body.error.message).toContain('once every');
    const feed = await request(ctx.http).get('/api/v1/listings?region=namangan&limit=1').expect(200);
    expect(feed.body.data[0].id).toBe(listingId); // bumped listing leads the organic "newest" order
  });

  it('two bump purchases paid at the same time apply only one bump (the other goes to review)', async () => {
    const bumper = await signIn(ctx.http); // own checkout rate-limit budget
    const fresh = await createListing(ctx.http, bumper, 'Redmi Note 13 Pro 8/256');
    // Both checkouts pass the cooldown check because neither is paid yet.
    const [a, b] = await Promise.all([
      checkout(bumper, { productId: 'listing_bump', targetId: fresh }).expect(201),
      checkout(bumper, { productId: 'listing_bump', targetId: fresh }).expect(201),
    ]);
    const payments = await Promise.all([paymentOf(ctx, a.body.data.id), paymentOf(ctx, b.body.data.id)]);
    await Promise.all(
      payments.map((p) =>
        devWebhook(ctx.http, {
          eventId: `evt_${p.id}_ok`,
          paymentId: p.id,
          status: 'succeeded',
          amountMinor: p.amountMinor.toString(),
        }).expect(200),
      ),
    );
    expect(await prisma.promotionActivation.count({ where: { targetId: fresh, kind: 'LISTING_BUMP' } })).toBe(
      1,
    );
    const purchases = await prisma.purchase.findMany({
      where: { id: { in: [a.body.data.id, b.body.data.id] } },
    });
    expect(purchases.map((p) => p.status).sort()).toEqual(['FULFILLED', 'NEEDS_REVIEW']);
    expect(purchases.find((p) => p.status === 'NEEDS_REVIEW')!.failureReason).toBe('bump_cooldown');
  });

  it('VIP outranks TOP inside the paid block; organic feed keeps its order', async () => {
    const vipListing = await createListing(ctx.http, seller, 'iPhone 15 Pro Max 512GB');
    const topListing = await createListing(ctx.http, seller, 'Xiaomi 14 Ultra 16/512');
    await buy(ctx, seller, { productId: 'listing_top_7d', targetId: topListing });
    await buy(ctx, seller, { productId: 'listing_vip_7d', targetId: vipListing });
    const promoted = await request(ctx.http).get('/api/v1/listings/promoted?region=namangan').expect(200);
    const ids = promoted.body.data.map((l: { id: string }) => l.id);
    expect(ids.indexOf(vipListing)).toBeLessThan(ids.indexOf(topListing));
    expect(promoted.body.data[ids.indexOf(vipListing)].badges).toEqual(['vip']);
    const organic = await request(ctx.http).get('/api/v1/listings?region=namangan&limit=50').expect(200);
    const organicIds = organic.body.data.map((l: { id: string }) => l.id);
    // Organic order is by ranking time (newest first), independent of payment.
    expect(organicIds.indexOf(topListing)).toBeLessThan(organicIds.indexOf(vipListing));
  });

  it('coupons: server-side discount, per-user and global limits, release on failure, 100 % coupons', async () => {
    const now = new Date(Date.now() - 60_000).toISOString();
    await as(ctx.http, admin)
      .post('/admin/monetization/coupons', {
        code: 'yarim50',
        discountType: 'percent',
        value: '50',
        validFrom: now,
        maxRedemptions: 2,
        perUserLimit: 1,
        productIds: ['listing_top_1d'],
      })
      .expect(201);
    await as(ctx.http, admin)
      .post('/admin/monetization/coupons', {
        code: 'BEPUL',
        discountType: 'percent',
        value: '100',
        validFrom: now,
        perUserLimit: 1,
      })
      .expect(201);

    const quote = await as(ctx.http, seller)
      .post('/checkout/quote', {
        productId: 'listing_top_1d',
        targetId: listingId,
        couponCode: 'YARIM50',
        platform: 'web',
      })
      .expect(200);
    expect(quote.body.data.total.amount).toBe(3_000);
    const wrongProduct = await as(ctx.http, seller)
      .post('/checkout/quote', {
        productId: 'listing_top_7d',
        targetId: listingId,
        couponCode: 'YARIM50',
        platform: 'web',
      })
      .expect(422);
    expect(wrongProduct.body.error.code).toBe('COUPON_INVALID');

    // A failed payment releases the reservation…
    const failing = await checkout(seller, {
      productId: 'listing_top_1d',
      targetId: listingId,
      couponCode: 'yarim50',
    }).expect(201);
    expect(failing.body.data.total.amount).toBe(3_000);
    const fp = await paymentOf(ctx, failing.body.data.id);
    await devWebhook(ctx.http, {
      eventId: `evt_${fp.id}_cf`,
      paymentId: fp.id,
      status: 'failed',
      amountMinor: fp.amountMinor.toString(),
    }).expect(200);
    // …so the same user can use it once, and only once.
    const pid = await buy(ctx, seller, {
      productId: 'listing_top_1d',
      targetId: listingId,
      couponCode: 'YARIM50',
    });
    expect((await as(ctx.http, seller).get(`/me/purchases/${pid}`)).body.data.discount.amount).toBe(3_000);
    await checkout(seller, {
      productId: 'listing_top_1d',
      targetId: listingId,
      couponCode: 'YARIM50',
    }).expect(422);

    // Global cap (2) across users.
    const other = await signIn(ctx.http);
    const otherListing = await createListing(ctx.http, other, 'Planshet Samsung Tab S9');
    await buy(ctx, other, { productId: 'listing_top_1d', targetId: otherListing, couponCode: 'YARIM50' });
    const third = await signIn(ctx.http);
    const thirdListing = await createListing(ctx.http, third, 'Noutbuk Lenovo Legion 5');
    await checkout(third, {
      productId: 'listing_top_1d',
      targetId: thirdListing,
      couponCode: 'YARIM50',
    }).expect(422);

    // 100 % coupon settles internally and activates without a payment provider.
    const free = await checkout(third, {
      productId: 'listing_top_1d',
      targetId: thirdListing,
      couponCode: 'BEPUL',
      provider: 'free',
    }).expect(201);
    expect(free.body.data.status).toBe('fulfilled');
    expect(free.body.data.total.amount).toBe(0);
    expect(free.body.data.activation.status).toBe('active');
  });

  it('promotion credits: ledger grant/consume, no overdraft, audited admin adjustment', async () => {
    await as(ctx.http, admin)
      .post(`/admin/monetization/users/${seller.userId}/credits`, {
        amount: 1,
        reason: 'Launch goodwill credit',
      })
      .expect(201);
    await as(ctx.http, seller)
      .post(`/admin/monetization/users/${seller.userId}/credits`, {
        amount: 100,
        reason: 'self grant attempt',
      })
      .expect(403);
    const res = await checkout(seller, {
      productId: 'listing_top_1d',
      targetId: listingId,
      provider: 'credits',
    }).expect(201);
    expect(res.body.data.status).toBe('fulfilled');
    expect(res.body.data.creditsUsed).toBe(1);
    const credits = await as(ctx.http, seller).get('/me/credits').expect(200);
    expect(credits.body.data.balance).toBe(0);
    expect(
      credits.body.data.entries.map((e: { type: string; amount: number }) => [e.type, e.amount]),
    ).toEqual([
      ['consume', -1],
      ['adjust', 1],
    ]);
    const broke = await checkout(seller, {
      productId: 'listing_top_1d',
      targetId: listingId,
      provider: 'credits',
    }).expect(409);
    expect(broke.body.error.code).toBe('INSUFFICIENT_CREDITS');
    // VIP has no credit price: credits are not accepted.
    await checkout(seller, { productId: 'listing_vip_7d', targetId: listingId, provider: 'credits' }).expect(
      422,
    );
    expect(
      await prisma.adminAuditLog.count({ where: { action: 'credits.adjust', entityId: seller.userId } }),
    ).toBe(1);
  });

  it('refunds: finance-only, policy-checked, audited; original payment is kept', async () => {
    const refundListing = await createListing(ctx.http, seller, 'Televizor LG OLED 55');
    const purchaseId = await buy(ctx, seller, { productId: 'listing_top_7d', targetId: refundListing });
    const payment = await paymentOf(ctx, purchaseId);
    await as(ctx.http, seller)
      .post(`/admin/monetization/payments/${payment.id}/refunds`, { reason: 'Customer request' })
      .expect(403);
    await as(ctx.http, finance)
      .post(`/admin/monetization/payments/${payment.id}/refunds`, {
        reason: 'Customer request',
        amountMinor: soum(999_999),
      })
      .expect(422);
    const refund = await as(ctx.http, finance)
      .post(`/admin/monetization/payments/${payment.id}/refunds`, { reason: 'Customer request' })
      .expect(201);
    expect(refund.body.data.status).toBe('succeeded');
    const after = await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
    expect(after.status).toBe('REFUNDED');
    expect(after.amountMinor).toBe(payment.amountMinor); // original record intact
    expect(after.refundedMinor).toBe(payment.amountMinor);
    const detail = await as(ctx.http, stranger).get(`/listings/${refundListing}`).expect(200);
    expect(detail.body.data.badges).toEqual([]);
    expect((await prisma.purchase.findUniqueOrThrow({ where: { id: purchaseId } })).status).toBe('REFUNDED');
    await as(ctx.http, finance)
      .post(`/admin/monetization/payments/${payment.id}/refunds`, { reason: 'Again' })
      .expect(409);

    // Bumps are not refundable unless explicitly overridden (and audited).
    const bumpListing = await createListing(ctx.http, seller, 'Konditsioner Artel 12');
    const bumpPurchase = await buy(ctx, seller, { productId: 'listing_bump', targetId: bumpListing });
    const bumpPayment = await paymentOf(ctx, bumpPurchase);
    const denied = await as(ctx.http, finance)
      .post(`/admin/monetization/payments/${bumpPayment.id}/refunds`, { reason: 'Customer request' })
      .expect(409);
    expect(denied.body.error.message).toContain('not refundable');
    await as(ctx.http, finance)
      .post(`/admin/monetization/payments/${bumpPayment.id}/refunds`, {
        reason: 'Double charge confirmed',
        overridePolicy: true,
      })
      .expect(201);
    expect(
      await prisma.adminAuditLog.count({
        where: { action: 'payment.refund.override', entityId: bumpPayment.id },
      }),
    ).toBe(1);
  });

  it('reconciliation recovers a success whose webhook never arrived; stale payments are abandoned', async () => {
    const res = await checkout(seller, { productId: 'listing_top_1d', targetId: listingId }).expect(201);
    const payment = await paymentOf(ctx, res.body.data.id);
    const dev = ctx.app.get(PaymentProviderRegistry).get('DEV') as DevPaymentProvider;
    await dev.simulate(payment, 'succeeded'); // provider state changes; webhook "lost"
    await prisma.payment.update({
      where: { id: payment.id },
      data: { createdAt: new Date(Date.now() - 10 * 60_000) },
    });
    const result = await tick(ctx);
    expect(result.reconciliation.applied).toBeGreaterThanOrEqual(1);
    expect((await prisma.purchase.findUniqueOrThrow({ where: { id: res.body.data.id } })).status).toBe(
      'FULFILLED',
    );

    const stale = await checkout(seller, { productId: 'listing_top_1d', targetId: listingId }).expect(201);
    const sp = await paymentOf(ctx, stale.body.data.id);
    await ctx.app.get(PrismaService)
      .$executeRaw`UPDATE "Payment" SET "createdAt" = now() - interval '2 days' WHERE "id" = ${sp.id}::uuid`;
    await ctx.app.get(PrismaService).$executeRaw`SELECT 1`;
    const redis = (
      ctx.app.get(PaymentProviderRegistry).get('DEV') as unknown as {
        redis: { del: (k: string) => Promise<number> };
      }
    ).redis;
    await redis.del(`devpay:${sp.id}`);
    await tick(ctx);
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: sp.id } })).status).toBe('CANCELLED');
  });

  it('revenue report uses accurate terms and excludes non-cash settlements', async () => {
    await as(ctx.http, seller).get('/admin/monetization/revenue?from=2020-01-01&to=2030-01-01').expect(403);
    const res = await as(ctx.http, finance)
      .get(
        `/admin/monetization/revenue?from=${new Date(Date.now() - 86400_000).toISOString()}&to=${new Date(Date.now() + 86400_000).toISOString()}`,
      )
      .expect(200);
    const report = res.body.data;
    const uzs = report.totals.find((t: { currency: string }) => t.currency === 'uzs');
    const succeeded = await prisma.payment.findMany({
      where: { provider: 'DEV', status: { in: ['SUCCEEDED', 'REFUNDED', 'PARTIALLY_REFUNDED'] } },
    });
    const gross = succeeded.reduce((sum, p) => sum + p.amountMinor, 0n);
    expect(uzs.grossPaymentVolumeMinor).toBe(gross.toString());
    expect(BigInt(uzs.netPaymentVolumeMinor)).toBe(gross - BigInt(uzs.refundsMinor));
    expect(report.nonCashSettlements.credits).toBeGreaterThanOrEqual(1);
    expect(report.payments.failed).toBeGreaterThanOrEqual(1);
    expect(report.note).toContain('not profit');
    expect(JSON.stringify(report)).not.toMatch(/profit"?:/i);
  });
});
