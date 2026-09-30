import { HttpStatus } from '@nestjs/common';
import { Payment, PaymentProviderKey, PaymentStatus, Purchase } from '@prisma/client';

import { AppError } from '../../../common/errors';
import { env } from '../../../config/env';
import { PrismaService } from '../../../infra/prisma.service';
import { JwsError, readPem, signEs256Jwt, verifyAppleJws } from './jws';
import {
  CheckoutAction,
  PaymentProvider,
  ProviderEvent,
  ReceiptInvalid,
  WebhookRejection,
  WebhookRequest,
} from './payment-provider';
import { storeProductFor } from './store-products';

const PRODUCTION_API = 'https://api.storekit.itunes.apple.com';
const SANDBOX_API = 'https://api.storekit-sandbox.itunes.apple.com';

interface TransactionInfo {
  transactionId: string;
  originalTransactionId?: string;
  bundleId: string;
  productId: string;
  environment?: string;
  appAccountToken?: string;
  revocationDate?: number;
  expiresDate?: number;
}

interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data?: { signedTransactionInfo?: string; bundleId?: string };
}

/**
 * App Store in-app purchases through the App Store Server API.
 *
 * Purchases are consumable-style (boosts, promotions, prepaid plan periods):
 * the app buys, sends the StoreKit transaction id, and this adapter asks
 * Apple for the signed transaction, verifies the JWS chain against the pinned
 * Apple root, and checks bundle, product, environment, account binding and
 * revocation before anything is activated. Refund/revoke notifications arrive
 * as signed payloads on the webhook and flag the payment for review.
 */
export class ApplePaymentProvider implements PaymentProvider {
  readonly key = PaymentProviderKey.APPLE;
  readonly capabilities = { refunds: false, statusLookup: false, autoRenewingSubscriptions: false };

  constructor(
    private readonly prisma: PrismaService,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  configured(): boolean {
    const c = env();
    return !!(
      c.APPLE_BUNDLE_ID &&
      c.APPLE_ISSUER_ID &&
      c.APPLE_KEY_ID &&
      c.APPLE_PRIVATE_KEY &&
      c.APPLE_ROOT_CA
    );
  }

  private config() {
    const c = env();
    if (!this.configured()) {
      throw new AppError(
        'PROVIDER_NOT_CONFIGURED',
        'App Store payments are not available',
        HttpStatus.SERVICE_UNAVAILABLE,
        { provider: 'apple' },
      );
    }
    return {
      bundleId: c.APPLE_BUNDLE_ID!,
      issuerId: c.APPLE_ISSUER_ID!,
      keyId: c.APPLE_KEY_ID!,
      privateKey: readPem(c.APPLE_PRIVATE_KEY!),
      rootPem: readPem(c.APPLE_ROOT_CA!),
      environment: c.APPLE_ENVIRONMENT,
      baseUrl: c.APPLE_API_URL ?? (c.APPLE_ENVIRONMENT === 'sandbox' ? SANDBOX_API : PRODUCTION_API),
    };
  }

  async createCheckout(payment: Payment, purchase: Purchase): Promise<{ action: CheckoutAction }> {
    this.config();
    const storeProductId = await storeProductFor(this.prisma, this.key, purchase);
    if (!storeProductId) {
      throw new AppError(
        'PAYMENT_ROUTE_UNAVAILABLE',
        'This product is not sold in the App Store',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    return { action: { type: 'store', store: 'apple', storeProductId, accountToken: payment.id } };
  }

  /** Short-lived ES256 JWT for the App Store Server API. */
  private authToken(): string {
    const c = this.config();
    const now = Math.floor(Date.now() / 1000);
    return signEs256Jwt(
      { kid: c.keyId, typ: 'JWT' },
      { iss: c.issuerId, iat: now, exp: now + 300, aud: 'appstoreconnect-v1', bid: c.bundleId },
      c.privateKey,
    );
  }

  /** Asks Apple for the transaction and verifies the signed answer; everything else is checked by the callers. */
  private async fetchTransaction(receipt: string): Promise<TransactionInfo> {
    const c = this.config();
    if (!/^\d{1,30}$/.test(receipt)) throw new ReceiptInvalid('malformed_transaction_id');
    const response = await this.fetchImpl(`${c.baseUrl}/inApps/v1/transactions/${receipt}`, {
      headers: { Authorization: `Bearer ${this.authToken()}` },
      signal: AbortSignal.timeout(15_000),
    });
    if (response.status === 404) throw new ReceiptInvalid('transaction_not_found');
    if (!response.ok) throw new Error(`App Store Server API HTTP ${response.status}`);
    const { signedTransactionInfo } = (await response.json()) as { signedTransactionInfo?: string };
    if (!signedTransactionInfo) throw new ReceiptInvalid('no_transaction_info');
    try {
      return verifyAppleJws<TransactionInfo>(signedTransactionInfo, c.rootPem);
    } catch (error) {
      if (error instanceof JwsError) throw new ReceiptInvalid(`bad_signature:${error.message}`);
      throw error;
    }
  }

  async identifyPayment(receipt: string): Promise<string> {
    const info = await this.fetchTransaction(receipt);
    if (!info.appAccountToken) throw new ReceiptInvalid('account_mismatch');
    return info.appAccountToken.toLowerCase();
  }

  async verifyReceipt(payment: Payment, purchase: Purchase, receipt: string): Promise<ProviderEvent> {
    const c = this.config();
    const info = await this.fetchTransaction(receipt);
    const expectedProduct = await storeProductFor(this.prisma, this.key, purchase);
    if (info.bundleId !== c.bundleId) throw new ReceiptInvalid('wrong_bundle');
    if (!expectedProduct || info.productId !== expectedProduct) throw new ReceiptInvalid('wrong_product');
    if (info.transactionId !== receipt) throw new ReceiptInvalid('transaction_mismatch');
    if (info.revocationDate) throw new ReceiptInvalid('revoked');
    if (info.expiresDate && info.expiresDate < Date.now()) throw new ReceiptInvalid('expired');
    if (info.environment && info.environment.toLowerCase() !== c.environment) {
      throw new ReceiptInvalid('wrong_environment');
    }
    // The app binds the purchase to this payment; a transaction made for someone else cannot be claimed.
    if (info.appAccountToken?.toLowerCase() !== payment.id.toLowerCase())
      throw new ReceiptInvalid('account_mismatch');

    return {
      eventId: `apple:${info.transactionId}`,
      paymentId: payment.id,
      externalId: info.transactionId,
      type: 'succeeded',
    };
  }

  // ─────────────────────────────────────────────────────── App Store Server Notifications V2

  async parseWebhook(request: WebhookRequest): Promise<ProviderEvent[]> {
    const c = this.config();
    let signedPayload: string | undefined;
    try {
      signedPayload = (JSON.parse(request.rawBody.toString('utf8')) as { signedPayload?: string })
        .signedPayload;
    } catch {
      /* handled below */
    }
    if (!signedPayload) throw new WebhookRejection({ error: 'bad_request' }, 'missing signedPayload');
    let notification: NotificationPayload;
    try {
      notification = verifyAppleJws<NotificationPayload>(signedPayload, c.rootPem);
    } catch {
      throw AppError.unauthenticated('Invalid notification signature', 'UNAUTHENTICATED');
    }
    if (notification.data?.bundleId !== c.bundleId) return [];
    if (notification.notificationType !== 'REFUND' && notification.notificationType !== 'REVOKE') return [];
    const signedTransaction = notification.data.signedTransactionInfo;
    if (!signedTransaction) return [];
    const info = verifyAppleJws<TransactionInfo>(signedTransaction, c.rootPem);
    const payment = await this.prisma.payment.findUnique({
      where: { provider_externalId: { provider: this.key, externalId: info.transactionId } },
    });
    if (!payment || payment.status === PaymentStatus.REFUNDED) return [];
    return [{ eventId: `apple:${notification.notificationUUID}`, paymentId: payment.id, type: 'refunded' }];
  }

  webhookAck(): unknown {
    return {};
  }
}
