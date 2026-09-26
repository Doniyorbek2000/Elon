import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/media_image.dart';
import '../../../data/demo/demo_database.dart';
import '../data/demo_auth_repository.dart';
import '../domain/auth.dart';

/// Only the demo auth flow exists until the OTP backend is available;
/// a remote implementation plugs in here.
final authRepositoryProvider = Provider<AuthRepository>((ref) => DemoAuthRepository(ref.watch(demoDatabaseProvider)));

/// Current account, or null for guests. Browsing never requires sign-in;
/// posting, chatting and applying do (see `ensureSignedIn`).
class SessionController extends Notifier<CurrentUser?> {
  @override
  CurrentUser? build() {
    // Demo database starts signed-in so every screen is explorable.
    return ref.watch(demoDatabaseProvider).currentUser;
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<void> requestCode(String phone) => _auth.requestCode(phone);

  Future<CurrentUser> verify({required String phone, required String code}) async {
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

final sessionProvider = NotifierProvider<SessionController, CurrentUser?>(SessionController.new);
