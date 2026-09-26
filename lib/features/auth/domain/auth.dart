import 'package:flutter/foundation.dart';

import '../../../core/domain/media_image.dart';
import '../../../core/domain/public_profile.dart';

/// The signed-in account. Unlike [PublicProfile] it carries the user's own
/// phone number, which is never shown to other users.
@immutable
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.displayId,
    required this.name,
    required this.phone,
    required this.memberSince,
    this.avatar,
    this.verification = VerificationLevel.none,
    this.accountType = AccountType.personal,
  });

  final String id;

  /// Short numeric ID users can quote to support ("ID: 123456").
  final String displayId;
  final String name;
  final String phone;
  final MediaImage? avatar;
  final VerificationLevel verification;
  final AccountType accountType;
  final DateTime memberSince;

  bool get isPhoneVerified => verification.isVerified;

  PublicProfile toPublic() => PublicProfile(
    id: id,
    name: name,
    avatar: avatar,
    verification: verification,
    accountType: accountType,
    isOnline: true,
    memberSince: memberSince,
  );

  CurrentUser copyWith({String? name, MediaImage? avatar, VerificationLevel? verification}) => CurrentUser(
    id: id,
    displayId: displayId,
    name: name ?? this.name,
    phone: phone,
    memberSince: memberSince,
    avatar: avatar ?? this.avatar,
    verification: verification ?? this.verification,
    accountType: accountType,
  );
}

abstract interface class AuthRepository {
  Future<CurrentUser?> restoreSession();

  /// Sends a one-time code by SMS. Server enforces rate limits.
  Future<void> requestCode(String phone);

  Future<CurrentUser> verifyCode({required String phone, required String code});

  Future<CurrentUser> updateProfile({required String name, MediaImage? avatar});

  Future<void> signOut();
}
