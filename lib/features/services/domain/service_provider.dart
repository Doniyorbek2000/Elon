import 'package:flutter/foundation.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/public_profile.dart';

@immutable
class ServiceCategory {
  const ServiceCategory({required this.id, required this.name, required this.iconKey, required this.tone});

  final String id;
  final String name;
  final String iconKey;
  final AccentTone tone;
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

  String get name => profile.name;
  double get rating => profile.rating ?? 0;
  int get reviewCount => profile.reviewCount;
  bool get isTop => promotion?.type == PromotionType.top || promotion?.type == PromotionType.featured;
}

enum ProviderFilter {
  all('Hammasi'),
  online('Onlayn'),
  top('TOP'),
  topRated('Yuqori reyting');

  const ProviderFilter(this.label);

  final String label;
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
}
