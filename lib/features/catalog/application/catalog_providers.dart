import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/data/bundled_service_categories.dart';
import '../../services/domain/service_provider.dart';
import '../data/bundled_categories.dart';
import '../domain/category.dart';

/// Taxonomy is bundled for instant first paint; a remote catalog source can
/// override this provider once the backend serves versioned categories.
final categoryTreeProvider = Provider<CategoryTree>((ref) => BundledCategories.tree);

final homeShortcutsProvider = Provider<List<Category>>((ref) {
  final tree = ref.watch(categoryTreeProvider);
  return [for (final id in BundledCategories.homeShortcutIds) ?tree.byId(id)];
});

final serviceCategoriesProvider = Provider<List<ServiceCategory>>((ref) => BundledServiceCategories.all);
