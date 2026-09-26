import 'package:bozor/core/domain/money.dart';
import 'package:bozor/core/storage/key_value_store.dart';
import 'package:bozor/features/jobs/application/job_providers.dart';
import 'package:bozor/features/jobs/domain/job.dart';
import 'package:bozor/features/listings/application/listing_providers.dart';
import 'package:bozor/features/listings/domain/listing.dart';
import 'package:bozor/features/listings/domain/listing_query.dart';
import 'package:bozor/features/location/application/location_controller.dart';
import 'package:bozor/features/location/domain/location.dart';
import 'package:bozor/features/saved/application/saved_items_controller.dart';
import 'package:bozor/features/search/application/search_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  late TestHarness harness;
  late ProviderContainer container;

  setUp(() async {
    harness = await TestHarness.create();
    container = harness.createContainer();
    addTearDown(container.dispose);
  });

  group('Listing repository', () {
    test('filters by nested category and sorts by price', () async {
      final repository = container.read(listingRepositoryProvider);
      final page = await repository.search(const ListingQuery(categoryId: 'transport', sort: ListingSort.priceAsc));
      expect(page.items, isNotEmpty);
      expect(page.items.every((l) => l.categoryId == 'cars'), isTrue);
      final prices = page.items.map((l) => l.price!.approxUzs).toList();
      expect(prices, [...prices]..sort());
    });

    test('paginates with cursors until exhausted', () async {
      final repository = container.read(listingRepositoryProvider);
      final first = await repository.search(const ListingQuery(pageSize: 5));
      expect(first.items, hasLength(5));
      expect(first.hasMore, isTrue);
      final second = await repository.search(const ListingQuery(pageSize: 5), cursor: first.nextCursor);
      expect(second.items.map((l) => l.id).toSet().intersection(first.items.map((l) => l.id).toSet()), isEmpty);
    });

    test('radius search limits results and computes distance', () async {
      final repository = container.read(listingRepositoryProvider);
      final page = await repository.search(
        const ListingQuery(regionId: 'namangan', districtId: 'chust', radiusKm: 5, sort: ListingSort.nearest),
      );
      expect(page.items, isNotEmpty);
      expect(page.items.every((l) => (l.distanceKm ?? 999) <= 5), isTrue);
    });

    test('price range and condition filters apply', () async {
      final repository = container.read(listingRepositoryProvider);
      final page = await repository.search(
        const ListingQuery(minPrice: 6000000, maxPrice: 8000000, condition: ItemCondition.used),
      );
      expect(page.items, isNotEmpty);
      for (final listing in page.items) {
        expect(listing.price!.approxUzs, inInclusiveRange(6000000, 8000000));
        expect(listing.condition, ItemCondition.used);
      }
    });

    test('typo-tolerant text search finds iPhones for "ayfon"', () async {
      final page = await container.read(listingRepositoryProvider).search(const ListingQuery(text: 'ayfon'));
      expect(page.items.map((l) => l.title), everyElement(contains('iPhone')));
    });

    test('phone numbers are revealed only on request', () async {
      final listing = await container.read(listingRepositoryProvider).getById('l_cobalt_2023');
      expect(listing.seller.toString(), isNot(contains('998')));
      final phone = await container.read(listingRepositoryProvider).revealPhone('l_cobalt_2023');
      expect(phone, startsWith('998'));
    });
  });

  group('Listing feed controller', () {
    test('loads first page and appends more', () async {
      const query = ListingQuery(pageSize: 4);
      final subscription = container.listen(listingFeedProvider(query), (_, _) {});
      addTearDown(subscription.close);
      final first = await container.read(listingFeedProvider(query).future);
      expect(first.items, hasLength(4));
      await container.read(listingFeedProvider(query).notifier).loadMore();
      expect(container.read(listingFeedProvider(query)).value!.items, hasLength(8));
    });
  });

  group('Universal search', () {
    test('finds jobs, services and listings in one query', () async {
      final repository = container.read(searchRepositoryProvider);
      final haydovchi = await repository.search('haydovchi', listingFilters: const ListingQuery());
      expect(haydovchi.jobs.map((j) => j.title), contains('Haydovchi kerak'));
      final santexnik = await repository.search('santexnik', listingFilters: const ListingQuery());
      expect(santexnik.providers.map((p) => p.profession), contains('Santexnik'));
    });

    test('suggestions include categories', () async {
      final suggestions = await container.read(searchRepositoryProvider).suggest('telef');
      expect(suggestions.map((s) => s.text), contains('Telefonlar'));
    });

    test('recent searches are de-duplicated, capped and persisted', () {
      final controller = container.read(recentSearchesProvider.notifier);
      for (var i = 0; i < 15; i++) {
        controller.add('q$i');
      }
      controller.add('Q14');
      final recent = container.read(recentSearchesProvider);
      expect(recent, hasLength(RecentSearchesController.maxEntries));
      expect(recent.first, 'Q14');
      expect(recent.where((q) => q.toLowerCase() == 'q14'), hasLength(1));
      expect(harness.store.getStringList(StoreKeys.recentSearches).first, 'Q14');
    });
  });

  group('Favorites', () {
    test('toggle persists across containers', () async {
      final controller = container.read(savedItemsProvider.notifier);
      expect(controller.toggle(SavedKind.listing, 'l_cobalt_2023'), isTrue);
      expect(container.read(isSavedProvider((SavedKind.listing, 'l_cobalt_2023'))), isTrue);
      await Future<void>.delayed(Duration.zero);

      final second = harness.createContainer();
      addTearDown(second.dispose);
      expect(second.read(isSavedProvider((SavedKind.listing, 'l_cobalt_2023'))), isTrue);

      expect(second.read(savedItemsProvider.notifier).toggle(SavedKind.listing, 'l_cobalt_2023'), isFalse);
      expect(second.read(savedItemsProvider), isEmpty);
    });
  });

  group('Location', () {
    test('defaults to Chust without GPS and persists manual selection', () async {
      expect(container.read(locationProvider).districtId, 'chust');
      await container
          .read(locationProvider.notifier)
          .select(
            const LocationSelection(
              regionId: 'tashkent_city',
              regionName: 'Toshkent shahri',
              districtId: 'chilonzor',
              districtName: 'Chilonzor tumani',
              radiusKm: 10,
            ),
          );
      final second = harness.createContainer();
      addTearDown(second.dispose);
      expect(second.read(locationProvider).districtId, 'chilonzor');
      expect(second.read(locationProvider).radiusKm, 10);
      expect(second.read(locationProvider).label, 'Chilonzor, Toshkent');
    });

    test('device location resolves to nearest district', () async {
      harness.locationService.point = const GeoPoint(40.87, 71.11);
      final selection = await container.read(locationProvider.notifier).useDeviceLocation();
      expect(selection.districtId, 'pop');
      expect(selection.fromDevice, isTrue);
    });
  });

  group('Jobs', () {
    test('filters by employment type and applies once', () async {
      final repository = container.read(jobRepositoryProvider);
      final remote = await repository.searchJobs(const JobQuery(types: {EmploymentType.remote}));
      expect(remote, isNotEmpty);
      expect(remote.every((j) => j.employmentType == EmploymentType.remote), isTrue);

      final bySalary = await repository.searchJobs(const JobQuery(sortBySalary: true));
      expect(bySalary.first.salarySortKey, greaterThanOrEqualTo(bySalary.last.salarySortKey));

      final subscription = container.listen(myApplicationsProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(myApplicationsProvider.future);
      final application = await container.read(myApplicationsProvider.notifier).apply('j_haydovchi', message: 'Salom');
      expect(application.status, ApplicationStatus.sent);
      expect(container.read(applicationForJobProvider('j_haydovchi')), isNotNull);
      expect(() => container.read(myApplicationsProvider.notifier).apply('j_haydovchi'), throwsA(anything));
    });

    test('salary normalization keeps USD comparable', () {
      expect(const Money.usd(1000).approxUzs, greaterThan(const Money.uzs(1000000).approxUzs));
    });
  });
}
