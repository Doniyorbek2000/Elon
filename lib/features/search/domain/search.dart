import 'package:flutter/foundation.dart';

import '../../../core/domain/public_profile.dart';
import '../../jobs/domain/job.dart';
import '../../listings/domain/listing.dart';
import '../../listings/domain/listing_query.dart';
import '../../services/domain/service_provider.dart';

enum SearchScope {
  all('Barchasi'),
  listings('E’lonlar'),
  jobs('Ishlar'),
  services('Xizmatlar'),
  users('Foydalanuvchilar');

  const SearchScope(this.label);

  final String label;
}

enum SuggestionKind { query, category, listing, job, service }

@immutable
class SearchSuggestion {
  const SearchSuggestion({required this.text, required this.kind, this.refId, this.subtitle});

  final String text;
  final SuggestionKind kind;
  final String? refId;
  final String? subtitle;
}

@immutable
class SearchResults {
  const SearchResults({
    this.listings = const [],
    this.jobs = const [],
    this.providers = const [],
    this.users = const [],
    this.correctedQuery,
  });

  final List<Listing> listings;
  final List<Job> jobs;
  final List<ServiceProvider> providers;
  final List<PublicProfile> users;

  /// Set when typo tolerance rewrote the query ("ayfon" → "iphone").
  final String? correctedQuery;

  bool get isEmpty => listings.isEmpty && jobs.isEmpty && providers.isEmpty && users.isEmpty;
  int get total => listings.length + jobs.length + providers.length + users.length;
}

/// Universal search across verticals. The demo implementation does local
/// fuzzy matching; production delegates to a server index (Elasticsearch/
/// Meilisearch) behind the same interface.
abstract interface class SearchRepository {
  Future<List<SearchSuggestion>> suggest(String query);
  Future<List<String>> popular();
  Future<SearchResults> search(String query, {required ListingQuery listingFilters});
}
