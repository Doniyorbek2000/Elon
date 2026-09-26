import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

enum SavedKind { listing, job, provider }

/// Locally persisted favorites for listings, jobs and service providers.
/// Keys look like `listing:l_cobalt_2023`. When accounts sync to the backend
/// this controller becomes the optimistic cache in front of the API.
class SavedItemsController extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(keyValueStoreProvider).getStringList(StoreKeys.savedItems).toSet();

  static String key(SavedKind kind, String id) => '${kind.name}:$id';

  bool isSaved(SavedKind kind, String id) => state.contains(key(kind, id));

  /// Returns the new saved state.
  bool toggle(SavedKind kind, String id) {
    final itemKey = key(kind, id);
    final saved = !state.contains(itemKey);
    final next = saved ? {...state, itemKey} : ({...state}..remove(itemKey));
    state = next;
    ref.read(keyValueStoreProvider).setStringList(StoreKeys.savedItems, next.toList()).ignore();
    return saved;
  }

  List<String> idsOf(SavedKind kind) => [
    for (final entry in state)
      if (entry.startsWith('${kind.name}:')) entry.substring(kind.name.length + 1),
  ];
}

final savedItemsProvider = NotifierProvider<SavedItemsController, Set<String>>(SavedItemsController.new);

/// Fine-grained selector so a card only rebuilds when its own state flips.
final isSavedProvider = Provider.family<bool, (SavedKind, String)>((ref, args) {
  return ref.watch(savedItemsProvider.select((items) => items.contains(SavedItemsController.key(args.$1, args.$2))));
});
