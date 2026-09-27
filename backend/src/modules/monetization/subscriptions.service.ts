import { Injectable } from '@nestjs/common';
import {
  BillingPeriod,
  NotificationType,
  PaymentProviderKey,
  Prisma,
  Purchase,
  Subscription,
  SubscriptionStatus,
} from '@prisma/client';

import { AppError } from '../../common/errors';
import { apiEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { presentEntitlements } from './catalog.service';
import { MonetizationConfig } from './config.service';
import { CreditsService } from './credits.service';
import { EntitlementService } from './entitlements.service';

type Tx = Prisma.TransactionClient;

const LIVE: SubscriptionStatus[] = [SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE_PERIOD];

/** Calendar period in UTC, clamped to month end (Jan 31 + 1 month = Feb 28/29). */
export function addPeriod(from: Date, period: BillingPeriod): Date {
  const months = period === BillingPeriod.MONTH ? 1 : 12;
  const next = new Date(from);
  const day = next.getUTCDate();
  next.setUTCDate(1);
  next.setUTCMonth(next.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0)).getUTCDate();
  next.setUTCDate(Math.min(day, lastDay));
  return next;
}

/**
 * Subscription state is server-side and authoritative. With one-off payment
 * providers (Payme/Click/dev) a paid period extends the subscription; nothing
 * renews silently. Store auto-renewing subscriptions will report renewals
 * through their provider adapters (not configured yet).
 */
@Injectable()
export class SubscriptionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly credits: CreditsService,
    private readonly entitlements: EntitlementService,
    private readonly notifications: NotificationsService,
    private readonly config: MonetizationConfig,
  ) {}

  /** Called inside the fulfillment transaction of a verified payment. */
  async applyPaidPeriod(
    tx: Tx,
    purchase: Purchase,
    provider: PaymentProviderKey,
    now = new Date(),
  ): Promise<Subscription> {
    if (!purchase.planPriceId) throw new Error('Subscription purchase without plan price');
    const price = await tx.planPrice.findUniqueOrThrow({
      where: { id: purchase.planPriceId },
      include: { plan: true },
    });
    const current = await tx.subscription.findFirst({
      where: { userId: purchase.userId, businessId: purchase.businessId, status: { in: LIVE } },
      orderBy: { currentPeriodEnd: 'desc' },
    });
    let subscription: Subscription;
    if (current && current.planId === price.planId) {
      // Renewal: the new period starts when the current one ends (no lost days).
      const start = current.currentPeriodEnd > now ? current.currentPeriodEnd : now;
      subscription = await tx.subscription.update({
        where: { id: current.id },
        data: {
          status: SubscriptionStatus.ACTIVE,
          currentPeriodEnd: addPeriod(start, price.period),
          graceUntil: null,
          cancelAtPeriodEnd: false,
          cancelledAt: null,
          lastPurchaseId: purchase.id,
          expiringNotifiedAt: null,
          provider,
        },
      });
    } else {
      if (current) {
        // Plan change: the old plan ends now (no proration in this phase).
        await tx.subscription.update({
          where: { id: current.id },
          data: { status: SubscriptionStatus.CANCELLED, cancelledAt: now },
        });
      }
      subscription = await tx.subscription.create({
        data: {
          userId: purchase.userId,
          businessId: purchase.businessId,
          planId: price.planId,
          provider,
          status: SubscriptionStatus.ACTIVE,
          currentPeriodStart: now,
          currentPeriodEnd: addPeriod(now, price.period),
          lastPurchaseId: purchase.id,
        },
      });
    }
    const months = price.period === BillingPeriod.MONTH ? 1 : 12;
    const grant = price.plan.monthlyPromotionCredits * months;
    if (grant > 0) {
      await this.credits.grant(tx, purchase.userId, grant, `${price.plan.title}: promotion credits`, {
        subscriptionId: subscription.id,
        purchaseId: purchase.id,
        expiresAt: subscription.currentPeriodEnd,
      });
    }
    return subscription;
  }

  async afterChange(userId: string, businessId: string | null) {
    await this.entitlements.invalidate([userId]);
    if (businessId) await this.entitlements.invalidateBusiness(businessId);
  }

  /** Stops renewal reminders; access continues to the end of the paid period. */
  async cancel(userId: string, subscriptionId: string) {
    const subscription = await this.prisma.subscription.findFirst({ where: { id: subscriptionId, userId } });
    if (!subscription) throw AppError.notFound('Subscription');
    if (!LIVE.includes(subscription.status)) throw AppError.invalidState('Subscription is not active');
    if (
      subscription.provider === PaymentProviderKey.APPLE ||
      subscription.provider === PaymentProviderKey.GOOGLE
    ) {
      throw AppError.invalidState(
        'Store subscriptions are cancelled in the App Store / Google Play settings',
      );
    }
    const updated = await this.prisma.subscription.update({
      where: { id: subscription.id },
      data: { cancelAtPeriodEnd: true, cancelledAt: new Date() },
      include: { plan: true },
    });
    return SubscriptionsService.present(updated);
  }

  /** Revocation after a full refund (inside the refund transaction). */
  async revoke(tx: Tx, subscriptionId: string, reason: string) {
    const subscription = await tx.subscription.update({
      where: { id: subscriptionId },
      data: { status: SubscriptionStatus.CANCELLED, cancelledAt: new Date() },
    });
    await this.credits.revokeSubscriptionGrants(tx, subscription.userId, subscription.id, reason);
    return subscription;
  }

  async mine(userId: string) {
    const rows = await this.prisma.subscription.findMany({
      where: { userId },
      include: { plan: true },
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
    return rows.map((s) => SubscriptionsService.present(s));
  }

  static present(
    s: Subscription & { plan: { id: string; title: string } & Parameters<typeof presentEntitlements>[0] },
  ) {
    return {
      id: s.id,
      plan: { id: s.plan.id, title: s.plan.title, entitlements: presentEntitlements(s.plan) },
      status: apiEnum(s.status),
      provider: apiEnum(s.provider),
      currentPeriodStart: s.currentPeriodStart,
      currentPeriodEnd: s.currentPeriodEnd,
      graceUntil: s.graceUntil,
      cancelAtPeriodEnd: s.cancelAtPeriodEnd,
      businessId: s.businessId,
    };
  }

  /** Worker: grace/expiry transitions and expiring reminders. Idempotent. */
  async sweep(now = new Date()): Promise<{ expired: number; grace: number; notified: number }> {
    const { subscriptionGraceDays, subscriptionExpiringDays } = await this.config.setting('notices');
    let expired = 0;
    let grace = 0;
    const ended = await this.prisma.subscription.findMany({
      where: {
        OR: [
          { status: SubscriptionStatus.ACTIVE, currentPeriodEnd: { lte: now } },
          { status: SubscriptionStatus.GRACE_PERIOD, graceUntil: { lte: now } },
        ],
      },
      take: 500,
    });
    for (const s of ended) {
      const toGrace =
        s.status === SubscriptionStatus.ACTIVE && subscriptionGraceDays > 0 && !s.cancelAtPeriodEnd;
      const { count } = await this.prisma.subscription.updateMany({
        where: { id: s.id, status: s.status },
        data: toGrace
          ? {
              status: SubscriptionStatus.GRACE_PERIOD,
              graceUntil: new Date(s.currentPeriodEnd.getTime() + subscriptionGraceDays * 86400_000),
            }
          : { status: SubscriptionStatus.EXPIRED },
      });
      if (!count) continue;
      if (toGrace) grace++;
      else expired++;
      await this.afterChange(s.userId, s.businessId);
      if (!toGrace) {
        await this.notifications.notify(
          s.userId,
          {
            type: NotificationType.SUBSCRIPTION,
            title: 'Tarif muddati tugadi',
            body: 'Biznes tarifingiz muddati tugadi. Bepul tarif imkoniyatlari saqlanadi.',
            route: '/account/plans',
            data: { subscriptionId: s.id },
          },
          { dedupeKey: `sub-expired:${s.id}:${s.currentPeriodEnd.toISOString()}` },
        );
      }
    }
    const soon = new Date(now.getTime() + subscriptionExpiringDays * 86400_000);
    const expiring = await this.prisma.subscription.findMany({
      where: {
        status: SubscriptionStatus.ACTIVE,
        currentPeriodEnd: { gt: now, lte: soon },
        expiringNotifiedAt: null,
      },
      take: 500,
    });
    let notified = 0;
    for (const s of expiring) {
      const { count } = await this.prisma.subscription.updateMany({
        where: { id: s.id, expiringNotifiedAt: null },
        data: { expiringNotifiedAt: now },
      });
      if (!count) continue;
      notified++;
      await this.notifications.notify(
        s.userId,
        {
          type: NotificationType.SUBSCRIPTION,
          title: 'Tarif muddati tugayapti',
          body: `Tarifingiz ${s.currentPeriodEnd.toISOString().slice(0, 10)} kuni tugaydi.`,
          route: '/account/plans',
          data: { subscriptionId: s.id },
        },
        { dedupeKey: `sub-expiring:${s.id}:${s.currentPeriodEnd.toISOString()}` },
      );
    }
    return { expired, grace, notified };
  }
}
