import 'package:flutter/foundation.dart';

import '../../../core/domain/media_image.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/sharing/share_service.dart';
import '../../listings/domain/listing.dart';

enum CreateStep {
  details('Ma’lumot'),
  photos('Rasmlar'),
  review('Ko‘rib chiqish');

  const CreateStep(this.label);

  final String label;
}

@immutable
class DraftPhoto {
  const DraftPhoto({required this.id, required this.localPath, this.progress = 0, this.remoteId, this.failed = false});

  final String id;
  final String localPath;
  final double progress;
  final String? remoteId;
  final bool failed;

  bool get isUploaded => remoteId != null;
  bool get isUploading => !isUploaded && !failed;

  DraftPhoto copyWith({double? progress, String? remoteId, bool? failed}) => DraftPhoto(
    id: id,
    localPath: localPath,
    progress: progress ?? this.progress,
    remoteId: remoteId ?? this.remoteId,
    failed: failed ?? this.failed,
  );

  factory DraftPhoto.fromJson(Map<String, dynamic> json) => DraftPhoto(
    id: json['id'] as String,
    localPath: json['path'] as String,
    remoteId: json['remoteId'] as String?,
    progress: json['remoteId'] == null ? 0 : 1,
  );

  Map<String, dynamic> toJson() => {'id': id, 'path': localPath, 'remoteId': ?remoteId};
}

/// Everything the user typed in the create flow. Persisted on every change so
/// an accidental close or process death never loses work.
@immutable
class ListingDraft {
  const ListingDraft({
    this.step = CreateStep.details,
    this.categoryId,
    this.title = '',
    this.description = '',
    this.price,
    this.priceMax,
    this.currency = Currency.uzs,
    this.negotiable = false,
    this.condition,
    this.attributes = const {},
    this.place,
    this.photos = const [],
    this.restored = false,
  });

  final CreateStep step;
  final String? categoryId;
  final String title;
  final String description;
  final int? price;

  /// Upper bound for salary ranges (jobs).
  final int? priceMax;
  final Currency currency;
  final bool negotiable;
  final ItemCondition? condition;
  final Map<String, String> attributes;
  final Place? place;
  final List<DraftPhoto> photos;

  /// True when this draft was recovered from storage on open.
  final bool restored;

  static const maxPhotos = 12;
  static const titleMinLength = 3;
  static const titleMaxLength = 70;
  static const descriptionMinLength = 10;
  static const descriptionMaxLength = 3000;

  bool get hasContent =>
      categoryId != null || title.isNotEmpty || description.isNotEmpty || price != null || photos.isNotEmpty;

  bool get uploadsPending => photos.any((p) => p.isUploading);
  bool get uploadsFailed => photos.any((p) => p.failed);

  Money? get money => price == null ? null : Money(price!, currency);

  ListingDraft copyWith({
    CreateStep? step,
    String? Function()? categoryId,
    String? title,
    String? description,
    int? Function()? price,
    int? Function()? priceMax,
    Currency? currency,
    bool? negotiable,
    ItemCondition? Function()? condition,
    Map<String, String>? attributes,
    Place? place,
    List<DraftPhoto>? photos,
    bool? restored,
  }) => ListingDraft(
    step: step ?? this.step,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    title: title ?? this.title,
    description: description ?? this.description,
    price: price != null ? price() : this.price,
    priceMax: priceMax != null ? priceMax() : this.priceMax,
    currency: currency ?? this.currency,
    negotiable: negotiable ?? this.negotiable,
    condition: condition != null ? condition() : this.condition,
    attributes: attributes ?? this.attributes,
    place: place ?? this.place,
    photos: photos ?? this.photos,
    restored: restored ?? this.restored,
  );

  factory ListingDraft.fromJson(Map<String, dynamic> json) => ListingDraft(
    step: CreateStep.values.where((s) => s.name == json['step']).firstOrNull ?? CreateStep.details,
    categoryId: json['categoryId'] as String?,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    price: json['price'] as int?,
    priceMax: json['priceMax'] as int?,
    currency: Currency.parse(json['currency']),
    negotiable: json['negotiable'] as bool? ?? false,
    condition: ItemCondition.parse(json['condition']),
    attributes: {
      for (final entry in (json['attributes'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: '${entry.value}',
    },
    place: json['place'] == null ? null : Place.fromJson(json['place'] as Map<String, dynamic>),
    photos: [
      for (final photo in json['photos'] as List<dynamic>? ?? const [])
        DraftPhoto.fromJson(photo as Map<String, dynamic>),
    ],
    restored: true,
  );

  Map<String, dynamic> toJson() => {
    'step': step.name,
    'categoryId': ?categoryId,
    'title': title,
    'description': description,
    'price': ?price,
    'priceMax': ?priceMax,
    'currency': currency.name,
    'negotiable': negotiable,
    'condition': ?condition?.name,
    'attributes': attributes,
    'place': ?place?.toJson(),
    'photos': [for (final photo in photos) photo.toJson()],
  };
}

/// Result of publishing, independent of the vertical it landed in.
@immutable
class PublishedItem {
  const PublishedItem({
    required this.target,
    required this.id,
    required this.title,
    required this.place,
    required this.pendingReview,
    this.subtitle,
    this.image,
  });

  final ShareTarget target;
  final String id;
  final String title;
  final String? subtitle;
  final Place place;
  final MediaImage? image;
  final bool pendingReview;
}
