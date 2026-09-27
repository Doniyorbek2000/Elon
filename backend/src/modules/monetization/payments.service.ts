import { createHash } from 'node:crypto';

import { Injectable, Logger } from '@nestjs/common';
import {
  ActivationSource,
  AdStatus,
  NotificationType,
  Payment,
  PaymentProviderKey,
  PaymentStatus,
  Prisma,
  Purchase,
  PurchaseKind,
  PurchaseStatus,
  RedemptionStatus,
  RefundStatus,
} from '@prisma/client';

import { AppError } from '../../common/errors';
import { PrismaService } from '../../infra/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { CreditsService } from './credits.service';
import { PromotionService, routeFor } from './promotion.service';
import { ProviderEvent, WebhookRequest } from './providers/payment-provider';
import { PaymentProviderRegistry } from './providers/providers.registry';
import { SubscriptionsService } from './subscriptions.service';

type Tx = Prisma.TransactionClient;

export type EventSource = 'webhook' | 'reconciliation' | 'internal';

/** After-commit side effects collected during a transaction. */
interface Effects {
  notify: Array<{ userId: string; type: NotificationType; title: string; body: string; route: string; key: string; data: Record<string, string> }>;
  subscriptionChanged: Array<{ userId: string; businessId: string | null }>;
}

/**
 * Payment state machine. Only verified provider events (signed webhooks,
 * provider status lookups) or internal settlements (credits, free) move a
 * payment; nothing the client sends can. Every transition runs in a
 * transaction with the payment row locked, and fulfillment happens in the
 * same transaction as the SUCCEEDED transition, so activation is exactly-once.
 */
@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly registry: PaymentProviderRegistry,
    private readonly promotions: PromotionService,
    private readonly subscriptions: SubscriptionsService,
    private readonly credits: CreditsService,
    private readonly notifications: NotificationsService,
  ) {}

  // ─────────────────────────────────────────────────────── webhooks

  async handleWebhook(providerKey: PaymentProviderKey, request: WebhookRequest): Promise<unknown> {
    const provider = this.registry.get(providerKey);
    const events = await provider.parseWebhook(request); // throws on bad signature
    for (const event of events) await this.applyEvent(providerKey, event, 'webhook');
    return provider.webhookAck(events);
  }

  /** Idempotent: the same (provider, eventId) is applied at most once. */
  async applyEvent(providerKey: PaymentProviderKey, event: ProviderEvent, source: EventSource): Promise<string> {
    const effects: Effects = { notify: [], subscriptionChanged: [] };
    const payloadHash = createHash('sha256').update(JSON.stringify({ ...event, amountMinor: event.amountMinor?.toString() })).digest('hex');
    let outcome: string;
    try {
      outcome = await this.prisma.$transaction(
        async (tx) => {
          const recorded = await tx.paymentEvent.create({
            data: {
              provider: providerKey,
              eventId: event.eventId,
              source,
              type: event.type,
              payloadHash,
              outcome: 'processing',
            },
          });
          const result = await this.transition(tx, providerKey, event, effects);
          await tx.paymentEvent.update({
            where: { id: recorded.id },
            data: { outcome: result, paymentId: result.startsWith('ignored:unknown') ? null : event.paymentId },
          });
          return result;
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.ReadCommitted, timeout: 15_000 },
      );
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return 'ignored:duplicate_event'; // replayed webhook
      }
      throw error;
    }
    await this.runEffects(effects);
    return outcome;
  }

  private async lockPayment(tx: Tx, paymentId: string): Promise<Payment | null> {
    if (!/^[0-9a-f-]{36}$/i.test(paymentId)) return null;
    await tx.$queryRaw`SELECT 1 FROM "Payment" WHERE "id" = ${paymentId}::uuid FOR UPDATE`;
    return tx.payment.findUnique({ where: { id: paymentId } });
  }

  private async transition(tx: Tx, providerKey: PaymentProviderKey, event: ProviderEvent, effects: Effects): Promise<string> {
    const payment = await this.lockPayment(tx, event.paymentId);
    if (!payment || payment.provider !== providerKey) return 'ignored:unknown_payment';
    if (payment.externalId && event.externalId && payment.externalId !== event.externalId) {
      await tx.payment.update({ where: { id: payment.id }, data: { needsReview: true } });
      return 'ignored:external_id_mismatch';
    }
    if (event.amountMinor != null && event.amountMinor !== payment.amountMinor) {
      // Never fulfill when the provider reports a different amount.
      await tx.payment.update({ where: { id: payment.id }, data: { needsReview: true } });
      return 'ignored:amount_mismatch';
    }
    const purchase = await tx.purchase.findUniqueOrThrow({ where: { id: payment.purchaseId } });
    const from = payment.status;
    switch (event.type) {
      case 'pending':
        if (from !== PaymentStatus.CREATED) return `ignored:${from.toLowerCase()}_to_pending`;
        await tx.payment.update({ where: { id: payment.id }, data: { status: PaymentStatus.PENDING, externalId: payment.externalId ?? event.externalId } });
        return 'applied';
      case 'succeeded': {
        if (from === PaymentStatus.SUCCEEDED || from === PaymentStatus.REFUNDED || from === PaymentStatus.PARTIALLY_REFUNDED) {
          return 'ignored:already_succeeded';
        }
        const late = from === PaymentStatus.FAILED || from === PaymentStatus.CANCELLED;
        await tx.payment.update({
          where: { id: payment.id },
          data: {
            status: PaymentStatus.SUCCEEDED,
            succeededAt: new Date(),
            externalId: payment.externalId ?? event.externalId,
            needsReview: late ? true : payment.needsReview,
          },
        });
        await this.fulfill(tx, purchase, providerKey, effects);
        return late ? 'applied:late_success' : 'applied';
      }
      case 'failed':
      case 'cancelled': {
        if (from !== PaymentStatus.CREATED && from !== PaymentStatus.PENDING) return `ignored:${from.toLowerCase()}_to_${event.type}`;
        const status = event.type === 'failed' ? PaymentStatus.FAILED : PaymentStatus.CANCELLED;
        await tx.payment.update({ where: { id: payment.id }, data: { status, failureCode: event.failureCode } });
        await tx.purchase.update({
          where: { id: purchase.id },
          data: { status: event.type === 'failed' ? PurchaseStatus.FAILED : PurchaseStatus.CANCELLED, failureReason: event.failureCode },
        });
        await tx.couponRedemption.updateMany({
          where: { purchaseId: purchase.id, status: RedemptionStatus.RESERVED },
          data: { status: RedemptionStatus.RELEASED },
        });
        if (event.type === 'failed') {
          effects.notify.push({
            userId: purchase.userId,
            type: NotificationType.PAYMENT,
            title: 'To‘lov amalga oshmadi',
            body: 'Hech narsa faollashtirilmadi va hisobingizdan yechilmadi.',
            route: `/account/payments/${purchase.id}`,
            key: `pay-failed:${payment.id}`,
            data: { purchaseId: purchase.id },
          });
        }
        return 'applied';
      }
      case 'refunded':
        // Provider-initiated refunds are recorded via the refund flow for audit.
        await tx.payment.update({ where: { id: payment.id }, data: { needsReview: true } });
        return 'ignored:provider_refund_needs_review';
    }
  }

  // ─────────────────────────────────────────────────────── fulfillment

  /** Exactly-once: guarded by purchase status and unique activation.purchaseId. */
  async fulfill(tx: Tx, purchase: Purchase, providerKey: PaymentProviderKey, effects: Effects): Promise<void> {
    const fresh = await tx.purchase.findUniqueOrThrow({ where: { id: purchase.id } });
    if (fresh.status === PurchaseStatus.FULFILLED) return;
    await tx.couponRedemption.updateMany({ where: { purchaseId: purchase.id }, data: { status: RedemptionStatus.REDEEMED } });

    if (fresh.kind === PurchaseKind.SUBSCRIPTION) {
      const subscription = await this.subscriptions.applyPaidPeriod(tx, fresh, providerKey);
      await tx.purchase.update({ where: { id: fresh.id }, data: { status: PurchaseStatus.FULFILLED, fulfilledAt: new Date() } });
      effects.subscriptionChanged.push({ userId: fresh.userId, businessId: fresh.businessId });
      effects.notify.push({
        userId: fresh.userId,
        type: NotificationType.SUBSCRIPTION,
        title: 'Tarif faollashtirildi',
        body: `Amal qilish muddati: ${subscription.currentPeriodEnd.toISOString().slice(0, 10)} gacha.`,
        route: `/account/payments/${fresh.id}`,
        key: `sub-active:${fresh.id}`,
        data: { purchaseId: fresh.id },
      });
      return;
    }

    const product = await tx.promotionProduct.findUniqueOrThrow({ where: { id: fresh.productId! } });
    if (product.kind === 'AD_CAMPAIGN') {
      const { count } = await tx.adCampaign.updateMany({
        where: { id: fresh.targetId!, purchaseId: fresh.id, status: AdStatus.AWAITING_PAYMENT },
        data: { status: AdStatus.PENDING_REVIEW },
      });
      await tx.purchase.update({
        where: { id: fresh.id },
        data: count ? { status: PurchaseStatus.FULFILLED, fulfilledAt: new Date() } : { status: PurchaseStatus.NEEDS_REVIEW, failureReason: 'campaign_unavailable' },
      });
      return;
    }
    const info = await this.promotions.targetInfo(fresh.target!, fresh.targetId!, tx);
    if (!info || !info.eligible || info.ownerId !== fresh.userId) {
      // Paid but the listing/job/provider is gone or inactive: nothing is
      // activated; finance reviews and refunds.
      await tx.purchase.update({ where: { id: fresh.id }, data: { status: PurchaseStatus.NEEDS_REVIEW, failureReason: 'target_unavailable' } });
      await tx.payment.updateMany({ where: { purchaseId: fresh.id, status: PaymentStatus.SUCCEEDED }, data: { needsReview: true } });
      return;
    }
    const activation = await this.promotions.activate(tx, {
      product,
      targetId: fresh.targetId!,
      info,
      source: providerKey === PaymentProviderKey.CREDITS ? ActivationSource.CREDITS : ActivationSource.PURCHASE,
      purchaseId: fresh.id,
    });
    await tx.purchase.update({ where: { id: fresh.id }, data: { status: PurchaseStatus.FULFILLED, fulfilledAt: new Date() } });
    effects.notify.push({
      userId: fresh.userId,
      type: NotificationType.PROMOTION,
      title: `${product.title} faollashtirildi`,
      body: activation.expiresAt && activation.expiresAt > activation.startsAt
        ? `${activation.startsAt.toISOString().slice(0, 10)} — ${activation.expiresAt.toISOString().slice(0, 10)}`
        : 'E’lon ro‘yxat boshiga ko‘tarildi.',
      route: routeFor(activation.target, activation.targetId),
      key: `promo-active:${fresh.id}`,
      data: { purchaseId: fresh.id, activationId: activation.id },
    });
  }

  private async runEffects(effects: Effects) {
    for (const change of effects.subscriptionChanged) await this.subscriptions.afterChange(change.userId, change.businessId);
    for (const n of effects.notify) {
      await this.notifications
        .notify(n.userId, { type: n.type, title: n.title, body: n.body, route: n.route, data: n.data }, { dedupeKey: n.key })
        .catch((error: Error) => this.logger.warn(`notification failed: ${error.message}`));
    }
  }

  /** Internal settlement (credits / 100 % discount) — same exactly-once path. */
  async settleInternally(tx: Tx, payment: Payment, purchase: Purchase, effects: Effects): Promise<void> {
    await tx.paymentEvent.create({
      data: {
        provider: payment.provider,
        eventId: `internal:${payment.id}`,
        paymentId: payment.id,
        source: 'internal',
        type: 'succeeded',
        payloadHash: createHash('sha256').update(payment.id).digest('hex'),
        outcome: 'applied',
      },
    });
    await tx.payment.update({ where: { id: payment.id }, data: { status: PaymentStatus.SUCCEEDED, succeededAt: new Date() } });
    await this.fulfill(tx, purchase, payment.provider, effects);
  }

  newEffects(): Effects {
    return { notify: [], subscriptionChanged: [] };
  }

  async flush(effects: Effects) {
    await this.runEffects(effects);
  }

  // ─────────────────────────────────────────────────────── refunds

  /**
   * Refund eligibility is explicit per product type. Admin may override the
   * policy only with a written reason (audited by the controller).
   */
  static refundPolicy(input: { kind: PurchaseKind; productKind?: string; activationStartedAt?: Date | null; now: Date }): string | null {
    if (input.productKind === 'LISTING_BUMP') return 'Bumps take effect immediately and are not refundable';
    if (input.kind === PurchaseKind.PROMOTION && input.activationStartedAt) {
      const hours = (input.now.getTime() - input.activationStartedAt.getTime()) / 3600_000;
      if (hours > 24) return 'Promotion has been running for more than 24 hours';
    }
    return null;
  }

  async refund(input: { paymentId: string; amountMinor?: bigint; reason: string; actorId: string; overridePolicy: boolean }) {
    if (!input.reason.trim()) throw AppError.validation('Reason is required');
    const effects = this.newEffects();
    const result = await this.prisma.$transaction(async (tx) => {
      const payment = await this.lockPayment(tx, input.paymentId);
      if (!payment) throw AppError.notFound('Payment');
      if (payment.status !== PaymentStatus.SUCCEEDED && payment.status !== PaymentStatus.PARTIALLY_REFUNDED) {
        throw AppError.invalidState('Only successful payments can be refunded');
      }
      const refundable = payment.amountMinor - payment.refundedMinor;
      const amount = input.amountMinor ?? refundable;
      if (amount <= 0n || amount > refundable) throw AppError.validation('Invalid refund amount', { refundableMinor: refundable.toString() });
      const purchase = await tx.purchase.findUniqueOrThrow({
        where: { id: payment.purchaseId },
        include: { product: true, activation: true },
      });
      const policy = PaymentsService.refundPolicy({
        kind: purchase.kind,
        productKind: purchase.product?.kind,
        activationStartedAt: purchase.activation?.status === 'SCHEDULED' ? null : purchase.activation?.startsAt,
        now: new Date(),
      });
      if (policy && !input.overridePolicy) throw AppError.invalidState(`Not refundable: ${policy}`);

      let status: RefundStatus;
      let providerRefundId: string | undefined;
      if (payment.provider === PaymentProviderKey.CREDITS) {
        await this.credits.grant(tx, purchase.userId, purchase.creditsUsed, `Refund of ${purchase.id}`, {
          purchaseId: purchase.id,
          type: 'REFUND',
        });
        status = RefundStatus.SUCCEEDED;
      } else if (payment.provider === PaymentProviderKey.FREE) {
        status = RefundStatus.SUCCEEDED;
      } else {
        const provider = this.registry.get(payment.provider);
        if (provider.capabilities.refunds && provider.refund) {
          const res = await provider.refund(payment, amount);
          status = res.succeeded ? RefundStatus.SUCCEEDED : RefundStatus.FAILED;
          providerRefundId = res.providerRefundId;
        } else {
          // Money must be returned in the provider/store console; recorded for audit.
          status = RefundStatus.MANUAL_REQUIRED;
        }
      }
      const refund = await tx.refund.create({
        data: { paymentId: payment.id, amountMinor: amount, status, reason: input.reason, providerRefundId, requestedById: input.actorId },
      });
      if (status === RefundStatus.SUCCEEDED) await this.applyRefund(tx, payment, purchase, amount, effects);
      return refund;
    });
    await this.runEffects(effects);
    return result;
  }

  /** Marks a manual refund as completed (after money was returned outside). */
  async completeManualRefund(refundId: string) {
    const effects = this.newEffects();
    const refund = await this.prisma.$transaction(async (tx) => {
      const refund = await tx.refund.findUnique({ where: { id: refundId } });
      if (!refund || refund.status !== RefundStatus.MANUAL_REQUIRED) throw AppError.invalidState('Refund is not awaiting manual completion');
      const payment = await this.lockPayment(tx, refund.paymentId);
      const purchase = await tx.purchase.findUniqueOrThrow({ where: { id: payment!.purchaseId }, include: { activation: true } });
      await this.applyRefund(tx, payment!, purchase, refund.amountMinor, effects);
      return tx.refund.update({ where: { id: refund.id }, data: { status: RefundStatus.SUCCEEDED } });
    });
    await this.runEffects(effects);
    return refund;
  }

  private async applyRefund(
    tx: Tx,
    payment: Payment,
    purchase: Purchase & { activation: { id: string } | null },
    amount: bigint,
    effects: Effects,
  ) {
    const refunded = payment.refundedMinor + amount;
    const full = refunded >= payment.amountMinor;
    await tx.payment.update({
      where: { id: payment.id },
      data: { refundedMinor: refunded, status: full ? PaymentStatus.REFUNDED : PaymentStatus.PARTIALLY_REFUNDED },
    });
    if (!full) return;
    await tx.purchase.update({ where: { id: purchase.id }, data: { status: PurchaseStatus.REFUNDED } });
    if (purchase.activation) await this.promotions.cancel(tx, purchase.activation.id);
    if (purchase.kind === PurchaseKind.SUBSCRIPTION) {
      const subscription = await tx.subscription.findFirst({ where: { lastPurchaseId: purchase.id } });
      if (subscription) {
        await this.subscriptions.revoke(tx, subscription.id, `Refund of ${purchase.id}`);
        effects.subscriptionChanged.push({ userId: subscription.userId, businessId: subscription.businessId });
      }
    }
    await tx.adCampaign.updateMany({ where: { purchaseId: purchase.id }, data: { status: AdStatus.ENDED } });
    effects.notify.push({
      userId: purchase.userId,
      type: NotificationType.PAYMENT,
      title: 'To‘lov qaytarildi',
      body: 'Xarid bekor qilindi va mablag‘ qaytarildi.',
      route: `/account/payments/${purchase.id}`,
      key: `refund:${payment.id}:${refunded.toString()}`,
      data: { purchaseId: purchase.id },
    });
  }

  // ─────────────────────────────────────────────────────── reconciliation

  /**
   * Compares our state with the provider's for payments stuck in
   * CREATED/PENDING (missed or delayed webhooks) and abandons stale ones.
   */
  async reconcile(now = new Date()): Promise<{ checked: number; applied: number; abandoned: number }> {
    const stuck = await this.prisma.payment.findMany({
      where: { status: { in: [PaymentStatus.CREATED, PaymentStatus.PENDING] }, createdAt: { lte: new Date(now.getTime() - 5 * 60_000) } },
      take: 200,
    });
    let applied = 0;
    let abandoned = 0;
    for (const payment of stuck) {
      const provider = this.registry.get(payment.provider);
      if (provider.configured() && provider.capabilities.statusLookup && provider.fetchStatus) {
        const event = await provider.fetchStatus(payment).catch(() => null);
        if (event && (await this.applyEvent(payment.provider, event, 'reconciliation')).startsWith('applied')) {
          applied++;
          continue;
        }
      }
      if (payment.createdAt <= new Date(now.getTime() - 24 * 3600_000)) {
        const outcome = await this.applyEvent(
          payment.provider,
          { eventId: `abandon:${payment.id}`, paymentId: payment.id, type: 'cancelled', failureCode: 'abandoned' },
          'reconciliation',
        );
        if (outcome.startsWith('applied')) abandoned++;
      }
    }
    return { checked: stuck.length, applied, abandoned };
  }
}
