import 'package:flutter/foundation.dart';

import '../../../core/domain/media_image.dart';
import '../../../core/network/api_client.dart';
import '../../jobs/data/remote_job_repository.dart';
import '../../jobs/domain/job.dart';
import '../../listings/domain/listing.dart';
import '../../listings/domain/listing_query.dart';
import '../../services/domain/service_provider.dart';

/// Native local ad; always rendered with a visible "Reklama" label.
@immutable
class AdCard {
  const AdCard({
    required this.id,
    required this.title,
    required this.body,
    required this.destination,
    required this.destinationId,
    this.image,
  });

  factory AdCard.fromJson(JsonMap json) => AdCard(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    image: json['image'] is Map ? MediaImage.fromJson(json['image'] as JsonMap) : null,
    destination: json['destination'] as String? ?? 'business',
    destinationId: json['destinationId'] as String,
  );

  final String id;
  final String title;
  final String body;
  final MediaImage? image;

  /// `listing`, `business`, `provider` or `job`.
  final String destination;
  final String destinationId;

  String get route => switch (destination) {
    'listing' => '/listing/$destinationId',
    'provider' => '/provider/$destinationId',
    'job' => '/job/$destinationId',
    _ => '/business/$destinationId',
  };
}

/// Paid placements are fetched separately from organic results, so paid
/// ranking never rewrites the organic order. Each block is labeled in UI.
abstract interface class PromotedRepository {
  Future<List<Listing>> promotedListings(ListingQuery query);

  /// [placement]: `home`, `category` or `region`.
  Future<List<Listing>> featuredListings({required String placement, String? regionId, String? categoryId});

  Future<List<Job>> promotedJobs(JobQuery query);

  Future<List<ServiceProvider>> promotedProviders({String text = '', String? categoryId, String? regionId});

  Future<List<ServiceProvider>> featuredProviders({required String placement, String? regionId, String? categoryId});

  Future<List<AdCard>> ads({String? regionId, String? districtId, String? categoryId});

  /// `impression` or `click`; deduplicated per viewer server-side.
  Future<void> recordAdEvent(String adId, String type);
}

class RemotePromotedRepository implements PromotedRepository {
  RemotePromotedRepository(this._api);

  final ApiClient _api;

  Future<List<T>> _list<T>(String path, T Function(JsonMap) parse, Map<String, Object?> query) async => [
    for (final item in await _api.get<List<dynamic>>(path, query: query)) parse(item as JsonMap),
  ];

  @override
  Future<List<Listing>> promotedListings(ListingQuery query) {
    final params = query.toQueryParameters()
      ..removeWhere((key, _) => const {'radius', 'sort', 'seller', 'limit', 'cursor'}.contains(key));
    return _list('/listings/promoted', Listing.fromJson, params);
  }

  @override
  Future<List<Listing>> featuredListings({required String placement, String? regionId, String? categoryId}) => _list(
    '/listings/featured',
    Listing.fromJson,
    {'placement': placement, 'region': regionId, 'category': categoryId},
  );

  @override
  Future<List<Job>> promotedJobs(JobQuery query) {
    final params = RemoteJobRepository.apiQuery(query)..removeWhere((key, _) => key == 'limit' || key == 'sort');
    return _list('/jobs/promoted', RemoteJobRepository.jobFromJson, params);
  }

  @override
  Future<List<ServiceProvider>> promotedProviders({String text = '', String? categoryId, String? regionId}) => _list(
    '/providers/promoted',
    ServiceProvider.fromJson,
    {'q': text.trim(), 'category': categoryId, 'region': regionId},
  );

  @override
  Future<List<ServiceProvider>> featuredProviders({required String placement, String? regionId, String? categoryId}) =>
      _list('/providers/featured', ServiceProvider.fromJson, {
        'placement': placement,
        'region': regionId,
        'category': categoryId,
      });

  @override
  Future<List<AdCard>> ads({String? regionId, String? districtId, String? categoryId}) =>
      _list('/ads', AdCard.fromJson, {'region': regionId, 'district': districtId, 'category': categoryId});

  @override
  Future<void> recordAdEvent(String adId, String type) async {
    await _api.post<Object?>('/ads/$adId/events', body: {'type': type});
  }
}

/// Demo builds: no paid placements are simulated.
class EmptyPromotedRepository implements PromotedRepository {
  const EmptyPromotedRepository();

  @override
  Future<List<Listing>> promotedListings(ListingQuery query) async => const [];

  @override
  Future<List<Listing>> featuredListings({required String placement, String? regionId, String? categoryId}) async =>
      const [];

  @override
  Future<List<Job>> promotedJobs(JobQuery query) async => const [];

  @override
  Future<List<ServiceProvider>> promotedProviders({String text = '', String? categoryId, String? regionId}) async =>
      const [];

  @override
  Future<List<ServiceProvider>> featuredProviders({
    required String placement,
    String? regionId,
    String? categoryId,
  }) async => const [];

  @override
  Future<List<AdCard>> ads({String? regionId, String? districtId, String? categoryId}) async => const [];

  @override
  Future<void> recordAdEvent(String adId, String type) async {}
}
