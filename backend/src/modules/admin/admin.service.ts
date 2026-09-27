import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { AppError } from '../../common/errors';
import { PrismaService } from '../../infra/prisma.service';
import { SETTING_DEFAULTS, SettingKey } from '../monetization/config.service';

const PROVIDERS = ['DEV', 'PAYME', 'CLICK', 'APPLE', 'GOOGLE'];

/** Validates admin-edited settings against the shape of their defaults. */
export function validateSetting(key: string, value: Record<string, unknown>): Prisma.InputJsonValue {
  if (!(key in SETTING_DEFAULTS)) throw AppError.notFound('Setting');
  const defaults = SETTING_DEFAULTS[key as SettingKey] as Record<string, unknown>;
  const result: Record<string, unknown> = {};
  for (const [field, fallback] of Object.entries(defaults)) {
    const next = value[field] ?? fallback;
    if (typeof fallback === 'number') {
      if (!Number.isInteger(next) || (next as number) < 0 || (next as number) > 720) {
        throw AppError.validation(`${field} must be an integer 0..720`);
      }
    } else if (Array.isArray(fallback)) {
      if (
        !Array.isArray(next) ||
        next.some((v) => typeof v !== 'string' || !PROVIDERS.includes(v.toUpperCase()))
      ) {
        throw AppError.validation(`${field} must list known providers`);
      }
    }
    result[field] = Array.isArray(next) ? (next as string[]).map((v) => v.toUpperCase()) : next;
  }
  const unknown = Object.keys(value).filter((k) => !(k in defaults));
  if (unknown.length) throw AppError.validation(`Unknown fields: ${unknown.join(', ')}`);
  return result as Prisma.InputJsonValue;
}

interface RevenueRow {
  bucket: Date;
  currency: string;
  gross_minor: bigint;
  payments: bigint;
}

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  /** Every admin mutation is recorded with actor, entity and payload. */
  async audit(actorId: string, action: string, entity: string, entityId: string | null, data?: unknown) {
    await this.prisma.adminAuditLog.create({
      data: {
        actorId,
        action,
        entity,
        entityId,
        data:
          data === undefined
            ? undefined
            : (JSON.parse(
                JSON.stringify(data, (_k, v: unknown) => (typeof v === 'bigint' ? v.toString() : v)),
              ) as Prisma.InputJsonValue),
      },
    });
  }

  /**
   * Revenue report. Terminology is deliberate:
   * - grossPaymentVolume: money captured by successful payments (before refunds, before provider/store fees and taxes);
   * - refunds: money returned;
   * - netPaymentVolume: gross − refunds. This is NOT profit.
   * Credit- and coupon-settled purchases move no money and are counted separately.
   */
  async revenue(from: Date, to: Date, groupBy: 'day' | 'week' | 'month') {
    if (to <= from || to.getTime() - from.getTime() > 400 * 86400_000)
      throw AppError.validation('Invalid range');
    const money = Prisma.sql`p."provider" NOT IN ('CREDITS', 'FREE')`;
    const succeeded = Prisma.sql`p."status" IN ('SUCCEEDED', 'REFUNDED', 'PARTIALLY_REFUNDED') AND p."succeededAt" >= ${from} AND p."succeededAt" < ${to}`;
    const unit = Prisma.raw(`'${groupBy}'`);
    const [series, byProvider, byKind, refunds, counts, nonCash] = await Promise.all([
      this.prisma.$queryRaw<RevenueRow[]>`
        SELECT date_trunc(${unit}, p."succeededAt") AS bucket, p."currency"::text AS currency,
               SUM(p."amountMinor")::bigint AS gross_minor, COUNT(*)::bigint AS payments
        FROM "Payment" p WHERE ${money} AND ${succeeded}
        GROUP BY 1, 2 ORDER BY 1`,
      this.prisma.$queryRaw<
        Array<{ provider: string; currency: string; gross_minor: bigint; payments: bigint }>
      >`
        SELECT p."provider"::text AS provider, p."currency"::text AS currency, SUM(p."amountMinor")::bigint AS gross_minor, COUNT(*)::bigint AS payments
        FROM "Payment" p WHERE ${money} AND ${succeeded} GROUP BY 1, 2 ORDER BY 3 DESC`,
      this.prisma.$queryRaw<
        Array<{ product: string; currency: string; gross_minor: bigint; payments: bigint }>
      >`
        SELECT COALESCE(pp."kind"::text, 'SUBSCRIPTION:' || pl."planId") AS product, p."currency"::text AS currency,
               SUM(p."amountMinor")::bigint AS gross_minor, COUNT(*)::bigint AS payments
        FROM "Payment" p JOIN "Purchase" pu ON pu."id" = p."purchaseId"
        LEFT JOIN "PromotionProduct" pp ON pp."id" = pu."productId"
        LEFT JOIN "PlanPrice" pl ON pl."id" = pu."planPriceId"
        WHERE ${money} AND ${succeeded} GROUP BY 1, 2 ORDER BY 3 DESC`,
      this.prisma.$queryRaw<Array<{ currency: string; refunded_minor: bigint; refunds: bigint }>>`
        SELECT p."currency"::text AS currency, SUM(r."amountMinor")::bigint AS refunded_minor, COUNT(*)::bigint AS refunds
        FROM "Refund" r JOIN "Payment" p ON p."id" = r."paymentId"
        WHERE r."status" = 'SUCCEEDED' AND r."updatedAt" >= ${from} AND r."updatedAt" < ${to} AND ${money}
        GROUP BY 1`,
      this.prisma.$queryRaw<Array<{ status: string; n: bigint }>>`
        SELECT p."status"::text AS status, COUNT(*)::bigint AS n FROM "Payment" p
        WHERE ${money} AND p."createdAt" >= ${from} AND p."createdAt" < ${to} GROUP BY 1`,
      this.prisma.$queryRaw<Array<{ provider: string; n: bigint }>>`
        SELECT p."provider"::text AS provider, COUNT(*)::bigint AS n FROM "Payment" p
        WHERE p."provider" IN ('CREDITS', 'FREE') AND p."status" = 'SUCCEEDED' AND p."succeededAt" >= ${from} AND p."succeededAt" < ${to}
        GROUP BY 1`,
    ]);
    const currencies = new Set([...series.map((r) => r.currency), ...refunds.map((r) => r.currency)]);
    const totals = [...currencies].map((currency) => {
      const gross = series
        .filter((r) => r.currency === currency)
        .reduce((sum, r) => sum + BigInt(r.gross_minor), 0n);
      const refunded = refunds
        .filter((r) => r.currency === currency)
        .reduce((sum, r) => sum + BigInt(r.refunded_minor), 0n);
      return {
        currency: currency.toLowerCase(),
        grossPaymentVolumeMinor: gross.toString(),
        refundsMinor: refunded.toString(),
        netPaymentVolumeMinor: (gross - refunded).toString(),
      };
    });
    const count = (status: string) => Number(counts.find((c) => c.status === status)?.n ?? 0);
    return {
      from,
      to,
      groupBy,
      totals,
      payments: {
        successful: count('SUCCEEDED') + count('REFUNDED') + count('PARTIALLY_REFUNDED'),
        failed: count('FAILED'),
        cancelled: count('CANCELLED'),
        pending: count('PENDING') + count('CREATED'),
        refunds: refunds.reduce((sum, r) => sum + Number(r.refunds), 0),
      },
      nonCashSettlements: Object.fromEntries(nonCash.map((r) => [r.provider.toLowerCase(), Number(r.n)])),
      series: series.map((r) => ({
        bucket: r.bucket,
        currency: r.currency.toLowerCase(),
        grossPaymentVolumeMinor: BigInt(r.gross_minor).toString(),
        payments: Number(r.payments),
      })),
      byProvider: byProvider.map((r) => ({
        provider: r.provider.toLowerCase(),
        currency: r.currency.toLowerCase(),
        grossPaymentVolumeMinor: BigInt(r.gross_minor).toString(),
        payments: Number(r.payments),
      })),
      byProduct: byKind.map((r) => ({
        product: r.product,
        currency: r.currency.toLowerCase(),
        grossPaymentVolumeMinor: BigInt(r.gross_minor).toString(),
        payments: Number(r.payments),
      })),
      note: 'Gross/net payment volume before provider or store fees and taxes; not profit.',
    };
  }
}
