import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import 'app_config.dart';

/// Product switches served by the backend (`GET /config`), so features can
/// be turned on or off without an app release. Everything commercial
/// defaults to off: if the config cannot be loaded the app stays free.
///
/// The server enforces every flag again; these only decide what is shown.
@immutable
class FeatureFlags {
  const FeatureFlags({
    this.monetization = false,
    this.listingTop = false,
    this.listingVip = false,
    this.listingBump = false,
    this.featuredListings = false,
    this.premiumJobs = false,
    this.featuredServices = false,
    this.businessAccounts = false,
    this.businessPlans = false,
    this.ads = false,
    this.coupons = false,
    this.promotionCredits = false,
    this.aiListingAssistEnabled = false,
  });

  factory FeatureFlags.fromJson(Map<String, dynamic> json, {bool aiListingAssist = false}) {
    bool flag(String key) => json[key] == true;
    return FeatureFlags(
      monetization: flag('monetization'),
      listingTop: flag('listingTop'),
      listingVip: flag('listingVip'),
      listingBump: flag('listingBump'),
      featuredListings: flag('featuredListings'),
      premiumJobs: flag('premiumJobs'),
      featuredServices: flag('featuredServices'),
      businessAccounts: flag('businessAccounts'),
      businessPlans: flag('businessPlans'),
      ads: flag('ads'),
      coupons: flag('coupons'),
      promotionCredits: flag('promotionCredits'),
      aiListingAssistEnabled: aiListingAssist,
    );
  }

  /// Master switch for anything that asks the user for money.
  final bool monetization;
  final bool listingTop;
  final bool listingVip;
  final bool listingBump;
  final bool featuredListings;
  final bool premiumJobs;
  final bool featuredServices;

  /// Free business profiles (not gated by [monetization]).
  final bool businessAccounts;
  final bool businessPlans;
  final bool ads;
  final bool coupons;
  final bool promotionCredits;

  /// Photo → suggested category/title/description/attributes (build-time).
  final bool aiListingAssistEnabled;

  bool get canPromoteListings => monetization && (listingTop || listingVip || listingBump || featuredListings);
  bool get canPromoteJobs => monetization && premiumJobs;
  bool get canPromoteProviders => monetization && featuredServices;
  bool get canBuyPlans => monetization && businessPlans;
  bool get canAdvertise => monetization && ads;
}

/// Free-tier limits as configured on the server (never hardcoded here).
@immutable
class FreePlanLimits {
  const FreePlanLimits({this.activeListingLimit, this.monthlyListingLimit, this.photoLimit, this.activeJobLimit});

  factory FreePlanLimits.fromJson(Map<String, dynamic> json) => FreePlanLimits(
    activeListingLimit: (json['activeListingLimit'] as num?)?.toInt(),
    monthlyListingLimit: (json['monthlyListingLimit'] as num?)?.toInt(),
    photoLimit: (json['photoLimit'] as num?)?.toInt(),
    activeJobLimit: (json['activeJobLimit'] as num?)?.toInt(),
  );

  /// `null` means unlimited.
  final int? activeListingLimit;
  final int? monthlyListingLimit;
  final int? photoLimit;
  final int? activeJobLimit;
}

@immutable
class RemoteConfig {
  const RemoteConfig({this.flags = const FeatureFlags(), this.freePlan});

  final FeatureFlags flags;
  final FreePlanLimits? freePlan;
}

const _aiListingAssist = bool.fromEnvironment('FF_AI_LISTING_ASSIST');

/// Loaded once per app start and on explicit refresh. Demo builds have no
/// commercial features at all (no invented prices or plans).
final remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  if (ref.watch(appConfigProvider).useDemoData) {
    return const RemoteConfig(flags: FeatureFlags(aiListingAssistEnabled: _aiListingAssist));
  }
  final json = await ref.watch(apiClientProvider).get<JsonMap>('/config');
  return RemoteConfig(
    flags: FeatureFlags.fromJson(json['flags'] as JsonMap? ?? const {}, aiListingAssist: _aiListingAssist),
    freePlan: json['freePlan'] is Map ? FreePlanLimits.fromJson(json['freePlan'] as JsonMap) : null,
  );
});

/// Synchronous view for widgets: all-off until (or unless) config loads.
final featureFlagsProvider = Provider<FeatureFlags>(
  (ref) => ref.watch(remoteConfigProvider).value?.flags ?? const FeatureFlags(aiListingAssistEnabled: _aiListingAssist),
);
