import '../../../core/errors/app_failure.dart';
import '../../../data/demo/demo_database.dart';
import '../../search/domain/search_normalizer.dart';
import '../domain/service_provider.dart';
import 'bundled_service_categories.dart';

class DemoServicesRepository implements ServicesRepository {
  DemoServicesRepository(this._db);

  final DemoDatabase _db;

  @override
  Future<List<ServiceCategory>> categories() async => BundledServiceCategories.all;

  @override
  Future<List<ServiceProvider>> recommended({String? regionId}) async {
    await _db.roundTrip();
    final sorted = [..._db.providers]
      ..sort((a, b) {
        final byTop = (b.isTop ? 1 : 0).compareTo(a.isTop ? 1 : 0);
        return byTop != 0 ? byTop : (b.rating * b.reviewCount).compareTo(a.rating * a.reviewCount);
      });
    return sorted
        .where((p) => regionId == null || p.place.regionId == regionId)
        .where((p) => !_db.blockedUserIds.contains(p.profile.id))
        .take(6)
        .toList();
  }

  @override
  Future<List<ServiceProvider>> search(ProviderQuery query) async {
    await _db.roundTrip();
    final tokens = SearchNormalizer.tokens(query.text);
    final results =
        _db.providers.where((provider) {
          if (_db.blockedUserIds.contains(provider.profile.id)) return false;
          if (query.categoryId != null && provider.categoryId != query.categoryId) return false;
          if (query.regionId != null && provider.place.regionId != query.regionId) return false;
          final categoryName = BundledServiceCategories.byId(provider.categoryId)?.name ?? '';
          if (!SearchNormalizer.matches(tokens, '${provider.name} ${provider.profession} $categoryName')) return false;
          return switch (query.filter) {
            ProviderFilter.all => true,
            ProviderFilter.online => provider.profile.isOnline,
            ProviderFilter.top => provider.isTop,
            ProviderFilter.topRated => provider.rating >= 4.8,
          };
        }).toList()..sort((a, b) {
          final byTop = (b.isTop ? 1 : 0).compareTo(a.isTop ? 1 : 0);
          return byTop != 0 ? byTop : b.rating.compareTo(a.rating);
        });
    return results;
  }

  @override
  Future<ServiceProvider> getProvider(String id) async {
    await _db.roundTrip(0.6);
    return _db.providers.where((p) => p.id == id).firstOrNull ?? (throw const NotFoundFailure('Usta topilmadi'));
  }

  @override
  Future<String> revealPhone(String providerId) async {
    await _db.roundTrip(0.4);
    final provider = await getProvider(providerId);
    return _db.seed.phoneBook[provider.profile.id] ?? '998901000000';
  }
}
