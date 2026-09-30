import '../../../core/l10n/l10n.dart';
import '../../../data/demo/demo_database.dart';
import '../../catalog/domain/category.dart';
import '../../jobs/domain/job.dart';
import '../../listings/domain/listing_query.dart';
import '../../listings/domain/listing_repository.dart';
import '../../services/domain/service_provider.dart';
import '../domain/search.dart';
import '../domain/search_normalizer.dart';

/// Universal search composed from the vertical repositories plus local
/// fuzzy suggestion matching.
class DemoSearchRepository implements SearchRepository {
  DemoSearchRepository({
    required this._db,
    required this._categories,
    required this._listings,
    required this._jobs,
    required this._services,
  });

  final DemoDatabase _db;
  final CategoryTree _categories;
  final ListingRepository _listings;
  final JobRepository _jobs;
  final ServicesRepository _services;

  static List<String> get _popular => [
    'iPhone 14',
    'Cobalt',
    tr('Kvartira ijaraga'),
    tr('Santexnik'),
    tr('Haydovchi kerak'),
    tr('Konditsioner'),
    tr('Sement'),
    tr('Repetitor'),
  ];

  @override
  Future<List<String>> popular() async => _popular;

  @override
  Future<List<SearchSuggestion>> suggest(String query) async {
    final tokens = SearchNormalizer.tokens(query);
    if (tokens.isEmpty) return const [];
    final scored = <(int, SearchSuggestion)>[];

    void consider(String text, SearchSuggestion suggestion) {
      final score = SearchNormalizer.score(tokens, text);
      if (score > 0) scored.add((score, suggestion));
    }

    void visit(Category category) {
      consider(
        category.name,
        SearchSuggestion(
          text: category.name,
          kind: SuggestionKind.category,
          refId: category.id,
          subtitle: category.parentId == null ? tr('Kategoriya') : _categories.byId(category.parentId)?.name,
        ),
      );
      category.children.forEach(visit);
    }

    _categories.roots.forEach(visit);
    final seenTitles = <String>{};
    for (final listing in _db.listings) {
      if (seenTitles.add(listing.title.toLowerCase())) {
        consider(
          listing.title,
          SearchSuggestion(text: listing.title, kind: SuggestionKind.query, subtitle: tr('E’lonlar')),
        );
      }
    }
    for (final job in _db.jobs) {
      consider(
        job.title,
        SearchSuggestion(text: job.title, kind: SuggestionKind.job, refId: job.id, subtitle: job.company.name),
      );
    }
    for (final provider in _db.providers) {
      consider(
        '${provider.profession} ${provider.name}',
        SearchSuggestion(
          text: provider.profession,
          kind: SuggestionKind.service,
          refId: provider.id,
          subtitle: provider.name,
        ),
      );
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final seen = <String>{};
    return [
      for (final (_, suggestion) in scored)
        if (seen.add('${suggestion.kind}:${suggestion.text}')) suggestion,
    ].take(8).toList();
  }

  @override
  Future<SearchResults> search(String query, {required ListingQuery listingFilters}) async {
    final (listingPage, jobs, providers) = await (
      _listings.search(listingFilters.copyWith(text: query)),
      _jobs.searchJobs(JobQuery(text: query, regionId: listingFilters.regionId)),
      _services.search(ProviderQuery(text: query, regionId: listingFilters.regionId)),
    ).wait;
    final tokens = SearchNormalizer.tokens(query);
    final users = [
      for (final user in _db.seed.users)
        if (!_db.blockedUserIds.contains(user.id) && SearchNormalizer.matches(tokens, user.name)) user,
    ];
    return SearchResults(
      listings: listingPage.items,
      jobs: jobs,
      providers: providers,
      users: users,
      correctedQuery: SearchNormalizer.correction(query),
    );
  }
}
