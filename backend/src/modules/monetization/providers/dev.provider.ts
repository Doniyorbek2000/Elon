import { createHmac, timingSafeEqual } from 'node:crypto';

import { HttpStatus } from '@nestjs/common';
import { Payment, PaymentProviderKey } from '@prisma/client';
import Redis from 'ioredis';

import { AppError } from '../../../common/errors';
import { env } from '../../../config/env';
import { CheckoutAction, PaymentProvider, ProviderEvent, WebhookRequest } from './payment-provider';

const SIGNATURE_HEADER = 'x-dev-signature';
const TIMESTAMP_HEADER = 'x-dev-timestamp';
/** Signed webhooks older than this are rejected (replay window). */
const MAX_SKEW_SECONDS = 300;

interface DevWebhookBody {
  eventId: string;
  paymentId: string;
  externalId: string;
  status: ProviderEvent['type'];
  amountMinor: string;
}

/**
 * Development/test provider that behaves like a real one: hosted checkout
 * page, asynchronous HMAC-SHA256 signed webhooks with a timestamp, its own
 * "remote" payment state (in Redis) for reconciliation, and refunds.
 * Disabled in production by env validation.
 */
export class DevPaymentProvider implements PaymentProvider {
  readonly key = PaymentProviderKey.DEV;
  readonly capabilities = { refunds: true, statusLookup: true, autoRenewingSubscriptions: false };

  constructor(private readonly redis: Redis) {}

  configured(): boolean {
    const config = env();
    return config.NODE_ENV !== 'production' && config.PAYMENT_DEV_ENABLED && !!config.PAYMENT_DEV_SECRET;
  }

  private secret(): string {
    const secret = env().PAYMENT_DEV_SECRET;
    if (!secret || !this.configured()) {
      throw new AppError(
        'PROVIDER_NOT_CONFIGURED',
        'Payment provider is not configured',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    return secret;
  }

  static sign(secret: string, timestamp: string, body: string): string {
    return createHmac('sha256', secret).update(`${timestamp}.${body}`).digest('hex');
  }

  /** Token for the hosted checkout page (prevents guessing other payments' pages). */
  pageToken(paymentId: string): string {
    return createHmac('sha256', this.secret()).update(`page:${paymentId}`).digest('hex').slice(0, 32);
  }

  async createCheckout(payment: Payment): Promise<{ action: CheckoutAction; externalId: string }> {
    const externalId = `dev_${payment.id}`;
    await this.redis.set(`devpay:${payment.id}`, 'pending', 'EX', 7 * 24 * 3600);
    const url = `${env().PUBLIC_API_URL}/api/v1/payments/dev/checkout/${payment.id}?token=${this.pageToken(payment.id)}`;
    return { action: { type: 'redirect', url }, externalId };
  }

  /** Simulated provider side: records the remote outcome and builds a signed webhook. */
  async simulate(payment: Payment, status: ProviderEvent['type'], eventId?: string) {
    await this.redis.set(`devpay:${payment.id}`, status, 'EX', 7 * 24 * 3600);
    const body = JSON.stringify({
      eventId: eventId ?? `dev_evt_${payment.id}_${status}_${Date.now()}`,
      paymentId: payment.id,
      externalId: payment.externalId ?? `dev_${payment.id}`,
      status,
      amountMinor: payment.amountMinor.toString(),
    } satisfies DevWebhookBody);
    const timestamp = Math.floor(Date.now() / 1000).toString();
    return {
      rawBody: Buffer.from(body),
      headers: {
        [SIGNATURE_HEADER]: DevPaymentProvider.sign(this.secret(), timestamp, body),
        [TIMESTAMP_HEADER]: timestamp,
      },
    };
  }

  async parseWebhook(request: WebhookRequest): Promise<ProviderEvent[]> {
    const signature = String(request.headers[SIGNATURE_HEADER] ?? '');
    const timestamp = String(request.headers[TIMESTAMP_HEADER] ?? '');
    const expected = DevPaymentProvider.sign(this.secret(), timestamp, request.rawBody.toString('utf8'));
    const valid =
      /^[0-9a-f]{64}$/.test(signature) &&
      timingSafeEqual(Buffer.from(signature, 'hex'), Buffer.from(expected, 'hex'));
    const age = Math.abs(Date.now() / 1000 - Number(timestamp));
    if (!valid || !Number.isFinite(age) || age > MAX_SKEW_SECONDS) {
      throw new AppError('SIGNATURE_INVALID', 'Invalid webhook signature', HttpStatus.UNAUTHORIZED);
    }
    const body = JSON.parse(request.rawBody.toString('utf8')) as DevWebhookBody;
    return [
      {
        eventId: body.eventId,
        paymentId: body.paymentId,
        externalId: body.externalId,
        type: body.status,
        amountMinor: BigInt(body.amountMinor),
      },
    ];
  }

  webhookAck(): unknown {
    return { received: true };
  }

  async fetchStatus(payment: Payment): Promise<ProviderEvent | null> {
    const status = (await this.redis.get(`devpay:${payment.id}`)) as ProviderEvent['type'] | null;
    if (!status || status === 'pending') return null;
    return {
      eventId: `dev_recon_${payment.id}_${status}`,
      paymentId: payment.id,
      externalId: payment.externalId ?? undefined,
      type: status,
      amountMinor: payment.amountMinor,
    };
  }

  async refund(payment: Payment, amountMinor: bigint) {
    if (amountMinor <= 0n || amountMinor > payment.amountMinor - payment.refundedMinor)
      return { succeeded: false };
    return { succeeded: true, providerRefundId: `dev_refund_${payment.id}_${Date.now()}` };
  }
}
