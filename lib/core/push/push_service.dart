import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';

/// Mobile push transport. The server decides what to send (and hides message
/// previews when the recipient disabled them); the app registers its token
/// and routes taps to `data.route`.
abstract interface class PushService {
  /// False when push is not configured for this build.
  bool get isAvailable;

  Future<void> initialize();

  /// Asks the OS for permission (iOS/Android 13+). Returns whether granted.
  Future<bool> requestPermission();

  Future<String?> token();
  Stream<String> get onTokenRefresh;

  /// In-app route of a notification the user tapped (cold start included).
  Stream<String> get onOpenRoute;
}

/// Used when no Firebase configuration is provided. Honest no-op: the app
/// shows in-app notifications only.
class DisabledPushService implements PushService {
  const DisabledPushService();

  @override
  bool get isAvailable => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<String> get onOpenRoute => const Stream.empty();
}

/// Firebase Cloud Messaging (Android + iOS via APNs). Options come from
/// `--dart-define` so no project configuration is committed:
/// `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`,
/// `FIREBASE_PROJECT_ID` (+ `FIREBASE_IOS_BUNDLE_ID` for iOS).
class FirebasePushService implements PushService {
  FirebasePushService(this._options, this._logger);

  final FirebaseOptions _options;
  final AppLogger _logger;
  final _routes = StreamController<String>.broadcast();
  bool _ready = false;

  @override
  bool get isAvailable => true;

  static String? _routeOf(RemoteMessage message) {
    final route = message.data['route'];
    return route is String && route.startsWith('/') ? route : null;
  }

  @override
  Future<void> initialize() async {
    if (_ready) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: _options);
      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final route = _routeOf(message);
        if (route != null) _routes.add(route);
      });
      final initial = await messaging.getInitialMessage();
      final initialRoute = initial == null ? null : _routeOf(initial);
      if (initialRoute != null) scheduleMicrotask(() => _routes.add(initialRoute));
      _ready = true;
    } on Object catch (error, stackTrace) {
      _logger.error('Push initialization failed', error: error, stackTrace: stackTrace, tag: 'push');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async {
    if (!_ready) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } on Object catch (error) {
      _logger.warning('Push token unavailable: $error');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _ready ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

  @override
  Stream<String> get onOpenRoute => _routes.stream;
}

FirebaseOptions? _firebaseOptionsFromEnvironment() {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_APP_ID');
  const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  if (apiKey.isEmpty || appId.isEmpty || senderId.isEmpty || projectId.isEmpty) return null;
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
  );
}

final pushServiceProvider = Provider<PushService>((ref) {
  if (ref.watch(appConfigProvider).useDemoData || kIsWeb) return const DisabledPushService();
  final options = _firebaseOptionsFromEnvironment();
  if (options == null) return const DisabledPushService();
  return FirebasePushService(options, ref.watch(appLoggerProvider));
});
