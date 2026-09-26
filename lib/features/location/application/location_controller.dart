import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/storage/key_value_store.dart';
import '../data/uzbekistan_locations.dart';
import '../domain/location.dart';

final locationTreeProvider = Provider<LocationTree>((ref) => UzbekistanLocations.tree);

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
    final district = tree.district(region.id, UzbekistanLocations.defaultDistrictId)!;
    return LocationSelection(
      regionId: region.id,
      regionName: region.name,
      districtId: district.id,
      districtName: district.name,
    );
  }

  Future<void> select(LocationSelection selection) async {
    state = selection;
    await ref.read(keyValueStoreProvider).setJson(StoreKeys.location, selection.toJson());
  }

  Future<void> setRadius(int? radiusKm) => select(state.withRadius(radiusKm));

  /// Resolves the device position to the nearest known district.
  Future<LocationSelection> useDeviceLocation() async {
    final point = await ref.read(deviceLocationServiceProvider).currentPosition();
    final nearest = ref.read(locationTreeProvider).nearestDistrict(point);
    if (nearest == null || nearest.distanceKm > 150) {
      throw const PermissionFailure('Joylashuvingiz O‘zbekiston hududidan tashqarida ko‘rinmoqda');
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

final locationProvider = NotifierProvider<LocationController, LocationSelection>(LocationController.new);

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
    if (!await Geolocator.isLocationServiceEnabled()) return LocationPermissionState.serviceDisabled;
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.always || LocationPermission.whileInUse => LocationPermissionState.granted,
      LocationPermission.deniedForever => LocationPermissionState.deniedForever,
      LocationPermission.denied || LocationPermission.unableToDetermine => LocationPermissionState.denied,
    };
  }

  @override
  Future<GeoPoint> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const PermissionFailure('Telefoningizda joylashuv xizmati o‘chirilgan');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      throw const PermissionFailure('Joylashuvga ruxsat berilmagan. Sozlamalardan yoqing', permanentlyDenied: true);
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
      throw const PermissionFailure('Joylashuvga ruxsat berilmadi');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 12)),
    );
    return GeoPoint(position.latitude, position.longitude);
  }

  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}

final deviceLocationServiceProvider = Provider<DeviceLocationService>((ref) => const GeolocatorLocationService());
