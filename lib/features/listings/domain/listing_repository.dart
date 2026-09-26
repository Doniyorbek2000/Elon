import '../../../core/domain/money.dart';
import '../../../core/domain/paged.dart';
import '../../../core/domain/place.dart';
import 'listing.dart';
import 'listing_query.dart';

/// Payload for publishing a listing. Image IDs refer to already-uploaded media.
class NewListing {
  const NewListing({
    required this.categoryId,
    required this.title,
    required this.description,
    required this.place,
    required this.imageIds,
    this.price,
    this.negotiable = false,
    this.condition,
    this.attributes = const [],
  });

  final String categoryId;
  final String title;
  final String description;
  final Place place;
  final List<String> imageIds;
  final Money? price;
  final bool negotiable;
  final ItemCondition? condition;
  final List<ListingAttribute> attributes;

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'title': title,
    'description': description,
    'place': place.toJson(),
    'imageIds': imageIds,
    'price': ?price?.toJson(),
    'negotiable': negotiable,
    'condition': ?condition?.name,
    'attributes': [for (final attribute in attributes) attribute.toJson()],
  };
}

abstract interface class ListingRepository {
  Future<PageResult<Listing>> search(ListingQuery query, {String? cursor});

  Future<Listing> getById(String id);

  Future<List<Listing>> getByIds(Iterable<String> ids);

  Future<List<Listing>> similar(Listing listing, {int limit = 8});

  Future<List<Listing>> bySeller(String sellerId);

  Future<void> recordView(String id);

  /// Contact numbers are fetched on explicit action (rate-limited server-side).
  Future<String> revealPhone(String listingId);

  Future<Listing> publish(NewListing listing, {required String sellerId});

  Future<void> updateStatus(String id, ListingStatus status);

  Future<void> delete(String id);
}
