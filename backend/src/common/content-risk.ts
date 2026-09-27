/**
 * Server-side content heuristics (the security boundary; the Flutter client
 * runs the same rules only as UX hints). Anything above INFO sends content to
 * moderation instead of publishing it directly.
 */
export type RiskSeverity = 'INFO' | 'WARNING' | 'BLOCKING';

export interface RiskSignal {
  code: string;
  severity: RiskSeverity;
}

const PHONE = /(\+?998[\s-]?)?\(?\d{2}\)?[\s-]?\d{3}[\s-]?\d{2}[\s-]?\d{2}/;
const CARD = /\b(?:8600|9860|5614|4\d{3}|5[1-5]\d{2})[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/;
const LINK = /(https?:\/\/|www\.|t\.me\/|@[a-z0-9_]{5,})/i;
const PREPAYMENT = /(oldindan\s+to.?lov|avans\s+to.?la|predoplat|предоплат|kartaga\s+tashla|zakalat)/i;

export function assessText(title: string, description: string): RiskSignal[] {
  const text = `${title}\n${description}`;
  const signals: RiskSignal[] = [];
  if (CARD.test(text)) signals.push({ code: 'card_number', severity: 'BLOCKING' });
  if (PHONE.test(text)) signals.push({ code: 'phone_in_text', severity: 'WARNING' });
  if (LINK.test(text)) signals.push({ code: 'external_link', severity: 'WARNING' });
  if (PREPAYMENT.test(text)) signals.push({ code: 'prepayment', severity: 'WARNING' });
  return signals;
}

export function assessPrice(priceUzs: bigint | null, referenceUzs: bigint | null): RiskSignal[] {
  if (priceUzs == null || referenceUzs == null || priceUzs <= 0n) return [];
  return priceUzs * 4n < referenceUzs ? [{ code: 'price_outlier', severity: 'WARNING' }] : [];
}

export function requiresModeration(signals: RiskSignal[]): boolean {
  return signals.some((s) => s.severity !== 'INFO');
}

export function hasBlocking(signals: RiskSignal[]): boolean {
  return signals.some((s) => s.severity === 'BLOCKING');
}

/** Chat heuristics: flag (not block) messages that ask for card data/prepayment. */
export function isRiskyMessage(text: string): boolean {
  return CARD.test(text) || PREPAYMENT.test(text);
}
