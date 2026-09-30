import 'package:bozor/core/errors/app_failure.dart';
import 'package:bozor/core/storage/feed_cache.dart';
import 'package:bozor/core/storage/key_value_store.dart';
import 'package:bozor/features/listings/data/remote_listing_repository.dart';
import 'package:bozor/features/listings/domain/listing_query.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../helpers/fake_backend.dart';

Map<String, dynamic> _listing(String id) => {
  'id': id,
  'title': 'Chevrolet Cobalt $id',
  'categoryId': 'cars',
  'publishedAt': '2026-09-20T10:00:00.000Z',
  'place': {'regionId': 'namangan', 'regionName': 'Namangan'},
  'seller': {'id': 'u1', 'name': 'Aziz', 'memberSince': '2026-01-01T00:00:00.000Z'},
};

void main() {
  late KeyValueStore store;
  var now = DateTime.utc(2026, 9, 30, 12);

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = await KeyValueStore.open();
    now = DateTime.utc(2026, 9, 30, 12);
  });

  group('FeedCache', () {
    test('keys are stable, order-independent and ignore empty values', () {
      final a = FeedCache.keyFor('/listings', {'q': 'cobalt', 'sort': 'newest', 'x': null, 'y': ''});
      final b = FeedCache.keyFor('/listings', {'sort': 'newest', 'q': 'cobalt'});
      expect(a, b);
      expect(a, isNot(FeedCache.keyFor('/listings', {'q': 'nexia', 'sort': 'newest'})));
      expect(a, startsWith('feedcache.page.v1.'));
    });

    test('round-trips a page and expires it after a week', () async {
      final cache = FeedCache(store, now: () => now);
      await cache.save('k', [_listing('a')], 'next');
      final loaded = cache.load('k')!;
      expect(loaded.items.single['id'], 'a');
      expect(loaded.nextCursor, 'next');
      now = now.add(const Duration(days: 8));
      expect(cache.load('k'), isNull);
    });

    test('never stores empty pages and keeps only the most recent entries', () async {
      final cache = FeedCache(store, now: () => now, maxEntries: 2);
      await cache.save('empty', const [], null);
      expect(cache.load('empty'), isNull);
      await cache.save('one', [_listing('1')], null);
      await cache.save('two', [_listing('2')], null);
      await cache.save('three', [_listing('3')], null);
      expect(cache.load('one'), isNull);
      expect(cache.load('two'), isNotNull);
      expect(cache.load('three'), isNotNull);
      await cache.clear();
      expect(cache.load('two'), isNull);
    });
  });

  group('RemoteListingRepository offline behaviour', () {
    test('serves the cached first page when offline, flagged as cached', () async {
      final c = buildClient();
      var offline = false;
      c.backend.on('GET', '/listings', (_) {
        if (offline) {
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/listings'),
            reason: 'offline',
          );
        }
        return (
          200,
          {
            'data': [_listing('a'), _listing('b')],
            'meta': {'nextCursor': 'c2'},
          },
        );
      });
      final repository = RemoteListingRepository(c.api, cache: FeedCache(store, now: () => now));
      const query = ListingQuery(categoryId: 'transport');

      final live = await repository.search(query);
      expect(live.fromCache, isFalse);
      await Future<void>.delayed(Duration.zero); // cache write is fire-and-forget

      offline = true;
      final cached = await repository.search(query);
      expect(cached.fromCache, isTrue);
      expect(cached.items.map((l) => l.id), ['a', 'b']);
      expect(cached.nextCursor, 'c2');

      // A query that was never loaded has nothing to fall back to.
      await expectLater(repository.search(const ListingQuery(categoryId: 'phones')), throwsA(isA<NetworkFailure>()));
      // Later pages are never served from cache.
      await expectLater(repository.search(query, cursor: 'c2'), throwsA(isA<NetworkFailure>()));
    });

    test('server errors are not masked by the cache', () async {
      final c = buildClient();
      var broken = false;
      c.backend.on('GET', '/listings', (_) {
        if (broken) return (500, error('INTERNAL'));
        return (
          200,
          {
            'data': [_listing('a')],
          },
        );
      });
      final repository = RemoteListingRepository(c.api, cache: FeedCache(store, now: () => now));
      await repository.search(const ListingQuery());
      await Future<void>.delayed(Duration.zero);
      broken = true;
      await expectLater(repository.search(const ListingQuery()), throwsA(isA<ServerFailure>()));
    });
  });
}
