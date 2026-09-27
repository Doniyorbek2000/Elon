import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../data/demo/demo_database.dart';

abstract interface class ProfilesRepository {
  Future<PublicProfile> getProfile(String userId);
}

class DemoProfilesRepository implements ProfilesRepository {
  DemoProfilesRepository(this._db);

  final DemoDatabase _db;

  @override
  Future<PublicProfile> getProfile(String userId) async {
    await _db.roundTrip(0.5);
    final me = _db.currentUser;
    if (me != null && me.id == userId) return me.toPublic();
    final candidates = [
      ..._db.seed.users,
      for (final provider in _db.providers) provider.profile,
      for (final candidate in _db.candidates) candidate.profile,
      for (final job in _db.jobs) job.employer,
      for (final conversation in _db.conversations.values) conversation.peer,
    ];
    return candidates.where((p) => p.id == userId).firstOrNull ??
        (throw const NotFoundFailure('Foydalanuvchi topilmadi'));
  }
}

class RemoteProfilesRepository implements ProfilesRepository {
  RemoteProfilesRepository(this._api);

  final ApiClient _api;

  @override
  Future<PublicProfile> getProfile(String userId) async =>
      PublicProfile.fromJson(await _api.get<JsonMap>('/users/$userId'));
}

final profilesRepositoryProvider = Provider<ProfilesRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData)
    return DemoProfilesRepository(ref.watch(demoDatabaseProvider));
  return RemoteProfilesRepository(ref.watch(apiClientProvider));
});

final publicProfileProvider = FutureProvider.autoDispose
    .family<PublicProfile, String>((ref, userId) {
      return ref.watch(profilesRepositoryProvider).getProfile(userId);
    });
