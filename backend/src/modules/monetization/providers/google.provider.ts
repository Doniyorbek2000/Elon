import { HttpStatus } from '@nestjs/common';
import { Payment, PaymentProviderKey, Purchase } from '@prisma/client';

import { AppError } from '../../../common/errors';
import { env } from '../../../config/env';
import { PrismaService } from '../../../infra/prisma.service';
import { readPem, signRs256Jwt } from './jws';
import {
  CheckoutAction,
  PaymentProvider,
  ProviderEvent,
  ReceiptInvalid,
  WebhookRequest,
} from './payment-provider';
import { storeProductFor } from './store-products';

const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface ProductPurchase {
  purchaseState?: number; // 0 purchased, 1 canceled, 2 pending
  consumptionState?: number;
  acknowledgementState?: number; // 0 not yet, 1 acknowledged
  orderId?: string;
  obfuscatedExternalAccountId?: string;
  purchaseType?: number; // 0 test, 1 promo, 2 rewarded (absent for real purchases)
}

/**
 * Google Play in-app purchases through the Play Developer API
 * (`purchases.products.get` + `acknowledge`). The app buys with the payment id
 * as the obfuscated account id, sends the purchase token, and this adapter
 * confirms state, product and account binding with Google before activating.
 */
export class GooglePaymentProvider implements PaymentProvider {
  readonly key = PaymentProviderKey.GOOGLE;
  readonly capabilities = { refunds: false, statusLookup: false, autoRenewingSubscriptions: false };

  private cachedToken?: { value: string; expiresAt: number };

  constructor(
    private readonly prisma: PrismaService,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  configured(): boolean {
    const c = env();
    return !!(c.GOOGLE_PACKAGE_NAME && c.GOOGLE_SERVICE_ACCOUNT);
  }

  private account(): ServiceAccount {
    if (!this.configured()) {
      throw new AppError(
        'PROVIDER_NOT_CONFIGURED',
        'Google Play payments are not available',
        HttpStatus.SERVICE_UNAVAILABLE,
        { provider: 'google' },
      );
    }
    const raw = readJson(env().GOOGLE_SERVICE_ACCOUNT!);
    return { ...raw, private_key: readPem(raw.private_key) };
  }

  async createCheckout(payment: Payment, purchase: Purchase): Promise<{ action: CheckoutAction }> {
    this.account();
    const storeProductId = await storeProductFor(this.prisma, this.key, purchase);
    if (!storeProductId) {
      throw new AppError(
        'PAYMENT_ROUTE_UNAVAILABLE',
        'This product is not sold on Google Play',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    return { action: { type: 'store', store: 'google', storeProductId, accountToken: payment.id } };
  }

  /** OAuth2 access token via the service-account JWT bearer flow (cached until shortly before expiry). */
  private async accessToken(): Promise<string> {
    if (this.cachedToken && this.cachedToken.expiresAt > Date.now() + 60_000) return this.cachedToken.value;
    const account = this.account();
    const now = Math.floor(Date.now() / 1000);
    const tokenUri = account.token_uri ?? 'https://oauth2.googleapis.com/token';
    const assertion = signRs256Jwt(
      { iss: account.client_email, scope: SCOPE, aud: tokenUri, iat: now, exp: now + 3600 },
      account.private_key,
    );
    const response = await this.fetchImpl(tokenUri, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }).toString(),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`Google OAuth HTTP ${response.status}`);
    const json = (await response.json()) as { access_token: string; expires_in: number };
    this.cachedToken = { value: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
    return json.access_token;
  }

  private productUrl(productId: string, token: string): string {
    const c = env();
    return `${c.GOOGLE_API_URL}/androidpublisher/v3/applications/${encodeURIComponent(c.GOOGLE_PACKAGE_NAME!)}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`;
  }

  private async fetchPurchase(
    productId: string,
    receipt: string,
  ): Promise<{ info: ProductPurchase; auth: Record<string, string> }> {
    if (!/^[\w.\-]{10,400}$/.test(receipt)) throw new ReceiptInvalid('malformed_purchase_token');
    const auth = { Authorization: `Bearer ${await this.accessToken()}` };
    const response = await this.fetchImpl(this.productUrl(productId, receipt), {
      headers: auth,
      signal: AbortSignal.timeout(15_000),
    });
    if (response.status === 404 || response.status === 410) throw new ReceiptInvalid('purchase_not_found');
    if (response.status === 400) throw new ReceiptInvalid('purchase_rejected');
    if (!response.ok) throw new Error(`Play Developer API HTTP ${response.status}`);
    return { info: (await response.json()) as ProductPurchase, auth };
  }

  async identifyPayment(receipt: string, storeProductId?: string): Promise<string> {
    this.account();
    if (!storeProductId) throw new ReceiptInvalid('wrong_product');
    const { info } = await this.fetchPurchase(storeProductId, receipt);
    if (!info.obfuscatedExternalAccountId) throw new ReceiptInvalid('account_mismatch');
    return info.obfuscatedExternalAccountId.toLowerCase();
  }

  async verifyReceipt(payment: Payment, purchase: Purchase, receipt: string): Promise<ProviderEvent> {
    this.account();
    const productId = await storeProductFor(this.prisma, this.key, purchase);
    if (!productId) throw new ReceiptInvalid('wrong_product');
    const { info, auth } = await this.fetchPurchase(productId, receipt);
    if (info.purchaseState !== 0)
      throw new ReceiptInvalid(info.purchaseState === 2 ? 'pending' : 'not_purchased');
    if (!info.orderId) throw new ReceiptInvalid('no_order');
    if (info.obfuscatedExternalAccountId?.toLowerCase() !== payment.id.toLowerCase()) {
      throw new ReceiptInvalid('account_mismatch');
    }
    if (info.acknowledgementState !== 1) {
      // Unacknowledged purchases are refunded by Google after 3 days.
      const ack = await this.fetchImpl(`${this.productUrl(productId, receipt)}:acknowledge`, {
        method: 'POST',
        headers: { ...auth, 'Content-Type': 'application/json' },
        body: '{}',
        signal: AbortSignal.timeout(15_000),
      });
      if (!ack.ok) throw new Error(`Play acknowledge HTTP ${ack.status}`);
    }
    return {
      eventId: `google:${info.orderId}`,
      paymentId: payment.id,
      externalId: info.orderId,
      type: 'succeeded',
    };
  }

  async parseWebhook(_request: WebhookRequest): Promise<ProviderEvent[]> {
    // Real-time developer notifications (Pub/Sub push) are not wired up; purchases are confirmed by the app's receipt call.
    throw AppError.notFound('Payment provider');
  }

  webhookAck(): unknown {
    return {};
  }
}

function readJson(value: string): ServiceAccount {
  const text = value.trim().startsWith('{') ? value : Buffer.from(value, 'base64').toString('utf8');
  return JSON.parse(text) as ServiceAccount;
}
