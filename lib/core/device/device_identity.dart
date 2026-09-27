import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/key_value_store.dart';

/// Stable per-install identifier sent at sign-in so the server can list and
/// revoke sessions per device. Random, not derived from hardware IDs.
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.platform,
    required this.name,
  });

  final String id;
  final String platform;
  final String name;

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform,
    'name': name,
  };

  static const _key = 'device.installId.v1';

  factory DeviceIdentity.load(KeyValueStore store) {
    var id = store.getString(_key);
    if (id == null || id.length < 8) {
      final random = Random.secure();
      id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      store.setString(_key, id);
    }
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => kIsWeb ? 'web' : 'other',
    };
    final name = switch (platform) {
      'android' => 'Android',
      'ios' => 'iPhone',
      _ => 'Qurilma',
    };
    return DeviceIdentity(id: id, platform: platform, name: name);
  }
}

final deviceIdentityProvider = Provider<DeviceIdentity>(
  (ref) => DeviceIdentity.load(ref.watch(keyValueStoreProvider)),
);
