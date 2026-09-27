import { HttpStatus } from '@nestjs/common';
import { PaymentProviderKey } from '@prisma/client';

import { AppError } from '../../../common/errors';
import { CheckoutAction, PaymentProvider, ProviderEvent } from './payment-provider';

/**
 * Placeholder adapter for a provider whose integration is not implemented in
 * this repository. It never accepts a webhook and never reports success, so
 * nothing can be activated through it by accident.
 *
 * What each provider needs is documented in docs/monetization.md
 * ("Payment providers: missing configuration").
 */
export class UnconfiguredPaymentProvider implements PaymentProvider {
  readonly capabilities = { refunds: false, statusLookup: false, autoRenewingSubscriptions: false };

  constructor(readonly key: PaymentProviderKey) {}

  configured(): boolean {
    return false;
  }

  private fail(): never {
    throw new AppError(
      'PROVIDER_NOT_CONFIGURED',
      `${this.key} payments are not available`,
      HttpStatus.SERVICE_UNAVAILABLE,
      { provider: this.key.toLowerCase() },
    );
  }

  async createCheckout(): Promise<{ action: CheckoutAction }> {
    return this.fail();
  }

  async parseWebhook(): Promise<ProviderEvent[]> {
    return this.fail();
  }

  webhookAck(): unknown {
    return this.fail();
  }
}
