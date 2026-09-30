import { isLang, msg, parseLang, render } from './i18n';

describe('server i18n', () => {
  it('renders Uzbek source with params and leaves unknown text alone', () => {
    expect(render(msg('Tarifingiz {date} kuni tugaydi.', { date: '2026-10-01' }), 'uz')).toBe(
      'Tarifingiz 2026-10-01 kuni tugaydi.',
    );
    expect(render('Noma’lum matn', 'ru')).toBe('Noma’lum matn');
  });

  it('translates to Russian keeping placeholders', () => {
    expect(render(msg('Tarifingiz {date} kuni tugaydi.', { date: '2026-10-01' }), 'ru')).toBe(
      'Ваш тариф заканчивается 2026-10-01.',
    );
    expect(render('Tarif faollashtirildi', 'ru')).toBe('Тариф активирован');
    expect(
      render(msg('{name} «{title}» vakansiyasiga ariza yubordi', { name: 'Aziz', title: 'Kassir' }), 'ru'),
    ).toBe('Aziz откликнулся на вакансию «Kassir»');
  });

  it('parses Accept-Language and validates languages', () => {
    expect(parseLang('ru-RU,ru;q=0.9,en;q=0.8')).toBe('ru');
    expect(parseLang('uz')).toBe('uz');
    expect(parseLang('en-US')).toBe('uz');
    expect(parseLang(undefined)).toBe('uz');
    expect(isLang('ru')).toBe(true);
    expect(isLang('de')).toBe(false);
  });
});
