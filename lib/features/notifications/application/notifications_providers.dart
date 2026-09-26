import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/demo/demo_database.dart';
import '../domain/app_notification.dart';

class DemoNotificationsRepository implements NotificationsRepository {
  DemoNotificationsRepository(this._db);

  final DemoDatabase _db;

  @override
  Future<List<AppNotification>> list() async {
    await _db.roundTrip(0.6);
    return List.unmodifiable(_db.notifications);
  }

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < _db.notifications.length; i++) {
      _db.notifications[i] = _db.notifications[i].markRead();
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => DemoNotificationsRepository(ref.watch(demoDatabaseProvider)),
);

class NotificationsController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() => ref.watch(notificationsRepositoryProvider).list();

  Future<void> markAllRead() async {
    await ref.read(notificationsRepositoryProvider).markAllRead();
    state = AsyncData([for (final n in state.value ?? const <AppNotification>[]) n.markRead()]);
  }
}

final notificationsProvider = AsyncNotifierProvider<NotificationsController, List<AppNotification>>(
  NotificationsController.new,
);

final unreadNotificationsProvider = Provider<int>((ref) {
  return (ref.watch(notificationsProvider).value ?? const []).where((n) => !n.isRead).length;
});
