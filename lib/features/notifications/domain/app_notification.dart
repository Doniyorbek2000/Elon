import 'package:flutter/foundation.dart';

import '../../../core/domain/paged.dart';

enum NotificationKind { message, priceDrop, application, listingApproved, system }

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.deepLink,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  /// In-app route to open when tapped (same format as push payloads).
  final String? deepLink;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    kind: switch (json['type']) {
      'message' => NotificationKind.message,
      'listingStatus' => NotificationKind.listingApproved,
      'applicationReceived' || 'applicationStatus' => NotificationKind.application,
      _ => NotificationKind.system,
    },
    title: json['title'] as String,
    body: json['body'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    isRead: json['isRead'] as bool? ?? false,
    deepLink: json['deepLink'] as String?,
  );

  AppNotification markRead() => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    isRead: true,
    deepLink: deepLink,
  );
}

abstract interface class NotificationsRepository {
  /// Newest first; [cursor] pages further back.
  Future<PageResult<AppNotification>> page({String? cursor});
  Future<int> unreadCount();
  Future<void> markRead(String id);
  Future<void> markAllRead();
}
