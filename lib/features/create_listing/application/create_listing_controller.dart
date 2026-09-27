import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/sharing/share_service.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/application/session_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/category.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/domain/job.dart';
import '../../listings/application/listing_providers.dart';
import '../../listings/domain/listing.dart';
import '../../listings/domain/listing_repository.dart';
import '../../location/application/location_controller.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../data/media_services.dart';
import '../domain/listing_draft.dart';

/// Field keys used in validation error maps.
abstract final class DraftField {
  static const category = 'category';
  static const title = 'title';
  static const price = 'price';
  static const description = 'description';
  static const place = 'place';
  static const photos = 'photos';
  static String attribute(String key) => 'attr.$key';
}

class CreateListingController extends Notifier<ListingDraft> {
  final Map<String, StreamSubscription<Object?>> _uploads = {};
  Timer? _persistTimer;
  int _photoSequence = 0;

  @override
  ListingDraft build() {
    ref.onDispose(() {
      _persistTimer?.cancel();
      for (final subscription in _uploads.values) {
        subscription.cancel();
      }
    });
    final stored = ref.read(keyValueStoreProvider).getJson(StoreKeys.listingDraft);
    if (stored != null) {
      try {
        final draft = ListingDraft.fromJson(stored);
        // Resume uploads that were interrupted by the app closing.
        Future.microtask(() => draft.photos.where((p) => !p.isUploaded).forEach(_startUpload));
        return draft;
      } on Object {
        ref.read(keyValueStoreProvider).remove(StoreKeys.listingDraft).ignore();
      }
    }
    return ListingDraft(place: ref.read(locationProvider).toPlace());
  }

  CategoryTree get _tree => ref.read(categoryTreeProvider);

  CategoryFormSchema get schema =>
      state.categoryId == null ? CategoryFormSchema.generic : _tree.schemaFor(state.categoryId!);

  void _update(ListingDraft next) {
    state = next;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  void _persistNow() {
    final store = ref.read(keyValueStoreProvider);
    if (state.hasContent) {
      store.setJson(StoreKeys.listingDraft, state.toJson()).ignore();
    } else {
      store.remove(StoreKeys.listingDraft).ignore();
    }
  }

  // ----------------------------------------------------------- field edits

  void setCategory(String categoryId) {
    final nextSchema = _tree.schemaFor(categoryId);
    final allowedKeys = nextSchema.fields.map((f) => f.key).toSet();
    _update(
      state.copyWith(
        categoryId: () => categoryId,
        attributes: {
          for (final entry in state.attributes.entries)
            if (allowedKeys.contains(entry.key)) entry.key: entry.value,
        },
        condition: nextSchema.supportsCondition ? null : () => null,
        currency: nextSchema.allowUsd ? state.currency : Currency.uzs,
      ),
    );
  }

  void setTitle(String value) => _update(state.copyWith(title: value));
  void setDescription(String value) => _update(state.copyWith(description: value));
  void setPrice(int? value) => _update(state.copyWith(price: () => value));
  void setPriceMax(int? value) => _update(state.copyWith(priceMax: () => value));
  void setCurrency(Currency value) => _update(state.copyWith(currency: value));
  void setNegotiable({required bool value}) => _update(state.copyWith(negotiable: value));
  void setCondition(ItemCondition? value) => _update(state.copyWith(condition: () => value));
  void setPlace(Place value) => _update(state.copyWith(place: value));

  void setAttribute(String key, String value) {
    final next = {...state.attributes};
    if (value.trim().isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    _update(state.copyWith(attributes: next));
  }

  // ---------------------------------------------------------------- photos

  int get remainingPhotoSlots => ListingDraft.maxPhotos - state.photos.length;

  void addPhotos(List<String> paths) {
    final accepted = paths.take(remainingPhotoSlots).toList();
    if (accepted.isEmpty) return;
    final added = [
      for (final path in accepted)
        DraftPhoto(id: 'p${DateTime.now().microsecondsSinceEpoch}_${_photoSequence++}', localPath: path),
    ];
    _update(state.copyWith(photos: [...state.photos, ...added]));
    added.forEach(_startUpload);
  }

  void _startUpload(DraftPhoto photo) {
    _uploads[photo.id]?.cancel();
    _uploads[photo.id] = ref
        .read(mediaUploadServiceProvider)
        .upload(photo.localPath)
        .listen(
          (progress) =>
              _patchPhoto(photo.id, (p) => p.copyWith(progress: progress.fraction, remoteId: progress.remoteId)),
          onError: (Object _) => _patchPhoto(photo.id, (p) => p.copyWith(failed: true)),
          onDone: () => _uploads.remove(photo.id),
        );
  }

  void _patchPhoto(String id, DraftPhoto Function(DraftPhoto) patch) {
    if (!ref.mounted) return;
    _update(state.copyWith(photos: [for (final p in state.photos) p.id == id ? patch(p) : p]));
  }

  void retryUpload(String id) {
    final photo = state.photos.where((p) => p.id == id).firstOrNull;
    if (photo == null) return;
    _patchPhoto(id, (p) => DraftPhoto(id: p.id, localPath: p.localPath));
    _startUpload(photo);
  }

  void removePhoto(String id) {
    _uploads.remove(id)?.cancel();
    _update(state.copyWith(photos: state.photos.where((p) => p.id != id).toList()));
  }

  void movePhoto(int from, int to) {
    if (from == to || from < 0 || from >= state.photos.length) return;
    final photos = [...state.photos];
    final photo = photos.removeAt(from);
    photos.insert(to.clamp(0, photos.length), photo);
    _update(state.copyWith(photos: photos));
  }

  /// The cover is always the first photo.
  void makeCover(String id) {
    final index = state.photos.indexWhere((p) => p.id == id);
    if (index > 0) movePhoto(index, 0);
  }

  // ------------------------------------------------------------ validation

  Map<String, String> validate(CreateStep step) {
    final errors = <String, String>{};
    final draft = state;
    switch (step) {
      case CreateStep.details:
        if (draft.categoryId == null) errors[DraftField.category] = 'Kategoriyani tanlang';
        final title = draft.title.trim();
        if (title.length < ListingDraft.titleMinLength) {
          errors[DraftField.title] = 'Sarlavha kamida ${ListingDraft.titleMinLength} ta belgidan iborat bo‘lsin';
        }
        final priceMode = schema.priceMode;
        if (priceMode == PriceMode.required && !draft.negotiable && (draft.price == null || draft.price! <= 0)) {
          errors[DraftField.price] = 'Narxni kiriting yoki «Kelishiladi»ni tanlang';
        }
        if (priceMode == PriceMode.salary &&
            draft.price != null &&
            draft.priceMax != null &&
            draft.priceMax! < draft.price!) {
          errors[DraftField.price] = 'Maksimal maosh minimaldan kam bo‘lmasin';
        }
        if (draft.description.trim().length < ListingDraft.descriptionMinLength) {
          errors[DraftField.description] =
              'Tavsifni batafsilroq yozing (kamida ${ListingDraft.descriptionMinLength} belgi)';
        }
        if (draft.place == null) errors[DraftField.place] = 'Manzilni tanlang';
        for (final field in schema.fields) {
          final error = field.validate(draft.attributes[field.key]);
          if (error != null) errors[DraftField.attribute(field.key)] = error;
        }
      case CreateStep.photos:
        if (schema.photosRequired && draft.photos.isEmpty) errors[DraftField.photos] = 'Kamida bitta rasm qo‘shing';
        if (draft.uploadsFailed) {
          errors[DraftField.photos] = 'Ba’zi rasmlar yuklanmadi — qayta urinib ko‘ring yoki o‘chiring';
        }
      case CreateStep.review:
        errors
          ..addAll(validate(CreateStep.details))
          ..addAll(validate(CreateStep.photos));
    }
    return errors;
  }

  /// Moves forward if the current step is valid; returns its errors otherwise.
  Map<String, String> next() {
    final errors = validate(state.step);
    if (errors.isEmpty && state.step != CreateStep.review) {
      _update(state.copyWith(step: CreateStep.values[state.step.index + 1]));
    }
    return errors;
  }

  void back() {
    if (state.step.index > 0) _update(state.copyWith(step: CreateStep.values[state.step.index - 1]));
  }

  void goTo(CreateStep step) {
    if (step.index <= state.step.index) _update(state.copyWith(step: step));
  }

  List<RiskSignal> riskSignals() => ListingRiskAssessor.assess(
    title: state.title,
    description: state.description,
    price: state.money,
    referencePrice: state.categoryId == null ? null : ref.read(categoryReferencePriceProvider(state.categoryId!)),
  );

  /// Publishes and clears the draft. Vacancies go to the jobs vertical;
  /// everything else becomes a marketplace listing. Throws [AppFailure].
  Future<PublishedItem> publish() async {
    final errors = validate(CreateStep.review);
    if (errors.isNotEmpty) throw StateError('Draft invalid: ${errors.keys.join(', ')}');
    if (state.uploadsPending) throw StateError('Uploads still in progress');
    final user = ref.read(sessionProvider);
    if (user == null) throw StateError('publish() requires a signed-in user');

    final draft = state;
    // Demo mode approximates moderation locally; the server decides otherwise.
    final needsReview =
        ref.read(appConfigProvider).useDemoData && ListingRiskAssessor.requiresModeration(riskSignals());
    final PublishedItem item;
    if (_tree.rootOf(draft.categoryId!)?.kind == CategoryKind.jobs) {
      item = await _publishVacancy(draft, user.toPublic());
    } else {
      item = await _publishListing(draft, user.id, needsReview: needsReview);
    }
    ref.read(listingsRevisionProvider.notifier).bump();
    await discard();
    return item;
  }

  Future<PublishedItem> _publishListing(ListingDraft draft, String userId, {required bool needsReview}) async {
    final fieldsByKey = {for (final f in schema.fields) f.key: f};
    final repository = ref.read(listingRepositoryProvider);
    final listing = await repository.publish(
      NewListing(
        categoryId: draft.categoryId!,
        title: draft.title.trim(),
        description: draft.description.trim(),
        place: draft.place!,
        imageIds: [for (final photo in draft.photos) photo.remoteId!],
        price: draft.negotiable && draft.price == null ? null : draft.money,
        negotiable: draft.negotiable,
        condition: draft.condition,
        attributes: [
          for (final entry in draft.attributes.entries)
            ListingAttribute(
              key: entry.key,
              label: fieldsByKey[entry.key]?.label ?? entry.key,
              value: fieldsByKey[entry.key]?.displayValue(entry.value) ?? entry.value,
            ),
        ],
        attributeValues: {
          for (final entry in draft.attributes.entries)
            if (fieldsByKey[entry.key]?.toApiValue(entry.value) case final Object value) entry.key: value,
        },
      ),
      sellerId: userId,
    );
    if (needsReview) await repository.updateStatus(listing.id, ListingStatus.pendingReview);
    final underReview = needsReview || listing.status == ListingStatus.pendingReview;
    return PublishedItem(
      target: ShareTarget.listing,
      id: listing.id,
      title: listing.title,
      subtitle: listing.price == null ? 'Kelishiladi' : Formatters.money(listing.price!),
      place: listing.place,
      image: listing.cover,
      pendingReview: underReview,
    );
  }

  Future<PublishedItem> _publishVacancy(ListingDraft draft, PublicProfile employer) async {
    T option<T extends Enum>(List<T> values, String key, String Function(T) label, T fallback) =>
        values.where((v) => label(v) == draft.attributes[key]).firstOrNull ?? fallback;
    final job = await ref
        .read(jobRepositoryProvider)
        .postVacancy(
          NewVacancy(
            title: draft.title.trim(),
            companyName: draft.attributes['company'] ?? employer.name,
            place: draft.place!,
            employmentType: option(EmploymentType.values, 'employment', (e) => e.label, EmploymentType.fullTime),
            experience: option(ExperienceLevel.values, 'experience', (e) => e.label, ExperienceLevel.none),
            description: draft.description.trim(),
            workingHours: draft.attributes['hours'] ?? '',
            salaryMin: draft.price,
            salaryMax: draft.priceMax,
          ),
          employer: employer,
        );
    ref.invalidate(jobSearchProvider);
    return PublishedItem(
      target: ShareTarget.job,
      id: job.id,
      title: job.title,
      subtitle: Formatters.salaryRange(job.salaryMin, job.salaryMax, job.currency),
      place: job.place,
      pendingReview: false,
    );
  }

  Future<void> discard() async {
    for (final subscription in _uploads.values) {
      await subscription.cancel();
    }
    _uploads.clear();
    _persistTimer?.cancel();
    state = ListingDraft(place: ref.read(locationProvider).toPlace());
    await ref.read(keyValueStoreProvider).remove(StoreKeys.listingDraft);
  }

  /// Flushes pending writes immediately (e.g. when the user closes the flow).
  Future<void> saveNow() async {
    _persistTimer?.cancel();
    _persistNow();
  }

  void acknowledgeRestore() => state = state.copyWith(restored: false);
}

final createListingProvider = NotifierProvider<CreateListingController, ListingDraft>(CreateListingController.new);
