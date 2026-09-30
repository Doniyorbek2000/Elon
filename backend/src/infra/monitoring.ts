import * as Sentry from '@sentry/node';

import { env } from '../config/env';

let enabled = false;

const REDACTED_HEADERS = ['authorization', 'cookie', 'x-dev-signature', 'x-forwarded-for'];

/**
 * Error reporting is opt-in via SENTRY_DSN. Request bodies, cookies and
 * credentials are stripped before anything leaves the process.
 */
export function initMonitoring(service: 'api' | 'worker'): void {
  const config = env();
  if (enabled || !config.SENTRY_DSN) return;
  Sentry.init({
    dsn: config.SENTRY_DSN,
    environment: config.SENTRY_ENVIRONMENT ?? config.NODE_ENV,
    tracesSampleRate: config.SENTRY_TRACES_SAMPLE_RATE,
    initialScope: { tags: { service } },
    beforeSend(event) {
      if (event.request) {
        delete event.request.data;
        delete event.request.cookies;
        delete event.request.query_string;
        if (event.request.headers) {
          for (const name of REDACTED_HEADERS) delete event.request.headers[name];
        }
      }
      delete event.user;
      return event;
    },
  });
  enabled = true;
}

export function isMonitoringEnabled(): boolean {
  return enabled;
}

/** No-op when monitoring is disabled. */
export function reportError(error: unknown, context: Record<string, string | undefined> = {}): void {
  if (!enabled) return;
  Sentry.withScope((scope) => {
    for (const [key, value] of Object.entries(context)) {
      if (value !== undefined) scope.setTag(key, value);
    }
    Sentry.captureException(error);
  });
}

export async function flushMonitoring(timeoutMs = 2000): Promise<void> {
  if (enabled) await Sentry.flush(timeoutMs);
}
