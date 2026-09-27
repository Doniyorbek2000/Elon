import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../auth/application/session_controller.dart';
import '../data/business_repository.dart';
import '../domain/business.dart';

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData) return const UnavailableBusinessRepository();
  return RemoteBusinessRepository(ref.watch(apiClientProvider));
});

final myBusinessProvider = FutureProvider.autoDispose<MyBusiness?>((ref) {
  if (ref.watch(sessionProvider) == null) return null;
  return ref.watch(businessRepositoryProvider).mine();
});

final storefrontProvider = FutureProvider.autoDispose.family<Storefront, String>((ref, id) {
  return ref.watch(businessRepositoryProvider).storefront(id);
});

final storefrontListingsProvider = FutureProvider.autoDispose.family((ref, String id) {
  return ref.watch(businessRepositoryProvider).storefrontListings(id);
});

typedef StatsKey = ({String listingId, int days});

final listingStatsProvider = FutureProvider.autoDispose.family<ListingStats, StatsKey>((ref, key) {
  return ref.watch(businessRepositoryProvider).listingStats(key.listingId, days: key.days);
});

final myPromotionsProvider = FutureProvider.autoDispose<List<MyPromotion>>((ref) {
  if (ref.watch(sessionProvider) == null) return const [];
  return ref.watch(businessRepositoryProvider).myPromotions();
});

final promotionResultsProvider = FutureProvider.autoDispose.family<PromotionResults, String>((ref, id) {
  return ref.watch(businessRepositoryProvider).promotionResults(id);
});

final campaignsProvider = FutureProvider.autoDispose<List<AdCampaign>>((ref) {
  return ref.watch(businessRepositoryProvider).campaigns();
});
