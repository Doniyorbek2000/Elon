import '../../../core/domain/paged.dart';
import '../../../core/network/api_client.dart';
import '../domain/listing.dart';
import '../domain/listing_query.dart';
import '../domain/listing_repository.dart';

/// REST implementation. Endpoint contract is documented in
/// `docs/backend-contract.md`; swap in via `API_BASE_URL`.
class RemoteListingRepository implements ListingRepository {
  RemoteListingRepository(this._api);

  final ApiClient _api;

  List<Listing> _list(JsonMap json, [String key = 'items']) => [
    for (final item in json[key] as List<dynamic>? ?? const []) Listing.fromJson(item as JsonMap),
  ];

  @override
  Future<PageResult<Listing>> search(ListingQuery query, {String? cursor}) async {
    final json = await _api.getJson('/listings', query: query.toQueryParameters(cursor: cursor));
    return PageResult(items: _list(json), nextCursor: json['nextCursor'] as String?, total: json['total'] as int?);
  }

  @override
  Future<Listing> getById(String id) async => Listing.fromJson(await _api.getJson('/listings/$id'));

  @override
  Future<List<Listing>> getByIds(Iterable<String> ids) async =>
      _list(await _api.getJson('/listings', query: {'ids': ids.join(',')}));

  @override
  Future<List<Listing>> similar(Listing listing, {int limit = 8}) async =>
      _list(await _api.getJson('/listings/${listing.id}/similar', query: {'limit': limit}));

  @override
  Future<List<Listing>> bySeller(String sellerId) async => _list(await _api.getJson('/users/$sellerId/listings'));

  @override
  Future<void> recordView(String id) async {
    await _api.postJson('/listings/$id/views');
  }

  @override
  Future<String> revealPhone(String listingId) async =>
      (await _api.postJson('/listings/$listingId/phone'))['phone'] as String;

  @override
  Future<Listing> publish(NewListing listing, {required String sellerId}) async =>
      Listing.fromJson(await _api.postJson('/listings', body: listing.toJson()));

  @override
  Future<void> updateStatus(String id, ListingStatus status) async {
    await _api.patchJson('/listings/$id', body: {'status': status.name});
  }

  @override
  Future<void> delete(String id) => _api.delete('/listings/$id');
}
