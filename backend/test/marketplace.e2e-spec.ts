import request from 'supertest';

import { StorageService } from '../src/infra/storage.service';
import { PrismaService } from '../src/infra/prisma.service';
import { as, clearOtpCooldown, NAMANGAN_CHUST, signIn, startTestApp, stopTestApp, TASHKENT_YUNUSOBOD, TestContext, TestUser, uploadReadyPhoto, waitFor } from './helpers';

describe('Marketplace: locations, listings, media, feed, favorites', () => {
  let ctx: TestContext;
  let seller: TestUser;
  let buyer: TestUser;
  let listingId: string;

  beforeAll(async () => {
    ctx = await startTestApp();
    [seller, buyer] = await Promise.all([signIn(ctx.http), signIn(ctx.http)]);
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  it('flow 1: login → choose location → feed respects the chosen area', async () => {
    const tree = await request(ctx.http).get('/api/v1/locations/tree').expect(200);
    expect(tree.body.data.length).toBe(14);
    const resolved = await request(ctx.http).get('/api/v1/locations/resolve?lat=41.0034&lng=71.2372').expect(200);
    expect(resolved.body.data).toEqual(expect.objectContaining({ regionId: 'namangan', districtId: 'chust' }));

    const me = await as(ctx.http, buyer).patch('/me', { preferredRegionId: 'namangan', preferredDistrictId: 'chust' }).expect(200);
    expect(me.body.data.preferredLocation.districtId).toBe('chust');
    // Hierarchy is validated server-side.
    await as(ctx.http, buyer).patch('/me', { preferredRegionId: 'namangan', preferredDistrictId: 'yunusobod' }).expect(422);

    const feed = await as(ctx.http, buyer).get('/listings?region=namangan&district=chust').expect(200);
    expect(Array.isArray(feed.body.data)).toBe(true);
  });

  it('serves server-driven category forms', async () => {
    const res = await request(ctx.http).get('/api/v1/categories?kind=marketplace').expect(200);
    const transport = res.body.data.find((c: { id: string }) => c.id === 'transport');
    const cars = transport.children.find((c: { id: string }) => c.id === 'cars');
    const keys = cars.schema.fields.map((f: { key: string }) => f.key);
    expect(keys).toEqual(expect.arrayContaining(['brand', 'model', 'year', 'mileage', 'transmission', 'fuel', 'color']));
    const types = new Set(cars.schema.fields.map((f: { type: string }) => f.type));
    expect(types).toEqual(new Set(['select', 'text', 'number', 'multiSelect', 'boolean']));
  });

  it('rejects unsupported uploads and strips metadata from renditions', async () => {
    const bad = await as(ctx.http, seller).upload(Buffer.from('%PDF-1.4 not an image'), 'listing', 'file.jpg');
    expect(bad.status).toBe(415);
    expect(bad.body.error.code).toBe('UNSUPPORTED_MEDIA');

    const mediaId = await uploadReadyPhoto(ctx.http, seller);
    const detail = await request(ctx.http).get(`/api/v1/media/${mediaId}/detail`).expect(200);
    expect(detail.headers['content-type']).toBe('image/webp');
    const sharp = (await import('sharp')).default;
    const meta = await sharp(detail.body as Buffer).metadata();
    expect(meta.exif).toBeUndefined();
    expect(meta.width).toBeLessThanOrEqual(1080);
  });

  it('marks media as failed when processing cannot succeed, and supports retry', async () => {
    const mediaId = await uploadReadyPhoto(ctx.http, seller);
    const prisma = ctx.app.get(PrismaService);
    const media = await prisma.media.findUniqueOrThrow({ where: { id: mediaId } });
    await as(ctx.http, seller).post(`/media/${mediaId}/retry`).expect(409); // only failed uploads

    // Corrupt the stored original, then retry: the worker must end in FAILED, never fake success.
    await prisma.media.update({ where: { id: mediaId }, data: { status: 'FAILED' } });
    await ctx.app.get(StorageService).put(media.originalKey, Buffer.from('corrupted bytes'), 'image/jpeg');
    const retried = await as(ctx.http, seller).post(`/media/${mediaId}/retry`).expect(200);
    expect(retried.body.data.status).toBe('processing');
    const failed = await waitFor(async () => {
      const res = await as(ctx.http, seller).get(`/media/${mediaId}`).expect(200);
      return res.body.data.status === 'failed' ? res.body.data : undefined;
    });
    expect(failed.failureReason).toBeTruthy();
    await as(ctx.http, buyer).post(`/media/${mediaId}/retry`).expect(404); // not the owner
  });

  it('flow 2: create listing with photos → appears in feed → another user opens it', async () => {
    const photos = [await uploadReadyPhoto(ctx.http, seller), await uploadReadyPhoto(ctx.http, seller)];
    const created = await as(ctx.http, seller)
      .post('/listings', {
        categoryId: 'cars',
        title: 'Chevrolet Cobalt 2021 oq rang',
        description: 'Yaxshi holatda, bir qo‘lda yurgan. Hujjatlari joyida.',
        price: { amount: 11500, currency: 'usd' },
        negotiable: true,
        condition: 'used',
        attributes: { brand: 'Chevrolet', model: 'Cobalt', year: 2021, mileage: 45000, transmission: 'Avtomat', options: ['Konditsioner'], credit: false },
        place: NAMANGAN_CHUST,
        mediaIds: photos,
      })
      .expect(201);
    listingId = created.body.data.id;
    expect(created.body.data.status).toBe('active');
    expect(created.body.data.images).toHaveLength(2);
    expect(created.body.data.images[0].id).toBe(photos[0]);

    const feed = await as(ctx.http, buyer).get('/listings?region=namangan&district=chust&category=transport').expect(200);
    expect(feed.body.data.map((l: { id: string }) => l.id)).toContain(listingId);

    const detail = await as(ctx.http, buyer).get(`/listings/${listingId}`).expect(200);
    expect(detail.body.data.attributes).toEqual(expect.arrayContaining([expect.objectContaining({ key: 'brand', value: 'Chevrolet' })]));
    expect(detail.body.data.seller.id).toBe(seller.userId);
    expect(detail.body.data.shareUrl).toContain(`/listing/${listingId}`);
    expect(detail.body.data.rejectReason).toBeUndefined();
  });

  it('validates dynamic attributes server-side', async () => {
    const res = await as(ctx.http, seller)
      .post('/listings', {
        categoryId: 'cars',
        title: 'Noto‘g‘ri e’lon',
        description: 'Atributlari noto‘g‘ri bo‘lgan e’lon matni.',
        price: { amount: 1000, currency: 'usd' },
        attributes: { brand: 'Ferrari-not-in-list', year: 1800, hacker: 'x' },
        place: NAMANGAN_CHUST,
        mediaIds: [],
        publish: false,
      })
      .expect(422);
    expect(Object.keys(res.body.error.details.fields)).toEqual(expect.arrayContaining(['brand', 'year', 'hacker']));
  });

  it('flow 8: feed respects area changes (Tashkent listing not in Chust feed)', async () => {
    const photo = await uploadReadyPhoto(ctx.http, seller);
    const tashkent = await as(ctx.http, seller)
      .post('/listings', {
        categoryId: 'phones',
        title: 'iPhone 13 128GB',
        description: 'Holati a’lo, qutisi bilan, zaryadlovchi bor.',
        price: { amount: 6500000, currency: 'uzs' },
        condition: 'used',
        attributes: { brand: 'Apple', memory: '128 GB' },
        place: TASHKENT_YUNUSOBOD,
        mediaIds: [photo],
      })
      .expect(201);
    const chust = await as(ctx.http, buyer).get('/listings?region=namangan&district=chust').expect(200);
    const chustIds = chust.body.data.map((l: { id: string }) => l.id);
    expect(chustIds).toContain(listingId);
    expect(chustIds).not.toContain(tashkent.body.data.id);

    const tashkentFeed = await as(ctx.http, buyer).get('/listings?region=tashkent_city').expect(200);
    expect(tashkentFeed.body.data.map((l: { id: string }) => l.id)).toEqual([tashkent.body.data.id]);

    // Nearby: 25 km around Chust centre includes Chust, excludes Tashkent.
    const nearby = await as(ctx.http, buyer).get('/listings?lat=41.0034&lng=71.2372&radius=25&sort=nearest').expect(200);
    const nearbyIds = nearby.body.data.map((l: { id: string }) => l.id);
    expect(nearbyIds).toContain(listingId);
    expect(nearbyIds).not.toContain(tashkent.body.data.id);
  });

  it('search tolerates Cyrillic and typos', async () => {
    const res = await as(ctx.http, buyer).get(`/search?q=${encodeURIComponent('кобалт')}&scope=listings`).expect(200);
    expect(res.body.data.listings.map((l: { id: string }) => l.id)).toContain(listingId);
    const typo = await as(ctx.http, buyer).get('/search?q=cobolt&scope=listings').expect(200);
    expect(typo.body.data.listings.map((l: { id: string }) => l.id)).toContain(listingId);
  });

  it('flow 3: favorite persists server-side across sessions', async () => {
    await as(ctx.http, buyer).put(`/favorites/listings/${listingId}`).expect(200);
    await as(ctx.http, buyer).put(`/favorites/listings/${listingId}`).expect(200); // idempotent
    await clearOtpCooldown(ctx, buyer.phone);
    const reader = await signIn(ctx.http, buyer.phone, 'buyer-second-device');
    const ids = await as(ctx.http, reader).get('/favorites/ids').expect(200);
    expect(ids.body.data.listings).toContain(listingId);
    const list = await as(ctx.http, reader).get('/favorites/listings').expect(200);
    expect(list.body.data[0]).toEqual(expect.objectContaining({ id: listingId, isFavorite: true }));
    const detail = await as(ctx.http, seller).get(`/listings/${listingId}`).expect(200);
    expect(detail.body.data.favorites).toBe(1);

    await as(ctx.http, buyer).delete(`/favorites/listings/${listingId}`).expect(200);
    const after = await as(ctx.http, buyer).get('/favorites/ids').expect(200);
    expect(after.body.data.listings).not.toContain(listingId);
  });

  it('flow 9: another user cannot modify, delete or change status of a listing', async () => {
    const intruder = as(ctx.http, buyer);
    await intruder.patch(`/listings/${listingId}`, { title: 'Hacked title here' }).expect(404);
    await intruder.post(`/listings/${listingId}/status`, { status: 'sold' }).expect(404);
    await intruder.delete(`/listings/${listingId}`).expect(404);
    await request(ctx.http).patch(`/api/v1/listings/${listingId}`).send({ title: 'Anonymous edit' }).expect(401);
    // Client-supplied owner fields are rejected, not trusted.
    await as(ctx.http, seller).patch(`/listings/${listingId}`, { sellerId: buyer.userId }).expect(422);
    // Media owned by someone else cannot be attached.
    const foreignPhoto = await uploadReadyPhoto(ctx.http, buyer);
    await as(ctx.http, seller).patch(`/listings/${listingId}`, { mediaIds: [foreignPhoto] }).expect(422);
    // Regular users cannot reach moderation.
    await as(ctx.http, seller).get('/moderation/listings').expect(403);
  });

  it('lifecycle: active → reserved → sold; sold listings leave the feed', async () => {
    await as(ctx.http, seller).post(`/listings/${listingId}/status`, { status: 'reserved' }).expect(200);
    await as(ctx.http, seller).post(`/listings/${listingId}/status`, { status: 'sold' }).expect(200);
    const invalid = await as(ctx.http, seller).post(`/listings/${listingId}/status`, { status: 'reserved' });
    expect(invalid.status).toBe(409);
    const feed = await as(ctx.http, buyer).get('/listings?region=namangan').expect(200);
    expect(feed.body.data.map((l: { id: string }) => l.id)).not.toContain(listingId);
    const mine = await as(ctx.http, seller).get('/me/listings?status=sold').expect(200);
    expect(mine.body.data.map((l: { id: string }) => l.id)).toContain(listingId);
  });

  it('cursor pagination returns disjoint pages', async () => {
    const photo = await uploadReadyPhoto(ctx.http, seller);
    for (let i = 0; i < 5; i++) {
      await as(ctx.http, seller)
        .post('/listings', {
          categoryId: 'furniture',
          title: `Divan to‘plami ${i + 1}`,
          description: 'Yumshoq mebel, yaxshi holatda, olib ketish kerak.',
          price: { amount: 1500000 + i * 1000, currency: 'uzs' },
          condition: 'used',
          place: NAMANGAN_CHUST,
          mediaIds: i === 0 ? [photo] : [await uploadReadyPhoto(ctx.http, seller)],
        })
        .expect(201);
    }
    const first = await as(ctx.http, buyer).get('/listings?category=home_goods&limit=2').expect(200);
    expect(first.body.data).toHaveLength(2);
    expect(first.body.meta.nextCursor).toBeTruthy();
    const second = await as(ctx.http, buyer).get(`/listings?category=home_goods&limit=2&cursor=${first.body.meta.nextCursor}`).expect(200);
    const ids = new Set([...first.body.data, ...second.body.data].map((l: { id: string }) => l.id));
    expect(ids.size).toBe(4);
    const priceSorted = await as(ctx.http, buyer).get('/listings?category=home_goods&sort=priceAsc&limit=50').expect(200);
    const prices = priceSorted.body.data.map((l: { price: { amount: number } }) => l.price.amount);
    expect(prices).toEqual([...prices].sort((a: number, b: number) => a - b));
    await as(ctx.http, buyer).get('/listings?cursor=not-a-real-cursor').expect(422);
  });
});
