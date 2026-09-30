import 'package:bozor/core/device/device_identity.dart';
import 'package:bozor/core/domain/place.dart';
import 'package:bozor/core/errors/app_failure.dart';
import 'package:bozor/core/l10n/l10n.dart';
import 'package:bozor/core/network/api_client.dart';
import 'package:bozor/core/storage/key_value_store.dart';
import 'package:bozor/features/auth/data/remote_auth_repository.dart';
import 'package:bozor/features/jobs/data/remote_job_repository.dart';
import 'package:bozor/features/jobs/domain/job.dart';
import 'package:bozor/features/listings/data/remote_listing_repository.dart';
import 'package:bozor/features/listings/domain/listing.dart';
import 'package:bozor/features/listings/domain/listing_query.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../helpers/fake_backend.dart';

void main() {
  group('Language header', () {
    tearDown(() => currentLanguage = AppLanguage.uz);

    test('requests carry the interface language', () async {
      final c = buildClient();
      final seen = <Object?>[];
      c.backend.on('GET', '/ping', (options) {
        seen.add(options.headers['accept-language']);
        return (200, {'data': <String, dynamic>{}});
      });
      await c.api.get<Object?>('/ping');
      currentLanguage = AppLanguage.ru;
      await c.api.get<Object?>('/ping');
      expect(seen, ['uz', 'ru']);
    });
  });

  group('Envelope and error mapping', () {
    test('unwraps data and page meta', () async {
      final c = buildClient();
      c.backend.on(
        'GET',
        '/things',
        (_) => (
          200,
          {
            'data': [
              {'id': 'a'},
              {'id': 'b'},
            ],
            'meta': {'nextCursor': 'next-1'},
          },
        ),
      );
      final page = await c.api.getPage('/things', (json) => json['id'] as String);
      expect(page.items, ['a', 'b']);
      expect(page.nextCursor, 'next-1');
    });

    test('maps server error codes to typed failures', () async {
      final c = buildClient();
      c.backend
        ..on('GET', '/blocked', (_) => (403, error('BLOCKED')))
        ..on('GET', '/forbidden', (_) => (403, error('FORBIDDEN')))
        ..on('GET', '/conflict', (_) => (409, error('INVALID_STATE')))
        ..on(
          'GET',
          '/invalid',
          (_) => (
            422,
            error('VALIDATION_FAILED', {
              'fields': {'year': 'Minimum is 1970'},
            }),
          ),
        )
        ..on('GET', '/limited', (_) => (429, error('OTP_COOLDOWN', {'retryAfterSeconds': 42})))
        ..on('GET', '/boom', (_) => (500, error('INTERNAL')))
        ..on('GET', '/unsupported', (_) => (415, error('UNSUPPORTED_MEDIA')));

      await expectLater(c.api.get<Object?>('/blocked'), throwsA(isA<BlockedFailure>()));
      await expectLater(c.api.get<Object?>('/forbidden'), throwsA(isA<ForbiddenFailure>()));
      await expectLater(
        c.api.get<Object?>('/conflict'),
        throwsA(isA<ConflictFailure>().having((f) => f.code, 'code', 'INVALID_STATE')),
      );
      await expectLater(
        c.api.get<Object?>('/invalid'),
        throwsA(isA<ValidationFailure>().having((f) => f.fieldErrors['year'], 'year', 'Minimum is 1970')),
      );
      await expectLater(
        c.api.get<Object?>('/limited'),
        throwsA(isA<RateLimitFailure>().having((f) => f.retryAfter, 'retryAfter', const Duration(seconds: 42))),
      );
      await expectLater(
        c.api.get<Object?>('/boom'),
        throwsA(isA<ServerFailure>().having((f) => f.statusCode, 'status', 500)),
      );
      await expectLater(c.api.get<Object?>('/unsupported'), throwsA(isA<ValidationFailure>()));
      await expectLater(c.api.get<Object?>('/missing'), throwsA(isA<NotFoundFailure>()));
    });

    test('maps transport errors to offline/timeout failures', () {
      AppFailure map(DioExceptionType type) =>
          ApiClient.mapDioException(DioException(requestOptions: RequestOptions(), type: type));
      expect(map(DioExceptionType.connectionError), isA<NetworkFailure>());
      expect(map(DioExceptionType.receiveTimeout), isA<TimeoutFailure>());
      expect(map(DioExceptionType.connectionTimeout), isA<TimeoutFailure>());
    });
  });

  group('Token refresh', () {
    test('refreshes once for concurrent 401s and retries with the new token', () async {
      final c = buildClient();
      await c.tokens.save(accessToken: 'old-access', refreshToken: 'refresh-1');
      var refreshCalls = 0;
      c.backend
        ..on('GET', '/me', (options) {
          final auth = options.headers['Authorization'];
          return auth == 'Bearer new-access'
              ? (
                  200,
                  {
                    'data': {'ok': true},
                  },
                )
              : (401, error('TOKEN_EXPIRED'));
        })
        ..on('POST', '/auth/refresh', (options) async {
          refreshCalls++;
          expect((options.data as Map)['refreshToken'], 'refresh-1');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return (
            200,
            {
              'data': {'accessToken': 'new-access', 'refreshToken': 'refresh-2'},
            },
          );
        });

      final results = await Future.wait([
        c.api.get<Map<String, dynamic>>('/me'),
        c.api.get<Map<String, dynamic>>('/me'),
      ]);
      expect(results.every((r) => r['ok'] == true), isTrue);
      expect(refreshCalls, 1);
      expect(await c.tokens.refreshToken, 'refresh-2');
    });

    test('a rejected refresh clears tokens and signals session expiry', () async {
      final c = buildClient();
      await c.tokens.save(accessToken: 'old-access', refreshToken: 'stolen-or-revoked');
      final expired = c.tokens.sessionExpired.first;
      c.backend
        ..on('GET', '/me', (_) => (401, error('TOKEN_EXPIRED')))
        ..on('POST', '/auth/refresh', (_) => (401, error('SESSION_REVOKED')));

      await expectLater(c.api.get<Object?>('/me'), throwsA(isA<UnauthorizedFailure>()));
      await expired.timeout(const Duration(seconds: 1));
      expect(await c.tokens.accessToken, isNull);
      expect(await c.tokens.refreshToken, isNull);
    });

    test('offline during refresh keeps the session', () async {
      final c = buildClient();
      await c.tokens.save(accessToken: 'old-access', refreshToken: 'refresh-1');
      c.backend
        ..on('GET', '/me', (_) => (401, error('TOKEN_EXPIRED')))
        ..on(
          'POST',
          '/auth/refresh',
          (_) => throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/auth/refresh'),
            reason: 'offline',
          ),
        );
      await expectLater(c.api.get<Object?>('/me'), throwsA(isA<AppFailure>()));
      expect(await c.tokens.refreshToken, 'refresh-1');
    });
  });

  group('Repositories speak the API contract', () {
    test('auth verify stores tokens and sends the device identity', () async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      final store = await KeyValueStore.open();
      final c = buildClient();
      c.backend
        ..on('POST', '/auth/otp/verify', (options) {
          final body = options.data as Map;
          expect(body['device'], {'id': 'install-123456', 'platform': 'android', 'name': 'Android'});
          return (
            200,
            {
              'data': {'accessToken': 'a1', 'refreshToken': 'r1', 'sessionId': 's1', 'userId': 'u1'},
            },
          );
        })
        ..on('GET', '/me', (options) {
          expect(options.headers['Authorization'], 'Bearer a1');
          return (
            200,
            {
              'data': {
                'id': 'u1',
                'displayId': 'ABCD1234',
                'phone': '998901234567',
                'name': 'Aziz',
                'verification': 'phone',
                'accountType': 'personal',
                'memberSince': '2026-09-01T00:00:00.000Z',
              },
            },
          );
        });
      final repository = RemoteAuthRepository(
        api: c.api,
        tokens: c.tokens,
        device: const DeviceIdentity(id: 'install-123456', platform: 'android', name: 'Android'),
        store: store,
      );
      final user = await repository.verifyCode(phone: '998901234567', code: '123456');
      expect(user.name, 'Aziz');
      expect(await c.tokens.refreshToken, 'r1');
      expect(repository.cachedUser?.id, 'u1');
    });

    test('listing feed query maps filters and device coordinates', () async {
      final c = buildClient();
      c.backend.on('GET', '/listings', (options) {
        expect(options.queryParameters, {
          'category': 'transport',
          'region': 'namangan',
          'district': 'chust',
          'radius': 25,
          'condition': 'new',
          'sort': 'nearest',
          'limit': 20,
          'lat': 41.0,
          'lng': 71.2,
          'cursor': 'c1',
        });
        return (
          200,
          {
            'data': <Object>[],
            'meta': {'nextCursor': null},
          },
        );
      });
      final repository = RemoteListingRepository(c.api, location: () => (lat: 41.0, lng: 71.2));
      final page = await repository.search(
        const ListingQuery(
          categoryId: 'transport',
          regionId: 'namangan',
          districtId: 'chust',
          radiusKm: 25,
          condition: ItemCondition.newItem,
          sort: ListingSort.nearest,
        ),
        cursor: 'c1',
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('vacancy body uses server enums (upTo1, remote work format)', () async {
      final json = const NewVacancy(
        title: 'Operator',
        companyName: 'Call markaz',
        place: _chust,
        employmentType: EmploymentType.remote,
        experience: ExperienceLevel.upToOne,
        description: 'Qo‘ng‘iroqlarni qabul qilish',
        workingHours: '09:00–18:00',
        salaryMin: 3000000,
      ).toJson();
      expect(json['employmentType'], 'fullTime');
      expect(json['workFormat'], 'remote');
      expect(json['experience'], 'upTo1');
      expect(json['workSchedule'], '09:00–18:00');
      expect(EmploymentType.fromApi('partTime', 'onSite'), EmploymentType.partTime);
      expect(EmploymentType.fromApi('fullTime', 'remote'), EmploymentType.remote);
      expect(ExperienceLevel.fromApi('oneTo3'), ExperienceLevel.oneToThree);
    });

    test('application statuses from the employer flow parse', () {
      final application = RemoteJobRepository.applicationFromJson({
        'id': 'app1',
        'status': 'shortlisted',
        'appliedAt': '2026-09-20T10:00:00.000Z',
        'message': null,
        'job': _jobJson,
      });
      expect(application.status, ApplicationStatus.shortlisted);
      expect(application.status.isOpen, isTrue);
      expect(application.job.experience, ExperienceLevel.upToOne);
    });
  });
}

const _chust = Place(regionId: 'namangan', regionName: 'Namangan viloyati', districtId: 'chust', districtName: 'Chust');

const _jobJson = <String, Object?>{
  'id': 'j1',
  'title': 'Sotuvchi',
  'company': {'id': 'u9', 'name': 'Savdo', 'iconKey': 'work', 'tone': 'teal', 'verification': 'none'},
  'place': {'regionId': 'namangan', 'regionName': 'Namangan viloyati', 'districtId': 'chust', 'districtName': 'Chust'},
  'publishedAt': '2026-09-19T10:00:00.000Z',
  'employmentType': 'fullTime',
  'workFormat': 'onSite',
  'experience': 'upTo1',
  'salaryMin': 4000000,
  'salaryMax': null,
  'currency': 'uzs',
  'status': 'active',
  'employer': {'id': 'u9', 'name': 'Anvar', 'memberSince': '2026-01-01T00:00:00.000Z'},
};
