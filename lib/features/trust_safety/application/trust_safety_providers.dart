import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/demo/demo_database.dart';
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
      if (entry.value.peer.id == userId) _db.conversations[entry.key] = entry.value.copyWith(isBlocked: true);
    }
  }

  @override
  Future<void> unblock(String userId) async {
    await _db.roundTrip(0.5);
    _db.blockedUserIds.remove(userId);
    for (final entry in _db.conversations.entries.toList()) {
      if (entry.value.peer.id == userId) _db.conversations[entry.key] = entry.value.copyWith(isBlocked: false);
    }
  }

  @override
  Future<Set<String>> blockedUserIds() async => Set.unmodifiable(_db.blockedUserIds);
}

final trustSafetyRepositoryProvider = Provider<TrustSafetyRepository>(
  (ref) => DemoTrustSafetyRepository(ref.watch(demoDatabaseProvider)),
);

class BlockedUsersController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => ref.watch(trustSafetyRepositoryProvider).blockedUserIds();

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

final blockedUsersProvider = AsyncNotifierProvider<BlockedUsersController, Set<String>>(BlockedUsersController.new);
