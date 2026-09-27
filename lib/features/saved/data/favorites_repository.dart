import '../../../core/network/api_client.dart';
import '../application/saved_items_controller.dart';

/// Server-side favorites (`/favorites/*`). The controller in front of it is
/// optimistic and rolls back when a write fails.
class FavoritesRepository {
  const FavoritesRepository(this._api);

  final ApiClient _api;

  static String pathOf(SavedKind kind) => switch (kind) {
    SavedKind.listing => 'listings',
    SavedKind.job => 'jobs',
    SavedKind.provider => 'providers',
  };

  /// All favorite ids as `kind:id` keys.
  Future<Set<String>> ids() async {
    final data = await _api.get<JsonMap>('/favorites/ids');
    return {
      for (final kind in SavedKind.values)
        for (final id in data[pathOf(kind)] as List<dynamic>? ?? const [])
          SavedItemsController.key(kind, '$id'),
    };
  }

  Future<void> add(SavedKind kind, String id) =>
      _api.put<Object?>('/favorites/${pathOf(kind)}/$id');

  Future<void> remove(SavedKind kind, String id) =>
      _api.delete('/favorites/${pathOf(kind)}/$id');

  Future<List<T>> list<T>(
    SavedKind kind,
    T Function(JsonMap json) parse,
  ) async => (await _api.getPage(
    '/favorites/${pathOf(kind)}',
    parse,
    query: {'limit': 50},
  )).items;
}
