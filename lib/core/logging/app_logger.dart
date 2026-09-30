import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crash_reporting.dart';

enum LogLevel { debug, info, warning, error }

/// Logging abstraction. Swap [DeveloperLogger] for a crash-reporting
/// implementation (Sentry, Crashlytics) in production without touching callers.
abstract interface class AppLogger {
  void log(LogLevel level, String message, {Object? error, StackTrace? stackTrace, String tag});
}

extension AppLoggerX on AppLogger {
  void debug(String message, {String tag = 'app'}) => log(LogLevel.debug, message, tag: tag);
  void info(String message, {String tag = 'app'}) => log(LogLevel.info, message, tag: tag);
  void warning(String message, {Object? error, String tag = 'app'}) =>
      log(LogLevel.warning, message, error: error, tag: tag);
  void error(String message, {Object? error, StackTrace? stackTrace, String tag = 'app'}) =>
      log(LogLevel.error, message, error: error, stackTrace: stackTrace, tag: tag);
}

class DeveloperLogger implements AppLogger {
  const DeveloperLogger({this.minLevel = kReleaseMode ? LogLevel.warning : LogLevel.debug});

  final LogLevel minLevel;

  @override
  void log(LogLevel level, String message, {Object? error, StackTrace? stackTrace, String tag = 'app'}) {
    if (level.index < minLevel.index) return;
    developer.log(
      message,
      name: 'bozor.$tag',
      level: switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      },
      error: error,
      stackTrace: stackTrace,
    );
  }
}

final appLoggerProvider = Provider<AppLogger>((ref) => const ReportingLogger(DeveloperLogger()));
