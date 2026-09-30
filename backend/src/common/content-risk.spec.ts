import { assessPrice, assessText, hasBlocking, isRiskyMessage, requiresModeration } from './content-risk';

const codes = (title: string, description = '') => assessText(title, description).map((s) => s.code);

describe('content risk – phone numbers', () => {
  it.each([
    ['plain international', '+998 90 123 45 67'],
    ['dashes', '90-123-45-67'],
    ['dots and parentheses', '(90) 123.45.67'],
    ['local nine digits', '901234567'],
    ['country prefix without plus', '998901234567'],
    ['spelled in Uzbek', 'to‘qqiz nol bir ikki uch tort besh olti yetti'],
    ['spelled in Russian', 'девять ноль один два три четыре пять шесть семь'],
    ['full-width digits', '９０１２３４５６７'],
  ])('flags %s', (_name, phone) => {
    expect(codes('Sotiladi', `Aloqa: ${phone}`)).toContain('phone_in_text');
  });

  it.each([
    ['a price with thousands grouping', 'Narxi 900 000 000'],
    ['a price followed by currency', 'Narxi 901234567 so‘m'],
    ['room and floor counts', '3 xonali, 5 qavat, 85 kv.m, 2020 yil'],
    ['a VIN-like short number', 'Kod 12345'],
    ['an unknown operator code', '123456789'],
  ])('does not flag %s', (_name, text) => {
    expect(codes('Kvartira', text)).not.toContain('phone_in_text');
  });
});

describe('content risk – cards', () => {
  it('blocks Luhn-valid card numbers in any spacing', () => {
    expect(hasBlocking(assessText('x', '8600 1234 5678 9012'))).toBe(true);
    expect(hasBlocking(assessText('x', '8600-1234-5678-9012'))).toBe(true);
    expect(hasBlocking(assessText('x', '8600123456789012'))).toBe(true);
  });

  it('only warns for card-shaped numbers that fail the checksum', () => {
    const signals = assessText('x', '8600 1234 5678 9013');
    expect(hasBlocking(signals)).toBe(false);
    expect(signals.map((s) => s.code)).toContain('card_like_number');
  });

  it('flags cards in chat', () => {
    expect(isRiskyMessage('karta: 8600 1234 5678 9012')).toBe(true);
    // Card-shaped numbers are flagged in chat even when the checksum fails (typos).
    expect(isRiskyMessage('karta 8600 1234 5678 9013')).toBe(true);
    expect(isRiskyMessage('order 1234 5678')).toBe(false);
  });
});

describe('content risk – links, contacts, prepayment', () => {
  it.each([
    'https://example.com/x',
    'www.olx.uz',
    't.me/seller_5',
    'instagram.com/shop',
    '@my_shop_uz',
    'olx nuqta uz',
    'shop.uz',
  ])('flags link %s', (link) => {
    expect(codes('Sotiladi', link)).toContain('external_link');
  });

  it('flags moving the conversation to a messenger', () => {
    expect(codes('Sotiladi', 'Telegramga yozing')).toContain('off_platform_contact');
    expect(codes('Sotiladi', 'Напишите в вацап')).toContain('off_platform_contact');
    expect(codes('Telefon', 'Telegram ilovasi o‘rnatilgan')).not.toContain('off_platform_contact');
  });

  it.each([
    'Oldindan to‘lov kerak',
    'Oldindan to`lov',
    'avans to‘lang',
    'Предоплата обязательна',
    'kartaga pul tashlang',
    'Payme orqali to‘lang',
    'zakalat kerak',
  ])('flags prepayment "%s"', (text) => {
    expect(codes('Sotiladi', text)).toContain('prepayment');
    expect(isRiskyMessage(text)).toBe(true);
  });
});

describe('content risk – clean content and pricing', () => {
  it('lets ordinary listings through without moderation', () => {
    expect(
      requiresModeration(assessText('Cobalt 2023', 'Yurgani 45 000 km, holati a’lo. Narxi 150 000 000 so‘m')),
    ).toBe(false);
    expect(
      requiresModeration(assessText('iPhone 13 128GB', '3 xonali emas, faqat telefon. Qutisi bor.')),
    ).toBe(false);
  });

  it('flags prices far below the reference', () => {
    expect(assessPrice(10_000_000n, 120_000_000n)).toHaveLength(1);
    expect(assessPrice(100_000_000n, 120_000_000n)).toHaveLength(0);
    expect(assessPrice(null, 120_000_000n)).toHaveLength(0);
    expect(assessPrice(0n, 120_000_000n)).toHaveLength(0);
  });
});
