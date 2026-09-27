import '../../../core/domain/paged.dart';
import '../../../core/network/api_client.dart';
import '../domain/listing.dart';
import '../domain/listing_query.dart';
import '../domain/listing_repository.dart';

/// `/listings` REST implementation. No local fallback: failures surface as
/// typed [AppFailure]s so screens show real error/offline states.
class RemoteListingRepository implements ListingRepository {
  RemoteListingRepository(this._api, {this.location});

  final ApiClient _api;

  /// Device coordinates for "nearest"/radius queries when GPS was granted.
  final ({double lat, double lng})? Function()? location;

  List<Listing> _parseList(List<dynamic> items) => [for (final item in items) Listing.fromJson(item as JsonMap)];

  @override
  Future<PageResult<Listing>> search(ListingQuery query, {String? cursor}) {
    final params = query.toQueryParameters();
    final coordinates = location?.call();
    if (coordinates != null && (query.sort == ListingSort.nearest || query.radiusKm != null)) {
      params['lat'] = coordinates.lat;
      params['lng'] = coordinates.lng;
    }
    params.remove('cursor');
    return _api.getPage('/listings', Listing.fromJson, query: params, cursor: cursor);
  }

  @override
  Future<Listing> getById(String id) async => Listing.fromJson(await _api.get<JsonMap>('/listings/$id'));

  /// Favorites-only batch lookup; missing/removed listings are skipped.
  @override
  Future<List<Listing>> getByIds(Iterable<String> ids) async {
    final results = await Future.wait(
      ids.take(50).map((id) => getById(id).then<Listing?>((l) => l, onError: (Object _) => null)),
    );
    return results.whereType<Listing>().toList();
  }

  @override
  Future<List<Listing>> similar(Listing listing, {int limit = 8}) async =>
      _parseList(await _api.get<List<dynamic>>('/listings/${listing.id}/similar'));

  @override
  Future<List<Listing>> bySeller(String sellerId) async =>
      (await _api.getPage('/listings', Listing.fromJson, query: {'seller': sellerId, 'limit': 50})).items;

  @override
  Future<List<Listing>> mine() async =>
      (await _api.getPage('/me/listings', Listing.fromJson, query: {'limit': 50})).items;

  /// Views are counted server-side when the detail is fetched (deduplicated).
  @override
  Future<void> recordView(String id) async {}

  @override
  Future<String> revealPhone(String listingId) async =>
      (await _api.post<JsonMap>('/listings/$listingId/contact'))['phone'] as String;

  @override
  Future<Listing> publish(NewListing listing, {required String sellerId}) async =>
      Listing.fromJson(await _api.post<JsonMap>('/listings', body: listing.toApiJson()));

  @override
  Future<void> updateStatus(String id, ListingStatus status) async {
    await _api.post<Object?>('/listings/$id/status', body: {'status': status.name});
  }

  @override
  Future<void> delete(String id) => _api.delete('/listings/$id');
}
