import 'dart:convert';

import 'key_value_store.dart';

/// A cached first page of a feed, exactly as the server returned it.
class CachedPage {
  const CachedPage({required this.items, required this.nextCursor, required this.savedAt});

  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final DateTime savedAt;
}

/// Small on-device cache of the first page of public feeds, used only when
/// the network is unavailable. Bounded (least recently saved entries are
/// dropped) and time-limited so stale data never lingers.
class FeedCache {
  FeedCache(this._store, {DateTime Function()? now, this.maxEntries = 12, this.maxItems = 24, this.maxAge})
    : _now = now ?? DateTime.now;

  static const _indexKey = 'feedcache.index.v1';
  static const _prefix = 'feedcache.page.v1.';

  final KeyValueStore _store;
  final DateTime Function() _now;
  final int maxEntries;
  final int maxItems;
  final Duration? maxAge;

  Duration get _maxAge => maxAge ?? const Duration(days: 7);

  /// Deterministic (unlike `hashCode`) 32-bit FNV-1a of the canonical query.
  static String keyFor(String scope, Map<String, Object?> params) {
    final entries = params.entries.where((e) => e.value != null && e.value != '').toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final canonical = '$scope?${entries.map((e) => '${e.key}=${e.value}').join('&')}';
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(canonical)) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return '$_prefix${hash.toRadixString(16).padLeft(8, '0')}';
  }

  Future<void> save(String key, List<Map<String, dynamic>> items, String? nextCursor) async {
    if (items.isEmpty) return;
    await _store.setJson(key, {
      'savedAt': _now().toIso8601String(),
      'nextCursor': nextCursor,
      'items': items.take(maxItems).toList(),
    });
    final index = _store.getStringList(_indexKey).where((k) => k != key).toList()..add(key);
    while (index.length > maxEntries) {
      await _store.remove(index.removeAt(0));
    }
    await _store.setStringList(_indexKey, index);
  }

  CachedPage? load(String key) {
    final json = _store.getJson(key);
    if (json == null) return null;
    final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '');
    final items = json['items'];
    if (savedAt == null || items is! List || _now().difference(savedAt) > _maxAge) return null;
    return CachedPage(
      items: [
        for (final item in items)
          if (item is Map<String, dynamic>) item,
      ],
      nextCursor: json['nextCursor'] as String?,
      savedAt: savedAt,
    );
  }

  Future<void> clear() async {
    for (final key in _store.getStringList(_indexKey)) {
      await _store.remove(key);
    }
    await _store.remove(_indexKey);
  }
}
