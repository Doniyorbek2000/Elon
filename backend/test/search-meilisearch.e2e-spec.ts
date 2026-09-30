import { resetEnvCache } from '../src/config/env';
import { PrismaService } from '../src/infra/prisma.service';
import { SEARCH_PROVIDER, SearchProvider } from '../src/modules/search/search.provider';
import {
  as,
  NAMANGAN_CHUST,
  signIn,
  startTestApp,
  stopTestApp,
  TestContext,
  TestUser,
  uploadReadyPhoto,
} from './helpers';

/**
 * Runs against a real Meilisearch (`TEST_MEILI_URL`, optional `TEST_MEILI_KEY`);
 * skipped when none is available so the default e2e run needs no extra service.
 */
const MEILI_URL = process.env.TEST_MEILI_URL;
const suite = MEILI_URL ? describe : describe.skip;

suite('Search: Meilisearch engine', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let provider: SearchProvider;
  let seller: TestUser;
  let buyer: TestUser;

  beforeAll(async () => {
    Object.assign(process.env, {
      SEARCH_PROVIDER: 'meilisearch',
      MEILI_URL,
      MEILI_API_KEY: process.env.TEST_MEILI_KEY ?? '',
      MEILI_INDEX_PREFIX: `e2e${Date.now()}`,
    });
    resetEnvCache();
    ctx = await startTestApp();
    prisma = ctx.app.get(PrismaService);
    provider = ctx.app.get<SearchProvider>(SEARCH_PROVIDER);
    [seller, buyer] = await Promise.all([signIn(ctx.http), signIn(ctx.http)]);
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  const SAMARKAND_URGUT = { regionId: 'samarkand', districtId: 'urgut' };

  async function post(user: TestUser, title: string, place = NAMANGAN_CHUST) {
    const photo = await uploadReadyPhoto(ctx.http, user);
    const res = await as(ctx.http, user)
      .post('/listings', {
        categoryId: 'phones',
        title,
        description: 'Holati yaxshi, qutisi va hujjatlari bilan birga.',
        price: { amount: 7_000_000, currency: 'uzs' },
        condition: 'used',
        attributes: { brand: 'Apple', memory: '128 GB' },
        place,
        mediaIds: [photo],
      })
      .expect(201);
    return res.body.data.id as string;
  }

  const ids = async (path: string, viewer = buyer) =>
    ((await as(ctx.http, viewer).get(path).expect(200)).body.data.listings as Array<{ id: string }>).map(
      (l) => l.id,
    );

  it('uses the Meilisearch provider and indexes only active content', async () => {
    expect(provider.name).toBe('meilisearch');
    const iphone = await post(seller, 'iPhone 13 Pro 128GB');
    // Not Tashkent: other suites assert on that region's feed and share the database.
    const samarkand = await post(seller, 'iPhone 12 mini', SAMARKAND_URGUT);
    const before = await provider.sync!();
    expect(before.indexed).toBeGreaterThanOrEqual(2);

    const found = await ids('/search?q=iphone&scope=listings');
    expect(found).toEqual(expect.arrayContaining([iphone, samarkand]));

    // Re-running is harmless: results do not change (the overlap window may re-apply the latest rows).
    await provider.sync!();
    expect(await ids('/search?q=iphone&scope=listings')).toEqual(expect.arrayContaining([iphone, samarkand]));
  });

  it('tolerates typos, Cyrillic and Uzbek spellings', async () => {
    const cobalt = await post(seller, 'Chevrolet Cobalt 2023 oq');
    await provider.sync!();
    expect(await ids('/search?q=cobolt&scope=listings')).toContain(cobalt);
    expect(await ids(`/search?q=${encodeURIComponent('кобалт')}&scope=listings`)).toContain(cobalt);
    expect(await ids('/search?q=chevrolet%202023&scope=listings')).toContain(cobalt);
    expect(await ids('/search?q=zzzzzzqq&scope=listings')).toEqual([]);
  });

  it('applies region filters', async () => {
    const chustOnly = await ids('/search?q=iphone&scope=listings&region=namangan');
    const samarkandOnly = await ids('/search?q=iphone&scope=listings&region=samarkand');
    expect(chustOnly.length).toBeGreaterThan(0);
    expect(samarkandOnly.length).toBeGreaterThan(0);
    expect(chustOnly.filter((id) => samarkandOnly.includes(id))).toEqual([]);
  });

  it('hides sellers the viewer blocked', async () => {
    const mine = await post(seller, 'Samsung Galaxy S24 Ultra');
    await provider.sync!();
    expect(await ids('/search?q=galaxy&scope=listings')).toContain(mine);
    await as(ctx.http, buyer).put(`/blocks/${seller.userId}`).expect(200);
    expect(await ids('/search?q=galaxy&scope=listings')).not.toContain(mine);
  });

  it('removes listings that stop being active', async () => {
    const other = await signIn(ctx.http);
    const gone = await post(other, 'Xiaomi Redmi Note 12');
    await provider.sync!();
    expect(await ids('/search?q=redmi&scope=listings')).toContain(gone);
    await as(ctx.http, other).post(`/listings/${gone}/status`, { status: 'archived' }).expect(200);
    const result = await provider.sync!();
    expect(result.removed).toBeGreaterThanOrEqual(1);
    expect(await ids('/search?q=redmi&scope=listings')).not.toContain(gone);
    expect(await prisma.listing.count({ where: { id: gone } })).toBe(1);
  });

  it('suggests titles', async () => {
    const titles = await provider.suggestTitles('iphon', 5);
    expect(titles.some((t) => t.toLowerCase().includes('iphone'))).toBe(true);
  });
});
