import 'package:flutter/foundation.dart';

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
  Future<List<AppNotification>> list();
  Future<void> markAllRead();
}
