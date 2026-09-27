import '../../../core/domain/public_profile.dart';
import '../../../core/network/api_client.dart';
import '../../jobs/data/remote_job_repository.dart';
import '../../listings/domain/listing.dart';
import '../../listings/domain/listing_query.dart';
import '../../services/domain/service_provider.dart';
import '../domain/search.dart';

/// `/search` (PostgreSQL trigram engine behind a provider abstraction on the
/// server; Uzbek Latin/Cyrillic normalization happens server-side too).
class RemoteSearchRepository implements SearchRepository {
  RemoteSearchRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<SearchSuggestion>> suggest(String query) async {
    if (query.trim().isEmpty) return const [];
    final items = await _api.get<List<dynamic>>('/search/suggest', query: {'q': query.trim()});
    return [
      for (final item in items.cast<JsonMap>())
        SearchSuggestion(
          text: item['text'] as String,
          kind: switch (item['kind']) {
            'category' => SuggestionKind.category,
            'serviceCategory' => SuggestionKind.service,
            _ => SuggestionKind.query,
          },
          refId: item['refId'] as String?,
          subtitle: item['subtitle'] as String?,
        ),
    ];
  }

  @override
  Future<List<String>> popular() async => [for (final q in await _api.get<List<dynamic>>('/search/popular')) '$q'];

  @override
  Future<SearchResults> search(String query, {required ListingQuery listingFilters}) async {
    final data = await _api.get<JsonMap>(
      '/search',
      query: {'q': query.trim(), 'region': listingFilters.regionId, 'category': listingFilters.categoryId},
    );
    List<T> parse<T>(String key, T Function(JsonMap) fromJson) => [
      for (final item in data[key] as List<dynamic>? ?? const []) fromJson(item as JsonMap),
    ];
    return SearchResults(
      listings: parse('listings', Listing.fromJson),
      jobs: parse('jobs', RemoteJobRepository.jobFromJson),
      providers: parse('providers', ServiceProvider.fromJson),
      users: parse('users', PublicProfile.fromJson),
      correctedQuery: data['correctedQuery'] as String?,
    );
  }
}
