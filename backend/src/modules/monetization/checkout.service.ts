import { HttpStatus, Injectable } from '@nestjs/common';
import {
  Currency,
  PaymentProviderKey,
  PaymentStatus,
  Prisma,
  PromotionTarget,
  Purchase,
  PurchaseKind,
  PurchaseStatus,
  RedemptionStatus,
} from '@prisma/client';

import { AuthUser } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { Page, keysetPage, keysetWhere, pageSize } from '../../common/pagination';
import { apiEnum, dbEnum } from '../../common/text';
import { env } from '../../config/env';
import { PrismaService } from '../../infra/prisma.service';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { CatalogService, PricedProduct } from './catalog.service';
import { MonetizationConfig } from './config.service';
import { CouponsService } from './coupons.service';
import { CreditsService } from './credits.service';
import { CheckoutDto, QuoteDto } from './checkout.dto';
import { presentAmount } from './money';
import { PaymentsService } from './payments.service';
import { PromotionService } from './promotion.service';
import { CheckoutAction, ReceiptInvalid } from './providers/payment-provider';
import { PaymentProviderRegistry } from './providers/providers.registry';

interface Priced {
  kind: PurchaseKind;
  product?: PricedProduct;
  planPrice?: Prisma.PlanPriceGetPayload<{ include: { plan: true } }>;
  target?: PromotionTarget;
  targetId?: string;
  businessId?: string | null;
  listAmountMinor: bigint;
  currency: Currency;
}

@Injectable()
export class CheckoutService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly catalog: CatalogService,
    private readonly config: MonetizationConfig,
    private readonly coupons: CouponsService,
    private readonly credits: CreditsService,
    private readonly promotions: PromotionService,
    private readonly payments: PaymentsService,
    private readonly registry: PaymentProviderRegistry,
    private readonly limiter: RateLimiterService,
  ) {}

  /** Providers the client may use for this platform, per configured routes. */
  async routes(platform: string): Promise<PaymentProviderKey[]> {
    const routes = await this.config.setting('checkoutRoutes');
    const allowed = new Set(
      (routes[platform as keyof typeof routes] ?? []).map((k) => k.toUpperCase() as PaymentProviderKey),
    );
    const devAllowed = env().NODE_ENV !== 'production';
    const configured = this.registry.configuredKeys();
    return configured.filter((key) => allowed.has(key) || (key === PaymentProviderKey.DEV && devAllowed));
  }

  /** Resolves what is bought and its *server* price. Ownership is checked here. */
  private async price(
    user: AuthUser,
    input: { productId?: string; planPriceId?: string; targetId?: string },
  ): Promise<Priced> {
    if (!(await this.config.enabled('monetization'))) throw AppError.featureDisabled('monetization');
    if (!!input.productId === !!input.planPriceId)
      throw AppError.validation('Choose exactly one product or plan');
    if (input.planPriceId) {
      const planPrice = await this.catalog.sellablePlanPrice(input.planPriceId);
      if (!planPrice)
        throw new AppError(
          'PRICE_UNAVAILABLE',
          'This plan is not available',
          HttpStatus.UNPROCESSABLE_ENTITY,
        );
      const business = await this.prisma.business.findUnique({
        where: { ownerId: user.userId },
        select: { id: true },
      });
      return {
        kind: PurchaseKind.SUBSCRIPTION,
        planPrice,
        businessId: business?.id ?? null,
        listAmountMinor: planPrice.amountMinor,
        currency: planPrice.currency,
      };
    }
    const product = await this.catalog.sellableProduct(input.productId!);
    if (!product)
      throw new AppError(
        'PRICE_UNAVAILABLE',
        'This product is not available',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    if (!input.targetId) throw AppError.validation('targetId is required', { field: 'targetId' });
    if (product.kind === 'AD_CAMPAIGN') {
      const campaign = await this.prisma.adCampaign.findFirst({
        where: { id: input.targetId, business: { members: { some: { userId: user.userId } } } },
      });
      if (!campaign) throw AppError.notFound('Campaign');
      if (campaign.status !== 'DRAFT' && campaign.status !== 'AWAITING_PAYMENT')
        throw AppError.invalidState('Campaign is already paid');
    } else {
      const info = await this.promotions.targetInfo(product.target, input.targetId);
      // Someone else's content is indistinguishable from missing content.
      if (!info || info.ownerId !== user.userId) throw AppError.notFound('Target');
      if (!info.eligible) throw AppError.invalidState('Only active items can be promoted');
      if (product.kind === 'LISTING_BUMP') await this.promotions.assertBumpAllowed(info);
    }
    return {
      kind: PurchaseKind.PROMOTION,
      product,
      target: product.target,
      targetId: input.targetId,
      listAmountMinor: product.price.amountMinor,
      currency: product.price.currency,
    };
  }

  async quote(user: AuthUser, dto: QuoteDto) {
    const priced = await this.price(user, dto);
    let discountMinor = 0n;
    if (dto.couponCode) {
      await this.limiter.consume(`coupon:${user.userId}`, 20, 3600);
      discountMinor = (
        await this.coupons.evaluate(
          this.prisma,
          dto.couponCode,
          user.userId,
          { productId: priced.product?.id, planId: priced.planPrice?.planId },
          priced.listAmountMinor,
          priced.currency,
          false,
        )
      ).discountMinor;
    }
    const balance =
      (await this.prisma.creditAccount.findUnique({ where: { userId: user.userId } }))?.balance ?? 0;
    const creditCost = priced.product?.creditCost ?? null;
    const providers = (await this.routes(dto.platform)).map((k) => apiEnum(k));
    return {
      list: presentAmount(priced.listAmountMinor, priced.currency),
      discount: presentAmount(discountMinor, priced.currency),
      total: presentAmount(priced.listAmountMinor - discountMinor, priced.currency),
      providers,
      credits: {
        cost: creditCost,
        balance,
        usable:
          creditCost != null && balance >= creditCost && (await this.config.enabled('promotionCredits')),
      },
    };
  }

  async checkout(user: AuthUser, dto: CheckoutDto) {
    await this.limiter.consume(`checkout:${user.userId}`, 30, 3600);
    const existing = await this.prisma.purchase.findUnique({
      where: { userId_idempotencyKey: { userId: user.userId, idempotencyKey: dto.idempotencyKey } },
    });
    if (existing) return this.replay(existing, dto);

    const priced = await this.price(user, dto);
    const providerKey = dto.provider.toUpperCase() as PaymentProviderKey;
    if (providerKey === PaymentProviderKey.CREDITS) {
      if (!(await this.config.enabled('promotionCredits')) || priced.product?.creditCost == null) {
        throw new AppError(
          'PAYMENT_ROUTE_UNAVAILABLE',
          'Credits cannot be used for this product',
          HttpStatus.UNPROCESSABLE_ENTITY,
        );
      }
    } else if (providerKey !== PaymentProviderKey.FREE) {
      const allowed = await this.routes(dto.platform);
      if (!allowed.includes(providerKey)) {
        const provider = this.registry.get(providerKey);
        throw provider.configured()
          ? new AppError(
              'PAYMENT_ROUTE_UNAVAILABLE',
              'This payment method is not available here',
              HttpStatus.UNPROCESSABLE_ENTITY,
              {
                providers: allowed.map((k) => apiEnum(k)),
              },
            )
          : new AppError(
              'PROVIDER_NOT_CONFIGURED',
              'This payment method is not available',
              HttpStatus.SERVICE_UNAVAILABLE,
              {
                provider: dto.provider,
              },
            );
      }
    }

    const effects = this.payments.newEffects();
    let created: { purchase: Purchase; paymentId: string; settled: boolean };
    try {
      created = await this.prisma.$transaction(async (tx) => {
        let discountMinor = 0n;
        let couponId: string | undefined;
        if (dto.couponCode && providerKey !== PaymentProviderKey.CREDITS) {
          const evaluated = await this.coupons.evaluate(
            tx,
            dto.couponCode,
            user.userId,
            { productId: priced.product?.id, planId: priced.planPrice?.planId },
            priced.listAmountMinor,
            priced.currency,
            true,
          );
          discountMinor = evaluated.discountMinor;
          couponId = evaluated.coupon.id;
        }
        const credits = providerKey === PaymentProviderKey.CREDITS;
        const total = credits ? 0n : priced.listAmountMinor - discountMinor;
        if (providerKey === PaymentProviderKey.FREE && total !== 0n) {
          throw new AppError(
            'PAYMENT_ROUTE_UNAVAILABLE',
            'Payment is required',
            HttpStatus.UNPROCESSABLE_ENTITY,
          );
        }
        const settleNow = credits || total === 0n;
        const purchase = await tx.purchase.create({
          data: {
            userId: user.userId,
            businessId: priced.businessId ?? null,
            kind: priced.kind,
            productId: priced.product?.id,
            planPriceId: priced.planPrice?.id,
            target: priced.target,
            targetId: priced.targetId,
            listAmountMinor: credits ? 0n : priced.listAmountMinor,
            discountMinor: credits ? 0n : discountMinor,
            totalMinor: total,
            currency: priced.currency,
            creditsUsed: credits ? priced.product!.creditCost! : 0,
            couponId,
            platform: dto.platform,
            idempotencyKey: dto.idempotencyKey,
          },
        });
        if (couponId)
          await tx.couponRedemption.create({
            data: { couponId, userId: user.userId, purchaseId: purchase.id },
          });
        if (priced.product?.kind === 'AD_CAMPAIGN') {
          const { count } = await tx.adCampaign.updateMany({
            where: { id: priced.targetId!, status: { in: ['DRAFT', 'AWAITING_PAYMENT'] } },
            data: { status: 'AWAITING_PAYMENT', purchaseId: purchase.id },
          });
          if (!count) throw AppError.invalidState('Campaign is already paid');
        }
        const payment = await tx.payment.create({
          data: {
            purchaseId: purchase.id,
            provider: settleNow
              ? credits
                ? PaymentProviderKey.CREDITS
                : PaymentProviderKey.FREE
              : providerKey,
            amountMinor: total,
            currency: priced.currency,
          },
        });
        if (credits) {
          await this.credits.consume(
            tx,
            user.userId,
            purchase.creditsUsed,
            `Promotion ${priced.product!.id}`,
            {
              purchaseId: purchase.id,
            },
          );
        }
        if (settleNow) await this.payments.settleInternally(tx, payment, purchase, effects);
        return { purchase, paymentId: payment.id, settled: settleNow };
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const raced = await this.prisma.purchase.findUnique({
          where: { userId_idempotencyKey: { userId: user.userId, idempotencyKey: dto.idempotencyKey } },
        });
        if (raced) return this.replay(raced, dto);
      }
      throw error;
    }
    await this.payments.flush(effects);
    if (created.settled) return this.present(created.purchase.id, user.userId, { type: 'none' });

    const payment = await this.prisma.payment.findUniqueOrThrow({ where: { id: created.paymentId } });
    const provider = this.registry.get(payment.provider);
    const { action, externalId } = await provider.createCheckout(payment, created.purchase);
    await this.prisma.payment.updateMany({
      where: { id: payment.id, status: PaymentStatus.CREATED },
      data: { status: PaymentStatus.PENDING, externalId },
    });
    return this.present(created.purchase.id, user.userId, action);
  }

  /** Same idempotency key: same purchase, never a second charge. */
  private async replay(purchase: Purchase, dto: CheckoutDto) {
    const same =
      (purchase.productId ?? undefined) === dto.productId &&
      (purchase.planPriceId ?? undefined) === dto.planPriceId &&
      (purchase.targetId ?? undefined) === dto.targetId;
    if (!same) throw AppError.conflict('Idempotency key was used for a different purchase');
    let action: CheckoutAction = { type: 'none' };
    if (purchase.status === PurchaseStatus.AWAITING_PAYMENT) {
      const payment = await this.prisma.payment.findFirst({
        where: { purchaseId: purchase.id },
        orderBy: { createdAt: 'desc' },
      });
      if (payment && (payment.status === PaymentStatus.PENDING || payment.status === PaymentStatus.CREATED)) {
        const provider = this.registry.get(payment.provider);
        if (provider.configured()) action = (await provider.createCheckout(payment, purchase)).action;
      }
    }
    return this.present(purchase.id, purchase.userId, action);
  }

  // ─────────────────────────────────────────────────────── history

  async history(userId: string, cursor?: string, limit?: number) {
    const take = pageSize(limit);
    const rows = await this.prisma.purchase.findMany({
      where: { userId, ...keysetWhere(cursor) },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: take + 1,
      include: {
        product: true,
        planPrice: { include: { plan: true } },
        payments: { orderBy: { createdAt: 'desc' }, take: 1 },
      },
    });
    const page = keysetPage(rows, take, (r) => r.createdAt);
    return new Page(
      page.items.map((p) => CheckoutService.presentPurchase(p)),
      page.nextCursor,
    );
  }

  async present(purchaseId: string, userId: string, action?: CheckoutAction) {
    const purchase = await this.prisma.purchase.findFirst({
      where: { id: purchaseId, userId },
      include: {
        product: true,
        planPrice: { include: { plan: true } },
        payments: { orderBy: { createdAt: 'desc' }, include: { refunds: true } },
        activation: true,
      },
    });
    if (!purchase) throw AppError.notFound('Purchase');
    const subscription =
      purchase.kind === PurchaseKind.SUBSCRIPTION
        ? await this.prisma.subscription.findFirst({ where: { lastPurchaseId: purchase.id } })
        : null;
    return {
      ...CheckoutService.presentPurchase(purchase),
      payments: purchase.payments.map((p) => ({
        id: p.id,
        provider: apiEnum(p.provider),
        status: apiEnum(p.status),
        amount: presentAmount(p.amountMinor, p.currency),
        refunded: presentAmount(p.refundedMinor, p.currency),
        createdAt: p.createdAt,
        succeededAt: p.succeededAt,
        refunds: p.refunds.map((r) => ({
          id: r.id,
          status: apiEnum(r.status),
          amount: presentAmount(r.amountMinor, p.currency),
          createdAt: r.createdAt,
        })),
      })),
      activation: purchase.activation
        ? {
            id: purchase.activation.id,
            status: apiEnum(purchase.activation.status),
            startsAt: purchase.activation.startsAt,
            expiresAt: purchase.activation.expiresAt,
          }
        : null,
      subscription: subscription
        ? {
            id: subscription.id,
            status: apiEnum(subscription.status),
            currentPeriodEnd: subscription.currentPeriodEnd,
          }
        : null,
      ...(action ? { action } : {}),
    };
  }

  static presentPurchase(
    p: Prisma.PurchaseGetPayload<{
      include: { product: true; planPrice: { include: { plan: true } }; payments: true };
    }>,
  ) {
    const payment = p.payments[0];
    return {
      id: p.id,
      kind: apiEnum(p.kind),
      status: apiEnum(p.status),
      title:
        p.product?.title ?? (p.planPrice ? `${p.planPrice.plan.title} (${apiEnum(p.planPrice.period)})` : ''),
      productId: p.productId,
      planId: p.planPrice?.planId ?? null,
      target: p.target ? apiEnum(p.target) : null,
      targetId: p.targetId,
      list: presentAmount(p.listAmountMinor, p.currency),
      discount: presentAmount(p.discountMinor, p.currency),
      total: presentAmount(p.totalMinor, p.currency),
      creditsUsed: p.creditsUsed,
      paymentStatus: payment ? apiEnum(payment.status) : null,
      provider: payment ? apiEnum(payment.provider) : null,
      createdAt: p.createdAt,
      fulfilledAt: p.fulfilledAt,
    };
  }

  static targetFromParam(value: string): PromotionTarget {
    return dbEnum(value) as PromotionTarget;
  }

  /** Pending purchases the user abandoned can be cancelled by the user. */
  /**
   * Store billing (App Store / Google Play): the app reports the receipt of a
   * purchase it made for this payment. Nothing is activated until the store's
   * server API confirms it; a receipt that does not check out is rejected.
   */
  async submitStoreReceipt(userId: string, purchaseId: string, receipt: string) {
    const purchase = await this.prisma.purchase.findFirst({ where: { id: purchaseId, userId } });
    if (!purchase) throw AppError.notFound('Purchase');
    const payment = await this.prisma.payment.findFirst({
      where: { purchaseId, provider: { in: [PaymentProviderKey.APPLE, PaymentProviderKey.GOOGLE] } },
      orderBy: { createdAt: 'desc' },
    });
    if (!payment) throw AppError.invalidState('This purchase is not paid through a store');
    if (purchase.status === PurchaseStatus.FULFILLED) return this.present(purchaseId, userId);
    if (purchase.status !== PurchaseStatus.AWAITING_PAYMENT)
      throw AppError.invalidState('Purchase is not awaiting payment');
    const provider = this.registry.get(payment.provider);
    if (!provider.verifyReceipt) throw AppError.invalidState('This provider does not take receipts');
    await this.limiter.consume(`store-receipt:${userId}`, 20, 3600);
    let event;
    try {
      event = await provider.verifyReceipt(payment, purchase, receipt);
    } catch (error) {
      if (error instanceof ReceiptInvalid) {
        throw new AppError(
          'RECEIPT_INVALID',
          'The store did not confirm this purchase',
          HttpStatus.UNPROCESSABLE_ENTITY,
          {
            reason: error.reason,
          },
        );
      }
      throw error;
    }
    await this.payments.applyEvent(payment.provider, event, 'internal');
    return this.present(purchaseId, userId);
  }

  async cancel(userId: string, purchaseId: string) {
    const purchase = await this.prisma.purchase.findFirst({ where: { id: purchaseId, userId } });
    if (!purchase) throw AppError.notFound('Purchase');
    if (purchase.status !== PurchaseStatus.AWAITING_PAYMENT)
      throw AppError.invalidState('Purchase cannot be cancelled');
    const payment = await this.prisma.payment.findFirst({
      where: { purchaseId },
      orderBy: { createdAt: 'desc' },
    });
    if (payment) {
      await this.payments.applyEvent(
        payment.provider,
        {
          eventId: `user-cancel:${payment.id}`,
          paymentId: payment.id,
          type: 'cancelled',
          failureCode: 'user_cancelled',
        },
        'internal',
      );
    }
    await this.prisma.couponRedemption.updateMany({
      where: { purchaseId, status: RedemptionStatus.RESERVED },
      data: { status: RedemptionStatus.RELEASED },
    });
    return this.present(purchaseId, userId);
  }
}
