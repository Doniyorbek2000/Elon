import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_logger.dart';

/// Opt-in crash reporting: enabled only when the build defines `SENTRY_DSN`
/// (`--dart-define=SENTRY_DSN=https://…`). Without it nothing is sent.
abstract final class CrashReporting {
  static const _dsn = String.fromEnvironment('SENTRY_DSN');
  static const _environment = String.fromEnvironment('SENTRY_ENVIRONMENT');
  static const _release = String.fromEnvironment('APP_RELEASE');

  static bool _enabled = false;
  static bool get enabled => _enabled;

  static Future<void> init() async {
    if (_dsn.isEmpty || _enabled) return;
    // SentryFlutter adds native crash capture (Android NDK/ANR, iOS signals) on top of Dart errors.
    await SentryFlutter.init((options) {
      options
        ..dsn = _dsn
        ..environment = _environment.isEmpty ? (kReleaseMode ? 'production' : 'development') : _environment
        ..release = _release.isEmpty ? null : _release
        ..sendDefaultPii = false
        ..attachScreenshot = false
        ..enableUserInteractionBreadcrumbs = false
        ..beforeSend = _scrub;
    });
    _enabled = true;
  }

  /// Nothing about the person or the request payload leaves the device.
  @visibleForTesting
  static SentryEvent? scrub(SentryEvent event, Hint hint) => _scrub(event, hint);

  static SentryEvent? _scrub(SentryEvent event, Hint hint) {
    // Empty replacements: the SDK's fields are immutable, and an empty user/request carries nothing.
    return event.copyWith(
      user: SentryUser(id: 'anonymous'),
      request: SentryRequest(),
    );
  }

  static Future<void> capture(Object error, StackTrace? stackTrace, {String? tag}) async {
    if (!_enabled) return;
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: tag == null ? null : (scope) => scope.setTag('area', tag),
    );
  }
}

/// Forwards to [inner] and reports errors (with an exception object) to Sentry.
/// Warnings become breadcrumbs so an eventual crash carries its lead-up.
class ReportingLogger implements AppLogger {
  const ReportingLogger(this.inner);

  final AppLogger inner;

  @override
  void log(LogLevel level, String message, {Object? error, StackTrace? stackTrace, String tag = 'app'}) {
    inner.log(level, message, error: error, stackTrace: stackTrace, tag: tag);
    if (!CrashReporting.enabled) return;
    if (level == LogLevel.error && error != null) {
      CrashReporting.capture(error, stackTrace, tag: tag);
    } else if (level.index >= LogLevel.warning.index) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          category: tag,
          level: level == LogLevel.error ? SentryLevel.error : SentryLevel.warning,
        ),
      );
    }
  }
}
