import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for non-sensitive persisted preferences. Centralized to avoid typos
/// and key collisions between features.
abstract final class StoreKeys {
  static const onboardingCompleted = 'onboarding.completed.v1';
  static const themeMode = 'settings.themeMode';
  static const language = 'settings.language';
  static const notificationsEnabled = 'settings.notifications';
  static const savedItems = 'saved.items.v1';
  static const recentSearches = 'search.recent.v1';
  static const location = 'location.selection.v1';
  static const listingDraft = 'create.listingDraft.v1';
}

/// Synchronous-read key/value storage backed by a pre-loaded
/// [SharedPreferencesWithCache], so state can hydrate without async gaps.
class KeyValueStore {
  KeyValueStore(this._prefs);

  final SharedPreferencesWithCache _prefs;

  String? getString(String key) => _prefs.getString(key);
  bool? getBool(String key) => _prefs.getBool(key);
  List<String> getStringList(String key) => _prefs.getStringList(key) ?? const [];

  Map<String, dynamic>? getJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  Future<void> setBool(String key, {required bool value}) => _prefs.setBool(key, value);
  Future<void> setStringList(String key, List<String> value) => _prefs.setStringList(key, value);
  Future<void> setJson(String key, Map<String, dynamic> value) => _prefs.setString(key, jsonEncode(value));
  Future<void> remove(String key) => _prefs.remove(key);

  static Future<KeyValueStore> open() async {
    final prefs = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
    return KeyValueStore(prefs);
  }
}

/// Overridden in `main()` with an opened store.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => throw StateError('keyValueStoreProvider must be overridden at startup'),
);
