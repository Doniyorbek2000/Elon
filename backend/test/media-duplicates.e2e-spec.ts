import sharp from 'sharp';

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

/** Deterministic textured "photo"; different seeds give visually different images. */
async function photo(seed: number, options: { width?: number; quality?: number } = {}): Promise<Buffer> {
  const width = 640;
  const height = 480;
  const raw = Buffer.alloc(width * height * 3);
  let state = seed * 2654435761;
  const rand = () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 0xffffffff;
  };
  const blobs = Array.from({ length: 12 }, () => ({
    x: rand() * width,
    y: rand() * height,
    r: 40 + rand() * 120,
    c: [rand() * 255, rand() * 255, rand() * 255],
  }));
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 3;
      for (let ch = 0; ch < 3; ch++) raw[i + ch] = ((x / width) * 90 + (y / height) * 60 + ch * 20) % 256;
      for (const b of blobs) {
        if ((x - b.x) ** 2 + (y - b.y) ** 2 < b.r ** 2) for (let ch = 0; ch < 3; ch++) raw[i + ch] = b.c[ch];
      }
    }
  }
  let image = sharp(raw, { raw: { width, height, channels: 3 } });
  if (options.width) image = image.resize(options.width);
  return image.jpeg({ quality: options.quality ?? 90 }).toBuffer();
}

describe('Media: duplicate photo detection', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let original: TestUser;
  let thief: TestUser;
  let honest: TestUser;

  beforeAll(async () => {
    ctx = await startTestApp();
    prisma = ctx.app.get(PrismaService);
    [original, thief, honest] = await Promise.all([signIn(ctx.http), signIn(ctx.http), signIn(ctx.http)]);
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  async function upload(user: TestUser, image: Buffer): Promise<string> {
    const res = await as(ctx.http, user).upload(image, 'listing').expect(201);
    const id = res.body.data.id as string;
    await waitFor(async () => {
      const media = await as(ctx.http, user).get(`/media/${id}`).expect(200);
      if (media.body.data.status === 'failed') throw new Error('media failed');
      return media.body.data.status === 'ready';
    });
    return id;
  }

  const publish = async (user: TestUser, mediaId: string, title: string) => {
    const res = await as(ctx.http, user)
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
      .expect(201);
    return res.body.data as { id: string; status: string };
  };

  it('stores a perceptual hash for listing photos', async () => {
    const id = await upload(original, await photo(11));
    const media = await prisma.media.findUniqueOrThrow({ where: { id } });
    expect(media.imageHash).not.toBeNull();
    expect(media.hashBand0).not.toBeNull();
  });

  it('routes a re-encoded copy of another seller’s photo to moderation, but not the owner’s own', async () => {
    const first = await publish(original, await upload(original, await photo(21)), 'Samsung Galaxy A54');
    expect(first.status).toBe('active');

    // Same picture, smaller and recompressed, uploaded by someone else.
    const copy = await upload(thief, await photo(21, { width: 480, quality: 55 }));
    const stolen = await publish(thief, copy, 'Samsung Galaxy A54 arzon');
    expect(stolen.status).toBe('pendingReview');
    const row = await prisma.listing.findUniqueOrThrow({ where: { id: stolen.id } });
    expect(row.riskFlags).toContain('duplicate_image');

    // The original owner reusing their own picture is fine.
    const own = await upload(original, await photo(21, { width: 500, quality: 70 }));
    expect((await publish(original, own, 'Samsung Galaxy A54 (2)')).status).toBe('active');
  });

  it('does not flag unrelated photos', async () => {
    const other = await publish(honest, await upload(honest, await photo(99)), 'Samsung Galaxy S21');
    expect(other.status).toBe('active');
  });
});
