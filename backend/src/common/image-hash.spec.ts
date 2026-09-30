import sharp from 'sharp';

import {
  bands,
  dHash,
  DUPLICATE_DISTANCE,
  fromSigned,
  hammingDistance,
  hasSignal,
  toSigned,
} from './image-hash';

/** Deterministic pseudo-photo: smooth gradients plus seeded blobs. */
async function photo(seed: number, width = 640, height = 480): Promise<Buffer> {
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
  return sharp(raw, { raw: { width, height, channels: 3 } })
    .jpeg({ quality: 90 })
    .toBuffer();
}

describe('image perceptual hash', () => {
  it('treats re-encoded, resized and watermark-free copies as the same photo', async () => {
    const original = await photo(7);
    const hash = await dHash(original);
    const smaller = await sharp(original).resize(320).jpeg({ quality: 60 }).toBuffer();
    const recompressed = await sharp(original).webp({ quality: 40 }).toBuffer();
    const brighter = await sharp(original).modulate({ brightness: 1.1 }).jpeg().toBuffer();
    for (const copy of [smaller, recompressed, brighter]) {
      expect(hammingDistance(hash, await dHash(copy))).toBeLessThanOrEqual(DUPLICATE_DISTANCE);
    }
  });

  it('keeps different photos far apart', async () => {
    const base = await dHash(await photo(1));
    for (const seed of [2, 3, 4, 5, 6]) {
      expect(hammingDistance(base, await dHash(await photo(seed)))).toBeGreaterThan(DUPLICATE_DISTANCE);
    }
  });

  it('ignores flat images that carry no signal', async () => {
    const flat = await sharp({ create: { width: 200, height: 200, channels: 3, background: '#c83c28' } })
      .jpeg()
      .toBuffer();
    expect(hasSignal(await dHash(flat))).toBe(false);
    expect(hasSignal(await dHash(await photo(9)))).toBe(true);
  });

  it('round-trips through signed storage and finds near copies through bands', () => {
    const hash = 0xf0f0_1234_abcd_9876n;
    expect(fromSigned(toSigned(hash))).toBe(hash);
    expect(toSigned(hash)).toBeLessThan(0n);
    // Flip three bits: at least one 16-bit band must still match exactly.
    const near = hash ^ ((1n << 3n) | (1n << 20n) | (1n << 40n));
    expect(hammingDistance(hash, near)).toBe(3);
    const a = bands(hash);
    const b = bands(near);
    expect(a.some((band, i) => band === b[i])).toBe(true);
  });
});
