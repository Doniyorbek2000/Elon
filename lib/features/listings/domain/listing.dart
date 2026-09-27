import 'package:flutter/foundation.dart';

import '../../../core/domain/media_image.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/public_profile.dart';

enum ItemCondition {
  newItem,
  used;

  String get label => switch (this) {
    ItemCondition.newItem => 'Yangi',
    ItemCondition.used => 'Ishlatilgan',
  };

  /// Wire value used by the API (`new` | `used`).
  String get apiValue => this == ItemCondition.newItem ? 'new' : 'used';

  static ItemCondition? parse(Object? value) => switch (value) {
    'new' || 'newItem' => ItemCondition.newItem,
    'used' => ItemCondition.used,
    _ => null,
  };
}

/// Mirrors the server lifecycle: draft → pendingReview → active ⇄ reserved →
/// sold; expired after the TTL; rejected by moderation; archived by owner.
enum ListingStatus {
  draft,
  active,
  pendingReview,
  reserved,
  rejected,
  sold,
  expired,
  archived;

  String get label => switch (this) {
    ListingStatus.draft => 'Qoralama',
    ListingStatus.active => 'Faol',
    ListingStatus.pendingReview => 'Tekshiruvda',
    ListingStatus.reserved => 'Band qilingan',
    ListingStatus.rejected => 'Rad etilgan',
    ListingStatus.sold => 'Sotilgan',
    ListingStatus.expired => 'Muddati tugagan',
    ListingStatus.archived => 'Arxivda',
  };

  static ListingStatus parse(Object? value) =>
      ListingStatus.values.firstWhere((s) => s.name == value, orElse: () => ListingStatus.active);
}

@immutable
class ListingAttribute {
  const ListingAttribute({required this.key, required this.label, required this.value});

  final String key;
  final String label;
  final String value;

  factory ListingAttribute.fromJson(Map<String, dynamic> json) =>
      ListingAttribute(key: json['key'] as String, label: json['label'] as String, value: '${json['value']}');

  Map<String, dynamic> toJson() => {'key': key, 'label': label, 'value': value};
}

@immutable
class Listing {
  const Listing({
    required this.id,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.images,
    required this.place,
    required this.publishedAt,
    required this.seller,
    this.price,
    this.negotiable = false,
    this.condition,
    this.attributes = const [],
    this.views = 0,
    this.favorites = 0,
    this.promotion,
    this.status = ListingStatus.active,
    this.distanceKm,
    this.shareUrl,
    this.rejectReason,
  });

  final String id;
  final String title;
  final String description;
  final String categoryId;
  final List<MediaImage> images;
  final Place place;
  final DateTime publishedAt;
  final PublicProfile seller;

  /// Null = price on request.
  final Money? price;
  final bool negotiable;
  final ItemCondition? condition;
  final List<ListingAttribute> attributes;
  final int views;
  final int favorites;
  final Promotion? promotion;
  final ListingStatus status;

  /// Filled by the backend for proximity queries.
  final double? distanceKm;

  /// Canonical web URL (App Links / Universal Links) from the server.
  final String? shareUrl;

  /// Moderation reason, visible to the owner only.
  final String? rejectReason;

  MediaImage? get cover => images.isEmpty ? null : images.first;

  Listing copyWith({int? views, int? favorites, ListingStatus? status, double? distanceKm, Promotion? promotion}) =>
      Listing(
        id: id,
        title: title,
        description: description,
        categoryId: categoryId,
        images: images,
        place: place,
        publishedAt: publishedAt,
        seller: seller,
        price: price,
        negotiable: negotiable,
        condition: condition,
        attributes: attributes,
        views: views ?? this.views,
        favorites: favorites ?? this.favorites,
        promotion: promotion ?? this.promotion,
        status: status ?? this.status,
        distanceKm: distanceKm ?? this.distanceKm,
        shareUrl: shareUrl,
        rejectReason: rejectReason,
      );

  factory Listing.fromJson(Map<String, dynamic> json) => Listing(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    categoryId: json['categoryId'] as String,
    images: [
      for (final image in json['images'] as List<dynamic>? ?? const [])
        MediaImage.fromJson(image as Map<String, dynamic>),
    ],
    place: Place.fromJson(json['place'] as Map<String, dynamic>),
    publishedAt: DateTime.parse(json['publishedAt'] as String),
    seller: PublicProfile.fromJson(json['seller'] as Map<String, dynamic>),
    price: json['price'] == null ? null : Money.fromJson(json['price'] as Map<String, dynamic>),
    negotiable: json['negotiable'] as bool? ?? false,
    condition: ItemCondition.parse(json['condition']),
    attributes: [
      for (final attribute in json['attributes'] as List<dynamic>? ?? const [])
        ListingAttribute.fromJson(attribute as Map<String, dynamic>),
    ],
    views: json['views'] as int? ?? 0,
    favorites: json['favorites'] as int? ?? 0,
    promotion: Promotion.fromJson(json),
    status: ListingStatus.parse(json['status']),
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
    shareUrl: json['shareUrl'] as String?,
    rejectReason: json['rejectReason'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Listing && other.id == id && other.views == views && other.status == status;

  @override
  int get hashCode => Object.hash(id, views, status);
}
