import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration. Values come from `--dart-define` so no
/// environment-specific values or secrets live in source.
///
/// ```
/// flutter run --dart-define=API_BASE_URL=https://api.bozor.uz/api/v1
/// ```
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.webBaseUrl,
    required this.appScheme,
    required this.supportTelegramUrl,
    required this.demoLatency,
    this.allowDemoInRelease = false,
    this.isReleaseBuild = kReleaseMode,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
    webBaseUrl: String.fromEnvironment('WEB_BASE_URL', defaultValue: 'https://bozor.uz'),
    appScheme: String.fromEnvironment('APP_SCHEME', defaultValue: 'bozor'),
    supportTelegramUrl: String.fromEnvironment('SUPPORT_TELEGRAM_URL', defaultValue: 'https://t.me/bozoruz_support'),
    demoLatency: Duration(milliseconds: int.fromEnvironment('DEMO_LATENCY_MS', defaultValue: 450)),
    allowDemoInRelease: bool.fromEnvironment('DEMO_MODE'),
  );

  /// Empty means no backend is configured and the app runs on local demo data.
  final String apiBaseUrl;

  /// Public web origin used for share links and universal/app links.
  final String webBaseUrl;

  /// Custom URL scheme (`bozor://app/listing/42`) for deep links.
  final String appScheme;

  final String supportTelegramUrl;

  /// Artificial latency of demo repositories so loading states are exercised.
  final Duration demoLatency;

  /// Explicit opt-in (`--dart-define=DEMO_MODE=true`) for store demo builds.
  final bool allowDemoInRelease;
  final bool isReleaseBuild;

  /// Demo data is a build-time choice, never a runtime fallback: when a
  /// backend is configured, server failures surface as errors.
  bool get useDemoData => apiBaseUrl.isEmpty && (!isReleaseBuild || allowDemoInRelease);

  /// A release build without a backend and without explicit demo opt-in.
  bool get isMisconfigured => apiBaseUrl.isEmpty && isReleaseBuild && !allowDemoInRelease;

  AppConfig copyWith({Duration? demoLatency, String? apiBaseUrl, bool? isReleaseBuild}) => AppConfig(
    apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
    webBaseUrl: webBaseUrl,
    appScheme: appScheme,
    supportTelegramUrl: supportTelegramUrl,
    demoLatency: demoLatency ?? this.demoLatency,
    allowDemoInRelease: allowDemoInRelease,
    isReleaseBuild: isReleaseBuild ?? this.isReleaseBuild,
  );
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());
