import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/domain/place.dart';

@immutable
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Haversine distance in kilometres.
  double distanceTo(GeoPoint other) {
    const earthRadiusKm = 6371.0;
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(other.latitude - latitude);
    final dLng = rad(other.longitude - longitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(latitude)) * math.cos(rad(other.latitude)) * math.pow(math.sin(dLng / 2), 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

@immutable
class Locality {
  const Locality({required this.id, required this.name});

  final String id;
  final String name;
}

@immutable
class District {
  const District({required this.id, required this.name, this.center, this.localities = const []});

  final String id;
  final String name;
  final GeoPoint? center;
  final List<Locality> localities;
}

@immutable
class Region {
  const Region({required this.id, required this.name, required this.center, this.districts = const []});

  final String id;
  final String name;
  final GeoPoint center;
  final List<District> districts;
}

/// Uzbekistan → Region → District/City → Locality (mahalla/village).
class LocationTree {
  const LocationTree(this.regions);

  final List<Region> regions;

  Region? region(String? id) => regions.where((r) => r.id == id).firstOrNull;

  District? district(String? regionId, String? districtId) =>
      region(regionId)?.districts.where((d) => d.id == districtId).firstOrNull;

  /// Nearest district center to [point] across the whole tree (offline reverse geocoding).
  ({Region region, District district, double distanceKm})? nearestDistrict(GeoPoint point) {
    ({Region region, District district, double distanceKm})? best;
    for (final region in regions) {
      for (final district in region.districts) {
        final center = district.center;
        if (center == null) continue;
        final distance = point.distanceTo(center);
        if (best == null || distance < best.distanceKm) {
          best = (region: region, district: district, distanceKm: distance);
        }
      }
    }
    return best;
  }
}

/// User's active location context. Every field below region is optional so
/// a user can browse a whole region without precise GPS.
@immutable
class LocationSelection {
  const LocationSelection({
    required this.regionId,
    required this.regionName,
    this.districtId,
    this.districtName,
    this.localityId,
    this.localityName,
    this.radiusKm,
    this.point,
    this.fromDevice = false,
  });

  final String regionId;
  final String regionName;
  final String? districtId;
  final String? districtName;
  final String? localityId;
  final String? localityName;

  /// Null = whole selected district/region.
  final int? radiusKm;
  final GeoPoint? point;
  final bool fromDevice;

  Place toPlace() => Place(
    regionId: regionId,
    regionName: regionName,
    districtId: districtId,
    districtName: districtName,
    localityName: localityName,
    latitude: point?.latitude,
    longitude: point?.longitude,
  );

  String get label => toPlace().shortLabel;

  LocationSelection withRadius(int? radiusKm) => LocationSelection(
    regionId: regionId,
    regionName: regionName,
    districtId: districtId,
    districtName: districtName,
    localityId: localityId,
    localityName: localityName,
    radiusKm: radiusKm,
    point: point,
    fromDevice: fromDevice,
  );

  factory LocationSelection.fromJson(Map<String, dynamic> json) => LocationSelection(
    regionId: json['regionId'] as String,
    regionName: json['regionName'] as String,
    districtId: json['districtId'] as String?,
    districtName: json['districtName'] as String?,
    localityId: json['localityId'] as String?,
    localityName: json['localityName'] as String?,
    radiusKm: json['radiusKm'] as int?,
    point: json['lat'] is num && json['lng'] is num
        ? GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble())
        : null,
    fromDevice: json['fromDevice'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'regionId': regionId,
    'regionName': regionName,
    'districtId': ?districtId,
    'districtName': ?districtName,
    'localityId': ?localityId,
    'localityName': ?localityName,
    'radiusKm': ?radiusKm,
    'lat': ?point?.latitude,
    'lng': ?point?.longitude,
    'fromDevice': fromDevice,
  };

  @override
  bool operator ==(Object other) =>
      other is LocationSelection &&
      other.regionId == regionId &&
      other.districtId == districtId &&
      other.localityId == localityId &&
      other.radiusKm == radiusKm &&
      other.fromDevice == fromDevice;

  @override
  int get hashCode => Object.hash(regionId, districtId, localityId, radiusKm, fromDevice);
}
