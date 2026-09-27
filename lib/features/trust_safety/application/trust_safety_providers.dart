import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../data/demo/demo_database.dart';
import '../../auth/application/session_controller.dart';
import '../../listings/application/listing_providers.dart';
import '../domain/trust_safety.dart';

class DemoTrustSafetyRepository implements TrustSafetyRepository {
  DemoTrustSafetyRepository(this._db);

  final DemoDatabase _db;

  @override
  Future<void> report(ReportRequest request) async {
    await _db.roundTrip();
    _db.reports.add(request);
  }

  @override
  Future<void> block(String userId) async {
    await _db.roundTrip(0.5);
    _db.blockedUserIds.add(userId);
    for (final entry in _db.conversations.entries.toList()) {
      if (entry.value.peer.id == userId)
        _db.conversations[entry.key] = entry.value.copyWith(isBlocked: true);
    }
  }

  @override
  Future<void> unblock(String userId) async {
    await _db.roundTrip(0.5);
    _db.blockedUserIds.remove(userId);
    for (final entry in _db.conversations.entries.toList()) {
      if (entry.value.peer.id == userId)
        _db.conversations[entry.key] = entry.value.copyWith(isBlocked: false);
    }
  }

  @override
  Future<Set<String>> blockedUserIds() async =>
      Set.unmodifiable(_db.blockedUserIds);
}

/// `/reports` and `/blocks`. Blocks are enforced server-side (chat, feed,
/// search); this client only reflects them.
class RemoteTrustSafetyRepository implements TrustSafetyRepository {
  RemoteTrustSafetyRepository(this._api);

  final ApiClient _api;

  @override
  Future<void> report(ReportRequest request) async {
    try {
      await _api.post<Object?>(
        '/reports',
        body: {
          'targetType': request.targetType.name,
          'targetId': request.targetId,
          'reason': request.reason.name,
          if (request.comment != null && request.comment!.trim().isNotEmpty)
            'comment': request.comment!.trim(),
        },
      );
    } on ConflictFailure {
      // Already reported by this user: treat as success.
    }
  }

  @override
  Future<void> block(String userId) => _api.put<Object?>('/blocks/$userId');

  @override
  Future<void> unblock(String userId) => _api.delete('/blocks/$userId');

  @override
  Future<Set<String>> blockedUserIds() async => {
    for (final row in await _api.get<List<dynamic>>('/blocks'))
      ((row as JsonMap)['user'] as JsonMap)['id'] as String,
  };
}

final trustSafetyRepositoryProvider = Provider<TrustSafetyRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData)
    return DemoTrustSafetyRepository(ref.watch(demoDatabaseProvider));
  return RemoteTrustSafetyRepository(ref.watch(apiClientProvider));
});

class BlockedUsersController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    if (!ref.watch(appConfigProvider).useDemoData &&
        ref.watch(sessionProvider) == null)
      return const {};
    return ref.watch(trustSafetyRepositoryProvider).blockedUserIds();
  }

  Future<void> block(String userId) async {
    await ref.read(trustSafetyRepositoryProvider).block(userId);
    state = AsyncData({...state.value ?? const <String>{}, userId});
    ref.read(listingsRevisionProvider.notifier).bump();
  }

  Future<void> unblock(String userId) async {
    await ref.read(trustSafetyRepositoryProvider).unblock(userId);
    state = AsyncData({...state.value ?? const <String>{}}..remove(userId));
    ref.read(listingsRevisionProvider.notifier).bump();
  }
}

final blockedUsersProvider =
    AsyncNotifierProvider<BlockedUsersController, Set<String>>(
      BlockedUsersController.new,
    );
