import '../../../core/domain/media_image.dart';
import '../../../core/domain/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/demo/demo_database.dart';
import '../../catalog/domain/category.dart';
import '../../location/data/uzbekistan_locations.dart';
import '../../location/domain/location.dart';
import '../../search/domain/search_normalizer.dart';
import '../domain/listing.dart';
import '../domain/listing_query.dart';
import '../domain/listing_repository.dart';

class DemoListingRepository implements ListingRepository {
  DemoListingRepository(this._db, this._categories, {required this._clock});

  final DemoDatabase _db;
  final CategoryTree _categories;
  final DateTime Function() _clock;

  GeoPoint? _origin(ListingQuery query) {
    const tree = UzbekistanLocations.tree;
    return tree.district(query.regionId, query.districtId)?.center ?? tree.region(query.regionId)?.center;
  }

  double? _distance(Listing listing, GeoPoint? origin) {
    final lat = listing.place.latitude;
    final lng = listing.place.longitude;
    if (origin == null || lat == null || lng == null) return null;
    return origin.distanceTo(GeoPoint(lat, lng));
  }

  List<Listing> _filter(ListingQuery query) {
    final tokens = SearchNormalizer.tokens(query.text);
    final origin = _origin(query);
    final results = <Listing>[];
    for (final listing in _db.listings) {
      if (listing.status != ListingStatus.active && query.sellerId == null) continue;
      if (_db.blockedUserIds.contains(listing.seller.id)) continue;
      if (query.sellerId != null && listing.seller.id != query.sellerId) continue;
      if (query.categoryId != null && !_categories.isWithin(listing.categoryId, query.categoryId!)) continue;
      if (query.condition != null && listing.condition != query.condition) continue;
      final price = listing.price?.approxUzs;
      if (query.minPrice != null && (price == null || price < query.minPrice!)) continue;
      if (query.maxPrice != null && (price == null || price > query.maxPrice!)) continue;
      if (tokens.isNotEmpty) {
        final haystack = '${listing.title} ${listing.description} ${_categories.byId(listing.categoryId)?.name ?? ''}';
        if (!SearchNormalizer.matches(tokens, haystack)) continue;
      }
      final distance = _distance(listing, origin);
      if (query.radiusKm != null) {
        if (distance == null || distance > query.radiusKm!) continue;
      } else {
        if (query.regionId != null && listing.place.regionId != query.regionId) continue;
        if (query.districtId != null && listing.place.districtId != query.districtId) continue;
      }
      results.add(listing.copyWith(distanceKm: distance));
    }

    int promoted(Listing l) => l.promotion?.isActive(_clock()) ?? false ? 1 : 0;
    switch (query.sort) {
      case ListingSort.newest:
        results.sort((a, b) {
          final byPromotion = promoted(b).compareTo(promoted(a));
          return byPromotion != 0 ? byPromotion : b.publishedAt.compareTo(a.publishedAt);
        });
      case ListingSort.priceAsc:
        results.sort((a, b) => (a.price?.approxUzs ?? 1 << 62).compareTo(b.price?.approxUzs ?? 1 << 62));
      case ListingSort.priceDesc:
        results.sort((a, b) => (b.price?.approxUzs ?? -1).compareTo(a.price?.approxUzs ?? -1));
      case ListingSort.popular:
        results.sort((a, b) => (b.views + b.favorites * 20).compareTo(a.views + a.favorites * 20));
      case ListingSort.nearest:
        results.sort((a, b) {
          final byDistance = (a.distanceKm ?? double.infinity).compareTo(b.distanceKm ?? double.infinity);
          return byDistance != 0 ? byDistance : b.publishedAt.compareTo(a.publishedAt);
        });
    }
    return results;
  }

  @override
  Future<PageResult<Listing>> search(ListingQuery query, {String? cursor}) async {
    await _db.roundTrip();
    final all = _filter(query);
    final offset = int.tryParse(cursor ?? '') ?? 0;
    final end = (offset + query.pageSize).clamp(0, all.length);
    final page = offset >= all.length ? const <Listing>[] : all.sublist(offset, end);
    return PageResult(items: page, nextCursor: end < all.length ? '$end' : null, total: all.length);
  }

  @override
  Future<Listing> getById(String id) async {
    await _db.roundTrip(0.6);
    final listing = _db.listings.where((l) => l.id == id).firstOrNull;
    if (listing == null) throw const NotFoundFailure('E’lon topilmadi yoki o‘chirilgan');
    return listing;
  }

  @override
  Future<List<Listing>> getByIds(Iterable<String> ids) async {
    await _db.roundTrip(0.5);
    final wanted = ids.toSet();
    return _db.listings.where((l) => wanted.contains(l.id)).toList();
  }

  @override
  Future<List<Listing>> similar(Listing listing, {int limit = 8}) async {
    await _db.roundTrip(0.8);
    final root = _categories.parentOf(listing.categoryId)?.id ?? listing.categoryId;
    return _db.listings
        .where(
          (l) => l.id != listing.id && l.status == ListingStatus.active && _categories.isWithin(l.categoryId, root),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<List<Listing>> mine() async {
    final user = _db.currentUser;
    if (user == null) throw const UnauthorizedFailure();
    return bySeller(user.id);
  }

  @override
  Future<List<Listing>> bySeller(String sellerId) async {
    await _db.roundTrip(0.6);
    return _db.listings.where((l) => l.seller.id == sellerId).toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }

  @override
  Future<void> recordView(String id) async {
    final index = _db.listings.indexWhere((l) => l.id == id);
    if (index >= 0) _db.listings[index] = _db.listings[index].copyWith(views: _db.listings[index].views + 1);
  }

  @override
  Future<String> revealPhone(String listingId) async {
    await _db.roundTrip(0.4);
    final listing = await getById(listingId);
    final phone = _db.seed.phoneBook[listing.seller.id];
    if (phone == null) throw const NotFoundFailure('Sotuvchi raqamini yashirgan. Chat orqali yozing.');
    return phone;
  }

  @override
  Future<Listing> publish(NewListing input, {required String sellerId}) async {
    await _db.roundTrip(2);
    final user = _db.currentUser;
    if (user == null || user.id != sellerId) throw const UnauthorizedFailure();
    final listing = Listing(
      id: _db.nextId('l'),
      title: input.title,
      description: input.description,
      categoryId: input.categoryId,
      images: [
        for (final id in input.imageIds)
          if (id.startsWith('local:')) MediaImage.local(id, id.substring('local:'.length)),
      ],
      place: input.place,
      publishedAt: _clock(),
      seller: user.toPublic(),
      price: input.price,
      negotiable: input.negotiable,
      condition: input.condition,
      attributes: input.attributes,
    );
    _db.listings.insert(0, listing);
    return listing;
  }

  @override
  Future<void> updateStatus(String id, ListingStatus status) async {
    await _db.roundTrip(0.5);
    final index = _db.listings.indexWhere((l) => l.id == id);
    if (index < 0) throw const NotFoundFailure();
    _db.listings[index] = _db.listings[index].copyWith(status: status);
  }

  @override
  Future<void> delete(String id) async {
    await _db.roundTrip(0.5);
    _db.listings.removeWhere((l) => l.id == id);
  }
}
