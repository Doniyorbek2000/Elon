import 'package:flutter/foundation.dart';

import '../../core/l10n/l10n.dart';

/// Paid-visibility labels asserted by the server (`promotion`, `badges`).
/// They are separate from quality signals (rating, verification) and are
/// always shown so paid placement is never disguised as organic.
enum PromotionType {
  vip,
  top,
  featured,
  urgent;

  String get badge => switch (this) {
    PromotionType.vip => 'VIP',
    PromotionType.top => 'TOP',
    PromotionType.featured => tr('Tavsiya'),
    PromotionType.urgent => tr('Shoshilinch'),
  };

  static PromotionType? parse(Object? value) => PromotionType.values.where((type) => type.name == value).firstOrNull;
}

@immutable
class Promotion {
  const Promotion(this.type, {this.until, this.badges = const []});

  /// Primary badge (the highest one).
  final PromotionType type;
  final DateTime? until;

  /// Every active badge, primary first (e.g. `top` + `urgent` on a vacancy).
  final List<PromotionType> badges;

  List<PromotionType> get all => badges.isEmpty ? [type] : badges;

  bool isActive(DateTime now) => until == null || until!.isAfter(now);

  /// Reads the card fields every listing/job/provider payload carries.
  static Promotion? fromJson(Map<String, dynamic> json) {
    final badges = [for (final value in json['badges'] as List<dynamic>? ?? const []) ?PromotionType.parse(value)];
    final primary = PromotionType.parse(json['promotion']) ?? badges.firstOrNull;
    if (primary == null) return null;
    return Promotion(primary, badges: badges.isEmpty ? [primary] : badges);
  }
}
