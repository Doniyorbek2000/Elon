import { Injectable, Logger } from '@nestjs/common';

import { env } from '../../config/env';
import { maskPhone } from '../../common/text';

/** Delivers one-time codes. Implementations must never log the code in production. */
export interface OtpSender {
  readonly name: string;
  send(phone: string, code: string): Promise<void>;
}

export const OTP_SENDER = Symbol('OTP_SENDER');

/**
 * Development sender: writes the code to the local log only. Startup
 * validation forbids this provider when NODE_ENV=production.
 */
@Injectable()
export class DevOtpSender implements OtpSender {
  readonly name = 'dev';
  private readonly logger = new Logger('DevOtpSender');
  /** Last codes by phone — read by e2e tests only. */
  static readonly outbox = new Map<string, string>();

  async send(phone: string, code: string): Promise<void> {
    DevOtpSender.outbox.set(phone, code);
    if (env().NODE_ENV === 'development') this.logger.log(`OTP for ${maskPhone(phone)}: ${code}`);
  }
}

/**
 * Eskiz.uz SMS gateway (widely used in Uzbekistan). Requires ESKIZ_EMAIL /
 * ESKIZ_PASSWORD. Not exercised in CI: no credentials are available.
 */
@Injectable()
export class EskizOtpSender implements OtpSender {
  readonly name = 'eskiz';
  private readonly logger = new Logger('EskizOtpSender');
  private token?: { value: string; expiresAt: number };
  private static readonly base = 'https://notify.eskiz.uz/api';

  private async authToken(): Promise<string> {
    if (this.token && this.token.expiresAt > Date.now()) return this.token.value;
    const config = env();
    const body = new FormData();
    body.set('email', config.ESKIZ_EMAIL ?? '');
    body.set('password', config.ESKIZ_PASSWORD ?? '');
    const response = await fetch(`${EskizOtpSender.base}/auth/login`, { method: 'POST', body });
    if (!response.ok) throw new Error(`Eskiz auth failed with HTTP ${response.status}`);
    const json = (await response.json()) as { data?: { token?: string } };
    const value = json.data?.token;
    if (!value) throw new Error('Eskiz auth response missing token');
    this.token = { value, expiresAt: Date.now() + 25 * 24 * 3600 * 1000 };
    return value;
  }

  async send(phone: string, code: string): Promise<void> {
    const body = new FormData();
    body.set('mobile_phone', phone);
    body.set('message', `Bozor.uz tasdiqlash kodi: ${code}. Kodni hech kimga bermang.`);
    body.set('from', env().ESKIZ_SENDER);
    const response = await fetch(`${EskizOtpSender.base}/message/sms/send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await this.authToken()}` },
      body,
    });
    if (!response.ok) {
      this.logger.error(`SMS delivery to ${maskPhone(phone)} failed with HTTP ${response.status}`);
      throw new Error('SMS delivery failed');
    }
  }
}

export class DisabledOtpSender implements OtpSender {
  readonly name = 'none';

  async send(): Promise<void> {
    throw new Error('OTP delivery is not configured (OTP_PROVIDER=none)');
  }
}
