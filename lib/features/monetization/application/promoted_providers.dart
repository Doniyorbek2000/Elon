import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/network/api_client.dart';
import '../../jobs/domain/job.dart';
import '../../listings/application/listing_providers.dart';
import '../../listings/domain/listing.dart';
import '../../listings/domain/listing_query.dart';
import '../../services/domain/service_provider.dart';
import '../data/promoted_repository.dart';

final promotedRepositoryProvider = Provider<PromotedRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData) return const EmptyPromotedRepository();
  return RemotePromotedRepository(ref.watch(apiClientProvider));
});

/// Paid blocks never break the page: a failure simply hides the block.
Future<List<T>> _quiet<T>(Future<List<T>> Function() load) async {
  try {
    return await load();
  } on Object {
    return const [];
  }
}

final promotedListingsProvider = FutureProvider.autoDispose.family<List<Listing>, ListingQuery>((ref, query) {
  final flags = ref.watch(featureFlagsProvider);
  ref.watch(listingsRevisionProvider);
  if (!flags.monetization || !(flags.listingTop || flags.listingVip)) return const [];
  return _quiet(() => ref.watch(promotedRepositoryProvider).promotedListings(query));
});

typedef FeaturedKey = ({String placement, String? regionId, String? categoryId});

final featuredListingsProvider = FutureProvider.autoDispose.family<List<Listing>, FeaturedKey>((ref, key) {
  final flags = ref.watch(featureFlagsProvider);
  if (!flags.monetization || !flags.featuredListings) return const [];
  return _quiet(
    () => ref
        .watch(promotedRepositoryProvider)
        .featuredListings(placement: key.placement, regionId: key.regionId, categoryId: key.categoryId),
  );
});

final promotedJobsProvider = FutureProvider.autoDispose.family<List<Job>, JobQuery>((ref, query) {
  if (!ref.watch(featureFlagsProvider).canPromoteJobs) return const [];
  return _quiet(() => ref.watch(promotedRepositoryProvider).promotedJobs(query));
});

typedef ProviderBlockKey = ({String text, String? categoryId, String? regionId});

final promotedProvidersProvider = FutureProvider.autoDispose.family<List<ServiceProvider>, ProviderBlockKey>((
  ref,
  key,
) {
  if (!ref.watch(featureFlagsProvider).canPromoteProviders) return const [];
  return _quiet(
    () => ref
        .watch(promotedRepositoryProvider)
        .promotedProviders(text: key.text, categoryId: key.categoryId, regionId: key.regionId),
  );
});

final featuredProvidersProvider = FutureProvider.autoDispose.family<List<ServiceProvider>, FeaturedKey>((ref, key) {
  if (!ref.watch(featureFlagsProvider).canPromoteProviders) return const [];
  return _quiet(
    () => ref
        .watch(promotedRepositoryProvider)
        .featuredProviders(placement: key.placement, regionId: key.regionId, categoryId: key.categoryId),
  );
});

typedef AdKey = ({String? regionId, String? districtId, String? categoryId});

final adsProvider = FutureProvider.autoDispose.family<List<AdCard>, AdKey>((ref, key) {
  if (!ref.watch(featureFlagsProvider).canAdvertise) return const [];
  return _quiet(
    () => ref
        .watch(promotedRepositoryProvider)
        .ads(regionId: key.regionId, districtId: key.districtId, categoryId: key.categoryId),
  );
});
