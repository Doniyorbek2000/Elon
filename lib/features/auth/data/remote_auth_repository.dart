import '../../../core/device/device_identity.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/auth.dart';

/// Phone OTP against `/auth/*`. Tokens live in secure storage only; the
/// non-sensitive profile is cached so the app can open offline.
class RemoteAuthRepository implements AuthRepository {
  RemoteAuthRepository({
    required this._api,
    required this._tokens,
    required this._device,
    required this._store,
  });

  final ApiClient _api;
  final TokenStore _tokens;
  final DeviceIdentity _device;
  final KeyValueStore _store;

  static const cachedUserKey = 'auth.cachedUser.v1';

  CurrentUser? get cachedUser {
    final json = _store.getJson(cachedUserKey);
    if (json == null) return null;
    try {
      return CurrentUser.fromJson(json);
    } on Object {
      return null;
    }
  }

  Future<CurrentUser> _saveUser(JsonMap json) async {
    final user = CurrentUser.fromJson(json);
    await _store.setJson(cachedUserKey, user.toJson());
    return user;
  }

  @override
  Future<CurrentUser?> restoreSession() async {
    if (await _tokens.refreshToken == null) return null;
    try {
      return await _saveUser(await _api.get<JsonMap>('/me'));
    } on UnauthorizedFailure {
      await _tokens.clear();
      await _store.remove(cachedUserKey);
      return null;
    } on NetworkFailure {
      return cachedUser;
    } on TimeoutFailure {
      return cachedUser;
    }
  }

  @override
  Future<OtpChallenge> requestCode(String phone) async {
    final data = await _api.post<JsonMap>(
      '/auth/otp/request',
      body: {'phone': phone},
    );
    return OtpChallenge(
      resendIn: Duration(
        seconds: (data['resendInSeconds'] as num?)?.toInt() ?? 60,
      ),
      expiresIn: Duration(
        seconds: (data['expiresInSeconds'] as num?)?.toInt() ?? 300,
      ),
      devCode: data['devCode'] as String?,
    );
  }

  @override
  Future<CurrentUser> verifyCode({
    required String phone,
    required String code,
  }) async {
    final data = await _api.post<JsonMap>(
      '/auth/otp/verify',
      body: {'phone': phone, 'code': code, 'device': _device.toJson()},
    );
    await _tokens.save(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    return _saveUser(await _api.get<JsonMap>('/me'));
  }

  @override
  Future<CurrentUser> updateProfile({
    required String name,
    MediaImage? avatar,
  }) async => _saveUser(
    await _api.patch<JsonMap>(
      '/me',
      body: {
        'displayName': name,
        if (avatar != null && !avatar.isLocal) 'avatarId': avatar.id,
      },
    ),
  );

  @override
  Future<void> signOut() async {
    try {
      await _api.post<Object?>('/auth/logout');
    } on AppFailure {
      // Local sign-out must succeed even offline; the server session expires on its own.
    } finally {
      await _tokens.clear();
      await _store.remove(cachedUserKey);
    }
  }
}
