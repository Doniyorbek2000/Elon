import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router/app_router.dart';
import '../../features/auth/application/session_controller.dart';
import '../device/device_identity.dart';
import '../errors/app_failure.dart';
import '../logging/app_logger.dart';
import '../network/api_client.dart';
import 'push_service.dart';

/// Registers the device's push token for the signed-in account and routes
/// notification taps. Tokens are tied to the session on the server, so a
/// logout or revoked session stops pushes to this device.
class PushRegistration extends Notifier<String?> {
  StreamSubscription<String>? _refresh;
  StreamSubscription<String>? _opens;

  @override
  String? build() {
    ref.onDispose(() {
      _refresh?.cancel();
      _opens?.cancel();
    });
    final push = ref.watch(pushServiceProvider);
    final userId = ref.watch(sessionProvider.select((user) => user?.id));
    if (!push.isAvailable) return null;
    unawaited(_start(push, signedIn: userId != null));
    return null;
  }

  Future<void> _start(PushService push, {required bool signedIn}) async {
    await push.initialize();
    _opens ??= push.onOpenRoute.listen((route) => ref.read(appRouterProvider).push(route));
    if (!signedIn) return;
    if (!await push.requestPermission()) return;
    final token = await push.token();
    if (token != null) await _register(token);
    _refresh ??= push.onTokenRefresh.listen((next) => unawaited(_register(next)));
  }

  Future<void> _register(String token) async {
    try {
      await ref
          .read(apiClientProvider)
          .put<Object?>('/push-devices', body: {'token': token, 'platform': ref.read(deviceIdentityProvider).platform});
      if (ref.mounted) state = token;
    } on AppFailure catch (failure) {
      ref.read(appLoggerProvider).warning('Push registration failed: ${failure.runtimeType}');
    }
  }

  /// Called before sign-out so this device stops receiving pushes at once.
  Future<void> unregister() async {
    final token = state;
    if (token == null) return;
    try {
      await ref.read(apiClientProvider).delete('/push-devices', body: {'token': token});
    } on AppFailure {
      // The server also drops tokens of revoked sessions on logout.
    }
    if (ref.mounted) state = null;
  }

  @visibleForTesting
  String? get registeredToken => state;
}

final pushRegistrationProvider = NotifierProvider<PushRegistration, String?>(PushRegistration.new);
