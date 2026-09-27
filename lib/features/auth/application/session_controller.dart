import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/device/device_identity.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../data/demo/demo_database.dart';
import '../data/demo_auth_repository.dart';
import '../data/remote_auth_repository.dart';
import '../domain/auth.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData)
    return DemoAuthRepository(ref.watch(demoDatabaseProvider));
  return RemoteAuthRepository(
    api: ref.watch(apiClientProvider),
    tokens: ref.watch(tokenStoreProvider),
    device: ref.watch(deviceIdentityProvider),
    store: ref.watch(keyValueStoreProvider),
  );
});

/// Current account, or null for guests. Browsing never requires sign-in;
/// posting, chatting and applying do (see `ensureSignedIn`).
///
/// With a backend, the cached profile is shown immediately (offline start)
/// and validated in the background; a rejected refresh token signs out.
class SessionController extends Notifier<CurrentUser?> {
  @override
  CurrentUser? build() {
    if (ref.watch(appConfigProvider).useDemoData) {
      // Demo database starts signed-in so every screen is explorable.
      return ref.watch(demoDatabaseProvider).currentUser;
    }
    final repository =
        ref.watch(authRepositoryProvider) as RemoteAuthRepository;
    final subscription = ref
        .watch(tokenStoreProvider)
        .sessionExpired
        .listen((_) => state = null);
    ref.onDispose(subscription.cancel);
    unawaited(_restore(repository));
    return repository.cachedUser;
  }

  Future<void> _restore(AuthRepository repository) async {
    final user = await repository.restoreSession().catchError(
      (Object _) => state,
    );
    if (ref.mounted) state = user;
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<OtpChallenge> requestCode(String phone) => _auth.requestCode(phone);

  Future<CurrentUser> verify({
    required String phone,
    required String code,
  }) async {
    final user = await _auth.verifyCode(phone: phone, code: code);
    state = user;
    return user;
  }

  Future<void> updateProfile({required String name, MediaImage? avatar}) async {
    state = await _auth.updateProfile(name: name, avatar: avatar);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionController, CurrentUser?>(
  SessionController.new,
);
