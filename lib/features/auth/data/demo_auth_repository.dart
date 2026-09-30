import '../../../core/domain/media_image.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';
import '../../../data/demo/demo_database.dart';
import '../domain/auth.dart';

/// Demo OTP flow. The accepted code is [demoCode]; the UI shows it only
/// when running on demo data so nobody mistakes it for real SMS.
class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository(this._db);

  static const demoCode = '123456';

  final DemoDatabase _db;

  @override
  Future<CurrentUser?> restoreSession() async => _db.currentUser;

  @override
  Future<OtpChallenge> requestCode(String phone) async {
    await _db.roundTrip();
    if (!RegExp(r'^998\d{9}$').hasMatch(phone)) {
      throw ValidationFailure(tr('Telefon raqami noto‘g‘ri'));
    }
    return const OtpChallenge(resendIn: Duration(seconds: 60), expiresIn: Duration(minutes: 5), devCode: demoCode);
  }

  @override
  Future<CurrentUser> verifyCode({required String phone, required String code}) async {
    await _db.roundTrip();
    if (code != demoCode) throw ValidationFailure(tr('Kod noto‘g‘ri. Qayta urinib ko‘ring'));
    final base = _db.seed.currentUser;
    final user = CurrentUser(
      id: base.id,
      displayId: base.displayId,
      name: base.name,
      phone: phone,
      avatar: base.avatar,
      memberSince: base.memberSince,
      verification: VerificationLevel.phone,
    );
    _db.currentUser = user;
    return user;
  }

  @override
  Future<CurrentUser> updateProfile({required String name, MediaImage? avatar}) async {
    await _db.roundTrip();
    final user = _db.currentUser;
    if (user == null) throw const UnauthorizedFailure();
    final updated = user.copyWith(name: name, avatar: avatar);
    _db.currentUser = updated;
    return updated;
  }

  @override
  Future<void> signOut() async {
    await _db.roundTrip(0.5);
    _db.currentUser = null;
  }
}
