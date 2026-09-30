import request from 'supertest';

import { PrismaService } from '../src/infra/prisma.service';
import { as, signIn, startTestApp, stopTestApp, TestContext, TestUser } from './helpers';

describe('Businesses (free): profile, team, storefront, verification, stats', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let owner: TestUser;
  let admin: TestUser;
  let businessId: string;

  const business = {
    name: 'Chust Telefon Markazi',
    description: 'Yangi va ishlatilgan telefonlar, kafolat bilan.',
    categoryId: 'phones',
    regionId: 'namangan',
    districtId: 'chust',
    phone: '+998 90 123 45 67',
    telegram: '@chust_telefon',
  };

  beforeAll(async () => {
    ctx = await startTestApp();
    prisma = ctx.app.get(PrismaService);
    [owner, admin] = await Promise.all([signIn(ctx.http), signIn(ctx.http)]);
    await prisma.user.update({ where: { id: admin.userId }, data: { role: 'ADMIN' } });
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  it('anyone can open a business; one per person; nothing is self-verified', async () => {
    const created = await as(ctx.http, owner).post('/businesses', business).expect(201);
    businessId = created.body.data.id;
    expect(created.body.data).toMatchObject({ myRole: 'owner', verified: false, businessBadge: false });
    expect(created.body.data.plan).toBeUndefined();
    expect(created.body.data.shareUrl).toMatch(new RegExp(`/business/${businessId}$`));
    await as(ctx.http, owner)
      .post('/businesses', { ...business, name: 'Ikkinchi' })
      .expect(409);
  });

  it('the storefront is public without any plan', async () => {
    const page = await request(ctx.http).get(`/api/v1/businesses/${businessId}`).expect(200);
    expect(page.body.data).toMatchObject({ name: business.name });
    await request(ctx.http).get(`/api/v1/businesses/${businessId}/listings`).expect(200);
  });

  it('the owner manages a team up to the fair-use limit; managers cannot add people', async () => {
    const managers: TestUser[] = [];
    for (let i = 0; i < 5; i++) {
      const manager = await signIn(ctx.http);
      managers.push(manager);
      await as(ctx.http, owner).post('/me/business/members', { phone: manager.phone }).expect(201);
    }
    const sixth = await signIn(ctx.http);
    const blocked = await as(ctx.http, owner)
      .post('/me/business/members', { phone: sixth.phone })
      .expect(403);
    expect(blocked.body.error).toMatchObject({
      code: 'LIMIT_REACHED',
      details: { limit: 'managers', max: 5 },
    });
    await as(ctx.http, managers[0]).post('/me/business/members', { phone: sixth.phone }).expect(403);

    await as(ctx.http, owner).delete(`/me/business/members/${managers[0].userId}`).expect(200);
    await as(ctx.http, owner).post('/me/business/members', { phone: sixth.phone }).expect(201);
  });

  it('verification is admin-only and shows the badge', async () => {
    await as(ctx.http, owner).post('/me/business/verification').expect(200);
    await as(ctx.http, owner)
      .patch(`/admin/businesses/${businessId}/verification`, { verification: 'verified' })
      .expect(403);
    await as(ctx.http, admin)
      .patch(`/admin/businesses/${businessId}/verification`, { verification: 'verified' })
      .expect(200);
    const mine = await as(ctx.http, owner).get('/me/business').expect(200);
    expect(mine.body.data).toMatchObject({ verified: true, businessBadge: true });
    expect(
      await prisma.adminAuditLog.count({ where: { action: 'business.verification', entityId: businessId } }),
    ).toBe(1);
  });

  it('a suspended business disappears from the public', async () => {
    await as(ctx.http, admin)
      .patch(`/admin/businesses/${businessId}/status`, { status: 'suspended' })
      .expect(200);
    await request(ctx.http).get(`/api/v1/businesses/${businessId}`).expect(404);
  });

  it('removed payment and promotion endpoints are gone', async () => {
    for (const path of ['/config', '/catalog/plans', '/catalog/promotions', '/me/purchases', '/ads']) {
      await request(ctx.http).get(`/api/v1${path}`).expect(404);
    }
    await as(ctx.http, owner).post('/checkout', {}).expect(404);
  });
});
