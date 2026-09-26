import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration. Values come from `--dart-define` so no
/// environment-specific values or secrets live in source.
///
/// ```
/// flutter run --dart-define=API_BASE_URL=https://api.bozor.uz/v1
/// ```
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.webBaseUrl,
    required this.appScheme,
    required this.supportTelegramUrl,
    required this.demoLatency,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
    webBaseUrl: String.fromEnvironment('WEB_BASE_URL', defaultValue: 'https://bozor.uz'),
    appScheme: String.fromEnvironment('APP_SCHEME', defaultValue: 'bozor'),
    supportTelegramUrl: String.fromEnvironment('SUPPORT_TELEGRAM_URL', defaultValue: 'https://t.me/bozoruz_support'),
    demoLatency: Duration(milliseconds: int.fromEnvironment('DEMO_LATENCY_MS', defaultValue: 450)),
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

  bool get useDemoData => apiBaseUrl.isEmpty;

  AppConfig copyWith({Duration? demoLatency, String? apiBaseUrl}) => AppConfig(
    apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
    webBaseUrl: webBaseUrl,
    appScheme: appScheme,
    supportTelegramUrl: supportTelegramUrl,
    demoLatency: demoLatency ?? this.demoLatency,
  );
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());
