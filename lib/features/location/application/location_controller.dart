import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/key_value_store.dart';
import '../../auth/application/session_controller.dart';
import '../data/uzbekistan_locations.dart';
import '../domain/location.dart';

/// Location tree: the bundled copy renders instantly (offline first launch);
/// with a backend the server tree replaces it and is cached for next start.
class LocationTreeController extends Notifier<LocationTree> {
  static const _cacheKey = 'locations.tree.v1';

  @override
  LocationTree build() {
    if (ref.watch(appConfigProvider).useDemoData)
      return UzbekistanLocations.tree;
    final store = ref.watch(keyValueStoreProvider);
    unawaited(_refresh(store));
    final cached = store.getString(_cacheKey);
    if (cached != null) {
      try {
        return LocationTree.fromJson(jsonDecode(cached) as List<dynamic>);
      } on Object {
        store.remove(_cacheKey).ignore();
      }
    }
    return UzbekistanLocations.tree;
  }

  Future<void> _refresh(KeyValueStore store) async {
    try {
      final json = await ref
          .read(apiClientProvider)
          .get<List<dynamic>>('/locations/tree');
      final tree = LocationTree.fromJson(json);
      if (tree.regions.isEmpty || !ref.mounted) return;
      state = tree;
      await store.setString(_cacheKey, jsonEncode(json));
    } on AppFailure {
      // Keep the cached/bundled tree; the next launch retries.
    }
  }
}

final locationTreeProvider =
    NotifierProvider<LocationTreeController, LocationTree>(
      LocationTreeController.new,
    );

/// Active browsing location. Defaults to the launch district so the app is
/// fully usable without granting GPS permission.
class LocationController extends Notifier<LocationSelection> {
  @override
  LocationSelection build() {
    final stored = ref.watch(keyValueStoreProvider).getJson(StoreKeys.location);
    if (stored != null) {
      try {
        return LocationSelection.fromJson(stored);
      } on Object {
        // Corrupt/legacy payload: fall through to default.
      }
    }
    return _default(ref.watch(locationTreeProvider));
  }

  static LocationSelection _default(LocationTree tree) {
    final region = tree.region(UzbekistanLocations.defaultRegionId)!;
    final district = tree.district(
      region.id,
      UzbekistanLocations.defaultDistrictId,
    )!;
    return LocationSelection(
      regionId: region.id,
      regionName: region.name,
      districtId: district.id,
      districtName: district.name,
    );
  }

  Future<void> select(LocationSelection selection) async {
    state = selection;
    await ref
        .read(keyValueStoreProvider)
        .setJson(StoreKeys.location, selection.toJson());
    unawaited(_syncPreferredArea(selection));
  }

  /// Signed-in users keep their preferred area across devices (best effort).
  Future<void> _syncPreferredArea(LocationSelection selection) async {
    if (ref.read(appConfigProvider).useDemoData ||
        ref.read(sessionProvider) == null)
      return;
    try {
      await ref
          .read(apiClientProvider)
          .patch<Object?>(
            '/me',
            body: {
              'preferredRegionId': selection.regionId,
              'preferredDistrictId': selection.districtId,
              'preferredLocalityId': selection.localityId,
              'preferredRadiusKm': selection.radiusKm,
            },
          );
    } on AppFailure {
      // Local selection already applied; the server copy updates next time.
    }
  }

  Future<void> setRadius(int? radiusKm) => select(state.withRadius(radiusKm));

  /// Resolves the device position to the nearest known district.
  Future<LocationSelection> useDeviceLocation() async {
    final point = await ref
        .read(deviceLocationServiceProvider)
        .currentPosition();
    final nearest = ref.read(locationTreeProvider).nearestDistrict(point);
    if (nearest == null || nearest.distanceKm > 150) {
      throw const PermissionFailure(
        'Joylashuvingiz O‘zbekiston hududidan tashqarida ko‘rinmoqda',
      );
    }
    final selection = LocationSelection(
      regionId: nearest.region.id,
      regionName: nearest.region.name,
      districtId: nearest.district.id,
      districtName: nearest.district.name,
      point: point,
      fromDevice: true,
      radiusKm: state.radiusKm,
    );
    await select(selection);
    return selection;
  }
}

final locationProvider =
    NotifierProvider<LocationController, LocationSelection>(
      LocationController.new,
    );

enum LocationPermissionState { granted, denied, deniedForever, serviceDisabled }

/// Wraps `geolocator` so permission flows are testable and the rest of the
/// app never touches the plugin directly.
abstract interface class DeviceLocationService {
  Future<LocationPermissionState> permissionState();
  Future<GeoPoint> currentPosition();
  Future<void> openSettings();
}

class GeolocatorLocationService implements DeviceLocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationPermissionState> permissionState() async {
    if (!await Geolocator.isLocationServiceEnabled())
      return LocationPermissionState.serviceDisabled;
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationPermissionState.granted,
      LocationPermission.deniedForever => LocationPermissionState.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationPermissionState.denied,
    };
  }

  @override
  Future<GeoPoint> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const PermissionFailure(
        'Telefoningizda joylashuv xizmati o‘chirilgan',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      throw const PermissionFailure(
        'Joylashuvga ruxsat berilmagan. Sozlamalardan yoqing',
        permanentlyDenied: true,
      );
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const PermissionFailure('Joylashuvga ruxsat berilmadi');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return GeoPoint(position.latitude, position.longitude);
  }

  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}

final deviceLocationServiceProvider = Provider<DeviceLocationService>(
  (ref) => const GeolocatorLocationService(),
);
