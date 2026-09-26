import 'package:flutter/foundation.dart';

import '../../../core/design/app_colors.dart';

/// Which vertical a category belongs to. Jobs and services have dedicated
/// experiences; marketplace categories share the listing flow.
enum CategoryKind { marketplace, jobs, services }

enum AttributeInputType { text, number, select }

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

  String? validate(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return required ? '$label kiritilishi shart' : null;
    if (type == AttributeInputType.number) {
      final number = int.tryParse(trimmed.replaceAll(RegExp(r'\s'), ''));
      if (number == null) return 'Faqat raqam kiriting';
      if (min != null && number < min!) return 'Kamida $min';
      if (max != null && number > max!) return 'Ko‘pi bilan $max';
    }
    if (type == AttributeInputType.select && options.isNotEmpty && !options.contains(trimmed)) {
      return 'Ro‘yxatdan tanlang';
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

  String get priceLabel => priceMode == PriceMode.salary ? 'Maosh' : 'Narx';

  static const generic = CategoryFormSchema();
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

  @override
  bool operator ==(Object other) => other is Category && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Flattened lookup over the category tree.
class CategoryTree {
  CategoryTree(this.roots) {
    void index(Category category) {
      _byId[category.id] = category;
      for (final child in category.children) {
        index(child);
      }
    }

    roots.forEach(index);
  }

  final List<Category> roots;
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
    if (!identical(category.schema, CategoryFormSchema.generic)) return category.schema;
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
