import 'package:flutter/foundation.dart';

import 'money.dart';

/// Paid visibility products. Present in the model from day one so
/// monetization can be switched on via feature flags without migrations.
enum PromotionType {
  top,
  vip,
  bump,
  featured,
  premiumVacancy;

  String get badge => switch (this) {
    PromotionType.top => 'TOP',
    PromotionType.vip => 'VIP',
    PromotionType.bump => 'Ko‘tarilgan',
    PromotionType.featured => 'Tavsiya',
    PromotionType.premiumVacancy => 'Premium',
  };

  static PromotionType? parse(Object? value) =>
      PromotionType.values.where((type) => type.name == value).firstOrNull;
}

@immutable
class Promotion {
  const Promotion(this.type, {this.until});

  final PromotionType type;
  final DateTime? until;

  bool isActive(DateTime now) => until == null || until!.isAfter(now);
}

enum PromotionTarget { listing, vacancy, provider, business }

/// Catalog entry for a purchasable promotion (served by backend when enabled).
@immutable
class PromotionProduct {
  const PromotionProduct({
    required this.id,
    required this.type,
    required this.target,
    required this.title,
    required this.description,
    required this.durationDays,
    required this.price,
  });

  final String id;
  final PromotionType type;
  final PromotionTarget target;
  final String title;
  final String description;
  final int durationDays;
  final Money price;
}

@immutable
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.title,
    required this.monthlyPrice,
    required this.benefits,
    this.highlighted = false,
  });

  final String id;
  final String title;
  final Money monthlyPrice;
  final List<String> benefits;
  final bool highlighted;
}
