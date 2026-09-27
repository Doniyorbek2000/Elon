/**
 * Reference taxonomy (mirrors the app's bundled catalog so offline-first
 * clients and the server agree on ids). Admin tooling can edit these rows
 * later; the seed only upserts, it never deletes admin changes to other rows.
 */

export type AttributeTypeName = 'TEXT' | 'NUMBER' | 'BOOLEAN' | 'SELECT' | 'MULTI_SELECT';

export interface AttributeSeed {
  key: string;
  label: string;
  type: AttributeTypeName;
  required?: boolean;
  filterable?: boolean;
  unit?: string;
  min?: number;
  max?: number;
  hint?: string;
  options?: string[];
}

export interface SchemaSeed {
  attributes: AttributeSeed[];
  priceMode?: 'REQUIRED' | 'OPTIONAL' | 'SALARY' | 'NONE';
  supportsCondition?: boolean;
  photosRequired?: boolean;
  allowUsd?: boolean;
  titleHint?: string;
}

export interface CategorySeed {
  id: string;
  name: string;
  subtitle?: string;
  iconKey: string;
  tone: string;
  kind?: 'MARKETPLACE' | 'JOBS' | 'SERVICES';
  schema?: SchemaSeed;
  children?: CategorySeed[];
}

const generic: SchemaSeed = { attributes: [] };

const car: SchemaSeed = {
  allowUsd: true,
  titleHint: 'Masalan: Chevrolet Cobalt 2022',
  attributes: [
    {
      key: 'brand',
      label: 'Marka',
      type: 'SELECT',
      required: true,
      filterable: true,
      options: ['Chevrolet', 'Kia', 'Hyundai', 'BYD', 'Toyota', 'Lada', 'Daewoo', 'Boshqa'],
    },
    { key: 'model', label: 'Model', type: 'TEXT', hint: 'Masalan: Cobalt' },
    { key: 'year', label: 'Yili', type: 'NUMBER', required: true, filterable: true, min: 1970, max: 2027 },
    { key: 'mileage', label: 'Probeg', type: 'NUMBER', unit: 'km', filterable: true, min: 0, max: 2000000 },
    {
      key: 'transmission',
      label: 'Uzatma',
      type: 'SELECT',
      filterable: true,
      options: ['Avtomat', 'Mexanika', 'Robot', 'Variator'],
    },
    {
      key: 'fuel',
      label: 'Yoqilg‘i',
      type: 'SELECT',
      filterable: true,
      options: ['Benzin', 'Metan', 'Propan', 'Dizel', 'Gibrid', 'Elektr'],
    },
    {
      key: 'color',
      label: 'Rang',
      type: 'SELECT',
      options: ['Oq', 'Qora', 'Kumush', 'Kulrang', 'Ko‘k', 'Qizil', 'Boshqa'],
    },
    {
      key: 'options',
      label: 'Qo‘shimcha jihozlar',
      type: 'MULTI_SELECT',
      options: [
        'Konditsioner',
        'Lyuk',
        'Orqa kamera',
        'Charm salon',
        'Multimediya',
        'Isitiladigan o‘rindiqlar',
      ],
    },
    { key: 'credit', label: 'Kreditga beriladi', type: 'BOOLEAN' },
  ],
};

const phone: SchemaSeed = {
  titleHint: 'Masalan: iPhone 14 Pro 256GB',
  attributes: [
    {
      key: 'brand',
      label: 'Brend',
      type: 'SELECT',
      required: true,
      filterable: true,
      options: ['Apple', 'Samsung', 'Xiaomi', 'Redmi', 'Honor', 'Vivo', 'Boshqa'],
    },
    { key: 'model', label: 'Model', type: 'TEXT', hint: 'Masalan: iPhone 14 Pro' },
    {
      key: 'memory',
      label: 'Xotira',
      type: 'SELECT',
      filterable: true,
      options: ['64 GB', '128 GB', '256 GB', '512 GB', '1 TB'],
    },
    { key: 'color', label: 'Rang', type: 'TEXT', hint: 'Masalan: Deep Purple' },
    { key: 'warranty', label: 'Kafolat bor', type: 'BOOLEAN' },
  ],
};

const propertyType = ['Kvartira', 'Hovli uy', 'Ofis', 'Do‘kon', 'Ombor'];

const apartment: SchemaSeed = {
  supportsCondition: false,
  allowUsd: true,
  titleHint: 'Masalan: 3 xonali kvartira, markazda',
  attributes: [
    {
      key: 'dealType',
      label: 'Bitim turi',
      type: 'SELECT',
      required: true,
      filterable: true,
      options: ['Sotish', 'Ijara', 'Kunlik ijara'],
    },
    { key: 'propertyType', label: 'Mulk turi', type: 'SELECT', filterable: true, options: propertyType },
    { key: 'rooms', label: 'Xonalar', type: 'NUMBER', required: true, filterable: true, min: 1, max: 20 },
    {
      key: 'area',
      label: 'Maydon',
      type: 'NUMBER',
      unit: 'm²',
      required: true,
      filterable: true,
      min: 5,
      max: 2000,
    },
    { key: 'floor', label: 'Qavat', type: 'NUMBER', min: 1, max: 60 },
    { key: 'floors', label: 'Qavatlar soni', type: 'NUMBER', min: 1, max: 60 },
    {
      key: 'renovation',
      label: 'Ta’mir',
      type: 'SELECT',
      options: ['Yevro ta’mir', 'O‘rtacha', 'Ta’mirsiz', 'Qora suvoq'],
    },
    {
      key: 'amenities',
      label: 'Qulayliklar',
      type: 'MULTI_SELECT',
      options: ['Gaz', 'Konditsioner', 'Internet', 'Mebel', 'Lift', 'Avtoturargoh'],
    },
  ],
};

const house: SchemaSeed = {
  supportsCondition: false,
  allowUsd: true,
  titleHint: 'Masalan: Hovli uy, 6 sotix',
  attributes: [
    {
      key: 'dealType',
      label: 'Bitim turi',
      type: 'SELECT',
      required: true,
      filterable: true,
      options: ['Sotish', 'Ijara'],
    },
    { key: 'rooms', label: 'Xonalar', type: 'NUMBER', required: true, filterable: true, min: 1, max: 40 },
    { key: 'land', label: 'Yer maydoni', type: 'NUMBER', unit: 'sotix', filterable: true, min: 1, max: 1000 },
    { key: 'area', label: 'Uy maydoni', type: 'NUMBER', unit: 'm²', min: 10, max: 5000 },
    { key: 'gas', label: 'Gaz', type: 'BOOLEAN' },
  ],
};

const land: SchemaSeed = {
  supportsCondition: false,
  allowUsd: true,
  titleHint: 'Masalan: 8 sotix yer, yo‘l bo‘yida',
  attributes: [
    {
      key: 'land',
      label: 'Maydon',
      type: 'NUMBER',
      unit: 'sotix',
      required: true,
      filterable: true,
      min: 1,
      max: 100000,
    },
    {
      key: 'purpose',
      label: 'Maqsadi',
      type: 'SELECT',
      filterable: true,
      options: ['Uy-joy qurilishi', 'Tijorat', 'Qishloq xo‘jaligi', 'Bog‘'],
    },
  ],
};

const animal: SchemaSeed = {
  supportsCondition: false,
  titleHint: 'Masalan: Sog‘in sigir',
  attributes: [
    { key: 'age', label: 'Yoshi', type: 'TEXT', hint: 'Masalan: 2 yosh' },
    { key: 'count', label: 'Soni', type: 'NUMBER', min: 1, max: 10000 },
  ],
};

/** Jobs and services have dedicated models; these roots only drive navigation. */
const jobRoot: SchemaSeed = {
  attributes: [],
  priceMode: 'SALARY',
  supportsCondition: false,
  photosRequired: false,
  titleHint: 'Masalan: Sotuvchi kerak',
};
const serviceRoot: SchemaSeed = {
  attributes: [],
  priceMode: 'OPTIONAL',
  supportsCondition: false,
  photosRequired: false,
  titleHint: 'Masalan: Santexnik xizmatlari',
};

export const CATEGORY_TREE: CategorySeed[] = [
  {
    id: 'transport',
    name: 'Avtomobil',
    subtitle: 'Avtomobillar, ehtiyot qismlar',
    iconKey: 'car',
    tone: 'red',
    children: [
      { id: 'cars', name: 'Yengil avtomobillar', iconKey: 'car', tone: 'red', schema: car },
      { id: 'car_parts', name: 'Ehtiyot qismlar', iconKey: 'parts', tone: 'red' },
      { id: 'trucks', name: 'Yuk mashinalari', iconKey: 'truck', tone: 'red', schema: car },
      { id: 'moto', name: 'Mototexnika', iconKey: 'moto', tone: 'red' },
    ],
  },
  {
    id: 'real_estate',
    name: 'Uy-joy',
    subtitle: 'Sotish, ijaraga berish',
    iconKey: 'home',
    tone: 'teal',
    children: [
      { id: 'apartments', name: 'Kvartiralar', iconKey: 'apartment', tone: 'teal', schema: apartment },
      { id: 'houses', name: 'Hovli uylar', iconKey: 'home', tone: 'teal', schema: house },
      { id: 'rent', name: 'Ijara', iconKey: 'key', tone: 'teal', schema: apartment },
      { id: 'commercial', name: 'Tijorat binolari', iconKey: 'store', tone: 'teal', schema: apartment },
    ],
  },
  {
    id: 'electronics',
    name: 'Elektronika',
    subtitle: 'Telefon, noutbuk, aksessuarlar',
    iconKey: 'phone',
    tone: 'blue',
    children: [
      { id: 'phones', name: 'Telefonlar', iconKey: 'phone', tone: 'blue', schema: phone },
      { id: 'laptops', name: 'Noutbuklar', iconKey: 'laptop', tone: 'blue' },
      { id: 'tv', name: 'Televizorlar', iconKey: 'tv', tone: 'blue' },
      { id: 'accessories', name: 'Aksessuarlar', iconKey: 'headphones', tone: 'blue' },
    ],
  },
  {
    id: 'appliances',
    name: 'Maishiy texnika',
    subtitle: 'Sovutgich, kir yuvish mashinasi',
    iconKey: 'appliance',
    tone: 'slate',
    children: [
      { id: 'fridges', name: 'Sovutgichlar', iconKey: 'fridge', tone: 'slate' },
      { id: 'washers', name: 'Kir yuvish mashinalari', iconKey: 'appliance', tone: 'slate' },
      { id: 'climate', name: 'Konditsionerlar', iconKey: 'climate', tone: 'slate' },
      { id: 'kitchen', name: 'Oshxona texnikasi', iconKey: 'kitchen', tone: 'slate' },
    ],
  },
  {
    id: 'clothing',
    name: 'Kiyim-kechak',
    subtitle: 'Erkaklar, ayollar, bolalar',
    iconKey: 'clothes',
    tone: 'purple',
    children: [
      { id: 'men', name: 'Erkaklar kiyimi', iconKey: 'clothes', tone: 'purple' },
      { id: 'women', name: 'Ayollar kiyimi', iconKey: 'dress', tone: 'purple' },
      { id: 'kids', name: 'Bolalar kiyimi', iconKey: 'child', tone: 'purple' },
      { id: 'shoes', name: 'Poyabzal', iconKey: 'shoe', tone: 'purple' },
    ],
  },
  {
    id: 'home_goods',
    name: 'Uy-ro‘zg‘or',
    subtitle: 'Mebel, idish-tovoq, dekor',
    iconKey: 'sofa',
    tone: 'orange',
    children: [
      { id: 'furniture', name: 'Mebel', iconKey: 'sofa', tone: 'orange' },
      { id: 'dishes', name: 'Idish-tovoq', iconKey: 'kitchen', tone: 'orange' },
      { id: 'decor', name: 'Dekor va gilamlar', iconKey: 'decor', tone: 'orange' },
      { id: 'garden', name: 'Bog‘ uchun', iconKey: 'garden', tone: 'orange' },
    ],
  },
  {
    id: 'construction',
    name: 'Qurilish',
    subtitle: 'Sement, g‘isht, taxta va boshqalar',
    iconKey: 'construction',
    tone: 'amber',
    children: [
      { id: 'cement', name: 'Sement va aralashmalar', iconKey: 'construction', tone: 'amber' },
      { id: 'bricks', name: 'G‘isht va blok', iconKey: 'brick', tone: 'amber' },
      { id: 'wood', name: 'Taxta va yog‘och', iconKey: 'wood', tone: 'amber' },
      { id: 'tools', name: 'Asbob-uskunalar', iconKey: 'tools', tone: 'amber' },
    ],
  },
  {
    id: 'animals',
    name: 'Hayvonlar',
    subtitle: 'Chorva, qushlar, uy hayvonlari',
    iconKey: 'pets',
    tone: 'pink',
    children: [
      { id: 'livestock', name: 'Chorva', iconKey: 'cow', tone: 'pink', schema: animal },
      { id: 'poultry', name: 'Parrandalar', iconKey: 'bird', tone: 'pink', schema: animal },
      { id: 'pets', name: 'Uy hayvonlari', iconKey: 'pets', tone: 'pink', schema: animal },
      { id: 'feed', name: 'Yem-xashak', iconKey: 'grass', tone: 'pink' },
    ],
  },
  {
    id: 'land',
    name: 'Yer/Imorat',
    subtitle: 'Yer uchastka, bino, tijorat',
    iconKey: 'land',
    tone: 'green',
    children: [
      { id: 'plots', name: 'Yer uchastkalari', iconKey: 'land', tone: 'green', schema: land },
      { id: 'buildings', name: 'Imoratlar', iconKey: 'building', tone: 'green', schema: house },
    ],
  },
  {
    id: 'jobs',
    name: 'Ish',
    subtitle: 'Vakansiyalar, ish qidiraman',
    iconKey: 'work',
    tone: 'teal',
    kind: 'JOBS',
    schema: jobRoot,
  },
  {
    id: 'services',
    name: 'Xizmatlar',
    subtitle: 'Ustalar, ta’mirlash, yetkazib berish',
    iconKey: 'services',
    tone: 'indigo',
    kind: 'SERVICES',
    schema: serviceRoot,
  },
  {
    id: 'other',
    name: 'Boshqalar',
    subtitle: 'Boshqa e’lonlar',
    iconKey: 'grid',
    tone: 'blue',
    schema: generic,
  },
];

export const HOME_SHORTCUTS = [
  'transport',
  'real_estate',
  'electronics',
  'appliances',
  'clothing',
  'home_goods',
  'construction',
  'animals',
  'services',
  'land',
  'jobs',
];

export const SERVICE_CATEGORIES = [
  { id: 'repair', name: 'Ta’mirlash', iconKey: 'build', tone: 'blue' },
  { id: 'plumber', name: 'Santexnik', iconKey: 'plumbing', tone: 'teal' },
  { id: 'electrician', name: 'Elektrik', iconKey: 'bolt', tone: 'amber' },
  { id: 'welder', name: 'Payvandchi', iconKey: 'welding', tone: 'purple' },
  { id: 'moving', name: 'Yuk tashish', iconKey: 'truck', tone: 'orange' },
  { id: 'cleaning', name: 'Tozalash', iconKey: 'cleaning', tone: 'blue' },
  { id: 'design', name: 'Dizayn', iconKey: 'design', tone: 'red' },
  { id: 'tutor', name: 'Repetitor', iconKey: 'school', tone: 'green' },
  { id: 'barber', name: 'Sartarosh', iconKey: 'barber', tone: 'orange' },
  { id: 'beauty', name: 'Go‘zallik', iconKey: 'beauty', tone: 'pink' },
  { id: 'it', name: 'IT xizmatlari', iconKey: 'computer', tone: 'indigo' },
  { id: 'other_services', name: 'Boshqalar', iconKey: 'grid', tone: 'slate' },
];
