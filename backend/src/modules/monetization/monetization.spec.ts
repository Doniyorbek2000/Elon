import { BillingPeriod, Coupon, CouponDiscountType, Currency, Prisma, PurchaseKind } from '@prisma/client';
import type Redis from 'ioredis';

import { badgesFromTier, presentBadges, sortBadges } from '../../common/badges';
import { AppError } from '../../common/errors';
import { loadEnv, resetEnvCache } from '../../config/env';
import { validateSetting } from '../admin/admin.service';
import { MonetizationConfig } from './config.service';
import { CouponsService } from './coupons.service';
import { assertWholeMajor, percentOf, presentAmount } from './money';
import { PaymentsService } from './payments.service';
import { DevPaymentProvider } from './providers/dev.provider';
import { addPeriod } from './subscriptions.service';

const HOUR = 3600_000;

describe('money (integer minor units only)', () => {
  it('presents BigInt minor units as strings plus whole major units', () => {
    expect(presentAmount(2_500_000n, Currency.UZS)).toEqual({
      amountMinor: '2500000',
      amount: 25_000,
      currency: 'uzs',
    });
    // Beyond Number.MAX_SAFE_INTEGER the exact value survives in the string.
    expect(presentAmount(9_007_199_254_740_993_00n, Currency.UZS).amountMinor).toBe('900719925474099300');
  });

  it('accepts only whole, non-negative major amounts', () => {
    expect(assertWholeMajor(2_500_000n, Currency.UZS)).toBe(true);
    expect(assertWholeMajor(2_500_050n, Currency.UZS)).toBe(false);
    expect(assertWholeMajor(-100n, Currency.UZS)).toBe(false);
    expect(assertWholeMajor(0n, Currency.UZS)).toBe(true);
  });

  it('percent discounts round down to whole units and never exceed the amount', () => {
    expect(percentOf(2_500_000n, 10n, Currency.UZS)).toBe(250_000n);
    expect(percentOf(3_333_300n, 33n, Currency.UZS)).toBe(1_099_900n); // 1 099 989 → 1 099 900
    expect(percentOf(100n, 1n, Currency.UZS)).toBe(0n);
    expect(percentOf(2_500_000n, 100n, Currency.UZS)).toBe(2_500_000n);
  });
});

describe('refund policy', () => {
  const now = new Date('2026-09-27T12:00:00Z');
  const policy = (input: Partial<Parameters<typeof PaymentsService.refundPolicy>[0]>) =>
    PaymentsService.refundPolicy({ kind: PurchaseKind.PROMOTION, now, ...input });

  it('bumps are never refundable (the effect is immediate)', () => {
    expect(policy({ productKind: 'LISTING_BUMP', activationStartedAt: now })).toMatch(/not refundable/);
  });

  it('promotions are refundable within 24 hours of starting', () => {
    expect(
      policy({ productKind: 'LISTING_TOP', activationStartedAt: new Date(now.getTime() - 23 * HOUR) }),
    ).toBeNull();
    expect(
      policy({ productKind: 'LISTING_TOP', activationStartedAt: new Date(now.getTime() - 25 * HOUR) }),
    ).toMatch(/24 hours/);
    expect(policy({ productKind: 'LISTING_TOP', activationStartedAt: null })).toBeNull(); // scheduled, not started
  });

  it('subscriptions and ads are left to finance judgement', () => {
    expect(policy({ kind: PurchaseKind.SUBSCRIPTION, activationStartedAt: new Date(0) })).toBeNull();
  });
});

describe('admin settings validation', () => {
  it('fills defaults and normalises provider keys', () => {
    expect(validateSetting('ranking', { promotedSlots: 5 })).toEqual({
      promotedSlots: 5,
      featuredSlots: 6,
      bumpCooldownHours: 24,
    });
    expect(validateSetting('checkoutRoutes', { web: ['payme', 'dev'] })).toEqual({
      ios: ['APPLE'],
      android: ['GOOGLE'],
      web: ['PAYME', 'DEV'],
    });
  });

  it.each([
    ['ranking', { promotedSlots: -1 }],
    ['ranking', { promotedSlots: 1.5 }],
    ['ranking', { bumpCooldownHours: 10_000 }],
    ['ranking', { promotedSlots: '3' }],
    ['ranking', { surprise: 1 }],
    ['checkoutRoutes', { ios: ['STRIPE'] }],
    ['checkoutRoutes', { ios: 'APPLE' }],
  ])('rejects invalid %s %j', (key, value) => {
    expect(() => validateSetting(key, value as Record<string, unknown>)).toThrow(AppError);
  });

  it('rejects unknown settings', () => {
    expect(() => validateSetting('pricing', {})).toThrow(AppError);
  });
});

describe('subscription periods', () => {
  it.each([
    ['2026-01-15T10:00:00Z', BillingPeriod.MONTH, '2026-02-15T10:00:00.000Z'],
    ['2026-01-31T10:00:00Z', BillingPeriod.MONTH, '2026-02-28T10:00:00.000Z'],
    ['2028-01-31T10:00:00Z', BillingPeriod.MONTH, '2028-02-29T10:00:00.000Z'],
    ['2026-12-31T23:00:00Z', BillingPeriod.MONTH, '2027-01-31T23:00:00.000Z'],
    ['2028-02-29T00:00:00Z', BillingPeriod.YEAR, '2029-02-28T00:00:00.000Z'],
  ])('%s + %s = %s', (from, period, expected) => {
    expect(addPeriod(new Date(from), period).toISOString()).toBe(expected);
  });
});

describe('badges', () => {
  const now = new Date('2026-09-27T12:00:00Z');
  it('derive from the ranking cache only while active', () => {
    expect(badgesFromTier(2, new Date(now.getTime() + HOUR), now)).toEqual(['vip']);
    expect(badgesFromTier(1, new Date(now.getTime() + HOUR), now)).toEqual(['top']);
    expect(badgesFromTier(1, new Date(now.getTime() - HOUR), now)).toEqual([]);
    expect(badgesFromTier(0, null, now)).toEqual([]);
  });

  it('are ordered and always marked sponsored', () => {
    expect(sortBadges(['urgent', 'top', 'urgent'])).toEqual(['top', 'urgent']);
    expect(presentBadges({ boostTier: 0, boostUntil: null }, { badges: ['featured'] })).toEqual({
      promotion: 'featured',
      badges: ['featured'],
      sponsored: true,
    });
    expect(presentBadges({ boostTier: 0, boostUntil: null }, {})).toEqual({
      promotion: null,
      badges: [],
      sponsored: false,
    });
  });
});

describe('coupon evaluation', () => {
  const coupon = (overrides: Partial<Coupon> = {}): Coupon => ({
    id: 'c1',
    code: 'BOZOR10',
    description: null,
    discountType: CouponDiscountType.PERCENT,
    value: 10n,
    currency: null,
    validFrom: new Date(Date.now() - HOUR),
    validUntil: null,
    maxRedemptions: null,
    perUserLimit: 1,
    productIds: [],
    planIds: [],
    active: true,
    createdById: 'admin',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  });

  const setup = (row: Coupon | null, counts: { total?: number; mine?: number } = {}, enabled = true) => {
    const tx = {
      coupon: {
        findUnique: jest.fn().mockResolvedValue(row),
        findUniqueOrThrow: jest.fn().mockResolvedValue(row),
      },
      couponRedemption: {
        count: jest.fn(({ where }: { where: { userId?: string } }) =>
          Promise.resolve(where.userId ? (counts.mine ?? 0) : (counts.total ?? 0)),
        ),
      },
      $queryRaw: jest.fn().mockResolvedValue([]),
    } as unknown as Prisma.TransactionClient;
    const config = { enabled: jest.fn().mockResolvedValue(enabled) } as unknown as MonetizationConfig;
    const service = new CouponsService(config);
    return (
      code: string,
      scope = { productId: 'listing_top_7d' },
      list = 2_500_000n,
      currency: Currency = Currency.UZS,
    ) => service.evaluate(tx, code, 'u1', scope, list, currency, true);
  };

  const rejects = async (promise: Promise<unknown>) => {
    await expect(promise).rejects.toMatchObject({ code: 'COUPON_INVALID' });
  };

  it('computes percent and fixed discounts server-side', async () => {
    await expect(setup(coupon())(' bozor10 ')).resolves.toMatchObject({ discountMinor: 250_000n });
    const fixed = coupon({ discountType: CouponDiscountType.FIXED, value: 500_000n, currency: Currency.UZS });
    await expect(setup(fixed)('BOZOR10')).resolves.toMatchObject({ discountMinor: 500_000n });
    // A fixed discount never exceeds the price.
    await expect(setup(fixed)('BOZOR10', undefined, 300_000n)).resolves.toMatchObject({
      discountMinor: 300_000n,
    });
  });

  it('fails every rule with the same generic error', async () => {
    await rejects(setup(coupon(), {}, false)('BOZOR10'));
    await rejects(setup(null)('NOPE'));
    await rejects(setup(coupon())('bad code!'));
    await rejects(setup(coupon({ active: false }))('BOZOR10'));
    await rejects(setup(coupon({ validFrom: new Date(Date.now() + HOUR) }))('BOZOR10'));
    await rejects(setup(coupon({ validUntil: new Date(Date.now() - 1) }))('BOZOR10'));
    await rejects(setup(coupon({ maxRedemptions: 5 }), { total: 5 })('BOZOR10'));
    await rejects(setup(coupon(), { mine: 1 })('BOZOR10'));
    await rejects(setup(coupon({ productIds: ['listing_vip_7d'] }))('BOZOR10'));
    await rejects(setup(coupon({ planIds: ['BUSINESS'] }))('BOZOR10'));
    await rejects(
      setup(coupon({ discountType: CouponDiscountType.FIXED, value: 100n, currency: Currency.USD }))(
        'BOZOR10',
      ),
    );
  });

  it('respects plan scoping', async () => {
    await expect(
      setup(coupon({ planIds: ['BUSINESS'] }))('BOZOR10', { planId: 'BUSINESS' } as never),
    ).resolves.toBeTruthy();
    await rejects(setup(coupon({ planIds: ['BUSINESS'] }))('BOZOR10', { planId: 'BUSINESS_PRO' } as never));
  });
});

describe('dev payment provider webhook verification', () => {
  const secret = 'x'.repeat(48);
  const saved = { ...process.env };

  beforeAll(() => {
    Object.assign(process.env, {
      NODE_ENV: 'test',
      DATABASE_URL: 'postgresql://u:p@localhost:5432/bozor_unit',
      REDIS_URL: 'redis://localhost:6379/0',
      JWT_ACCESS_SECRET: 'a'.repeat(64),
      OTP_HASH_SECRET: 'b'.repeat(64),
      S3_BUCKET: 'bozor-unit',
      S3_ACCESS_KEY_ID: 'key',
      S3_SECRET_ACCESS_KEY: 'secret',
      PAYMENT_DEV_ENABLED: 'true',
      PAYMENT_DEV_SECRET: secret,
    });
    resetEnvCache();
  });

  afterAll(() => {
    process.env = saved;
    resetEnvCache();
  });

  const provider = new DevPaymentProvider({} as Redis);
  const body = JSON.stringify({
    eventId: 'e1',
    paymentId: 'p1',
    externalId: 'dev_p1',
    status: 'succeeded',
    amountMinor: '2500000',
  });
  const request = (signature: string, timestamp: string, raw = body) => ({
    rawBody: Buffer.from(raw),
    headers: { 'x-dev-signature': signature, 'x-dev-timestamp': timestamp },
  });
  const nowSeconds = () => String(Math.floor(Date.now() / 1000));

  it('accepts a fresh, correctly signed event and parses money as BigInt', async () => {
    const ts = nowSeconds();
    const [event] = await provider.parseWebhook(request(DevPaymentProvider.sign(secret, ts, body), ts));
    expect(event).toEqual({
      eventId: 'e1',
      paymentId: 'p1',
      externalId: 'dev_p1',
      type: 'succeeded',
      amountMinor: 2_500_000n,
    });
  });

  it.each([
    ['wrong secret', () => DevPaymentProvider.sign('y'.repeat(48), nowSeconds(), body), nowSeconds, body],
    [
      'tampered body',
      () => DevPaymentProvider.sign(secret, nowSeconds(), body),
      nowSeconds,
      body.replace('2500000', '100'),
    ],
    ['stale timestamp', () => DevPaymentProvider.sign(secret, '1000', body), () => '1000', body],
    ['missing signature', () => '', nowSeconds, body],
    ['non-hex signature', () => 'z'.repeat(64), nowSeconds, body],
    ['non-numeric timestamp', () => DevPaymentProvider.sign(secret, 'abc', body), () => 'abc', body],
  ])('rejects %s', async (_name, signature, timestamp, raw) => {
    await expect(provider.parseWebhook(request(signature(), timestamp(), raw))).rejects.toMatchObject({
      code: 'SIGNATURE_INVALID',
    });
  });
});

describe('payment configuration', () => {
  const base = {
    NODE_ENV: 'production',
    DATABASE_URL: 'postgresql://u:p@db:5432/bozor',
    REDIS_URL: 'redis://redis:6379/0',
    JWT_ACCESS_SECRET: 'a'.repeat(64),
    OTP_HASH_SECRET: 'b'.repeat(64),
    S3_ENDPOINT: 'https://s3.example.com',
    S3_BUCKET: 'bozor',
    S3_ACCESS_KEY_ID: 'key',
    S3_SECRET_ACCESS_KEY: 'secret',
    PUBLIC_API_URL: 'https://api.example.com',
    CORS_ORIGINS: 'https://bozor.example.com',
    OTP_PROVIDER: 'none',
  };

  it('never enables the dev payment provider in production', () => {
    expect(loadEnv(base).PAYMENT_DEV_ENABLED).toBe(false);
    expect(() =>
      loadEnv({ ...base, PAYMENT_DEV_ENABLED: 'true', PAYMENT_DEV_SECRET: 'c'.repeat(48) }),
    ).toThrow(/PAYMENT_DEV/);
  });

  it('requires a strong secret when the dev provider is enabled', () => {
    expect(() =>
      loadEnv({ ...base, NODE_ENV: 'development', PAYMENT_DEV_ENABLED: 'true', PAYMENT_DEV_SECRET: 'short' }),
    ).toThrow(/PAYMENT_DEV_SECRET/);
  });
});
