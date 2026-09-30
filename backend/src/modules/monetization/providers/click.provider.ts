import { createHash, timingSafeEqual } from 'node:crypto';

import { HttpStatus } from '@nestjs/common';
import { Currency, Payment, PaymentProviderKey, PaymentStatus } from '@prisma/client';

import { AppError } from '../../../common/errors';
import { env } from '../../../config/env';
import { PrismaService } from '../../../infra/prisma.service';
import {
  CheckoutAction,
  PaymentProvider,
  ProviderEvent,
  WebhookRejection,
  WebhookRequest,
} from './payment-provider';

/** Error codes from the Click Shop API ("Prepare"/"Complete" responses). */
export const ClickError = {
  Success: 0,
  SignFailed: -1,
  IncorrectAmount: -2,
  ActionNotFound: -3,
  AlreadyPaid: -4,
  OrderNotFound: -5,
  TransactionNotFound: -6,
  UpdateFailed: -7,
  RequestError: -8,
  TransactionCancelled: -9,
} as const;
type ClickErrorCode = (typeof ClickError)[keyof typeof ClickError];

const ERROR_NOTES: Record<ClickErrorCode, string> = {
  [ClickError.Success]: 'Success',
  [ClickError.SignFailed]: 'SIGN CHECK FAILED!',
  [ClickError.IncorrectAmount]: 'Incorrect parameter amount',
  [ClickError.ActionNotFound]: 'Action not found',
  [ClickError.AlreadyPaid]: 'Already paid',
  [ClickError.OrderNotFound]: 'Order not found',
  [ClickError.TransactionNotFound]: 'Transaction does not exist',
  [ClickError.UpdateFailed]: 'Failed to update user',
  [ClickError.RequestError]: 'Error in request from click',
  [ClickError.TransactionCancelled]: 'Transaction cancelled',
};

const CHECKOUT_URL = 'https://my.click.uz/services/pay';

interface ClickCallback {
  clickTransId: string;
  serviceId: string;
  merchantTransId: string;
  merchantPrepareId: string;
  amount: string;
  action: 0 | 1;
  error: number;
  signTime: string;
  signString: string;
}

const md5 = (value: string) => createHash('md5').update(value).digest('hex');

/** "2500", "2500.5" or "2500.00" (so‘m) → tiyin. Null for anything else. */
export function sumToTiyin(value: string): bigint | null {
  const match = /^(\d{1,12})(?:\.(\d{1,2}))?$/.exec(value);
  if (!match) return null;
  return BigInt(match[1]) * 100n + BigInt((match[2] ?? '').padEnd(2, '0') || '0');
}

/** Click wants an integer id back; derive a stable one from the payment UUID (48 bits). */
export function clickPrepareId(paymentId: string): number {
  return parseInt(paymentId.replace(/-/g, '').slice(0, 12), 16);
}

/**
 * Click Shop API (two-phase "Prepare"/"Complete" callbacks signed with MD5).
 * Every rejection is answered with HTTP 200 and a Click error code, as the
 * protocol requires; amounts arrive in so‘m and are compared in tiyin.
 */
export class ClickPaymentProvider implements PaymentProvider {
  readonly key = PaymentProviderKey.CLICK;
  readonly capabilities = { refunds: false, statusLookup: false, autoRenewingSubscriptions: false };

  constructor(private readonly prisma: PrismaService) {}

  configured(): boolean {
    const config = env();
    return !!(config.CLICK_SERVICE_ID && config.CLICK_MERCHANT_ID && config.CLICK_SECRET_KEY);
  }

  private credentials() {
    const config = env();
    if (!config.CLICK_SERVICE_ID || !config.CLICK_MERCHANT_ID || !config.CLICK_SECRET_KEY) {
      throw new AppError(
        'PROVIDER_NOT_CONFIGURED',
        'Click payments are not available',
        HttpStatus.SERVICE_UNAVAILABLE,
        { provider: 'click' },
      );
    }
    return {
      serviceId: config.CLICK_SERVICE_ID,
      merchantId: config.CLICK_MERCHANT_ID,
      secret: config.CLICK_SECRET_KEY,
    };
  }

  async createCheckout(payment: Payment): Promise<{ action: CheckoutAction }> {
    const { serviceId, merchantId } = this.credentials();
    if (payment.currency !== Currency.UZS) {
      throw new AppError(
        'PAYMENT_ROUTE_UNAVAILABLE',
        'Click accepts UZS only',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    const sum = `${payment.amountMinor / 100n}.${(payment.amountMinor % 100n).toString().padStart(2, '0')}`;
    const params = new URLSearchParams({
      service_id: serviceId,
      merchant_id: merchantId,
      amount: sum,
      transaction_param: payment.id,
      return_url: `${env().WEB_BASE_URL}/payment/return`,
    });
    return { action: { type: 'redirect', url: `${CHECKOUT_URL}?${params.toString()}` } };
  }

  // ─────────────────────────────────────────────────────── callbacks

  private parse(request: WebhookRequest): ClickCallback | null {
    const form = new URLSearchParams(request.rawBody.toString('utf8'));
    const field = (name: string) => form.get(name) ?? '';
    const action = field('action');
    if (action !== '0' && action !== '1') return null;
    return {
      clickTransId: field('click_trans_id'),
      serviceId: field('service_id'),
      merchantTransId: field('merchant_trans_id'),
      merchantPrepareId: field('merchant_prepare_id'),
      amount: field('amount'),
      action: action === '0' ? 0 : 1,
      error: Number(field('error') || 0),
      signTime: field('sign_time'),
      signString: field('sign_string'),
    };
  }

  private signatureValid(secret: string, c: ClickCallback): boolean {
    const parts =
      c.action === 0
        ? [c.clickTransId, c.serviceId, secret, c.merchantTransId, c.amount, '0', c.signTime]
        : [
            c.clickTransId,
            c.serviceId,
            secret,
            c.merchantTransId,
            c.merchantPrepareId,
            c.amount,
            '1',
            c.signTime,
          ];
    const expected = md5(parts.join(''));
    const given = c.signString.toLowerCase();
    return (
      /^[0-9a-f]{32}$/.test(given) && timingSafeEqual(Buffer.from(given, 'hex'), Buffer.from(expected, 'hex'))
    );
  }

  private reply(c: Partial<ClickCallback> | null, code: ClickErrorCode, extra: Record<string, unknown> = {}) {
    return {
      click_trans_id: c?.clickTransId ? Number(c.clickTransId) : null,
      merchant_trans_id: c?.merchantTransId ?? null,
      ...extra,
      error: code,
      error_note: ERROR_NOTES[code],
    };
  }

  private reject(c: ClickCallback | null, code: ClickErrorCode, reason: string): never {
    throw new WebhookRejection(this.reply(c, code), reason);
  }

  async parseWebhook(request: WebhookRequest): Promise<ProviderEvent[]> {
    const { secret, serviceId } = this.credentials();
    const callback = this.parse(request);
    if (!callback) this.reject(null, ClickError.ActionNotFound, 'unknown action');
    if (callback.serviceId !== serviceId || !this.signatureValid(secret, callback)) {
      this.reject(callback, ClickError.SignFailed, 'bad signature');
    }
    if (!/^\d{1,20}$/.test(callback.clickTransId)) {
      this.reject(callback, ClickError.RequestError, 'bad click_trans_id');
    }
    const amountMinor = sumToTiyin(callback.amount);
    if (amountMinor == null) this.reject(callback, ClickError.IncorrectAmount, 'bad amount');

    const payment = /^[0-9a-f-]{36}$/i.test(callback.merchantTransId)
      ? await this.prisma.payment.findUnique({ where: { id: callback.merchantTransId } })
      : null;
    if (!payment || payment.provider !== PaymentProviderKey.CLICK) {
      this.reject(callback, ClickError.OrderNotFound, 'unknown payment');
    }
    if (payment.amountMinor !== amountMinor) {
      this.reject(callback, ClickError.IncorrectAmount, 'amount mismatch');
    }
    if (payment.status === PaymentStatus.SUCCEEDED) {
      this.reject(callback, ClickError.AlreadyPaid, 'already paid');
    }
    if (payment.status === PaymentStatus.FAILED || payment.status === PaymentStatus.CANCELLED) {
      this.reject(callback, ClickError.TransactionCancelled, 'payment closed');
    }

    if (callback.action === 0) return []; // Prepare: validation only, nothing changes yet.

    if (Number(callback.merchantPrepareId) !== clickPrepareId(payment.id)) {
      this.reject(callback, ClickError.TransactionNotFound, 'prepare id mismatch');
    }
    const eventBase = { paymentId: payment.id, externalId: callback.clickTransId, amountMinor };
    if (callback.error < 0) {
      // Click reports that the customer's payment failed after Prepare.
      return [
        {
          ...eventBase,
          eventId: `click:${callback.clickTransId}:failed`,
          type: 'failed',
          failureCode: `click_${callback.error}`,
        },
      ];
    }
    return [{ ...eventBase, eventId: `click:${callback.clickTransId}:complete`, type: 'succeeded' }];
  }

  webhookAck(events: ProviderEvent[], request: WebhookRequest): unknown {
    const callback = this.parse(request);
    if (!callback) return this.reply(null, ClickError.ActionNotFound);
    const prepareId = clickPrepareId(callback.merchantTransId);
    if (callback.action === 0) {
      return this.reply(callback, ClickError.Success, { merchant_prepare_id: prepareId });
    }
    if (events[0]?.type === 'failed') return this.reply(callback, ClickError.TransactionCancelled);
    return this.reply(callback, ClickError.Success, { merchant_confirm_id: prepareId });
  }
}
