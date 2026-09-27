import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/key_value_store.dart';
import '../../services/data/bundled_service_categories.dart';
import '../../services/domain/service_provider.dart';
import '../data/bundled_categories.dart';
import '../domain/category.dart';

/// Server-driven taxonomy. The bundled copy paints the first frame (and works
/// offline on first launch); with a backend the `/categories` response (forms
/// included) replaces it and is cached for the next start.
class CategoryTreeController extends Notifier<CategoryTree> {
  static const _cacheKey = 'catalog.categories.v1';

  @override
  CategoryTree build() {
    if (ref.watch(appConfigProvider).useDemoData) return BundledCategories.tree;
    final store = ref.watch(keyValueStoreProvider);
    unawaited(_refresh(store));
    final cached = store.getString(_cacheKey);
    if (cached != null) {
      try {
        return _parse(jsonDecode(cached) as List<dynamic>);
      } on Object {
        store.remove(_cacheKey).ignore();
      }
    }
    return BundledCategories.tree;
  }

  static CategoryTree _parse(List<dynamic> json) {
    final roots = [for (final node in json) Category.fromJson(node as Map<String, dynamic>)];
    return CategoryTree(
      roots,
      inheritRootSchema: false,
      homeShortcutIds: [
        for (final node in json.cast<Map<String, dynamic>>())
          if (node['homeShortcut'] == true) node['id'] as String,
      ],
    );
  }

  Future<void> _refresh(KeyValueStore store) async {
    try {
      final json = await ref.read(apiClientProvider).get<List<dynamic>>('/categories');
      if (json.isEmpty || !ref.mounted) return;
      state = _parse(json);
      await store.setString(_cacheKey, jsonEncode(json));
    } on AppFailure {
      // Keep the cached/bundled catalog until the next successful refresh.
    }
  }
}

final categoryTreeProvider = NotifierProvider<CategoryTreeController, CategoryTree>(CategoryTreeController.new);

final homeShortcutsProvider = Provider<List<Category>>((ref) {
  final tree = ref.watch(categoryTreeProvider);
  final serverIds = tree.homeShortcutIds;
  final ids = serverIds == null || serverIds.isEmpty
      ? BundledCategories.homeShortcutIds
      : [
          // Keep the designed order for known ids; append new server shortcuts.
          ...BundledCategories.homeShortcutIds.where(serverIds.contains),
          ...serverIds.where((id) => !BundledCategories.homeShortcutIds.contains(id)),
        ];
  return [for (final id in ids) ?tree.byId(id)];
});

/// Service categories come from `/service-categories` (bundled until loaded).
class ServiceCategoriesController extends Notifier<List<ServiceCategory>> {
  @override
  List<ServiceCategory> build() {
    if (ref.watch(appConfigProvider).useDemoData) return BundledServiceCategories.all;
    unawaited(_refresh());
    return BundledServiceCategories.all;
  }

  Future<void> _refresh() async {
    try {
      final json = await ref.read(apiClientProvider).get<List<dynamic>>('/service-categories');
      if (json.isEmpty || !ref.mounted) return;
      state = [for (final item in json) ServiceCategory.fromJson(item as Map<String, dynamic>)];
    } on AppFailure {
      // Bundled list stays in place.
    }
  }
}

final serviceCategoriesProvider = NotifierProvider<ServiceCategoriesController, List<ServiceCategory>>(
  ServiceCategoriesController.new,
);
