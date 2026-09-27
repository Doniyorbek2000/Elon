/**
 * Search normalization shared by indexing and querying (mirrors the Flutter
 * `SearchNormalizer`): case folding, Uzbek apostrophe variants, Cyrillic →
 * Latin transliteration and colloquial synonyms.
 */
const CYRILLIC: Record<string, string> = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'j', з: 'z', и: 'i', й: 'y', к: 'k',
  л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'x', ц: 's',
  ч: 'ch', ш: 'sh', щ: 'sh', ъ: '', ы: 'i', ь: '', э: 'e', ю: 'yu', я: 'ya', ў: 'o', қ: 'q', ғ: 'g', ҳ: 'h',
};

const SYNONYMS: Record<string, string> = {
  ayfon: 'iphone',
  aifon: 'iphone',
  iphon: 'iphone',
  kobalt: 'cobalt',
  jentra: 'gentra',
  neksiya: 'nexia',
  nexiya: 'nexia',
  malibo: 'malibu',
  notebook: 'noutbuk',
  laptop: 'noutbuk',
  xonadon: 'kvartira',
  santexnika: 'santexnik',
  elektrika: 'elektrik',
  shofyor: 'haydovchi',
  voditel: 'haydovchi',
};

export function normalizeText(input: string): string {
  let out = '';
  for (const ch of input.toLowerCase()) out += CYRILLIC[ch] ?? ch;
  return out
    .replace(/[‘’ʻʼ`']/g, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function searchTokens(input: string): string[] {
  return normalizeText(input)
    .split(' ')
    .filter(Boolean)
    .map((token) => SYNONYMS[token] ?? token);
}

/** Normalized query string used against `searchText` columns. */
export function normalizeQuery(input: string): string {
  return searchTokens(input).join(' ');
}

/** Builds the indexed `searchText` for a document from its fields. */
export function buildSearchText(...parts: Array<string | null | undefined>): string {
  return searchTokens(parts.filter(Boolean).join(' ')).join(' ');
}

/**
 * Normalizes Uzbek mobile numbers to E.164 digits without '+':
 * "+998 90 123-45-67", "901234567", "8 90 1234567" → "998901234567".
 * Returns null when the number is not a plausible Uzbek number.
 */
export function normalizeUzPhone(raw: string): string | null {
  let digits = raw.replace(/\D/g, '');
  if (digits.length === 9) digits = `998${digits}`;
  if (digits.length === 10 && digits.startsWith('8')) digits = `998${digits.slice(1)}`;
  if (!/^998\d{9}$/.test(digits)) return null;
  const operator = digits.slice(3, 5);
  const known = ['20', '33', '50', '55', '77', '88', '90', '91', '93', '94', '95', '97', '98', '99', '61', '62', '65', '66', '67', '69', '71', '73', '74', '75', '76', '79'];
  return known.includes(operator) ? digits : null;
}

/** "+998 90 *** ** 67" */
export function maskPhone(phone: string): string {
  return `+998 ${phone.slice(3, 5)} *** ** ${phone.slice(10)}`;
}

/** 'PENDING_REVIEW' → 'pendingReview' (API enum style). */
export function apiEnum<T extends string>(value: T): string;
export function apiEnum<T extends string>(value: T | null | undefined): string | null;
export function apiEnum<T extends string>(value: T | null | undefined): string | null {
  if (value == null) return null;
  return value.toLowerCase().replace(/_([a-z0-9])/g, (_m, c: string) => c.toUpperCase());
}

/** 'pendingReview' → 'PENDING_REVIEW'. */
export function dbEnum(value: string): string {
  return value.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toUpperCase();
}
