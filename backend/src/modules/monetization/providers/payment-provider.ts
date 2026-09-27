import { Payment, PaymentProviderKey, Purchase } from '@prisma/client';

/** What the client must do to pay. Never contains secrets. */
export type CheckoutAction =
  | { type: 'redirect'; url: string }
  | { type: 'store'; store: 'apple' | 'google'; storeProductId: string }
  | { type: 'none' };

/** Provider-reported fact about a payment, normalized. */
export interface ProviderEvent {
  /** Provider's unique id for this notification (replay protection). */
  eventId: string;
  paymentId: string;
  externalId?: string;
  type: 'pending' | 'succeeded' | 'failed' | 'cancelled' | 'refunded';
  amountMinor?: bigint;
  failureCode?: string;
}

export interface WebhookRequest {
  headers: Record<string, string | string[] | undefined>;
  rawBody: Buffer;
}

export interface ProviderCapabilities {
  refunds: boolean;
  statusLookup: boolean;
  autoRenewingSubscriptions: boolean;
}

/**
 * Payment company adapter. Business logic (checkout, state machine,
 * fulfillment) only talks to this interface.
 */
export interface PaymentProvider {
  readonly key: PaymentProviderKey;
  readonly capabilities: ProviderCapabilities;
  /** False until credentials exist *and* the adapter is implemented. */
  configured(): boolean;
  createCheckout(
    payment: Payment,
    purchase: Purchase,
  ): Promise<{ action: CheckoutAction; externalId?: string }>;
  /** Verifies the signature exactly per provider docs; throws on failure. */
  parseWebhook(request: WebhookRequest): Promise<ProviderEvent[]>;
  /** Response body the provider expects for an accepted webhook. */
  webhookAck(events: ProviderEvent[]): unknown;
  fetchStatus?(payment: Payment): Promise<ProviderEvent | null>;
  refund?(payment: Payment, amountMinor: bigint): Promise<{ succeeded: boolean; providerRefundId?: string }>;
}

export const PAYMENT_PROVIDERS = Symbol('PAYMENT_PROVIDERS');
