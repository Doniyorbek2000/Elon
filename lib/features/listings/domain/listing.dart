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

  static ItemCondition? parse(Object? value) => switch (value) {
    'new' || 'newItem' => ItemCondition.newItem,
    'used' => ItemCondition.used,
    _ => null,
  };
}

enum ListingStatus {
  active,
  pendingReview,
  rejected,
  sold,
  archived;

  String get label => switch (this) {
    ListingStatus.active => 'Faol',
    ListingStatus.pendingReview => 'Tekshiruvda',
    ListingStatus.rejected => 'Rad etilgan',
    ListingStatus.sold => 'Sotilgan',
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
    promotion: switch (PromotionType.parse(json['promotion'])) {
      final PromotionType type => Promotion(type),
      null => null,
    },
    status: ListingStatus.parse(json['status']),
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is Listing && other.id == id && other.views == views && other.status == status;

  @override
  int get hashCode => Object.hash(id, views, status);
}
