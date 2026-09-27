import 'package:bozor/core/sharing/share_service.dart';
import 'package:bozor/core/storage/key_value_store.dart';
import 'package:bozor/features/create_listing/application/create_listing_controller.dart';
import 'package:bozor/features/create_listing/domain/listing_draft.dart';
import 'package:bozor/features/jobs/application/job_providers.dart';
import 'package:bozor/features/jobs/domain/job.dart';
import 'package:bozor/features/listings/application/listing_providers.dart';
import 'package:bozor/features/listings/domain/listing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  late TestHarness harness;
  late ProviderContainer container;

  CreateListingController controller() =>
      container.read(createListingProvider.notifier);
  ListingDraft draft() => container.read(createListingProvider);

  Future<void> flush() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    harness = await TestHarness.create();
    container = harness.createContainer();
    addTearDown(container.dispose);
    container.listen(createListingProvider, (_, _) {});
  });

  void fillValidCar() {
    controller()
      ..setCategory('cars')
      ..setTitle('Cobalt 2023')
      ..setPrice(118000000)
      ..setDescription('Holati a’lo, bitta xo‘jayin, garajda turgan.')
      ..setAttribute('brand', 'Chevrolet')
      ..setAttribute('year', '2023')
      ..setCondition(ItemCondition.used);
  }

  test('starts on details step with the current location prefilled', () {
    expect(draft().step, CreateStep.details);
    expect(draft().place?.districtId, 'chust');
    expect(draft().hasContent, isFalse);
  });

  test('details step validates required fields and dynamic attributes', () {
    final errors = controller().next();
    expect(
      errors.keys,
      containsAll([
        DraftField.category,
        DraftField.title,
        DraftField.description,
      ]),
    );
    expect(draft().step, CreateStep.details);

    controller()
      ..setCategory('cars')
      ..setTitle('Cobalt')
      ..setDescription('Holati a’lo, tez sotiladi.');
    final carErrors = controller().next();
    expect(
      carErrors.keys,
      containsAll([
        DraftField.price,
        DraftField.attribute('brand'),
        DraftField.attribute('year'),
      ]),
    );

    controller()
      ..setNegotiable(value: true)
      ..setAttribute('brand', 'Chevrolet')
      ..setAttribute('year', '2023');
    expect(controller().next(), isEmpty);
    expect(draft().step, CreateStep.photos);
  });

  test('changing category drops attributes that no longer apply', () {
    controller()
      ..setCategory('cars')
      ..setAttribute('year', '2020')
      ..setAttribute('brand', 'Kia')
      ..setCategory('apartments');
    expect(draft().attributes, isEmpty);
  });

  test('photos upload, reorder, change cover and remove', () async {
    fillValidCar();
    controller().addPhotos(['/a.jpg', '/b.jpg', '/c.jpg']);
    await flush();
    expect(draft().photos, hasLength(3));
    expect(draft().photos.every((p) => p.isUploaded), isTrue);

    final third = draft().photos[2].id;
    controller().makeCover(third);
    expect(draft().photos.first.id, third);

    controller().movePhoto(0, 2);
    expect(draft().photos.last.id, third);

    controller().removePhoto(third);
    expect(draft().photos, hasLength(2));
  });

  test('photo limit is enforced', () async {
    controller().addPhotos(List.generate(20, (i) => '/p$i.jpg'));
    await flush();
    expect(draft().photos, hasLength(ListingDraft.maxPhotos));
    expect(controller().remainingPhotoSlots, 0);
  });

  test('photos are required for marketplace categories', () {
    fillValidCar();
    expect(controller().next(), isEmpty);
    expect(controller().next().keys, contains(DraftField.photos));
  });

  test('draft survives a restart', () async {
    fillValidCar();
    controller().addPhotos(['/a.jpg']);
    await flush();
    await controller().saveNow();

    final restarted = harness.createContainer();
    addTearDown(restarted.dispose);
    restarted.listen(createListingProvider, (_, _) {});
    final restored = restarted.read(createListingProvider);
    expect(restored.restored, isTrue);
    expect(restored.title, 'Cobalt 2023');
    expect(restored.categoryId, 'cars');
    expect(restored.photos, hasLength(1));
    expect(restored.attributes['year'], '2023');
  });

  test(
    'publishing creates a listing, clears the draft and refreshes feeds',
    () async {
      fillValidCar();
      controller().addPhotos(['/a.jpg', '/b.jpg']);
      await flush();
      final revision = container.read(listingsRevisionProvider);

      final item = await controller().publish();
      expect(item.target, ShareTarget.listing);
      expect(item.pendingReview, isFalse);
      expect(draft().hasContent, isFalse);
      expect(harness.store.getJson(StoreKeys.listingDraft), isNull);
      expect(container.read(listingsRevisionProvider), revision + 1);

      final listing = await container
          .read(listingRepositoryProvider)
          .getById(item.id);
      expect(listing.title, 'Cobalt 2023');
      expect(listing.images, hasLength(2));
      expect(listing.attributes.map((a) => a.value), contains('2023'));
    },
  );

  test('risky listings are published for moderation', () async {
    fillValidCar();
    controller()
      ..setDescription(
        'Oldindan to‘lov qiling, keyin olib ketasiz. Telefon: 90 123 45 67',
      )
      ..addPhotos(['/a.jpg']);
    await flush();
    final item = await controller().publish();
    expect(item.pendingReview, isTrue);
    final listing = await container
        .read(listingRepositoryProvider)
        .getById(item.id);
    expect(listing.status, ListingStatus.pendingReview);
  });

  test('vacancies are published to the jobs vertical', () async {
    controller()
      ..setCategory('jobs')
      ..setTitle('Sotuvchi kerak')
      ..setPrice(3000000)
      ..setPriceMax(4500000)
      ..setDescription('Do‘konga xushmuomala sotuvchi kerak.')
      ..setAttribute('company', 'Chust Market')
      ..setAttribute('employment', EmploymentType.partTime.label);
    expect(controller().next(), isEmpty);
    expect(
      controller().next(),
      isEmpty,
      reason: 'photos are optional for vacancies',
    );

    final item = await controller().publish();
    expect(item.target, ShareTarget.job);
    final job = await container.read(jobRepositoryProvider).getJob(item.id);
    expect(job.company.name, 'Chust Market');
    expect(job.employmentType, EmploymentType.partTime);
    expect(job.salaryMax, 4500000);
  });
}
