import 'package:flutter/foundation.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/l10n/l10n.dart';

@immutable
class ServiceCategory {
  const ServiceCategory({required this.id, required this.name, required this.iconKey, required this.tone});

  final String id;
  final String name;
  final String iconKey;
  final AccentTone tone;

  factory ServiceCategory.fromJson(Map<String, dynamic> json) => ServiceCategory(
    id: json['id'] as String,
    name: json['name'] as String,
    iconKey: json['iconKey'] as String? ?? 'grid',
    tone: AccentTone.values.firstWhere((t) => t.name == json['tone'], orElse: () => AccentTone.blue),
  );
}

@immutable
class Review {
  const Review({
    required this.id,
    required this.authorName,
    required this.rating,
    required this.text,
    required this.createdAt,
    this.authorAvatar,
  });

  final String id;
  final String authorName;
  final MediaImage? authorAvatar;
  final int rating;
  final String text;
  final DateTime createdAt;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
    id: json['id'] as String,
    authorName: json['authorName'] as String? ?? tr('Foydalanuvchi'),
    authorAvatar: json['authorAvatar'] == null
        ? null
        : MediaImage.fromJson(json['authorAvatar'] as Map<String, dynamic>),
    rating: (json['rating'] as num).toInt(),
    text: json['text'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

enum PricingType {
  fixed('Qat’iy narx'),
  from('…dan boshlab'),
  hourly('Soatbay'),
  negotiable('Kelishiladi');

  const PricingType(this._label);

  final String _label;

  String get label => tr(_label);
}

/// A concrete service a provider sells ("Kran almashtirish — 100 000 so‘mdan").
@immutable
class ServiceOffering {
  const ServiceOffering({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.pricingType,
    this.description,
    this.priceFrom,
    this.priceUnit,
  });

  final String id;
  final String categoryId;
  final String title;
  final String? description;
  final PricingType pricingType;
  final Money? priceFrom;
  final String? priceUnit;

  factory ServiceOffering.fromJson(Map<String, dynamic> json) => ServiceOffering(
    id: json['id'] as String,
    categoryId: json['categoryId'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    pricingType: PricingType.values.firstWhere(
      (t) => t.name == json['pricingType'],
      orElse: () => PricingType.negotiable,
    ),
    priceFrom: json['priceFrom'] == null ? null : Money.fromJson(json['priceFrom'] as Map<String, dynamic>),
    priceUnit: json['priceUnit'] as String?,
  );
}

/// Input for creating/updating the signed-in user's provider profile.
@immutable
class ProviderDraft {
  const ProviderDraft({
    required this.displayName,
    required this.profession,
    required this.description,
    required this.categoryIds,
    required this.place,
    this.experienceYears = 0,
    this.areaDistrictIds = const [],
  });

  final String displayName;
  final String profession;
  final String description;
  final List<String> categoryIds;
  final Place place;
  final int experienceYears;

  /// Extra districts served, all within [place]'s region.
  final List<String> areaDistrictIds;

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'profession': profession,
    'description': description,
    'categoryIds': categoryIds,
    'experienceYears': experienceYears,
    'place': {'regionId': place.regionId, 'districtId': ?place.districtId},
    'areas': [
      for (final districtId in {?place.districtId, ...areaDistrictIds})
        {'regionId': place.regionId, 'districtId': districtId},
    ],
  };
}

@immutable
class OfferingDraft {
  const OfferingDraft({
    required this.categoryId,
    required this.title,
    required this.pricingType,
    this.description,
    this.priceFrom,
    this.priceUnit,
  });

  final String categoryId;
  final String title;
  final PricingType pricingType;
  final String? description;
  final int? priceFrom;
  final String? priceUnit;

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'title': title,
    'pricingType': pricingType.name,
    if (description != null && description!.trim().isNotEmpty) 'description': description!.trim(),
    'priceFrom': ?priceFrom,
    'currency': 'uzs',
    if (priceUnit != null && priceUnit!.trim().isNotEmpty) 'priceUnit': priceUnit!.trim(),
  };
}

@immutable
class ServiceProvider {
  const ServiceProvider({
    required this.id,
    required this.profile,
    required this.profession,
    required this.categoryId,
    required this.place,
    required this.description,
    required this.experienceYears,
    required this.serviceArea,
    this.portfolio = const [],
    this.reviews = const [],
    this.priceFrom,
    this.priceUnit,
    this.completedJobs = 0,
    this.promotion,
    this.offerings = const [],
    this.shareUrl,
  });

  final String id;
  final PublicProfile profile;
  final String profession;
  final String categoryId;
  final Place place;
  final String description;
  final int experienceYears;
  final List<String> serviceArea;
  final List<MediaImage> portfolio;
  final List<Review> reviews;
  final Money? priceFrom;

  /// "xizmat uchun", "soatiga", "m² uchun"…
  final String? priceUnit;
  final int completedJobs;
  final Promotion? promotion;
  final List<ServiceOffering> offerings;
  final String? shareUrl;

  String get name => profile.name;

  factory ServiceProvider.fromJson(Map<String, dynamic> json) => ServiceProvider(
    id: json['id'] as String,
    profile: PublicProfile.fromJson(json['profile'] as Map<String, dynamic>),
    profession: json['profession'] as String,
    categoryId: json['categoryId'] as String? ?? 'other_services',
    place: Place.fromJson(json['place'] as Map<String, dynamic>),
    description: json['description'] as String? ?? '',
    experienceYears: (json['experienceYears'] as num?)?.toInt() ?? 0,
    serviceArea: [for (final area in json['serviceArea'] as List<dynamic>? ?? const []) '$area'],
    portfolio: [
      for (final image in json['portfolio'] as List<dynamic>? ?? const [])
        MediaImage.fromJson(image as Map<String, dynamic>),
    ],
    reviews: [
      for (final review in json['reviews'] as List<dynamic>? ?? const [])
        Review.fromJson(review as Map<String, dynamic>),
    ],
    priceFrom: json['priceFrom'] == null ? null : Money.fromJson(json['priceFrom'] as Map<String, dynamic>),
    priceUnit: json['priceUnit'] as String?,
    promotion: Promotion.fromJson(json),
    offerings: [
      for (final offering in json['offerings'] as List<dynamic>? ?? const [])
        ServiceOffering.fromJson(offering as Map<String, dynamic>),
    ],
    shareUrl: json['shareUrl'] as String?,
  );
  double get rating => profile.rating ?? 0;
  int get reviewCount => profile.reviewCount;
  bool get isTop => promotion?.type == PromotionType.top || promotion?.type == PromotionType.featured;
}

enum ProviderFilter {
  all('Hammasi'),
  online('Onlayn'),
  top('TOP'),
  topRated('Yuqori reyting');

  const ProviderFilter(this._label);

  final String _label;

  String get label => tr(_label);
}

@immutable
class ProviderQuery {
  const ProviderQuery({this.text = '', this.categoryId, this.filter = ProviderFilter.all, this.regionId});

  final String text;
  final String? categoryId;
  final ProviderFilter filter;
  final String? regionId;

  @override
  bool operator ==(Object other) =>
      other is ProviderQuery &&
      other.text == text &&
      other.categoryId == categoryId &&
      other.filter == filter &&
      other.regionId == regionId;

  @override
  int get hashCode => Object.hash(text, categoryId, filter, regionId);
}

abstract interface class ServicesRepository {
  Future<List<ServiceCategory>> categories();
  Future<List<ServiceProvider>> recommended({String? regionId});
  Future<List<ServiceProvider>> search(ProviderQuery query);
  Future<ServiceProvider> getProvider(String id);
  Future<String> revealPhone(String providerId);

  /// Signed-in user's provider profile (null if they don't offer services).
  Future<ServiceProvider?> myProvider();
  Future<ServiceProvider> saveProvider(ProviderDraft draft);
  Future<void> addOffering(OfferingDraft draft);
  Future<void> deleteOffering(String offeringId);

  /// One review per customer (editing replaces it). The server only accepts
  /// it after a real two-way conversation with the provider.
  Future<void> submitReview(String providerId, {required int rating, String? text});
}
