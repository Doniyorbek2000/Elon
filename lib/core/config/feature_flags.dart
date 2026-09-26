import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Product feature switches. Defaults reflect the free growth phase:
/// monetization surfaces exist in code but stay hidden until enabled.
///
/// Today values come from `--dart-define`; the provider is the single seam
/// to swap in remote config later without touching feature code.
class FeatureFlags {
  const FeatureFlags({
    this.monetizationEnabled = false,
    this.paidPromotionsEnabled = false,
    this.businessAccountsEnabled = false,
    this.advertisingEnabled = false,
    this.subscriptionsEnabled = false,
    this.aiListingAssistEnabled = false,
    this.showPromotionBadges = true,
    this.realtimeChatEnabled = false,
  });

  factory FeatureFlags.fromEnvironment() => const FeatureFlags(
    monetizationEnabled: bool.fromEnvironment('FF_MONETIZATION'),
    paidPromotionsEnabled: bool.fromEnvironment('FF_PAID_PROMOTIONS'),
    businessAccountsEnabled: bool.fromEnvironment('FF_BUSINESS_ACCOUNTS'),
    advertisingEnabled: bool.fromEnvironment('FF_ADVERTISING'),
    subscriptionsEnabled: bool.fromEnvironment('FF_SUBSCRIPTIONS'),
    aiListingAssistEnabled: bool.fromEnvironment('FF_AI_LISTING_ASSIST'),
    showPromotionBadges: bool.fromEnvironment('FF_PROMOTION_BADGES', defaultValue: true),
    realtimeChatEnabled: bool.fromEnvironment('FF_REALTIME_CHAT'),
  );

  /// Master switch for anything that asks the user for money.
  final bool monetizationEnabled;

  /// TOP / VIP / bump / featured purchases for listings, vacancies, providers.
  final bool paidPromotionsEnabled;
  final bool businessAccountsEnabled;
  final bool advertisingEnabled;
  final bool subscriptionsEnabled;

  /// Photo → suggested category/title/description/attributes.
  final bool aiListingAssistEnabled;

  /// Promoted content can still be labeled during the free phase
  /// (e.g. editorially featured providers) without selling promotions.
  final bool showPromotionBadges;

  /// Use the WebSocket gateway instead of the polling/demo transport.
  final bool realtimeChatEnabled;

  bool get canSellPromotions => monetizationEnabled && paidPromotionsEnabled;
}

final featureFlagsProvider = Provider<FeatureFlags>((ref) => FeatureFlags.fromEnvironment());
