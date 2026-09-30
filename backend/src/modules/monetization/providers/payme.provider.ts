import { HttpStatus } from '@nestjs/common';
import { Currency, Payment, PaymentProviderKey } from '@prisma/client';

import { AppError } from '../../../common/errors';
import { env } from '../../../config/env';
import { CheckoutAction, PaymentProvider, ProviderEvent } from './payment-provider';

/**
 * Payme Business adapter: hosted checkout link only. The Merchant API
 * (JSON-RPC callbacks from Payme) is served by `PaymeService`, because its
 * responses depend on per-transaction state that the generic webhook
 * contract cannot express.
 */
export class PaymePaymentProvider implements PaymentProvider {
  readonly key = PaymentProviderKey.PAYME;
  readonly capabilities = { refunds: false, statusLookup: false, autoRenewingSubscriptions: false };

  configured(): boolean {
    const config = env();
    return !!(config.PAYME_MERCHANT_ID && config.PAYME_KEY);
  }

  /** `https://checkout.paycom.uz/<base64 of "m=…;ac.order_id=…;a=<tiyin>;l=uz;c=<return url>">` */
  async createCheckout(payment: Payment): Promise<{ action: CheckoutAction }> {
    const config = env();
    if (!config.PAYME_MERCHANT_ID || !config.PAYME_KEY) {
      throw new AppError(
        'PROVIDER_NOT_CONFIGURED',
        'Payme payments are not available',
        HttpStatus.SERVICE_UNAVAILABLE,
        { provider: 'payme' },
      );
    }
    if (payment.currency !== Currency.UZS) {
      throw new AppError(
        'PAYMENT_ROUTE_UNAVAILABLE',
        'Payme accepts UZS only',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    const params = [
      `m=${config.PAYME_MERCHANT_ID}`,
      `ac.order_id=${payment.id}`,
      `a=${payment.amountMinor.toString()}`,
      'l=uz',
      `c=${config.WEB_BASE_URL}/payment/return`,
    ].join(';');
    const host = config.PAYME_TEST_MODE ? 'https://test.paycom.uz' : 'https://checkout.paycom.uz';
    return { action: { type: 'redirect', url: `${host}/${Buffer.from(params).toString('base64')}` } };
  }

  async parseWebhook(): Promise<ProviderEvent[]> {
    throw AppError.notFound('Payment provider'); // served by POST /payments/webhooks/payme
  }

  webhookAck(): unknown {
    throw AppError.notFound('Payment provider');
  }
}
