// End-to-end check of the Flutter data layer against a running backend.
//
//   LIVE_API_URL=http://localhost:3000/api/v1 flutter test test/integration
//
// Requires a development server with OTP_PROVIDER=dev and OTP_DEV_ECHO=true
// (the code is echoed only there) plus the media worker. Skipped otherwise.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bozor/core/device/device_identity.dart';
import 'package:bozor/core/domain/media_image.dart';
import 'package:bozor/core/domain/money.dart';
import 'package:bozor/core/domain/place.dart';
import 'package:bozor/core/errors/app_failure.dart';
import 'package:bozor/core/logging/app_logger.dart';
import 'package:bozor/core/network/api_client.dart';
import 'package:bozor/core/storage/key_value_store.dart';
import 'package:bozor/core/storage/secure_store.dart';
import 'package:bozor/features/auth/data/remote_auth_repository.dart';
import 'package:bozor/features/auth/domain/auth.dart';
import 'package:bozor/features/catalog/domain/category.dart';
import 'package:bozor/features/chat/data/remote_chat_repository.dart';
import 'package:bozor/features/chat/domain/chat.dart';
import 'package:bozor/features/create_listing/data/media_services.dart';
import 'package:bozor/features/jobs/data/remote_job_repository.dart';
import 'package:bozor/features/jobs/domain/job.dart';
import 'package:bozor/features/listings/data/remote_listing_repository.dart';
import 'package:bozor/features/listings/domain/listing.dart';
import 'package:bozor/features/listings/domain/listing_query.dart';
import 'package:bozor/features/listings/domain/listing_repository.dart';
import 'package:bozor/features/notifications/application/notifications_providers.dart';
import 'package:bozor/features/saved/application/saved_items_controller.dart';
import 'package:bozor/features/saved/data/favorites_repository.dart';
import 'package:bozor/features/services/data/remote_services_repository.dart';
import 'package:bozor/features/services/domain/service_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _apiUrl = Platform.environment['LIVE_API_URL'];

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAIAAAAuKetIAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAfUlEQVRoge2SAQkAURSDlsScF9FYF2M8/sAAOhY+T5O6AQuwviK7kHdJ3YAFWF+RXci7pG7AAqyvyC7kXVI3YAHWV2QX8i6pG7AA6yuyC3mX1A1YgPUV2YW8S+oGLMD6iuxC3iV1AxZgfUV2Ie+SugELsL4iu5B3Sd2AxwN+UX1o8ehqlvIAAAAASUVORK5CYII=';

class _QuietLogger implements AppLogger {
  @override
  void log(LogLevel level, String message, {Object? error, StackTrace? stackTrace, String tag = 'app'}) {}
}

/// One simulated device/account.
class _Client {
  _Client._(this.api, this.tokens, this.auth, this.user);

  final ApiClient api;
  final TokenStore tokens;
  final RemoteAuthRepository auth;
  final CurrentUser user;

  static Future<_Client> signIn(String phone) async {
    final tokens = TokenStore(MemorySecureStore());
    final options = BaseOptions(
      baseUrl: _apiUrl!,
      contentType: Headers.jsonContentType,
      // Each simulated device gets its own client IP (server trusts one proxy hop).
      headers: {'X-Forwarded-For': '10.99.${Random().nextInt(250)}.${Random().nextInt(250)}'},
    );
    final dio = Dio(options);
    dio.interceptors.add(AuthInterceptor(tokens: tokens, dio: dio, refreshDio: Dio(options)));
    final api = ApiClient(dio: dio, logger: _QuietLogger());
    final auth = RemoteAuthRepository(
      api: api,
      tokens: tokens,
      device: DeviceIdentity(id: 'live-test-$phone', platform: 'android', name: 'Test'),
      store: await KeyValueStore.open(),
    );
    final challenge = await auth.requestCode(phone);
    final code = challenge.devCode;
    if (code == null) throw StateError('Server must run with OTP_DEV_ECHO=true for live tests');
    return _Client._(api, tokens, auth, await auth.verifyCode(phone: phone, code: code));
  }
}

String _phone() => '99890${Random().nextInt(8999999) + 1000000}';

void main() {
  final skip = _apiUrl == null ? 'Set LIVE_API_URL to run against a backend' : null;
  late _Client seller;
  late _Client buyer;
  late String listingId;
  late File photo;

  setUpAll(() async {
    if (skip != null) return;
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    seller = await _Client.signIn(_phone());
    buyer = await _Client.signIn(_phone());
    photo = File('${Directory.systemTemp.createTempSync('bozor_live').path}/photo.png')
      ..writeAsBytesSync(base64Decode(_png));
  });

  test('server-driven categories parse (boolean & multi-select fields)', () async {
    final json = await seller.api.get<List<dynamic>>('/categories');
    final tree = CategoryTree([
      for (final node in json) Category.fromJson(node as Map<String, dynamic>),
    ], inheritRootSchema: false);
    final cars = tree.schemaFor('cars');
    expect(cars.fields.map((f) => f.type).toSet(), containsAll(AttributeInputType.values));
    expect(tree.schemaFor('car_parts').fields, isEmpty);
  }, skip: skip);

  test('flow 2: photo upload → listing → visible to another user', () async {
    final uploads = RemoteMediaUploadService(seller.api, pollInterval: const Duration(milliseconds: 250));
    final progress = await uploads.upload(photo.path).toList();
    expect(progress.last.remoteId, isNotNull);
    expect(progress.where((p) => p.fraction > 0 && p.fraction < 1), isNotEmpty);

    final listing = await RemoteListingRepository(seller.api).publish(
      NewListing(
        categoryId: 'cars',
        title: 'Chevrolet Gentra 2020',
        description: 'Bir qo‘lda, texnik holati a’lo, kreditga ham mumkin.',
        place: const Place(regionId: 'namangan', regionName: 'Namangan viloyati', districtId: 'chust'),
        imageIds: [progress.last.remoteId!],
        price: const Money.usd(10800),
        condition: ItemCondition.used,
        attributeValues: const {
          'brand': 'Chevrolet',
          'year': 2020,
          'options': ['Konditsioner'],
          'credit': true,
        },
      ),
      sellerId: seller.user.id,
    );
    listingId = listing.id;
    expect(listing.status, ListingStatus.active);
    expect(listing.images.single.url(ImageVariant.feed), contains('/media/'));

    final feed = await RemoteListingRepository(buyer.api)
        .search(const ListingQuery(regionId: 'namangan', districtId: 'chust', categoryId: 'transport'));
    expect(feed.items.map((l) => l.id), contains(listingId));
    final detail = await RemoteListingRepository(buyer.api).getById(listingId);
    expect(detail.attributes.map((a) => a.key), containsAll(['brand', 'year', 'options', 'credit']));
    expect(detail.shareUrl, endsWith('/listing/$listingId'));

    final mine = await RemoteListingRepository(seller.api).mine();
    expect(mine.map((l) => l.id), contains(listingId));
  }, skip: skip);

  test('flow 3: favorite persists server-side', () async {
    final favorites = FavoritesRepository(buyer.api);
    await favorites.add(SavedKind.listing, listingId);
    expect(await favorites.ids(), contains(SavedItemsController.key(SavedKind.listing, listingId)));
    final saved = await favorites.list(SavedKind.listing, Listing.fromJson);
    expect(saved.single.id, listingId);
  }, skip: skip);

  test('flow 9: another user cannot change the listing', () async {
    await expectLater(
      RemoteListingRepository(buyer.api).updateStatus(listingId, ListingStatus.sold),
      throwsA(isA<NotFoundFailure>()),
    );
  }, skip: skip);

  test('flow 4: realtime chat between two app clients', () async {
    RemoteChatRepository chatFor(_Client client) => RemoteChatRepository(
      api: client.api,
      tokens: client.tokens,
      uploads: RemoteMediaUploadService(client.api),
      socketOrigin: Uri.parse(_apiUrl!).origin,
      currentUserId: () => client.user.id,
      logger: _QuietLogger(),
    );
    final buyerChat = chatFor(buyer);
    final sellerChat = chatFor(seller);
    addTearDown(buyerChat.dispose);
    addTearDown(sellerChat.dispose);

    final conversation = await buyerChat.openConversation(
      peer: seller.user.toPublic(),
      context: ConversationContext(subject: ConversationSubject.listing, refId: listingId, title: 'Gentra'),
    );
    expect(conversation.peer.id, seller.user.id);

    // Seller is watching the thread (socket connected) before the buyer writes.
    final sellerMessages = sellerChat.watchMessages(conversation.id).asBroadcastStream();
    await sellerMessages.first;
    await buyerChat.watchConversations().first;
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final received = sellerMessages.firstWhere(
      (list) => list.any((m) => m.text == 'Assalomu alaykum, hali sotuvdami?'),
    );
    await buyerChat.sendText(conversation.id, 'Assalomu alaykum, hali sotuvdami?');
    final list = await received.timeout(const Duration(seconds: 10));
    expect(list.last.senderId, buyer.user.id);

    // History survives (REST) for a fresh client.
    final fresh = chatFor(buyer);
    addTearDown(fresh.dispose);
    final history = await fresh.watchMessages(conversation.id).first;
    expect(history.single.text, 'Assalomu alaykum, hali sotuvdami?');
    expect(history.single.delivery, isNot(DeliveryState.failed));
  }, skip: skip);

  test('flow 6: vacancy → application → employer decision → candidate notified', () async {
    final employerJobs = RemoteJobRepository(seller.api);
    final candidateJobs = RemoteJobRepository(buyer.api);
    final job = await employerJobs.postVacancy(
      const NewVacancy(
        title: 'Kassir kerak',
        companyName: 'Chust Market',
        place: Place(regionId: 'namangan', regionName: 'Namangan viloyati', districtId: 'chust'),
        employmentType: EmploymentType.partTime,
        experience: ExperienceLevel.upToOne,
        description: 'Kassada ishlash, mijozlarga xizmat ko‘rsatish. Tajriba shart emas.',
        workingHours: '10:00–16:00',
        salaryMin: 2500000,
      ),
      employer: seller.user.toPublic(),
    );
    expect(job.employmentType, EmploymentType.partTime);
    expect(job.experience, ExperienceLevel.upToOne);

    await candidateJobs.saveResume(
      const ResumeDraft(title: 'Kassir', experienceYears: 1, visibility: ResumeVisibility.applicationsOnly),
    );
    final application = await candidateJobs.apply(jobId: job.id, applicantId: buyer.user.id, message: 'Tayyorman');
    expect(application.status, ApplicationStatus.submitted);

    final applicants = await employerJobs.applicants(job.id);
    expect(applicants.single.profile.id, buyer.user.id);
    expect(applicants.single.resume?.desiredPosition, 'Kassir');
    await employerJobs.setApplicationStatus(applicants.single.applicationId, ApplicationStatus.shortlisted);

    final mine = await candidateJobs.myApplications(buyer.user.id);
    expect(mine.single.status, ApplicationStatus.shortlisted);
    final inbox = await RemoteNotificationsRepository(buyer.api).page();
    expect(inbox.items.first.deepLink, '/account/applications');
    expect(await RemoteNotificationsRepository(buyer.api).unreadCount(), greaterThan(0));
  }, skip: skip);

  test('flow 7: provider profile + offering → discovered → review needs a real chat', () async {
    final providerRepo = RemoteServicesRepository(seller.api);
    final saved = await providerRepo.saveProvider(
      const ProviderDraft(
        displayName: 'Bekzod usta',
        profession: 'Elektrik',
        description: 'Uy va ofislarda elektr montaj, rozetka va chiroqlar o‘rnatish.',
        categoryIds: ['electrician'],
        place: Place(regionId: 'namangan', regionName: 'Namangan viloyati', districtId: 'chust'),
        experienceYears: 6,
      ),
    );
    expect(saved.profile.rating, isNull); // no fabricated rating
    await providerRepo.addOffering(
      const OfferingDraft(
        categoryId: 'electrician',
        title: 'Rozetka o‘rnatish',
        pricingType: PricingType.from,
        priceFrom: 50000,
      ),
    );
    final found = await RemoteServicesRepository(buyer.api)
        .search(const ProviderQuery(categoryId: 'electrician', regionId: 'namangan'));
    expect(found.map((p) => p.id), contains(saved.id));
    final detail = await RemoteServicesRepository(buyer.api).getProvider(saved.id);
    expect(detail.offerings.single.title, 'Rozetka o‘rnatish');

    await expectLater(
      RemoteServicesRepository(buyer.api).submitReview(saved.id, rating: 5),
      throwsA(isA<ForbiddenFailure>()),
    );
  }, skip: skip);

  test('logout revokes the session for API calls', () async {
    final client = await _Client.signIn(_phone());
    await client.auth.signOut();
    expect(await client.tokens.refreshToken, isNull);
    await expectLater(client.api.get<Object?>('/me'), throwsA(isA<UnauthorizedFailure>()));
  }, skip: skip);
}
