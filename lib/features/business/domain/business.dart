import 'package:flutter/foundation.dart';

import '../../../core/domain/media_image.dart';
import '../../../core/domain/place.dart';
import '../../../core/l10n/l10n.dart';
import '../../jobs/data/remote_job_repository.dart';
import '../../jobs/domain/job.dart';
import '../../services/domain/service_provider.dart';

typedef Json = Map<String, dynamic>;

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

enum BusinessRole {
  owner,
  manager;

  static BusinessRole parse(Object? value) => value == 'owner' ? BusinessRole.owner : BusinessRole.manager;

  String get label => this == BusinessRole.owner ? tr('Egasi') : tr('Menejer');
}

@immutable
class BusinessMember {
  const BusinessMember({required this.userId, required this.name, required this.role});

  factory BusinessMember.fromJson(Json json) => BusinessMember(
    userId: json['userId'] as String,
    name: json['name'] as String? ?? '',
    role: BusinessRole.parse(json['role']),
  );

  final String userId;
  final String name;
  final BusinessRole role;
}

/// Business profile. `verified` is set only by admins — never purchasable.
@immutable
class Business {
  const Business({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.description,
    required this.place,
    required this.verified,
    required this.verification,
    required this.businessBadge,
    required this.memberSince,
    this.logo,
    this.categoryId,
    this.address,
    this.phone,
    this.website,
    this.telegram,
    this.openingHours,
    this.shareUrl,
  });

  factory Business.fromJson(Json json) {
    final place = json['place'] as Json? ?? const {};
    return Business(
      id: json['id'] as String,
      ownerId: json['ownerId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      logo: json['logo'] is Map ? MediaImage.fromJson(json['logo'] as Json) : null,
      categoryId: json['categoryId'] as String?,
      place: Place(
        regionId: place['regionId'] as String? ?? '',
        regionName: place['regionName'] as String? ?? '',
        districtId: place['districtId'] as String?,
        districtName: place['districtName'] as String?,
      ),
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      website: json['website'] as String?,
      telegram: json['telegram'] as String?,
      openingHours: json['openingHours'] as String?,
      verified: json['verified'] as bool? ?? false,
      verification: json['verification'] as String? ?? 'none',
      businessBadge: json['businessBadge'] as bool? ?? false,
      memberSince: _date(json['memberSince']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      shareUrl: json['shareUrl'] as String?,
    );
  }

  final String id;
  final String ownerId;
  final String name;
  final String description;
  final MediaImage? logo;
  final String? categoryId;
  final Place place;
  final String? address;
  final String? phone;
  final String? website;
  final String? telegram;
  final String? openingHours;
  final bool verified;

  /// `none`, `pending`, `verified`, `rejected`.
  final String verification;
  final bool businessBadge;
  final DateTime memberSince;
  final String? shareUrl;

  String get verificationLabel => switch (verification) {
    'verified' => tr('Tasdiqlangan'),
    'pending' => tr('Tekshiruvda'),
    'rejected' => tr('Rad etilgan'),
    _ => tr('Tasdiqlanmagan'),
  };
}

@immutable
class MyBusiness {
  const MyBusiness({required this.business, required this.myRole, required this.members, required this.maxManagers});

  factory MyBusiness.fromJson(Json json) => MyBusiness(
    business: Business.fromJson(json),
    myRole: BusinessRole.parse(json['myRole']),
    members: [for (final m in json['members'] as List<dynamic>? ?? const []) BusinessMember.fromJson(m as Json)],
    maxManagers: (json['maxManagers'] as num?)?.toInt() ?? 0,
  );

  final Business business;
  final BusinessRole myRole;
  final List<BusinessMember> members;
  final int maxManagers;

  bool get isOwner => myRole == BusinessRole.owner;
  int get managerCount => members.where((m) => m.role == BusinessRole.manager).length;
}

@immutable
class Storefront {
  const Storefront({
    required this.business,
    required this.activeListings,
    required this.reviewCount,
    required this.jobs,
    required this.providers,
    this.rating,
  });

  factory Storefront.fromJson(Json json) => Storefront(
    business: Business.fromJson(json),
    activeListings: ((json['stats'] as Json?)?['activeListings'] as num?)?.toInt() ?? 0,
    rating: (json['rating'] as num?)?.toDouble(),
    reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
    jobs: [for (final j in json['jobs'] as List<dynamic>? ?? const []) RemoteJobRepository.jobFromJson(j as Json)],
    providers: [for (final p in json['providers'] as List<dynamic>? ?? const []) ServiceProvider.fromJson(p as Json)],
  );

  final Business business;
  final int activeListings;

  /// Only from real reviews; null when there are none.
  final double? rating;
  final int reviewCount;
  final List<Job> jobs;
  final List<ServiceProvider> providers;
}

@immutable
class BusinessDraft {
  const BusinessDraft({
    required this.name,
    required this.regionId,
    this.description = '',
    this.districtId,
    this.categoryId,
    this.address,
    this.phone,
    this.website,
    this.telegram,
    this.openingHours,
  });

  final String name;
  final String description;
  final String regionId;
  final String? districtId;
  final String? categoryId;
  final String? address;
  final String? phone;
  final String? website;
  final String? telegram;
  final String? openingHours;

  static String? _blank(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  Map<String, Object?> toJson() => {
    'name': name.trim(),
    'description': description.trim(),
    'regionId': regionId,
    'districtId': ?districtId,
    'categoryId': ?categoryId,
    'address': ?_blank(address),
    'phone': ?_blank(phone),
    'website': ?_blank(website),
    'telegram': ?_blank(telegram),
    'openingHours': ?_blank(openingHours),
  };
}

@immutable
class StatTotals {
  const StatTotals({this.views = 0, this.favorites = 0, this.contacts = 0, this.chats = 0, this.shares = 0});

  factory StatTotals.fromJson(Json? json) => StatTotals(
    views: (json?['views'] as num?)?.toInt() ?? 0,
    favorites: (json?['favorites'] as num?)?.toInt() ?? 0,
    contacts: (json?['contacts'] as num?)?.toInt() ?? 0,
    chats: (json?['chats'] as num?)?.toInt() ?? 0,
    shares: (json?['shares'] as num?)?.toInt() ?? 0,
  );

  final int views;
  final int favorites;
  final int contacts;
  final int chats;
  final int shares;
}

@immutable
class ListingStats {
  const ListingStats({
    required this.from,
    required this.to,
    required this.totals,
    required this.daily,
    required this.lifetimeViews,
    required this.lifetimeFavorites,
  });

  factory ListingStats.fromJson(Json json) => ListingStats(
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    totals: StatTotals.fromJson(json['totals'] as Json?),
    daily: [
      for (final d in json['daily'] as List<dynamic>? ?? const [])
        (day: (d as Json)['day'] as String, totals: StatTotals.fromJson(d)),
    ],
    lifetimeViews: ((json['lifetime'] as Json?)?['views'] as num?)?.toInt() ?? 0,
    lifetimeFavorites: ((json['lifetime'] as Json?)?['favorites'] as num?)?.toInt() ?? 0,
  );

  final String from;
  final String to;
  final StatTotals totals;
  final List<({String day, StatTotals totals})> daily;
  final int lifetimeViews;
  final int lifetimeFavorites;
}
