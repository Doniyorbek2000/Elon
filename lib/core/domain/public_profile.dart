import 'package:flutter/foundation.dart';

import 'media_image.dart';

/// Verification is server-issued. The client only renders what the backend
/// asserts and never upgrades a level locally.
enum VerificationLevel {
  none,
  phone,
  identity,
  business;

  bool get isVerified => this != VerificationLevel.none;

  String get label => switch (this) {
    VerificationLevel.none => 'Tasdiqlanmagan',
    VerificationLevel.phone => 'Telefon tasdiqlangan',
    VerificationLevel.identity => 'Shaxsi tasdiqlangan',
    VerificationLevel.business => 'Biznes tasdiqlangan',
  };

  static VerificationLevel parse(Object? value) =>
      VerificationLevel.values.firstWhere((level) => level.name == value, orElse: () => VerificationLevel.none);
}

enum AccountType { personal, business }

/// Public-facing user summary. Deliberately excludes phone number/e-mail:
/// contact details are fetched on explicit user action only.
@immutable
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.name,
    required this.memberSince,
    this.avatar,
    this.verification = VerificationLevel.none,
    this.accountType = AccountType.personal,
    this.isOnline = false,
    this.lastActiveAt,
    this.rating,
    this.reviewCount = 0,
    this.responseRate,
    this.responseTimeMinutes,
    this.activeListings = 0,
  });

  final String id;
  final String name;
  final MediaImage? avatar;
  final VerificationLevel verification;
  final AccountType accountType;
  final bool isOnline;
  final DateTime? lastActiveAt;
  final DateTime memberSince;
  final double? rating;
  final int reviewCount;

  /// 0..1 share of chats answered.
  final double? responseRate;
  final int? responseTimeMinutes;
  final int activeListings;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  factory PublicProfile.fromJson(Map<String, dynamic> json) => PublicProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    avatar: json['avatar'] == null ? null : MediaImage.fromJson(json['avatar'] as Map<String, dynamic>),
    verification: VerificationLevel.parse(json['verification']),
    accountType: json['accountType'] == 'business' ? AccountType.business : AccountType.personal,
    isOnline: json['isOnline'] as bool? ?? false,
    lastActiveAt: DateTime.tryParse(json['lastActiveAt'] as String? ?? ''),
    memberSince: DateTime.parse(json['memberSince'] as String),
    rating: (json['rating'] as num?)?.toDouble(),
    reviewCount: json['reviewCount'] as int? ?? 0,
    responseRate: (json['responseRate'] as num?)?.toDouble(),
    responseTimeMinutes: json['responseTimeMinutes'] as int?,
    activeListings: json['activeListings'] as int? ?? 0,
  );

  @override
  bool operator ==(Object other) => other is PublicProfile && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
