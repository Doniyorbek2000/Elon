import { Logger } from '@nestjs/common';
import { GoogleAuth } from 'google-auth-library';

import { env } from '../../config/env';

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  data: Record<string, string>;
}

export type PushResult = 'sent' | 'invalid_token' | 'retry';

/** Transport for mobile push. FCM covers Android and iOS (APNs via Firebase). */
export interface PushProvider {
  readonly name: string;
  send(message: PushMessage): Promise<PushResult>;
}

export const PUSH_PROVIDER = Symbol('PUSH_PROVIDER');

/**
 * Firebase Cloud Messaging HTTP v1. Needs FCM_PROJECT_ID and a service
 * account with the "Firebase Cloud Messaging API Admin" role.
 */
export class FcmPushProvider implements PushProvider {
  readonly name = 'fcm';
  private readonly logger = new Logger('FcmPushProvider');
  private readonly auth: GoogleAuth;
  private readonly projectId: string;

  constructor() {
    const config = env();
    const raw = config.FCM_SERVICE_ACCOUNT ?? '';
    const json = raw.trim().startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
    this.projectId = config.FCM_PROJECT_ID ?? '';
    this.auth = new GoogleAuth({
      credentials: JSON.parse(json) as Record<string, string>,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });
  }

  async send(message: PushMessage): Promise<PushResult> {
    const client = await this.auth.getClient();
    const accessToken = (await client.getAccessToken()).token;
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${this.projectId}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: message.token,
          notification: { title: message.title, body: message.body },
          data: message.data,
          android: { priority: 'HIGH', notification: { channel_id: 'default', click_action: 'FLUTTER_NOTIFICATION_CLICK' } },
          apns: { payload: { aps: { sound: 'default', 'mutable-content': 1 } } },
        },
      }),
    });
    if (response.ok) return 'sent';
    if (response.status === 404 || response.status === 400) return 'invalid_token';
    this.logger.warn(`FCM send failed with HTTP ${response.status}`);
    return 'retry';
  }
}

/** Development/test transport: records pushes instead of sending them. */
export class LogPushProvider implements PushProvider {
  readonly name = 'log';
  private readonly logger = new Logger('LogPushProvider');
  static readonly outbox: PushMessage[] = [];

  async send(message: PushMessage): Promise<PushResult> {
    LogPushProvider.outbox.push(message);
    if (env().NODE_ENV === 'development') this.logger.log(`push → ${message.data.route ?? ''} "${message.title}"`);
    return 'sent';
  }
}

export class DisabledPushProvider implements PushProvider {
  readonly name = 'none';

  async send(): Promise<PushResult> {
    return 'sent';
  }
}

export function createPushProvider(): PushProvider {
  switch (env().PUSH_PROVIDER) {
    case 'fcm':
      return new FcmPushProvider();
    case 'log':
      return new LogPushProvider();
    case 'none':
      return new DisabledPushProvider();
  }
}
