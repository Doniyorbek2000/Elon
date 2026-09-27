import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/domain/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../data/demo/demo_database.dart';
import '../../auth/application/session_controller.dart';
import '../domain/app_notification.dart';

class DemoNotificationsRepository implements NotificationsRepository {
  DemoNotificationsRepository(this._db);

  final DemoDatabase _db;

  @override
  Future<PageResult<AppNotification>> page({String? cursor}) async {
    await _db.roundTrip(0.6);
    return PageResult(
      items: List.unmodifiable(_db.notifications),
      nextCursor: null,
    );
  }

  @override
  Future<int> unreadCount() async =>
      _db.notifications.where((n) => !n.isRead).length;

  @override
  Future<void> markRead(String id) async {
    final index = _db.notifications.indexWhere((n) => n.id == id);
    if (index >= 0)
      _db.notifications[index] = _db.notifications[index].markRead();
  }

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < _db.notifications.length; i++) {
      _db.notifications[i] = _db.notifications[i].markRead();
    }
  }
}

/// `/notifications` (in-app inbox; push delivery is server-side).
class RemoteNotificationsRepository implements NotificationsRepository {
  RemoteNotificationsRepository(this._api);

  final ApiClient _api;

  @override
  Future<PageResult<AppNotification>> page({String? cursor}) => _api.getPage(
    '/notifications',
    AppNotification.fromJson,
    query: {'limit': 30},
    cursor: cursor,
  );

  @override
  Future<int> unreadCount() async =>
      ((await _api.get<JsonMap>('/notifications/unread-count'))['count'] as num)
          .toInt();

  @override
  Future<void> markRead(String id) async {
    await _api.post<Object?>('/notifications/$id/read');
  }

  @override
  Future<void> markAllRead() async {
    await _api.post<Object?>('/notifications/read-all');
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  if (ref.watch(appConfigProvider).useDemoData)
    return DemoNotificationsRepository(ref.watch(demoDatabaseProvider));
  return RemoteNotificationsRepository(ref.watch(apiClientProvider));
});

class NotificationsController
    extends AsyncNotifier<PagedState<AppNotification>> {
  NotificationsRepository get _repository =>
      ref.read(notificationsRepositoryProvider);

  @override
  Future<PagedState<AppNotification>> build() async {
    final signedIn = ref.watch(sessionProvider) != null;
    if (!signedIn && !ref.watch(appConfigProvider).useDemoData) {
      return const PagedState(items: [], nextCursor: null);
    }
    return PagedState.fromPage(
      await ref.watch(notificationsRepositoryProvider).page(),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    try {
      final page = await _repository.page(cursor: current.nextCursor);
      if (ref.mounted) state = AsyncData(current.appending(page));
    } on Object catch (error) {
      if (ref.mounted)
        state = AsyncData(
          current.copyWith(
            isLoadingMore: false,
            loadMoreError: error.asFailure(),
          ),
        );
    }
  }

  /// Optimistic; restores the previous state if the server rejects it.
  Future<void> markRead(String id) async {
    final previous = state.value;
    if (previous == null) return;
    state = AsyncData(
      previous.copyWith(
        items: [for (final n in previous.items) n.id == id ? n.markRead() : n],
      ),
    );
    try {
      await _repository.markRead(id);
      ref.invalidate(unreadNotificationsCountProvider);
    } on AppFailure {
      if (ref.mounted) state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    final previous = state.value;
    if (previous == null) return;
    state = AsyncData(
      previous.copyWith(items: [for (final n in previous.items) n.markRead()]),
    );
    try {
      await _repository.markAllRead();
      ref.invalidate(unreadNotificationsCountProvider);
    } on AppFailure {
      if (ref.mounted) state = AsyncData(previous);
      rethrow;
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, PagedState<AppNotification>>(
      NotificationsController.new,
    );

/// Server-side unread count (covers items beyond the loaded page).
final unreadNotificationsCountProvider = FutureProvider<int>((ref) async {
  ref.watch(notificationsProvider);
  if (ref.watch(sessionProvider) == null &&
      !ref.watch(appConfigProvider).useDemoData)
    return 0;
  return ref.watch(notificationsRepositoryProvider).unreadCount();
});

final unreadNotificationsProvider = Provider<int>((ref) {
  final server = ref.watch(unreadNotificationsCountProvider).value;
  if (server != null) return server;
  return (ref.watch(notificationsProvider).value?.items ?? const [])
      .where((n) => !n.isRead)
      .length;
});
