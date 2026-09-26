import '../../../core/design/app_colors.dart';
import '../domain/category.dart';

/// Taxonomy shipped with the app so the first frame never waits on the
/// network. A backend can later serve the same structure (with versioning)
/// and the catalog repository will refresh it in the background.
abstract final class BundledCategories {
  static const _carFields = [
    AttributeField(
      key: 'brand',
      label: 'Marka',
      type: AttributeInputType.select,
      required: true,
      options: ['Chevrolet', 'Kia', 'Hyundai', 'BYD', 'Toyota', 'Lada', 'Daewoo', 'Boshqa'],
    ),
    AttributeField(key: 'year', label: 'Yili', type: AttributeInputType.number, required: true, min: 1970, max: 2027),
    AttributeField(key: 'mileage', label: 'Probeg', type: AttributeInputType.number, unit: 'km', min: 0, max: 2000000),
    AttributeField(
      key: 'transmission',
      label: 'Uzatma',
      type: AttributeInputType.select,
      options: ['Avtomat', 'Mexanika', 'Robot', 'Variator'],
    ),
    AttributeField(
      key: 'fuel',
      label: 'Yoqilg‘i',
      type: AttributeInputType.select,
      options: ['Benzin', 'Metan', 'Propan', 'Dizel', 'Gibrid', 'Elektr'],
    ),
    AttributeField(
      key: 'color',
      label: 'Rang',
      type: AttributeInputType.select,
      options: ['Oq', 'Qora', 'Kumush', 'Kulrang', 'Ko‘k', 'Qizil', 'Boshqa'],
    ),
  ];

  static const _carSchema = CategoryFormSchema(fields: _carFields, allowUsd: true);

  static const _phoneSchema = CategoryFormSchema(
    fields: [
      AttributeField(
        key: 'brand',
        label: 'Brend',
        type: AttributeInputType.select,
        required: true,
        options: ['Apple', 'Samsung', 'Xiaomi', 'Redmi', 'Honor', 'Vivo', 'Boshqa'],
      ),
      AttributeField(
        key: 'memory',
        label: 'Xotira',
        type: AttributeInputType.select,
        options: ['64 GB', '128 GB', '256 GB', '512 GB', '1 TB'],
      ),
      AttributeField(key: 'color', label: 'Rang', type: AttributeInputType.text, hint: 'Masalan: Deep Purple'),
    ],
    titleHint: 'Masalan: iPhone 14 Pro 256GB',
  );

  static const _apartmentSchema = CategoryFormSchema(
    fields: [
      AttributeField(key: 'rooms', label: 'Xonalar', type: AttributeInputType.number, required: true, min: 1, max: 20),
      AttributeField(
        key: 'area',
        label: 'Maydon',
        type: AttributeInputType.number,
        unit: 'm²',
        required: true,
        min: 5,
        max: 2000,
      ),
      AttributeField(key: 'floor', label: 'Qavat', type: AttributeInputType.number, min: 1, max: 60),
      AttributeField(key: 'floors', label: 'Qavatlar soni', type: AttributeInputType.number, min: 1, max: 60),
      AttributeField(
        key: 'renovation',
        label: 'Ta’mir',
        type: AttributeInputType.select,
        options: ['Yevro ta’mir', 'O‘rtacha', 'Ta’mirsiz', 'Qora suvoq'],
      ),
    ],
    supportsCondition: false,
    allowUsd: true,
    titleHint: 'Masalan: 3 xonali kvartira, markazda',
  );

  static const _houseSchema = CategoryFormSchema(
    fields: [
      AttributeField(key: 'rooms', label: 'Xonalar', type: AttributeInputType.number, required: true, min: 1, max: 40),
      AttributeField(
        key: 'land',
        label: 'Yer maydoni',
        type: AttributeInputType.number,
        unit: 'sotix',
        min: 1,
        max: 1000,
      ),
      AttributeField(key: 'area', label: 'Uy maydoni', type: AttributeInputType.number, unit: 'm²', min: 10, max: 5000),
      AttributeField(key: 'gas', label: 'Gaz', type: AttributeInputType.select, options: ['Bor', 'Yo‘q']),
    ],
    supportsCondition: false,
    allowUsd: true,
    titleHint: 'Masalan: Hovli uy, 6 sotix',
  );

  static const _landSchema = CategoryFormSchema(
    fields: [
      AttributeField(
        key: 'land',
        label: 'Maydon',
        type: AttributeInputType.number,
        unit: 'sotix',
        required: true,
        min: 1,
        max: 100000,
      ),
      AttributeField(
        key: 'purpose',
        label: 'Maqsadi',
        type: AttributeInputType.select,
        options: ['Uy-joy qurilishi', 'Tijorat', 'Qishloq xo‘jaligi', 'Bog‘'],
      ),
    ],
    supportsCondition: false,
    allowUsd: true,
    titleHint: 'Masalan: 8 sotix yer, yo‘l bo‘yida',
  );

  static const _animalSchema = CategoryFormSchema(
    fields: [
      AttributeField(key: 'age', label: 'Yoshi', type: AttributeInputType.text, hint: 'Masalan: 2 yosh'),
      AttributeField(key: 'count', label: 'Soni', type: AttributeInputType.number, min: 1, max: 10000),
    ],
    supportsCondition: false,
    titleHint: 'Masalan: Sog‘in sigir',
  );

  static const _jobSchema = CategoryFormSchema(
    fields: [
      AttributeField(key: 'company', label: 'Kompaniya', type: AttributeInputType.text, required: true),
      AttributeField(
        key: 'employment',
        label: 'Bandlik turi',
        type: AttributeInputType.select,
        required: true,
        options: ['To‘liq stavka', 'Yarim stavka', 'Masofaviy', 'Vaqtinchalik'],
      ),
      AttributeField(
        key: 'experience',
        label: 'Tajriba',
        type: AttributeInputType.select,
        options: ['Tajribasiz', '1 yilgacha', '1–3 yil', '3 yildan ortiq'],
      ),
      AttributeField(key: 'hours', label: 'Ish vaqti', type: AttributeInputType.text, hint: 'Masalan: 09:00–18:00'),
    ],
    priceMode: PriceMode.salary,
    supportsCondition: false,
    photosRequired: false,
    titleHint: 'Masalan: Sotuvchi kerak',
  );

  static const _serviceSchema = CategoryFormSchema(
    fields: [
      AttributeField(key: 'experience', label: 'Tajriba (yil)', type: AttributeInputType.number, min: 0, max: 70),
      AttributeField(key: 'area', label: 'Xizmat hududi', type: AttributeInputType.text, hint: 'Masalan: Chust tumani'),
    ],
    priceMode: PriceMode.optional,
    supportsCondition: false,
    photosRequired: false,
    titleHint: 'Masalan: Santexnik xizmatlari',
  );

  static Category _node(
    String id,
    String name, {
    required String parent,
    required String icon,
    required AccentTone tone,
    CategoryFormSchema schema = CategoryFormSchema.generic,
  }) => Category(id: id, name: name, iconKey: icon, tone: tone, parentId: parent, schema: schema);

  static final List<Category> roots = [
    Category(
      id: 'transport',
      name: 'Avtomobil',
      subtitle: 'Avtomobillar, ehtiyot qismlar',
      iconKey: 'car',
      tone: AccentTone.red,
      schema: _carSchema,
      children: [
        _node(
          'cars',
          'Yengil avtomobillar',
          parent: 'transport',
          icon: 'car',
          tone: AccentTone.red,
          schema: _carSchema,
        ),
        _node('car_parts', 'Ehtiyot qismlar', parent: 'transport', icon: 'parts', tone: AccentTone.red),
        _node(
          'trucks',
          'Yuk mashinalari',
          parent: 'transport',
          icon: 'truck',
          tone: AccentTone.red,
          schema: _carSchema,
        ),
        _node('moto', 'Mototexnika', parent: 'transport', icon: 'moto', tone: AccentTone.red),
      ],
    ),
    Category(
      id: 'real_estate',
      name: 'Uy-joy',
      subtitle: 'Sotish, ijaraga berish',
      iconKey: 'home',
      tone: AccentTone.teal,
      schema: _apartmentSchema,
      children: [
        _node(
          'apartments',
          'Kvartiralar',
          parent: 'real_estate',
          icon: 'apartment',
          tone: AccentTone.teal,
          schema: _apartmentSchema,
        ),
        _node(
          'houses',
          'Hovli uylar',
          parent: 'real_estate',
          icon: 'home',
          tone: AccentTone.teal,
          schema: _houseSchema,
        ),
        _node('rent', 'Ijara', parent: 'real_estate', icon: 'key', tone: AccentTone.teal, schema: _apartmentSchema),
        _node(
          'commercial',
          'Tijorat binolari',
          parent: 'real_estate',
          icon: 'store',
          tone: AccentTone.teal,
          schema: _apartmentSchema,
        ),
      ],
    ),
    Category(
      id: 'electronics',
      name: 'Elektronika',
      subtitle: 'Telefon, noutbuk, aksessuarlar',
      iconKey: 'phone',
      tone: AccentTone.blue,
      children: [
        _node(
          'phones',
          'Telefonlar',
          parent: 'electronics',
          icon: 'phone',
          tone: AccentTone.blue,
          schema: _phoneSchema,
        ),
        _node('laptops', 'Noutbuklar', parent: 'electronics', icon: 'laptop', tone: AccentTone.blue),
        _node('tv', 'Televizorlar', parent: 'electronics', icon: 'tv', tone: AccentTone.blue),
        _node('accessories', 'Aksessuarlar', parent: 'electronics', icon: 'headphones', tone: AccentTone.blue),
      ],
    ),
    Category(
      id: 'appliances',
      name: 'Maishiy texnika',
      subtitle: 'Sovutgich, kir yuvish mashinasi',
      iconKey: 'appliance',
      tone: AccentTone.slate,
      children: [
        _node('fridges', 'Sovutgichlar', parent: 'appliances', icon: 'fridge', tone: AccentTone.slate),
        _node('washers', 'Kir yuvish mashinalari', parent: 'appliances', icon: 'appliance', tone: AccentTone.slate),
        _node('climate', 'Konditsionerlar', parent: 'appliances', icon: 'climate', tone: AccentTone.slate),
        _node('kitchen', 'Oshxona texnikasi', parent: 'appliances', icon: 'kitchen', tone: AccentTone.slate),
      ],
    ),
    Category(
      id: 'clothing',
      name: 'Kiyim-kechak',
      subtitle: 'Erkaklar, ayollar, bolalar',
      iconKey: 'clothes',
      tone: AccentTone.purple,
      children: [
        _node('men', 'Erkaklar kiyimi', parent: 'clothing', icon: 'clothes', tone: AccentTone.purple),
        _node('women', 'Ayollar kiyimi', parent: 'clothing', icon: 'dress', tone: AccentTone.purple),
        _node('kids', 'Bolalar kiyimi', parent: 'clothing', icon: 'child', tone: AccentTone.purple),
        _node('shoes', 'Poyabzal', parent: 'clothing', icon: 'shoe', tone: AccentTone.purple),
      ],
    ),
    Category(
      id: 'home_goods',
      name: 'Uy-ro‘zg‘or',
      subtitle: 'Mebel, idish-tovoq, dekor',
      iconKey: 'sofa',
      tone: AccentTone.orange,
      children: [
        _node('furniture', 'Mebel', parent: 'home_goods', icon: 'sofa', tone: AccentTone.orange),
        _node('dishes', 'Idish-tovoq', parent: 'home_goods', icon: 'kitchen', tone: AccentTone.orange),
        _node('decor', 'Dekor va gilamlar', parent: 'home_goods', icon: 'decor', tone: AccentTone.orange),
        _node('garden', 'Bog‘ uchun', parent: 'home_goods', icon: 'garden', tone: AccentTone.orange),
      ],
    ),
    Category(
      id: 'construction',
      name: 'Qurilish',
      subtitle: 'Sement, g‘isht, taxta va boshqalar',
      iconKey: 'construction',
      tone: AccentTone.amber,
      children: [
        _node('cement', 'Sement va aralashmalar', parent: 'construction', icon: 'construction', tone: AccentTone.amber),
        _node('bricks', 'G‘isht va blok', parent: 'construction', icon: 'brick', tone: AccentTone.amber),
        _node('wood', 'Taxta va yog‘och', parent: 'construction', icon: 'wood', tone: AccentTone.amber),
        _node('tools', 'Asbob-uskunalar', parent: 'construction', icon: 'tools', tone: AccentTone.amber),
      ],
    ),
    Category(
      id: 'animals',
      name: 'Hayvonlar',
      subtitle: 'Chorva, qushlar, uy hayvonlari',
      iconKey: 'pets',
      tone: AccentTone.pink,
      schema: _animalSchema,
      children: [
        _node('livestock', 'Chorva', parent: 'animals', icon: 'cow', tone: AccentTone.pink, schema: _animalSchema),
        _node('poultry', 'Parrandalar', parent: 'animals', icon: 'bird', tone: AccentTone.pink, schema: _animalSchema),
        _node('pets', 'Uy hayvonlari', parent: 'animals', icon: 'pets', tone: AccentTone.pink, schema: _animalSchema),
        _node('feed', 'Yem-xashak', parent: 'animals', icon: 'grass', tone: AccentTone.pink),
      ],
    ),
    Category(
      id: 'land',
      name: 'Yer/Imorat',
      subtitle: 'Yer uchastka, bino, tijorat',
      iconKey: 'land',
      tone: AccentTone.green,
      schema: _landSchema,
      children: [
        _node('plots', 'Yer uchastkalari', parent: 'land', icon: 'land', tone: AccentTone.green, schema: _landSchema),
        _node('buildings', 'Imoratlar', parent: 'land', icon: 'building', tone: AccentTone.green, schema: _houseSchema),
      ],
    ),
    const Category(
      id: 'jobs',
      name: 'Ish',
      subtitle: 'Vakansiyalar, ish qidiraman',
      iconKey: 'work',
      tone: AccentTone.teal,
      kind: CategoryKind.jobs,
      schema: _jobSchema,
    ),
    const Category(
      id: 'services',
      name: 'Xizmatlar',
      subtitle: 'Ustalar, ta’mirlash, yetkazib berish',
      iconKey: 'services',
      tone: AccentTone.indigo,
      kind: CategoryKind.services,
      schema: _serviceSchema,
    ),
    const Category(id: 'other', name: 'Boshqalar', subtitle: 'Boshqa e’lonlar', iconKey: 'grid', tone: AccentTone.blue),
  ];

  /// Order of shortcuts on the home grid (the last tile is "Barchasi").
  static const homeShortcutIds = [
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

  static final tree = CategoryTree(roots);
}
