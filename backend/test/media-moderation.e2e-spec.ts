import { createServer, Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import sharp from 'sharp';

import { resetEnvCache } from '../src/config/env';
import { PrismaService } from '../src/infra/prisma.service';
import {
  as,
  snapshotEnv,
  jpeg,
  NAMANGAN_CHUST,
  signIn,
  startTestApp,
  stopTestApp,
  TestContext,
  TestUser,
  waitFor,
} from './helpers';

/**
 * A stand-in for the Sightengine API: reads the uploaded picture and answers
 * by its dominant colour (red = explicit, green = borderline, blue = provider
 * outage, anything else = clean) and records what the client sent.
 */
function startFakeSightengine() {
  const requests: Array<{ fields: Record<string, string>; bytes: number }> = [];
  const server: Server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (c: Buffer) => chunks.push(c));
    req.on('end', () => {
      void (async () => {
        const body = Buffer.concat(chunks);
        const boundary = /boundary=(.+)$/.exec(req.headers['content-type'] ?? '')?.[1] ?? '';
        const fields: Record<string, string> = {};
        let image = Buffer.alloc(0);
        for (const part of body.toString('latin1').split(`--${boundary}`)) {
          const name = /name="([^"]+)"/.exec(part)?.[1];
          if (!name) continue;
          const start = part.indexOf('\r\n\r\n') + 4;
          const start8 = Buffer.byteLength(part.slice(0, start), 'latin1');
          const offset = body.indexOf(Buffer.from(part.slice(0, start), 'latin1'));
          if (name === 'media')
            image = body.subarray(offset + start8, offset + Buffer.byteLength(part, 'latin1') - 2);
          else fields[name] = part.slice(start).replace(/\r\n$/, '');
        }
        requests.push({ fields, bytes: image.length });
        const { dominant } = await sharp(image).stats();
        res.setHeader('Content-Type', 'application/json');
        if (dominant.b > 200 && dominant.r < 60) {
          res.statusCode = 503;
          res.end('{}');
        } else if (dominant.r > 180 && dominant.g < 90) {
          res.end(
            JSON.stringify({ status: 'success', nudity: { sexual_activity: 0.97 }, gore: { prob: 0 } }),
          );
        } else if (dominant.g > 180 && dominant.r < 90) {
          res.end(JSON.stringify({ status: 'success', nudity: { sexual_display: 0.65 }, gore: { prob: 0 } }));
        } else {
          res.end(
            JSON.stringify({ status: 'success', nudity: { sexual_activity: 0.01 }, gore: { prob: 0 } }),
          );
        }
      })();
    });
  });
  return new Promise<{ url: string; requests: typeof requests; close: () => Promise<void> }>((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address() as AddressInfo;
      resolve({
        url: `http://127.0.0.1:${port}/1.0/check.json`,
        requests,
        close: () => new Promise((done) => server.close(() => done())),
      });
    });
  });
}

describe('Media: automated content moderation', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let user: TestUser;
  let fake: Awaited<ReturnType<typeof startFakeSightengine>>;

  let restoreEnv: () => void;

  beforeAll(async () => {
    fake = await startFakeSightengine();
    restoreEnv = snapshotEnv();
    Object.assign(process.env, {
      IMAGE_MODERATION_PROVIDER: 'sightengine',
      SIGHTENGINE_USER: 'test-user',
      SIGHTENGINE_SECRET: 'test-secret',
      SIGHTENGINE_URL: fake.url,
    });
    resetEnvCache();
    ctx = await startTestApp();
    prisma = ctx.app.get(PrismaService);
    user = await signIn(ctx.http);
  });

  afterAll(async () => {
    await stopTestApp(ctx);
    restoreEnv();
    await fake.close();
  });

  async function upload(color: { r: number; g: number; b: number }) {
    const res = await as(ctx.http, user)
      .upload(await jpeg(800, 600, color), 'listing')
      .expect(201);
    const id = res.body.data.id as string;
    await waitFor(async () => {
      const media = await prisma.media.findUniqueOrThrow({ where: { id } });
      return media.status !== 'PROCESSING' ? media : null;
    });
    return prisma.media.findUniqueOrThrow({ where: { id } });
  }

  const publish = async (mediaId: string, title: string) =>
    (
      await as(ctx.http, user)
        .post('/listings', {
          categoryId: 'phones',
          title,
          description: 'Holati yaxshi, qutisi va hujjatlari bilan birga.',
          price: { amount: 7_000_000, currency: 'uzs' },
          condition: 'used',
          attributes: { brand: 'Samsung' },
          place: NAMANGAN_CHUST,
          mediaIds: [mediaId],
        })
        .expect(201)
    ).body.data as { id: string; status: string };

  it('sends credentials and the models we rely on, with a compressed picture', async () => {
    await upload({ r: 90, g: 90, b: 90 });
    const sent = fake.requests.at(-1)!;
    expect(sent.fields).toMatchObject({
      api_user: 'test-user',
      api_secret: 'test-secret',
      models: 'nudity-2.1,gore-2.0,offensive',
    });
    expect(sent.bytes).toBeGreaterThan(100);
  });

  it('clean photos publish immediately', async () => {
    const media = await upload({ r: 90, g: 90, b: 90 });
    expect(media).toMatchObject({ status: 'READY', moderation: 'CLEAN' });
    expect((await publish(media.id, 'Samsung Galaxy A34')).status).toBe('active');
  });

  it('explicit photos are rejected and cannot be attached', async () => {
    const media = await upload({ r: 230, g: 40, b: 40 });
    expect(media).toMatchObject({ status: 'FAILED', failureReason: 'content_policy', moderation: 'BLOCKED' });
    expect(media.moderationLabels).toContain('sexual_activity');
    await as(ctx.http, user)
      .post('/listings', {
        categoryId: 'phones',
        title: 'Samsung Galaxy A35',
        description: 'Holati yaxshi, qutisi va hujjatlari bilan birga.',
        price: { amount: 7_000_000, currency: 'uzs' },
        condition: 'used',
        attributes: { brand: 'Samsung' },
        place: NAMANGAN_CHUST,
        mediaIds: [media.id],
      })
      .expect(422);
  });

  it('borderline photos go to human review', async () => {
    const media = await upload({ r: 40, g: 230, b: 40 });
    expect(media).toMatchObject({ status: 'READY', moderation: 'REVIEW' });
    const listing = await publish(media.id, 'Samsung Galaxy A36');
    expect(listing.status).toBe('pendingReview');
    const row = await prisma.listing.findUniqueOrThrow({ where: { id: listing.id } });
    expect(row.riskFlags).toContain('image_review');
  });

  it('a provider outage never blocks uploads but forces review', async () => {
    const media = await upload({ r: 30, g: 30, b: 235 });
    expect(media).toMatchObject({ status: 'READY', moderation: 'UNCHECKED' });
    const listing = await publish(media.id, 'Samsung Galaxy A37');
    expect(listing.status).toBe('pendingReview');
    expect((await prisma.listing.findUniqueOrThrow({ where: { id: listing.id } })).riskFlags).toContain(
      'image_unchecked',
    );
  });
});
