import 'package:flutter/foundation.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/l10n/l10n.dart';

/// Which vertical a category belongs to. Jobs and services have dedicated
/// experiences; marketplace categories share the listing flow.
enum CategoryKind { marketplace, jobs, services }

enum AttributeInputType {
  text,
  number,
  select,
  multiSelect,
  boolean;

  static AttributeInputType parse(Object? value) =>
      values.firstWhere((type) => type.name == value, orElse: () => AttributeInputType.text);
}

/// Multi-select values are stored in drafts as a `|`-joined string.
const multiSelectSeparator = '|';

/// Server-drivable form field definition for category-specific attributes
/// (car year, apartment rooms, phone memory, …).
@immutable
class AttributeField {
  const AttributeField({
    required this.key,
    required this.label,
    required this.type,
    this.options = const [],
    this.unit,
    this.required = false,
    this.min,
    this.max,
    this.hint,
  });

  final String key;
  final String label;
  final AttributeInputType type;
  final List<String> options;
  final String? unit;
  final bool required;
  final int? min;
  final int? max;
  final String? hint;

  factory AttributeField.fromJson(Map<String, dynamic> json) => AttributeField(
    key: json['key'] as String,
    label: json['label'] as String,
    type: AttributeInputType.parse(json['type']),
    options: [for (final option in json['options'] as List<dynamic>? ?? const []) '$option'],
    unit: json['unit'] as String?,
    required: json['required'] as bool? ?? false,
    min: (json['min'] as num?)?.toInt(),
    max: (json['max'] as num?)?.toInt(),
    hint: json['hint'] as String?,
  );

  /// Converts the draft's string value to the typed API value.
  Object? toApiValue(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return switch (type) {
      AttributeInputType.number => int.tryParse(trimmed.replaceAll(RegExp(r'\s'), '')),
      AttributeInputType.boolean => trimmed == 'true',
      AttributeInputType.multiSelect => trimmed.split(multiSelectSeparator).where((v) => v.isNotEmpty).toList(),
      AttributeInputType.text || AttributeInputType.select => trimmed,
    };
  }

  /// Human-readable value (units appended, multi-select joined).
  String displayValue(String value) => switch (type) {
    AttributeInputType.boolean => value == 'true' ? tr('Ha') : tr('Yo‘q'),
    AttributeInputType.multiSelect => value.split(multiSelectSeparator).join(', '),
    _ => unit == null ? value : '$value $unit',
  };

  String? validate(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return required ? tr('{label} kiritilishi shart', {'label': label}) : null;
    if (type == AttributeInputType.multiSelect &&
        trimmed.split(multiSelectSeparator).any((v) => v.isNotEmpty && !options.contains(v))) {
      return tr('Ro‘yxatdan tanlang');
    }
    if (type == AttributeInputType.number) {
      final number = int.tryParse(trimmed.replaceAll(RegExp(r'\s'), ''));
      if (number == null) return tr('Faqat raqam kiriting');
      if (min != null && number < min!) return tr('Kamida {min}', {'min': min});
      if (max != null && number > max!) return tr('Ko‘pi bilan {max}', {'max': max});
    }
    if (type == AttributeInputType.select && options.isNotEmpty && !options.contains(trimmed)) {
      return tr('Ro‘yxatdan tanlang');
    }
    return null;
  }
}

/// How the price field behaves for a category.
enum PriceMode { required, optional, salary, none }

@immutable
class CategoryFormSchema {
  const CategoryFormSchema({
    this.fields = const [],
    this.priceMode = PriceMode.required,
    this.supportsCondition = true,
    this.photosRequired = true,
    this.allowUsd = false,
    this.titleHint = 'Masalan: Cobalt 2023',
  });

  final List<AttributeField> fields;
  final PriceMode priceMode;
  final bool supportsCondition;
  final bool photosRequired;
  final bool allowUsd;
  final String titleHint;

  String get priceLabel => priceMode == PriceMode.salary ? tr('Maosh') : tr('Narx');

  static const generic = CategoryFormSchema();

  factory CategoryFormSchema.fromJson(Map<String, dynamic> json) => CategoryFormSchema(
    fields: [
      for (final field in json['fields'] as List<dynamic>? ?? const [])
        AttributeField.fromJson(field as Map<String, dynamic>),
    ],
    priceMode: PriceMode.values.firstWhere((m) => m.name == json['priceMode'], orElse: () => PriceMode.required),
    supportsCondition: json['supportsCondition'] as bool? ?? true,
    photosRequired: json['photosRequired'] as bool? ?? true,
    allowUsd: json['allowUsd'] as bool? ?? false,
    titleHint: json['titleHint'] as String? ?? generic.titleHint,
  );
}

@immutable
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.tone,
    this.subtitle,
    this.kind = CategoryKind.marketplace,
    this.children = const [],
    this.schema = CategoryFormSchema.generic,
    this.parentId,
  });

  final String id;
  final String name;
  final String? subtitle;

  /// Resolved to an icon in the presentation layer (see `CategoryVisuals`).
  final String iconKey;
  final AccentTone tone;
  final CategoryKind kind;
  final List<Category> children;
  final CategoryFormSchema schema;
  final String? parentId;

  bool get hasChildren => children.isNotEmpty;

  /// Parses a node of `GET /categories` (children included).
  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    subtitle: json['subtitle'] as String?,
    iconKey: json['iconKey'] as String? ?? 'grid',
    tone: AccentTone.values.firstWhere((t) => t.name == json['tone'], orElse: () => AccentTone.blue),
    kind: CategoryKind.values.firstWhere((k) => k.name == json['kind'], orElse: () => CategoryKind.marketplace),
    parentId: json['parentId'] as String?,
    schema: json['schema'] is Map<String, dynamic>
        ? CategoryFormSchema.fromJson(json['schema'] as Map<String, dynamic>)
        : CategoryFormSchema.generic,
    children: [
      for (final child in json['children'] as List<dynamic>? ?? const [])
        Category.fromJson(child as Map<String, dynamic>),
    ],
  );

  @override
  bool operator ==(Object other) => other is Category && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Flattened lookup over the category tree.
class CategoryTree {
  /// [inheritRootSchema]: the bundled catalog defines forms on roots; the
  /// server defines them per category, so its tree must not inherit.
  CategoryTree(this.roots, {this.inheritRootSchema = true, this.homeShortcutIds}) {
    void index(Category category) {
      _byId[category.id] = category;
      for (final child in category.children) {
        index(child);
      }
    }

    roots.forEach(index);
  }

  final List<Category> roots;
  final bool inheritRootSchema;

  /// Server-flagged home shortcuts (null = use the bundled order).
  final List<String>? homeShortcutIds;
  final Map<String, Category> _byId = {};

  Category? byId(String? id) => id == null ? null : _byId[id];

  Category? parentOf(String id) => byId(byId(id)?.parentId);

  /// Root category for any node.
  Category? rootOf(String id) {
    var current = byId(id);
    while (current?.parentId != null) {
      current = byId(current!.parentId);
    }
    return current;
  }

  /// Schema of a leaf falls back to its root when the leaf has none.
  CategoryFormSchema schemaFor(String id) {
    final category = byId(id);
    if (category == null) return CategoryFormSchema.generic;
    if (!inheritRootSchema || !identical(category.schema, CategoryFormSchema.generic)) return category.schema;
    return rootOf(id)?.schema ?? CategoryFormSchema.generic;
  }

  /// True when [id] is [ancestorId] or one of its descendants.
  bool isWithin(String id, String ancestorId) {
    var current = byId(id);
    while (current != null) {
      if (current.id == ancestorId) return true;
      current = byId(current.parentId);
    }
    return false;
  }

  List<Category> get marketplaceRoots => roots.where((c) => c.kind == CategoryKind.marketplace).toList();
}
