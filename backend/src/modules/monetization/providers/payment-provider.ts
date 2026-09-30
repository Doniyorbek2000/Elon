import { Payment, PaymentProviderKey, Purchase } from '@prisma/client';

/** What the client must do to pay. Never contains secrets. */
export type CheckoutAction =
  | { type: 'redirect'; url: string }
  | { type: 'store'; store: 'apple' | 'google'; storeProductId: string; accountToken: string }
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

/**
 * Thrown by an adapter when the provider's protocol expects a specific
 * (HTTP 200) error body instead of an HTTP error, e.g. Click's `error: -1`.
 */
export class WebhookRejection extends Error {
  constructor(
    readonly body: unknown,
    readonly reason: string,
  ) {
    super(reason);
  }
}

/** The store does not confirm this purchase (unknown, refunded, wrong product or account…). */
export class ReceiptInvalid extends Error {
  constructor(readonly reason: string) {
    super(reason);
  }
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
  webhookAck(events: ProviderEvent[], request: WebhookRequest): unknown;
  /**
   * Store billing: the app reports a receipt (Apple transaction id / Google
   * purchase token); the provider verifies it with the store's server API and
   * returns the verified fact. Throws `ReceiptInvalid` when it does not check out.
   */
  verifyReceipt?(payment: Payment, purchase: Purchase, receipt: string): Promise<ProviderEvent>;
  /**
   * Store billing recovery: finds which payment a store receipt belongs to (the
   * app attaches the payment id to the store transaction) without knowing the purchase.
   */
  identifyPayment?(receipt: string, storeProductId?: string): Promise<string>;
  fetchStatus?(payment: Payment): Promise<ProviderEvent | null>;
  refund?(payment: Payment, amountMinor: bigint): Promise<{ succeeded: boolean; providerRefundId?: string }>;
}

export const PAYMENT_PROVIDERS = Symbol('PAYMENT_PROVIDERS');
