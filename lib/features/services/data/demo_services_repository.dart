import '../../../core/domain/money.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';
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
        return (b.rating * b.reviewCount).compareTo(a.rating * a.reviewCount);
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
            ProviderFilter.topRated => provider.rating >= 4.8,
          };
        }).toList()..sort((a, b) {
          return b.rating.compareTo(a.rating);
        });
    return results;
  }

  @override
  Future<ServiceProvider> getProvider(String id) async {
    await _db.roundTrip(0.6);
    return _db.providers.where((p) => p.id == id).firstOrNull ?? (throw NotFoundFailure(tr('Usta topilmadi')));
  }

  @override
  Future<String> revealPhone(String providerId) async {
    await _db.roundTrip(0.4);
    final provider = await getProvider(providerId);
    return _db.seed.phoneBook[provider.profile.id] ??
        (throw NotFoundFailure(tr('Raqam yashirilgan. Chat orqali yozing.')));
  }

  ServiceProvider? _mine;

  @override
  Future<ServiceProvider?> myProvider() async {
    await _db.roundTrip(0.4);
    return _mine;
  }

  @override
  Future<ServiceProvider> saveProvider(ProviderDraft draft) async {
    await _db.roundTrip();
    final user = _db.currentUser;
    if (user == null) throw const UnauthorizedFailure();
    final provider = ServiceProvider(
      id: _mine?.id ?? _db.nextId('sp'),
      profile: user.toPublic(),
      profession: draft.profession,
      categoryId: draft.categoryIds.first,
      place: draft.place,
      description: draft.description,
      experienceYears: draft.experienceYears,
      serviceArea: [?draft.place.districtName],
      offerings: _mine?.offerings ?? const [],
    );
    _mine = provider;
    return provider;
  }

  @override
  Future<void> addOffering(OfferingDraft draft) async {
    await _db.roundTrip(0.6);
    final mine = _mine;
    if (mine == null) throw ValidationFailure(tr('Avval usta profilini yarating'));
    _mine = ServiceProvider(
      id: mine.id,
      profile: mine.profile,
      profession: mine.profession,
      categoryId: mine.categoryId,
      place: mine.place,
      description: mine.description,
      experienceYears: mine.experienceYears,
      serviceArea: mine.serviceArea,
      offerings: [
        ...mine.offerings,
        ServiceOffering(
          id: _db.nextId('of'),
          categoryId: draft.categoryId,
          title: draft.title,
          pricingType: draft.pricingType,
          description: draft.description,
          priceFrom: draft.priceFrom == null ? null : Money.uzs(draft.priceFrom!),
          priceUnit: draft.priceUnit,
        ),
      ],
    );
  }

  @override
  Future<void> deleteOffering(String offeringId) async {
    await _db.roundTrip(0.4);
    final mine = _mine;
    if (mine == null) return;
    _mine = ServiceProvider(
      id: mine.id,
      profile: mine.profile,
      profession: mine.profession,
      categoryId: mine.categoryId,
      place: mine.place,
      description: mine.description,
      experienceYears: mine.experienceYears,
      serviceArea: mine.serviceArea,
      offerings: mine.offerings.where((o) => o.id != offeringId).toList(),
    );
  }

  /// Demo has no conversation history to prove eligibility, so reviews are
  /// refused rather than faked.
  @override
  Future<void> submitReview(String providerId, {required int rating, String? text}) async {
    await _db.roundTrip(0.4);
    throw ValidationFailure(
      tr('Sharh qoldirish uchun avval usta bilan yozishgan bo‘lishingiz kerak'),
      code: 'NOT_ELIGIBLE',
    );
  }
}
