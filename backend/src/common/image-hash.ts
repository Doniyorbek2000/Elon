import sharp from 'sharp';

/**
 * 64-bit difference hash (dHash): the image is reduced to a 9×8 grayscale
 * grid and each bit records whether a pixel is brighter than its right
 * neighbour. Re-encoding, resizing and mild edits change only a few bits, so
 * the Hamming distance between two hashes measures visual similarity.
 */
export async function dHash(image: Buffer): Promise<bigint> {
  const { data } = await sharp(image, { failOn: 'none' })
    .rotate()
    .grayscale()
    .resize(9, 8, { fit: 'fill', kernel: 'lanczos3' })
    .raw()
    .toBuffer({ resolveWithObject: true });
  let hash = 0n;
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      hash = (hash << 1n) | (data[row * 9 + col] > data[row * 9 + col + 1] ? 1n : 0n);
    }
  }
  return hash;
}

export function hammingDistance(a: bigint, b: bigint): number {
  let diff = a ^ b;
  let count = 0;
  while (diff) {
    count += Number(diff & 1n);
    diff >>= 1n;
  }
  return count;
}

/** Postgres BIGINT is signed; keep the bit pattern intact. */
export const toSigned = (hash: bigint): bigint => BigInt.asIntN(64, hash);
export const fromSigned = (value: bigint): bigint => BigInt.asUintN(64, value);

/**
 * Four 16-bit bands. Two hashes within Hamming distance ≤ 3 must share at
 * least one identical band (pigeonhole), so an indexed band lookup finds all
 * candidates without scanning every image.
 */
export function bands(hash: bigint): [number, number, number, number] {
  const part = (shift: bigint) => Number((hash >> shift) & 0xffffn);
  return [part(48n), part(32n), part(16n), part(0n)];
}

/** Flat or near-flat images (solid colour, blank screenshots) carry no signal. */
export function hasSignal(hash: bigint): boolean {
  const ones = hammingDistance(hash, 0n);
  return ones >= 8 && ones <= 56;
}

/** Maximum distance still treated as "the same photo". */
export const DUPLICATE_DISTANCE = 3;
