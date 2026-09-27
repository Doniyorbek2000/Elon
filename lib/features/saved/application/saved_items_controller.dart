import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/key_value_store.dart';
import '../../auth/application/session_controller.dart';
import '../data/favorites_repository.dart';

enum SavedKind { listing, job, provider }

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => FavoritesRepository(ref.watch(apiClientProvider)),
);

/// Favorites for listings, jobs and service providers. Keys look like
/// `listing:<id>`.
///
/// * Demo/guest: persisted locally only.
/// * Signed in with a backend: the server is the source of truth. Toggles are
///   optimistic and roll back on failure; guest favorites are uploaded once
///   after sign-in.
class SavedItemsController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final local = ref.watch(keyValueStoreProvider).getStringList(StoreKeys.savedItems).toSet();
    final remote = !ref.watch(appConfigProvider).useDemoData;
    final signedIn = ref.watch(sessionProvider.select((user) => user?.id));
    if (remote && signedIn != null) unawaited(_sync(local));
    return local;
  }

  bool get _remote => !ref.read(appConfigProvider).useDemoData && ref.read(sessionProvider) != null;

  FavoritesRepository get _repository => ref.read(favoritesRepositoryProvider);

  static String key(SavedKind kind, String id) => '${kind.name}:$id';

  bool isSaved(SavedKind kind, String id) => state.contains(key(kind, id));

  Future<void> _sync(Set<String> local) async {
    try {
      final server = await _repository.ids();
      // Upload favorites made while signed out (bounded, best effort).
      for (final entry in local.difference(server).take(50)) {
        final (kind, id) = _parse(entry);
        await _repository.add(kind, id);
        server.add(entry);
      }
      if (ref.mounted) _persist(server);
    } on AppFailure catch (failure) {
      ref.read(appLoggerProvider).warning('Favorites sync failed: ${failure.runtimeType}');
    }
  }

  (SavedKind, String) _parse(String entry) {
    final separator = entry.indexOf(':');
    return (SavedKind.values.byName(entry.substring(0, separator)), entry.substring(separator + 1));
  }

  void _persist(Set<String> next) {
    state = next;
    ref.read(keyValueStoreProvider).setStringList(StoreKeys.savedItems, next.toList()).ignore();
  }

  /// Returns the new saved state. Throws an [AppFailure] (after rolling
  /// back) when the server rejects the change.
  Future<bool> toggle(SavedKind kind, String id) async {
    final itemKey = key(kind, id);
    final previous = state;
    final saved = !previous.contains(itemKey);
    _persist(saved ? {...previous, itemKey} : ({...previous}..remove(itemKey)));
    if (!_remote) return saved;
    try {
      if (saved) {
        await _repository.add(kind, id);
      } else {
        await _repository.remove(kind, id);
      }
      return saved;
    } on NotFoundFailure {
      // The item was removed server-side; drop it locally as well.
      _persist({...state}..remove(itemKey));
      rethrow;
    } on AppFailure {
      if (ref.mounted) _persist(previous);
      rethrow;
    }
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
