import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SecureStoreKey { accessToken, refreshToken }

/// Keychain (iOS) / EncryptedSharedPreferences-backed (Android) storage for
/// credentials. Never put tokens in [KeyValueStore].
abstract interface class SecureStore {
  Future<String?> read(SecureStoreKey key);
  Future<void> write(SecureStoreKey key, String value);
  Future<void> delete(SecureStoreKey key);
  Future<void> clear();
}

class PlatformSecureStore implements SecureStore {
  const PlatformSecureStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(SecureStoreKey key) => _storage.read(key: key.name);

  @override
  Future<void> write(SecureStoreKey key, String value) =>
      _storage.write(key: key.name, value: value);

  @override
  Future<void> delete(SecureStoreKey key) => _storage.delete(key: key.name);

  @override
  Future<void> clear() async {
    for (final key in SecureStoreKey.values) {
      await _storage.delete(key: key.name);
    }
  }
}

/// In-memory implementation for tests and demo sessions.
class MemorySecureStore implements SecureStore {
  final Map<SecureStoreKey, String> _values = {};

  @override
  Future<String?> read(SecureStoreKey key) async => _values[key];

  @override
  Future<void> write(SecureStoreKey key, String value) async =>
      _values[key] = value;

  @override
  Future<void> delete(SecureStoreKey key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();
}

final secureStoreProvider = Provider<SecureStore>(
  (ref) => const PlatformSecureStore(),
);
