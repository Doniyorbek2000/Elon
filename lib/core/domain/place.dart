import 'package:flutter/foundation.dart';

/// Denormalized location attached to content (listing, job, provider).
/// IDs reference the location tree; names are cached for display.
@immutable
class Place {
  const Place({
    required this.regionId,
    required this.regionName,
    this.districtId,
    this.districtName,
    this.localityName,
    this.latitude,
    this.longitude,
  });

  final String regionId;
  final String regionName;
  final String? districtId;
  final String? districtName;
  final String? localityName;
  final double? latitude;
  final double? longitude;

  /// "Chust, Namangan" — the short label used on cards.
  String get shortLabel {
    final district = districtName;
    final region = regionName
        .replaceAll(' viloyati', '')
        .replaceAll(' shahri', '');
    if (district == null) return region;
    final cleanDistrict = district
        .replaceAll(' tumani', '')
        .replaceAll(' shahri', '');
    return cleanDistrict == region ? cleanDistrict : '$cleanDistrict, $region';
  }

  /// "Chust" — tightest label for dense cards.
  String get compactLabel {
    String clean(String v) => v
        .replaceAll(' tumani', '')
        .replaceAll(' shahri', '')
        .replaceAll(' viloyati', '');
    return clean(districtName ?? regionName);
  }

  /// "Karkidon, Chust tumani, Namangan viloyati"
  String get fullLabel => [?localityName, ?districtName, regionName].join(', ');

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    regionId: json['regionId'] as String,
    regionName: json['regionName'] as String,
    districtId: json['districtId'] as String?,
    districtName: json['districtName'] as String?,
    localityName: json['localityName'] as String?,
    latitude: (json['lat'] as num?)?.toDouble(),
    longitude: (json['lng'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'regionId': regionId,
    'regionName': regionName,
    'districtId': ?districtId,
    'districtName': ?districtName,
    'localityName': ?localityName,
    'lat': ?latitude,
    'lng': ?longitude,
  };

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.regionId == regionId &&
      other.districtId == districtId &&
      other.localityName == localityName;

  @override
  int get hashCode => Object.hash(regionId, districtId, localityName);
}
