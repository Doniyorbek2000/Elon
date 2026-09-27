import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../data/demo/demo_database.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../listings/application/listing_providers.dart';
import '../../listings/domain/listing_query.dart';
import '../../services/application/services_providers.dart';
import '../data/demo_search_repository.dart';
import '../data/remote_search_repository.dart';
import '../domain/search.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  if (!ref.watch(appConfigProvider).useDemoData)
    return RemoteSearchRepository(ref.watch(apiClientProvider));
  return DemoSearchRepository(
    db: ref.watch(demoDatabaseProvider),
    categories: ref.watch(categoryTreeProvider),
    listings: ref.watch(listingRepositoryProvider),
    jobs: ref.watch(jobRepositoryProvider),
    services: ref.watch(servicesRepositoryProvider),
  );
});

/// Most-recent-first, de-duplicated, capped search history.
class RecentSearchesController extends Notifier<List<String>> {
  static const maxEntries = 10;

  @override
  List<String> build() =>
      ref.watch(keyValueStoreProvider).getStringList(StoreKeys.recentSearches);

  void add(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final next = [
      trimmed,
      ...state.where((q) => q.toLowerCase() != trimmed.toLowerCase()),
    ].take(maxEntries).toList();
    _save(next);
  }

  void remove(String query) => _save(state.where((q) => q != query).toList());

  void clear() => _save(const []);

  void _save(List<String> next) {
    state = next;
    ref
        .read(keyValueStoreProvider)
        .setStringList(StoreKeys.recentSearches, next)
        .ignore();
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

final popularSearchesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(searchRepositoryProvider).popular(),
);

final searchSuggestionsProvider = FutureProvider.autoDispose
    .family<List<SearchSuggestion>, String>((ref, query) async {
      // Debounce: if the query changes within 250 ms this provider is disposed
      // and the request is never sent.
      var disposed = false;
      ref.onDispose(() => disposed = true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (disposed) return const [];
      return ref.watch(searchRepositoryProvider).suggest(query);
    });

typedef SearchRequest = ({String text, ListingQuery filters});

final searchResultsProvider = FutureProvider.autoDispose
    .family<SearchResults, SearchRequest>((ref, request) {
      return ref
          .watch(searchRepositoryProvider)
          .search(request.text, listingFilters: request.filters);
    });
