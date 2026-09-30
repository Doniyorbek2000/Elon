import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time product switches. The service is free, so nothing here is
/// commercial.
@immutable
class FeatureFlags {
  const FeatureFlags({this.aiListingAssistEnabled = false});

  /// Photo → suggested category/title/description/attributes (build-time).
  final bool aiListingAssistEnabled;
}

const _aiListingAssist = bool.fromEnvironment('FF_AI_LISTING_ASSIST');

final featureFlagsProvider = Provider<FeatureFlags>(
  (ref) => const FeatureFlags(aiListingAssistEnabled: _aiListingAssist),
);
