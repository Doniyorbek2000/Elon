import { Currency } from '@prisma/client';

import { apiEnum } from '../../common/text';

/**
 * Money is always an integer count of minor units (tiyin for UZS, cents for
 * USD) held in BigInt. No floating point is used for amounts anywhere.
 */
export const MINOR_PER_MAJOR: Record<Currency, bigint> = { UZS: 100n, USD: 100n };

export function presentAmount(amountMinor: bigint, currency: Currency) {
  const per = MINOR_PER_MAJOR[currency];
  return {
    amountMinor: amountMinor.toString(),
    /** Whole major units; prices are validated to have no fractional part. */
    amount: Number(amountMinor / per),
    currency: apiEnum(currency),
  };
}

export function assertWholeMajor(amountMinor: bigint, currency: Currency): boolean {
  return amountMinor >= 0n && amountMinor % MINOR_PER_MAJOR[currency] === 0n;
}

/** Percentage discount rounded down to whole major units (never negative). */
export function percentOf(amountMinor: bigint, percent: bigint, currency: Currency): bigint {
  const per = MINOR_PER_MAJOR[currency];
  const raw = (amountMinor * percent) / 100n;
  return (raw / per) * per;
}
