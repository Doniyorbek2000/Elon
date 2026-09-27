import request from 'supertest';

import { PrismaService } from '../src/infra/prisma.service';
import {
  as,
  NAMANGAN_CHUST,
  signIn,
  startTestApp,
  stopTestApp,
  TestContext,
  TestUser,
  waitFor,
} from './helpers';
import {
  buy,
  createListing,
  idem,
  makeAdmin,
  priceAndActivate,
  setFlags,
  soum,
  tick,
} from './monetization.helpers';

const DAY = 86400_000;
const ids = (res: request.Response) => (res.body.data as Array<{ id: string }>).map((x) => x.id);

describe('Monetization: business plans, entitlements, premium jobs, providers, ads, analytics', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let admin: TestUser;
  let owner: TestUser;
  let manager: TestUser;
  let manager2: TestUser;
  let viewer: TestUser;
  let businessId: string;
  let ownerListingId: string;

  beforeAll(async () => {
    ctx = await startTestApp();
    prisma = ctx.app.get(PrismaService);
    [admin, owner, manager, manager2, viewer] = await Promise.all([
      makeAdmin(ctx),
      signIn(ctx.http),
      signIn(ctx.http),
      signIn(ctx.http),
      signIn(ctx.http),
    ]);
    ownerListingId = await createListing(ctx.http, owner, 'Do‘kon: iPhone 14 Pro 128GB');
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  const business = {
    name: 'Chust Telefon Markazi',
    description: 'Yangi va ishlatilgan telefonlar, kafolat bilan.',
    categoryId: 'phones',
    regionId: 'namangan',
    districtId: 'chust',
    phone: '+998 90 123 45 67',
    telegram: '@chust_telefon',
  };

  it('business accounts are flag-gated; free businesses have no storefront or managers', async () => {
    const off = await as(ctx.http, owner).post('/businesses', business).expect(403);
    expect(off.body.error.code).toBe('FEATURE_DISABLED');

    await setFlags(ctx.http, admin, { businessAccounts: true });
    const created = await as(ctx.http, owner).post('/businesses', business).expect(201);
    businessId = created.body.data.id;
    expect(created.body.data.myRole).toBe('owner');
    expect(created.body.data.verified).toBe(false); // never self-declared
    expect(created.body.data.plan.id).toBe('FREE');
    expect(created.body.data.shareUrl).toMatch(new RegExp(`/business/${businessId}$`));
    await as(ctx.http, owner)
      .post('/businesses', { ...business, name: 'Ikkinchi' })
      .expect(409);

    // Storefront is a paid entitlement: a free business is not publicly listed.
    await request(ctx.http).get(`/api/v1/businesses/${businessId}`).expect(404);
    const managers = await as(ctx.http, owner)
      .post('/me/business/members', { phone: manager.phone })
      .expect(403);
    expect(managers.body.error.code).toBe('LIMIT_REACHED');
    expect(managers.body.error.details).toEqual({ limit: 'managers', max: 0 });

    // Verification is admin-only.
    await as(ctx.http, owner).post('/me/business/verification').expect(200);
    await as(ctx.http, owner)
      .patch(`/admin/monetization/businesses/${businessId}/verification`, { verification: 'verified' })
      .expect(403);
  });

  it('free tier limits come from the backend plan and apply immediately', async () => {
    const seller = await signIn(ctx.http);
    await createListing(ctx.http, seller, 'Birinchi e’lon: Redmi Note 12');
    await as(ctx.http, admin).patch('/admin/monetization/plans/FREE', { activeListingLimit: 1 }).expect(200);
    try {
      const config = await request(ctx.http).get('/api/v1/config').expect(200);
      expect(config.body.data.freePlan.activeListingLimit).toBe(1);
      const blocked = await as(ctx.http, seller)
        .post('/listings', {
          categoryId: 'phones',
          title: 'Ikkinchi e’lon: Redmi Note 13',
          description: 'Holati yaxshi, qutisi va hujjatlari bilan birga.',
          price: { amount: 2_000_000, currency: 'uzs' },
          condition: 'used',
          attributes: { brand: 'Xiaomi' },
          place: NAMANGAN_CHUST,
          mediaIds: [],
        })
        .expect(403);
      expect(blocked.body.error.code).toBe('LIMIT_REACHED');
      expect(blocked.body.error.details).toEqual({ limit: 'activeListings', max: 1 });
      const me = await as(ctx.http, seller).get('/me/entitlements').expect(200);
      expect(me.body.data.usage.activeListings).toBe(1);
    } finally {
      await as(ctx.http, admin)
        .patch('/admin/monetization/plans/FREE', { activeListingLimit: 50 })
        .expect(200);
    }
    expect(await prisma.adminAuditLog.count({ where: { action: 'plan.update', entityId: 'FREE' } })).toBe(2);
  });

  it('flow D: business subscription unlocks storefront, managers and advanced analytics; expiry downgrades safely', async () => {
    // Plans are invisible until the admin enables and prices them.
    expect((await as(ctx.http, owner).get('/catalog/plans').expect(200)).body.data).toEqual([]);
    await setFlags(ctx.http, admin, { monetization: true, businessPlans: true });
    await as(ctx.http, admin)
      .post('/admin/monetization/plans/BUSINESS/prices', { amountMinor: soum(150_000), currency: 'uzs' })
      .expect(422);
    await as(ctx.http, admin)
      .post('/admin/monetization/plans/FREE/prices', {
        amountMinor: soum(1),
        currency: 'uzs',
        period: 'month',
      })
      .expect(422);
    await as(ctx.http, admin)
      .post('/admin/monetization/plans/BUSINESS/prices', {
        amountMinor: soum(150_000),
        currency: 'uzs',
        period: 'month',
      })
      .expect(201);
    await as(ctx.http, admin).patch('/admin/monetization/plans/BUSINESS', { active: true }).expect(200);

    const plans = await as(ctx.http, owner).get('/catalog/plans').expect(200);
    const plan = plans.body.data.find((p: { id: string }) => p.id === 'BUSINESS');
    expect(plan.entitlements.storefront).toBe(true);
    expect(plan.prices).toEqual([
      {
        id: expect.any(String),
        period: 'month',
        amountMinor: soum(150_000),
        amount: 150_000,
        currency: 'uzs',
      },
    ]);

    // A viewer cannot activate a plan by any client call; only a verified payment does.
    await as(ctx.http, owner)
      .post('/checkout', {
        planPriceId: plan.prices[0].id,
        provider: 'dev',
        platform: 'web',
        idempotencyKey: idem(),
      })
      .expect(201);
    expect((await as(ctx.http, owner).get('/me/entitlements').expect(200)).body.data.plan.id).toBe('FREE');

    const purchaseId = await buy(ctx, owner, { planPriceId: plan.prices[0].id });
    const detail = await as(ctx.http, owner).get(`/me/purchases/${purchaseId}`).expect(200);
    expect(detail.body.data.status).toBe('fulfilled');
    expect(detail.body.data.subscription.status).toBe('active');
    const me = await as(ctx.http, owner).get('/me/entitlements').expect(200);
    expect(me.body.data.plan.id).toBe('BUSINESS');
    expect(me.body.data.businessId).toBe(businessId);
    const subscription = await prisma.subscription.findUniqueOrThrow({
      where: { id: me.body.data.subscriptionId },
    });
    expect(
      subscription.currentPeriodEnd.getTime() - subscription.currentPeriodStart.getTime(),
    ).toBeGreaterThanOrEqual(28 * DAY);

    // Storefront is public and deep-linkable; rating only from real reviews.
    const store = await request(ctx.http).get(`/api/v1/businesses/${businessId}`).expect(200);
    expect(store.body.data.name).toBe(business.name);
    expect(store.body.data.businessBadge).toBe(true);
    expect(store.body.data.rating).toBeNull();
    expect(store.body.data.stats.activeListings).toBe(1);
    const storeListings = await request(ctx.http)
      .get(`/api/v1/businesses/${businessId}/listings`)
      .expect(200);
    expect(ids(storeListings)).toEqual([ownerListingId]);

    // Managers: shared plan, owner-only administration, plan limit enforced.
    await as(ctx.http, owner).post('/me/business/members', { phone: manager.phone }).expect(201);
    expect((await as(ctx.http, manager).get('/me/entitlements').expect(200)).body.data.plan.id).toBe(
      'BUSINESS',
    );
    await as(ctx.http, manager).post('/me/business/members', { phone: manager2.phone }).expect(403);
    const full = await as(ctx.http, owner)
      .post('/me/business/members', { phone: manager2.phone })
      .expect(403);
    expect(full.body.error.details).toEqual({ limit: 'managers', max: 1 });
    const managerListing = await createListing(ctx.http, manager, 'Do‘kon: Samsung A54');
    expect(ids(await request(ctx.http).get(`/api/v1/businesses/${businessId}/listings`).expect(200))).toEqual(
      [managerListing, ownerListingId],
    );

    // Advanced analytics: daily series and a custom range.
    await as(ctx.http, viewer).get(`/listings/${ownerListingId}`).expect(200);
    const stats = await waitFor(async () => {
      const res = await as(ctx.http, owner).get(`/me/listings/${ownerListingId}/stats?days=30`).expect(200);
      return res.body.data.totals.views >= 1 && res.body.data;
    });
    expect(stats.level).toBe('advanced');
    expect(stats.daily.length).toBeGreaterThanOrEqual(1);
    await as(ctx.http, viewer).get(`/me/listings/${ownerListingId}/stats`).expect(404);

    // Cancelling keeps access until the paid period ends.
    await as(ctx.http, owner).post(`/me/subscriptions/${subscription.id}/cancel`).expect(200);
    expect((await as(ctx.http, owner).get('/me/entitlements').expect(200)).body.data.plan.id).toBe(
      'BUSINESS',
    );

    // Expiry: worker downgrades everyone to FREE; nothing is deleted.
    await tick(ctx, new Date(subscription.currentPeriodEnd.getTime() + 60_000));
    expect((await prisma.subscription.findUniqueOrThrow({ where: { id: subscription.id } })).status).toBe(
      'EXPIRED',
    );
    expect((await as(ctx.http, owner).get('/me/entitlements').expect(200)).body.data.plan.id).toBe('FREE');
    expect((await as(ctx.http, manager).get('/me/entitlements').expect(200)).body.data.plan.id).toBe('FREE');
    await request(ctx.http).get(`/api/v1/businesses/${businessId}`).expect(404);
    const basic = await as(ctx.http, owner).get(`/me/listings/${ownerListingId}/stats?days=30`).expect(200);
    expect(basic.body.data.level).toBe('basic');
    expect(basic.body.data.daily).toEqual([]);
    expect(basic.body.data.totals.views).toBeGreaterThanOrEqual(1); // real counts stay visible
    expect((await prisma.listing.findUniqueOrThrow({ where: { id: ownerListingId } })).status).toBe('ACTIVE');
    expect((await as(ctx.http, owner).get('/me/business').expect(200)).body.data.members).toHaveLength(2);
    const notice = await prisma.notification.findFirst({
      where: { userId: owner.userId, type: 'SUBSCRIPTION' },
    });
    expect(notice).toBeTruthy();
  });

  it('a manager cannot open a second business', async () => {
    const res = await as(ctx.http, manager)
      .post('/businesses', { ...business, name: 'Menejer do‘koni' })
      .expect(409);
    expect(res.body.error.code).toBe('CONFLICT');
  });

  it('admin verification is audited and shown on the business', async () => {
    await as(ctx.http, admin)
      .patch(`/admin/monetization/businesses/${businessId}/verification`, { verification: 'verified' })
      .expect(200);
    const mine = await as(ctx.http, owner).get('/me/business').expect(200);
    expect(mine.body.data.verified).toBe(true);
    expect(
      await prisma.adminAuditLog.count({ where: { action: 'business.verification', entityId: businessId } }),
    ).toBe(1);
    // Renaming a verified business requires re-verification.
    const renamed = await as(ctx.http, owner)
      .patch('/me/business', { name: 'Chust Telefon Markazi 2' })
      .expect(200);
    expect(renamed.body.data.verification).toBe('pending');
  });

  it('flow E: premium job TOP and "Shoshilinch" are paid, labeled, and expire', async () => {
    const employer = await signIn(ctx.http);
    const job = await as(ctx.http, employer)
      .post('/jobs', {
        title: 'Kassir kerak',
        companyName: 'Chust Market',
        description: 'Supermarketga kassir kerak. Tajriba shart emas, o‘rgatamiz.',
        requirements: ['Mas’uliyat'],
        responsibilities: ['Kassada ishlash'],
        salaryMin: 3000000,
        salaryMax: 4000000,
        salaryCurrency: 'uzs',
        employmentType: 'fullTime',
        workFormat: 'onSite',
        experience: 'upTo1',
        workSchedule: '08:00–17:00',
        applicationMode: 'both',
        place: NAMANGAN_CHUST,
      })
      .expect(201);
    const jobId = job.body.data.id as string;

    const disabled = await as(ctx.http, employer)
      .post('/checkout', {
        productId: 'job_top_7d',
        targetId: jobId,
        provider: 'dev',
        platform: 'web',
        idempotencyKey: idem(),
      })
      .expect(422);
    expect(disabled.body.error.code).toBe('PRICE_UNAVAILABLE'); // product flag off → not sellable
    await setFlags(ctx.http, admin, { premiumJobs: true });
    await priceAndActivate(ctx.http, admin, 'job_top_7d', 40_000);
    await priceAndActivate(ctx.http, admin, 'job_urgent_7d', 20_000);

    expect(
      ids(await request(ctx.http).get('/api/v1/jobs/promoted?region=namangan').expect(200)),
    ).not.toContain(jobId);
    await buy(ctx, employer, { productId: 'job_top_7d', targetId: jobId });
    await buy(ctx, employer, { productId: 'job_urgent_7d', targetId: jobId });

    const promoted = await request(ctx.http).get('/api/v1/jobs/promoted?region=namangan').expect(200);
    const card = promoted.body.data.find((j: { id: string }) => j.id === jobId);
    expect(card.badges).toEqual(expect.arrayContaining(['top', 'urgent']));
    expect(card.sponsored).toBe(true);
    // Other regions do not see it.
    expect(
      ids(await request(ctx.http).get('/api/v1/jobs/promoted?region=tashkent').expect(200)),
    ).not.toContain(jobId);
    const organic = await request(ctx.http).get('/api/v1/jobs?region=namangan').expect(200);
    expect(organic.body.data.find((j: { id: string }) => j.id === jobId).badges).toContain('urgent');

    await tick(ctx, new Date(Date.now() + 8 * DAY));
    expect(
      ids(await request(ctx.http).get('/api/v1/jobs/promoted?region=namangan').expect(200)),
    ).not.toContain(jobId);
    const after = await request(ctx.http).get('/api/v1/jobs?region=namangan').expect(200);
    expect(after.body.data.find((j: { id: string }) => j.id === jobId).badges).toEqual([]);
    expect((await prisma.job.findUniqueOrThrow({ where: { id: jobId } })).boostTier).toBe(0);
  });

  it('flow F: provider TOP/featured is visible and labeled, but never changes the rating', async () => {
    const provider = await signIn(ctx.http);
    const profile = await as(ctx.http, provider)
      .put('/me/provider', {
        displayName: 'Bekzod Elektrik',
        profession: 'Elektrik',
        description: 'Uy va ofislarda elektr montaj ishlari, rozetka va yoritish.',
        experienceYears: 6,
        categoryIds: ['electrician'],
        place: NAMANGAN_CHUST,
        areas: [{ regionId: 'namangan', districtId: 'chust' }],
        availability: 'available',
      })
      .expect(200);
    const providerId = profile.body.data.id as string;
    await setFlags(ctx.http, admin, { featuredServices: true });
    await priceAndActivate(ctx.http, admin, 'provider_top_7d', 30_000);
    await priceAndActivate(ctx.http, admin, 'provider_featured_region_7d', 35_000);

    const before = await prisma.serviceProvider.findUniqueOrThrow({ where: { id: providerId } });
    await buy(ctx, provider, { productId: 'provider_top_7d', targetId: providerId });
    await buy(ctx, provider, { productId: 'provider_featured_region_7d', targetId: providerId });

    const promoted = await request(ctx.http)
      .get('/api/v1/providers/promoted?region=namangan&category=electrician')
      .expect(200);
    const card = promoted.body.data.find((p: { id: string }) => p.id === providerId);
    expect(card.badges).toContain('top');
    expect(card.sponsored).toBe(true);
    const featured = await request(ctx.http)
      .get('/api/v1/providers/featured?placement=region&region=namangan')
      .expect(200);
    expect(ids(featured)).toContain(providerId);
    expect(
      ids(
        await request(ctx.http)
          .get('/api/v1/providers/featured?placement=region&region=tashkent')
          .expect(200),
      ),
    ).not.toContain(providerId);

    const after = await prisma.serviceProvider.findUniqueOrThrow({ where: { id: providerId } });
    expect(after.ratingAvg).toBe(before.ratingAvg);
    expect(after.reviewCount).toBe(0);
    const detail = await request(ctx.http).get(`/api/v1/providers/${providerId}`).expect(200);
    expect(detail.body.data.profile.rating).toBeNull();
    expect(detail.body.data.profile.reviewCount).toBe(0);
  });

  it('ads: pay → admin review → served with a sponsored label; events deduplicated; targeting is coarse', async () => {
    const campaign = {
      title: 'Yangi iPhone’lar',
      body: 'Chust markazida kafolatli telefonlar. Bo‘lib to‘lash mavjud.',
      destination: 'business',
      destinationId: businessId,
      regionId: 'namangan',
    };
    const off = await as(ctx.http, owner).post('/me/business/campaigns', campaign).expect(403);
    expect(off.body.error.code).toBe('FEATURE_DISABLED');
    await setFlags(ctx.http, admin, { ads: true });
    await priceAndActivate(ctx.http, admin, 'ad_campaign_7d', 100_000);

    // Advertising someone else's content is refused.
    const foreignListing = await createListing(ctx.http, viewer, 'Begona e’lon: Nokia 3310');
    await as(ctx.http, owner)
      .post('/me/business/campaigns', { ...campaign, destination: 'listing', destinationId: foreignListing })
      .expect(422);
    await as(ctx.http, viewer).post('/me/business/campaigns', campaign).expect(404);

    const created = await as(ctx.http, owner).post('/me/business/campaigns', campaign).expect(201);
    const campaignId = created.body.data.id as string;
    expect(created.body.data.status).toBe('draft');
    // Only a member of the business can pay for it.
    await as(ctx.http, viewer)
      .post('/checkout', {
        productId: 'ad_campaign_7d',
        targetId: campaignId,
        provider: 'dev',
        platform: 'web',
        idempotencyKey: idem(),
      })
      .expect(404);

    await buy(ctx, owner, { productId: 'ad_campaign_7d', targetId: campaignId });
    const paid = await as(ctx.http, owner).get('/me/business/campaigns').expect(200);
    expect(paid.body.data[0].status).toBe('pendingReview');
    expect(
      await request(ctx.http)
        .get('/api/v1/ads?region=namangan')
        .expect(200)
        .then((r) => r.body.data),
    ).toEqual([]);
    await as(ctx.http, owner).post(`/admin/monetization/campaigns/${campaignId}/approve`).expect(403);
    await as(ctx.http, admin).post(`/admin/monetization/campaigns/${campaignId}/approve`).expect(201);

    const served = await request(ctx.http).get('/api/v1/ads?region=namangan').expect(200);
    expect(served.body.data).toHaveLength(1);
    expect(served.body.data[0]).toMatchObject({ id: campaignId, sponsored: true, destination: 'business' });
    expect(
      await request(ctx.http)
        .get('/api/v1/ads?region=tashkent')
        .expect(200)
        .then((r) => r.body.data),
    ).toEqual([]);

    const first = await as(ctx.http, viewer)
      .post(`/ads/${campaignId}/events`, { type: 'impression' })
      .expect(200);
    const repeat = await as(ctx.http, viewer)
      .post(`/ads/${campaignId}/events`, { type: 'impression' })
      .expect(200);
    expect([first.body.data.counted, repeat.body.data.counted]).toEqual([true, false]);
    await as(ctx.http, viewer).post(`/ads/${campaignId}/events`, { type: 'click' }).expect(200);
    await as(ctx.http, manager2).post(`/ads/${campaignId}/events`, { type: 'impression' }).expect(200);
    await as(ctx.http, viewer).post(`/ads/${campaignId}/events`, { type: 'purchase' }).expect(422);

    const stats = await as(ctx.http, owner).get('/me/business/campaigns').expect(200);
    expect(stats.body.data[0].stats).toMatchObject({ impressions: 2, clicks: 1 });
    expect(stats.body.data[0].stats.daily).toHaveLength(1);
    // Viewer identities are not persisted anywhere in the database.
    const stored = JSON.stringify(await prisma.adDailyStat.findMany({ where: { campaignId } }));
    expect(stored).not.toContain(viewer.userId);

    // Paused ads are not served; expiry ends the campaign.
    await as(ctx.http, owner).post(`/me/business/campaigns/${campaignId}/pause`).expect(200);
    expect(
      await request(ctx.http)
        .get('/api/v1/ads?region=namangan')
        .expect(200)
        .then((r) => r.body.data),
    ).toEqual([]);
    await as(ctx.http, owner).post(`/me/business/campaigns/${campaignId}/resume`).expect(200);
    await tick(ctx, new Date(Date.now() + 8 * DAY));
    expect((await prisma.adCampaign.findUniqueOrThrow({ where: { id: campaignId } })).status).toBe('ENDED');
  });

  it('seller analytics (basic) and promotion results make no unsupported claims', async () => {
    const seller = await signIn(ctx.http);
    const listingId = await createListing(ctx.http, seller, 'Statistika uchun: Honor X8');
    await as(ctx.http, viewer).get(`/listings/${listingId}`).expect(200);
    await as(ctx.http, viewer).get(`/listings/${listingId}`).expect(200); // same viewer, same day
    await as(ctx.http, viewer).put(`/favorites/listings/${listingId}`).expect(200);
    const stats = await waitFor(async () => {
      const res = await as(ctx.http, seller).get(`/me/listings/${listingId}/stats?days=90`).expect(200);
      return res.body.data.totals.favorites >= 1 && res.body.data.totals.views >= 1 && res.body.data;
    });
    expect(stats.level).toBe('basic');
    expect(stats.totals.views).toBe(1);
    expect(stats.daily).toEqual([]);
    // Basic range is fixed to 7 days regardless of the request.
    expect(new Date(stats.to).getTime() - new Date(stats.from).getTime()).toBe(6 * DAY);

    await setFlags(ctx.http, admin, { listingTop: true });
    await priceAndActivate(ctx.http, admin, 'listing_top_3d', 12_000);
    await buy(ctx, seller, { productId: 'listing_top_3d', targetId: listingId });
    const promotions = await as(ctx.http, seller).get('/me/promotions').expect(200);
    const activation = promotions.body.data[0];
    expect(activation).toMatchObject({ kind: 'listingTop', status: 'active', targetId: listingId });
    const result = await as(ctx.http, seller).get(`/me/promotions/${activation.id}/stats`).expect(200);
    // A fresh listing has no equally long "before" period: no comparison is shown.
    expect(result.body.data.comparable).toBe(false);
    expect(result.body.data.before).toBeNull();
    expect(result.body.data.note).toMatch(/not predictions/);
    await as(ctx.http, viewer).get(`/me/promotions/${activation.id}/stats`).expect(404);
  });
});
