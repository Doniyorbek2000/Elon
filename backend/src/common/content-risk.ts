/**
 * Server-side content heuristics (the security boundary; the Flutter client
 * runs the same rules only as UX hints). Anything above INFO sends content to
 * moderation instead of publishing it directly.
 *
 * Text is normalized before matching so the usual evasions do not work:
 * apostrophe variants, full-width digits, digits spelled as Uzbek/Russian
 * words ("to‘qqiz nol bir …"), and arbitrary separators between digits.
 */
export type RiskSeverity = 'INFO' | 'WARNING' | 'BLOCKING';

export interface RiskSignal {
  code: string;
  severity: RiskSeverity;
}

/** Digit words → digit. Longest forms first so "to'qqiz" wins over shorter stems. */
const NUMBER_WORDS: ReadonlyArray<readonly [string, string]> = [
  ['toqqiz', '9'],
  ['sakkiz', '8'],
  ['yetti', '7'],
  ['olti', '6'],
  ['tort', '4'],
  ['besh', '5'],
  ['ikki', '2'],
  ['nol', '0'],
  ['nul', '0'],
  ['uch', '3'],
  ['bir', '1'],
  ['девять', '9'],
  ['восемь', '8'],
  ['четыре', '4'],
  ['шесть', '6'],
  ['пять', '5'],
  ['семь', '7'],
  ['ноль', '0'],
  ['один', '1'],
  ['два', '2'],
  ['три', '3'],
  ['тўққиз', '9'],
  ['саккиз', '8'],
  ['етти', '7'],
  ['олти', '6'],
  ['тўрт', '4'],
  ['беш', '5'],
  ['икки', '2'],
  ['нол', '0'],
  ['уч', '3'],
  ['бир', '1'],
];

const APOSTROPHES = /[‘’ʻʼ'`´ʹ]/g;

/** Lower-case, NFKC (full-width → ASCII), apostrophes removed. */
function fold(text: string): string {
  return text.normalize('NFKC').toLowerCase().replace(APOSTROPHES, '');
}

function spellDigits(folded: string): string {
  let result = folded;
  for (const [word, digit] of NUMBER_WORDS) {
    result = result.replace(new RegExp(`(?<![\\p{L}])${word}(?![\\p{L}])`, 'gu'), digit);
  }
  return result;
}

/** Uzbek mobile/landline operator codes (after the optional 998 country prefix). */
const OPERATOR_CODES =
  '(?:33|50|55|61|62|65|66|67|69|70|71|72|73|74|75|76|77|78|79|88|90|91|93|94|95|97|98|99)';
const PHONE_DIGITS = new RegExp(`^(?:998)?${OPERATOR_CODES}\\d{7}$`);
const CARD_PREFIX = /^(?:8600|9860|5614|4\d{3}|5[1-5]\d{2}|6\d{3})/;

/** Runs of digits that may be split by separators, e.g. "+998 (90) 123-45-67" or "90.123.45.67". */
const DIGIT_RUN = /\+?\d(?:[\d\s.\-_()/,*·•]{0,3}\d){7,20}/g;
const CURRENCY_AFTER = /^\s*(?:so.?m|сум|sum|uzs|usd|dollar|\$|у\.?е|y\.?e|ming|mln|million)/;
/** "900 000 000" – a price written with thousands grouping, not a phone number. */
const THOUSANDS_GROUPING = /^\d{1,3}(?:[ .,]\d{3}){2,}$/;

interface DigitRun {
  raw: string;
  digits: string;
  after: string;
}

function digitRuns(text: string): DigitRun[] {
  const prepared = spellDigits(fold(text));
  const runs: DigitRun[] = [];
  for (const match of prepared.matchAll(DIGIT_RUN)) {
    const raw = match[0];
    const end = (match.index ?? 0) + raw.length;
    runs.push({ raw, digits: raw.replace(/\D/g, ''), after: prepared.slice(end, end + 12) });
  }
  return runs;
}

function luhn(digits: string): boolean {
  let sum = 0;
  for (let i = 0; i < digits.length; i++) {
    let d = Number(digits[digits.length - 1 - i]);
    if (i % 2 === 1) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 === 0;
}

function isPhoneRun(run: DigitRun): boolean {
  if (!PHONE_DIGITS.test(run.digits)) return false;
  if (THOUSANDS_GROUPING.test(run.raw.trim())) return false;
  return !CURRENCY_AFTER.test(run.after);
}

/** 13–19 digits with a known issuer prefix. */
function cardMatch(run: DigitRun): 'valid' | 'shaped' | null {
  if (run.digits.length < 13 || run.digits.length > 19 || !CARD_PREFIX.test(run.digits)) return null;
  return luhn(run.digits) ? 'valid' : run.digits.length === 16 ? 'shaped' : null;
}

const LINK =
  /(https?:\/\/|www\.|t\.me\b|\btme\/|telegram\.me|wa\.me|instagram\.com|(?<![\w.])@[a-z0-9_]{5,})/i;
const DOMAIN =
  /\b[a-z0-9][a-z0-9-]{1,}\s?(?:\.|\(dot\)|\[dot\]|\bnuqta\b)\s?(?:uz|com|ru|net|org|me|io|ly|xyz|info|site)\b/i;
const MESSENGER =
  /(telegram|телеграм|whatsapp|watsap|vatsap|вацап|ватсап|viber|вайбер|instagram|инстаграм|imo)/i;
const CONTACT_VERB = /(yoz|aloqa|boglan|murojaat|raqam|nomer|номер|напиш|пиш|связ|позвон|@)/i;
const PREPAYMENT =
  /(oldindan\s+(?:tolov|pul)|avans|predoplat|предоплат|kartaga\s+(?:pul\s+)?(?:tashla|otkaz|yubor)|zakalat|zalog|depozit|kafolat\s+pul|перевед\w*\s+на\s+карт|click\s+orqali\s+(?:tola|otkaz)|payme\s+orqali\s+(?:tola|otkaz))/i;

export function assessText(title: string, description: string): RiskSignal[] {
  const text = `${title}\n${description}`;
  const folded = fold(text);
  const signals: RiskSignal[] = [];
  const runs = digitRuns(text);

  const cards = runs.map(cardMatch);
  if (cards.includes('valid')) signals.push({ code: 'card_number', severity: 'BLOCKING' });
  else if (cards.includes('shaped')) signals.push({ code: 'card_like_number', severity: 'WARNING' });

  if (runs.some(isPhoneRun)) signals.push({ code: 'phone_in_text', severity: 'WARNING' });
  if (LINK.test(folded) || DOMAIN.test(folded)) signals.push({ code: 'external_link', severity: 'WARNING' });
  if (MESSENGER.test(folded) && CONTACT_VERB.test(folded)) {
    signals.push({ code: 'off_platform_contact', severity: 'WARNING' });
  }
  if (PREPAYMENT.test(folded)) signals.push({ code: 'prepayment', severity: 'WARNING' });
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
  const runs = digitRuns(text);
  return runs.some((run) => cardMatch(run) !== null) || PREPAYMENT.test(fold(text));
}
