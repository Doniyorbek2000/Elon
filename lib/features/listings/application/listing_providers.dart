import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/clock.dart';
import '../../../data/demo/demo_database.dart';
import '../../../data/demo/demo_seed.dart';
import '../../catalog/application/catalog_providers.dart';
import '../data/demo_listing_repository.dart';
import '../data/remote_listing_repository.dart';
import '../domain/listing.dart';
import '../domain/listing_query.dart';
import '../domain/listing_repository.dart';

final listingRepositoryProvider = Provider<ListingRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData) {
    return DemoListingRepository(
      ref.watch(demoDatabaseProvider),
      ref.watch(categoryTreeProvider),
      clock: ref.watch(clockProvider),
    );
  }
  return RemoteListingRepository(ref.watch(apiClientProvider));
});

/// Bumped after mutations (publish, status change) so feeds refetch.
final listingsRevisionProvider = NotifierProvider<ListingsRevision, int>(ListingsRevision.new);

class ListingsRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Infinite, pull-to-refreshable feed for any [ListingQuery].
final listingFeedProvider = AsyncNotifierProvider.autoDispose
    .family<ListingFeedController, PagedState<Listing>, ListingQuery>(ListingFeedController.new);

class ListingFeedController extends AsyncNotifier<PagedState<Listing>> {
  ListingFeedController(this.query);

  final ListingQuery query;

  ListingRepository get _repository => ref.read(listingRepositoryProvider);

  @override
  Future<PagedState<Listing>> build() async {
    ref.watch(listingsRevisionProvider);
    final page = await ref.watch(listingRepositoryProvider).search(query);
    return PagedState.fromPage(page);
  }

  Future<void> refresh() async {
    final page = await AsyncValue.guard(() => _repository.search(query));
    if (!ref.mounted) return;
    state = page.whenData(PagedState.fromPage);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    try {
      final page = await _repository.search(query, cursor: current.nextCursor);
      if (!ref.mounted) return;
      state = AsyncData(current.appending(page));
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isLoadingMore: false, loadMoreError: error.asFailure()));
    }
  }
}

final listingDetailProvider = FutureProvider.autoDispose.family<Listing, String>((ref, id) async {
  final repository = ref.watch(listingRepositoryProvider);
  final listing = await repository.getById(id);
  await repository.recordView(id);
  return listing;
});

final similarListingsProvider = FutureProvider.autoDispose.family<List<Listing>, Listing>((ref, listing) {
  return ref.watch(listingRepositoryProvider).similar(listing);
});

final sellerListingsProvider = FutureProvider.autoDispose.family<List<Listing>, String>((ref, sellerId) {
  ref.watch(listingsRevisionProvider);
  return ref.watch(listingRepositoryProvider).bySeller(sellerId);
});

/// Typical price for a category, used to flag suspicious outliers. Served by
/// backend market statistics in production.
final categoryReferencePriceProvider = Provider.family<Money?, String>((ref, categoryId) {
  return ref.watch(appConfigProvider).useDemoData ? DemoSeed.referencePrices[categoryId] : null;
});
