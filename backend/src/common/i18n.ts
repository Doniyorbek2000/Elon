/**
 * Server-generated text (notifications, push) is written in Uzbek and
 * translated per recipient. Dynamic parts use `{name}` placeholders so the
 * whole sentence can be reordered by a translation.
 */
export const LANGUAGES = ['uz', 'ru'] as const;
export type Lang = (typeof LANGUAGES)[number];

export interface Msg {
  template: string;
  params?: Record<string, string | number>;
}

export const msg = (template: string, params?: Record<string, string | number>): Msg => ({
  template,
  params,
});

const RU: Record<string, string> = {
  'Yangi ariza': 'Новый отклик',
  '{name} «{title}» vakansiyasiga ariza yubordi': '{name} откликнулся на вакансию «{title}»',
  Nomzod: 'Кандидат',
  'Arizangiz ko‘rib chiqildi': 'Ваш отклик просмотрен',
  'Siz saralangan nomzodlar ro‘yxatidasiz': 'Вы в списке отобранных кандидатов',
  'Arizangiz qabul qilindi': 'Ваш отклик принят',
  'Arizangiz bo‘yicha javob keldi': 'Получен ответ по вашему отклику',
  'Ariza holati yangilandi': 'Статус отклика обновлён',
  '«{title}» — {company}': '«{title}» — {company}',
  'Yangi sharh': 'Новый отзыв',
  'To‘lov amalga oshmadi': 'Платёж не прошёл',
  'Hech narsa faollashtirilmadi va hisobingizdan yechilmadi.':
    'Ничего не активировано, деньги с вашего счёта не списаны.',
  'Tarif faollashtirildi': 'Тариф активирован',
  'Amal qilish muddati: {date} gacha.': 'Срок действия: до {date}.',
  '{title} faollashtirildi': '«{title}» активировано',
  'To‘lov qaytarildi': 'Платёж возвращён',
  'Xarid bekor qilindi va mablag‘ qaytarildi.': 'Покупка отменена, средства возвращены.',
  'Tarif muddati tugadi': 'Срок тарифа истёк',
  'Biznes tarifingiz muddati tugadi. Bepul tarif imkoniyatlari saqlanadi.':
    'Срок вашего бизнес-тарифа истёк. Возможности бесплатного тарифа сохраняются.',
  'Tarif muddati tugayapti': 'Срок тарифа заканчивается',
  'Tarifingiz {date} kuni tugaydi.': 'Ваш тариф заканчивается {date}.',
  '{title} tugayapti': 'Срок «{title}» заканчивается',
  'Targ‘ibot muddati tez orada tugaydi.': 'Срок продвижения скоро закончится.',
  'Yangi xabar': 'Новое сообщение',
  'E’loningiz faollashtirildi': 'Ваше объявление опубликовано',
  'E’loningiz rad etildi': 'Ваше объявление отклонено',
  Bepul: 'Бесплатно',
};

export function render(message: string | Msg, lang: Lang): string {
  const { template, params } =
    typeof message === 'string' ? { template: message, params: undefined } : message;
  let text = lang === 'ru' ? (RU[template] ?? template) : template;
  if (params)
    for (const [key, value] of Object.entries(params)) text = text.split(`{${key}}`).join(String(value));
  return text;
}

/** "ru-RU,ru;q=0.9,en;q=0.8" → "ru"; anything unsupported → "uz". */
export function parseLang(header: string | undefined): Lang {
  const first = header?.split(',')[0]?.trim().slice(0, 2).toLowerCase();
  return first === 'ru' ? 'ru' : 'uz';
}

export function isLang(value: unknown): value is Lang {
  return typeof value === 'string' && (LANGUAGES as readonly string[]).includes(value);
}
