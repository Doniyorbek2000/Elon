import '../../../core/design/app_colors.dart';
import '../domain/service_provider.dart';

abstract final class BundledServiceCategories {
  static const all = [
    ServiceCategory(
      id: 'repair',
      name: 'Ta’mirlash',
      iconKey: 'build',
      tone: AccentTone.blue,
    ),
    ServiceCategory(
      id: 'plumber',
      name: 'Santexnik',
      iconKey: 'plumbing',
      tone: AccentTone.teal,
    ),
    ServiceCategory(
      id: 'electrician',
      name: 'Elektrik',
      iconKey: 'bolt',
      tone: AccentTone.amber,
    ),
    ServiceCategory(
      id: 'welder',
      name: 'Payvandchi',
      iconKey: 'welding',
      tone: AccentTone.purple,
    ),
    ServiceCategory(
      id: 'moving',
      name: 'Yuk tashish',
      iconKey: 'truck',
      tone: AccentTone.orange,
    ),
    ServiceCategory(
      id: 'cleaning',
      name: 'Tozalash',
      iconKey: 'cleaning',
      tone: AccentTone.blue,
    ),
    ServiceCategory(
      id: 'design',
      name: 'Dizayn',
      iconKey: 'design',
      tone: AccentTone.red,
    ),
    ServiceCategory(
      id: 'tutor',
      name: 'Repetitor',
      iconKey: 'school',
      tone: AccentTone.green,
    ),
    ServiceCategory(
      id: 'barber',
      name: 'Sartarosh',
      iconKey: 'barber',
      tone: AccentTone.orange,
    ),
    ServiceCategory(
      id: 'beauty',
      name: 'Go‘zallik',
      iconKey: 'beauty',
      tone: AccentTone.pink,
    ),
    ServiceCategory(
      id: 'it',
      name: 'IT xizmatlari',
      iconKey: 'computer',
      tone: AccentTone.indigo,
    ),
    ServiceCategory(
      id: 'other_services',
      name: 'Boshqalar',
      iconKey: 'grid',
      tone: AccentTone.slate,
    ),
  ];

  static ServiceCategory? byId(String? id) =>
      all.where((c) => c.id == id).firstOrNull;
}
