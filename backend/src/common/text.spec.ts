import { $Enums } from '@prisma/client';
import {
  apiEnum,
  buildSearchText,
  dbEnum,
  maskPhone,
  normalizeQuery,
  normalizeText,
  normalizeUzPhone,
} from './text';

describe('text normalization', () => {
  it('folds case, apostrophes and Cyrillic', () => {
    expect(normalizeText('Qo‘ng‘iroq')).toBe('qongiroq');
    expect(normalizeText('Кобальт 2023!')).toBe('kobalt 2023');
  });

  it('maps colloquial spellings to canonical tokens', () => {
    expect(normalizeQuery('Ayfon 14')).toBe('iphone 14');
    expect(buildSearchText('Santexnika', null, 'xizmati')).toBe('santexnik xizmati');
  });
});

describe('phone normalization', () => {
  it.each([
    ['+998 90 123-45-67', '998901234567'],
    ['901234567', '998901234567'],
    ['8 90 1234567', '998901234567'],
    ['998 33 111 22 33', '998331112233'],
  ])('%s → %s', (raw, expected) => expect(normalizeUzPhone(raw)).toBe(expected));

  it.each(['12345', '+7 999 123 45 67', '998001234567', ''])('rejects %s', (raw) =>
    expect(normalizeUzPhone(raw)).toBeNull(),
  );

  it('masks all but operator and last two digits', () => {
    expect(maskPhone('998901234567')).toBe('+998 90 *** ** 67');
  });
});

describe('api enums', () => {
  it('round-trips between DB and API styles', () => {
    expect(apiEnum('PENDING_REVIEW')).toBe('pendingReview');
    expect(apiEnum('UP_TO_1')).toBe('upTo1');
    expect(dbEnum('pendingReview')).toBe('PENDING_REVIEW');
    expect(dbEnum('active')).toBe('ACTIVE');
    expect(dbEnum('upTo1')).toBe('UP_TO_1');
    expect(apiEnum('ONE_TO_3')).toBe('oneTo3');
  });

  it('round-trips every database enum value', () => {
    for (const values of Object.values($Enums)) {
      for (const value of Object.values(values as Record<string, string>)) {
        expect(dbEnum(apiEnum(value))).toBe(value);
      }
    }
    expect(apiEnum(null)).toBeNull();
  });
});
