import { Inject, Injectable } from '@nestjs/common';
import { PaymentProviderKey } from '@prisma/client';

import { AppError } from '../../../common/errors';
import { PAYMENT_PROVIDERS, PaymentProvider } from './payment-provider';

@Injectable()
export class PaymentProviderRegistry {
  private readonly byKey: Map<PaymentProviderKey, PaymentProvider>;

  constructor(@Inject(PAYMENT_PROVIDERS) providers: PaymentProvider[]) {
    this.byKey = new Map(providers.map((p) => [p.key, p]));
  }

  get(key: PaymentProviderKey): PaymentProvider {
    const provider = this.byKey.get(key);
    if (!provider) throw AppError.notFound('Payment provider');
    return provider;
  }

  /** Providers usable right now (credentials + implementation present). */
  configuredKeys(): PaymentProviderKey[] {
    return [...this.byKey.values()].filter((p) => p.configured()).map((p) => p.key);
  }

  parseKey(value: string): PaymentProviderKey {
    const key = value.toUpperCase() as PaymentProviderKey;
    if (!this.byKey.has(key)) throw AppError.notFound('Payment provider');
    return key;
  }
}
