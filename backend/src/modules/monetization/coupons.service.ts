import { HttpStatus, Injectable } from '@nestjs/common';
import { Coupon, CouponDiscountType, Currency, Prisma, RedemptionStatus } from '@prisma/client';

import { AppError } from '../../common/errors';
import { MonetizationConfig } from './config.service';
import { percentOf } from './money';

type Tx = Prisma.TransactionClient;

/** One generic message: we do not reveal which rule a code failed. */
const invalid = () => new AppError('COUPON_INVALID', 'Promo kod yaroqsiz', HttpStatus.UNPROCESSABLE_ENTITY);

export interface CouponScope {
  productId?: string;
  planId?: string;
}

@Injectable()
export class CouponsService {
  constructor(private readonly config: MonetizationConfig) {}

  static normalize(code: string): string {
    return code.trim().toUpperCase();
  }

  /**
   * Validates a code and computes the discount. With `lock`, the coupon row
   * is locked so limit checks and the reservation are atomic under
   * concurrency (call inside the purchase transaction).
   */
  async evaluate(
    tx: Tx,
    rawCode: string,
    userId: string,
    scope: CouponScope,
    listAmountMinor: bigint,
    currency: Currency,
    lock: boolean,
  ): Promise<{ coupon: Coupon; discountMinor: bigint }> {
    if (!(await this.config.enabled('coupons'))) throw invalid();
    const code = CouponsService.normalize(rawCode);
    if (!/^[A-Z0-9_-]{3,32}$/.test(code)) throw invalid();
    const found = await tx.coupon.findUnique({ where: { code } });
    if (!found) throw invalid();
    if (lock) await tx.$queryRaw`SELECT 1 FROM "Coupon" WHERE "id" = ${found.id}::uuid FOR UPDATE`;
    const coupon = lock ? await tx.coupon.findUniqueOrThrow({ where: { id: found.id } }) : found;
    const now = new Date();
    if (!coupon.active || coupon.validFrom > now || (coupon.validUntil && coupon.validUntil <= now))
      throw invalid();
    const applies =
      (scope.productId &&
        (coupon.productIds.length === 0
          ? coupon.planIds.length === 0
          : coupon.productIds.includes(scope.productId))) ||
      (scope.planId &&
        (coupon.planIds.length === 0
          ? coupon.productIds.length === 0
          : coupon.planIds.includes(scope.planId)));
    if (!applies) throw invalid();
    const live = [RedemptionStatus.RESERVED, RedemptionStatus.REDEEMED];
    const [total, mine] = await Promise.all([
      tx.couponRedemption.count({ where: { couponId: coupon.id, status: { in: live } } }),
      tx.couponRedemption.count({ where: { couponId: coupon.id, userId, status: { in: live } } }),
    ]);
    if (coupon.maxRedemptions != null && total >= coupon.maxRedemptions) throw invalid();
    if (mine >= coupon.perUserLimit) throw invalid();
    let discountMinor: bigint;
    if (coupon.discountType === CouponDiscountType.PERCENT) {
      discountMinor = percentOf(listAmountMinor, coupon.value, currency);
    } else {
      if (coupon.currency && coupon.currency !== currency) throw invalid();
      discountMinor = coupon.value > listAmountMinor ? listAmountMinor : coupon.value;
    }
    return { coupon, discountMinor };
  }
}
