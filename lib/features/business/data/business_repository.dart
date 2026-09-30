import '../../../core/domain/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../listings/domain/listing.dart';
import '../domain/business.dart';

abstract interface class BusinessRepository {
  /// The caller's business (as owner or manager), or null when none.
  Future<MyBusiness?> mine();

  Future<MyBusiness> create(BusinessDraft draft);

  Future<MyBusiness> update(BusinessDraft draft);

  Future<MyBusiness> requestVerification();

  Future<MyBusiness> addManager(String phone);

  Future<MyBusiness> removeManager(String userId);

  Future<Storefront> storefront(String id);

  Future<PageResult<Listing>> storefrontListings(String id, {String? cursor});

  Future<ListingStats> listingStats(String listingId, {int? days});
}

class RemoteBusinessRepository implements BusinessRepository {
  RemoteBusinessRepository(this._api);

  final ApiClient _api;

  @override
  Future<MyBusiness?> mine() async {
    try {
      return MyBusiness.fromJson(await _api.get<JsonMap>('/me/business'));
    } on NotFoundFailure {
      return null;
    }
  }

  @override
  Future<MyBusiness> create(BusinessDraft draft) async =>
      MyBusiness.fromJson(await _api.post<JsonMap>('/businesses', body: draft.toJson()));

  @override
  Future<MyBusiness> update(BusinessDraft draft) async =>
      MyBusiness.fromJson(await _api.patch<JsonMap>('/me/business', body: draft.toJson()));

  @override
  Future<MyBusiness> requestVerification() async =>
      MyBusiness.fromJson(await _api.post<JsonMap>('/me/business/verification'));

  @override
  Future<MyBusiness> addManager(String phone) async =>
      MyBusiness.fromJson(await _api.post<JsonMap>('/me/business/members', body: {'phone': phone}));

  @override
  Future<MyBusiness> removeManager(String userId) async {
    await _api.delete('/me/business/members/$userId');
    return (await mine())!;
  }

  @override
  Future<Storefront> storefront(String id) async => Storefront.fromJson(await _api.get<JsonMap>('/businesses/$id'));

  @override
  Future<PageResult<Listing>> storefrontListings(String id, {String? cursor}) =>
      _api.getPage('/businesses/$id/listings', Listing.fromJson, query: {'limit': 20}, cursor: cursor);

  @override
  Future<ListingStats> listingStats(String listingId, {int? days}) async =>
      ListingStats.fromJson(await _api.get<JsonMap>('/me/listings/$listingId/stats', query: {'days': days}));
}

/// Demo builds have no business accounts (nothing is simulated).
class UnavailableBusinessRepository implements BusinessRepository {
  const UnavailableBusinessRepository();

  static const _off = FeatureDisabledFailure();

  @override
  Future<MyBusiness?> mine() async => null;

  @override
  Future<MyBusiness> create(BusinessDraft draft) => throw _off;

  @override
  Future<MyBusiness> update(BusinessDraft draft) => throw _off;

  @override
  Future<MyBusiness> requestVerification() => throw _off;

  @override
  Future<MyBusiness> addManager(String phone) => throw _off;

  @override
  Future<MyBusiness> removeManager(String userId) => throw _off;

  @override
  Future<Storefront> storefront(String id) => throw const NotFoundFailure();

  @override
  Future<PageResult<Listing>> storefrontListings(String id, {String? cursor}) => throw const NotFoundFailure();

  @override
  Future<ListingStats> listingStats(String listingId, {int? days}) => throw _off;
}
