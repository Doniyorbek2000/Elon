import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/clock.dart';
import '../../../data/demo/demo_database.dart';
import '../../auth/application/session_controller.dart';
import '../data/demo_job_repository.dart';
import '../data/remote_job_repository.dart';
import '../domain/job.dart';

final jobRepositoryProvider = Provider<JobRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData) {
    return DemoJobRepository(
      ref.watch(demoDatabaseProvider),
      clock: ref.watch(clockProvider),
    );
  }
  return RemoteJobRepository(ref.watch(apiClientProvider));
});

final jobSearchProvider = FutureProvider.autoDispose
    .family<List<Job>, JobQuery>((ref, query) {
      return ref.watch(jobRepositoryProvider).searchJobs(query);
    });

final candidateSearchProvider = FutureProvider.autoDispose
    .family<List<CandidateProfile>, JobQuery>((ref, query) {
      return ref.watch(jobRepositoryProvider).searchCandidates(query);
    });

final jobDetailProvider = FutureProvider.autoDispose.family<Job, String>((
  ref,
  id,
) {
  return ref.watch(jobRepositoryProvider).getJob(id);
});

final candidateDetailProvider = FutureProvider.autoDispose
    .family<CandidateProfile, String>((ref, id) {
      return ref.watch(jobRepositoryProvider).getCandidate(id);
    });

/// The signed-in user's applications; also the source of "already applied".
class MyApplicationsController extends AsyncNotifier<List<JobApplication>> {
  @override
  Future<List<JobApplication>> build() async {
    final user = ref.watch(sessionProvider);
    if (user == null) return const [];
    return ref.watch(jobRepositoryProvider).myApplications(user.id);
  }

  Future<JobApplication> apply(String jobId, {String? message}) async {
    final user = ref.read(sessionProvider);
    if (user == null) throw StateError('apply() requires a signed-in user');
    final application = await ref
        .read(jobRepositoryProvider)
        .apply(jobId: jobId, applicantId: user.id, message: message);
    final current = state.value ?? const [];
    state = AsyncData([application, ...current]);
    return application;
  }
}

final myApplicationsProvider =
    AsyncNotifierProvider<MyApplicationsController, List<JobApplication>>(
      MyApplicationsController.new,
    );

final applicationForJobProvider = Provider.autoDispose
    .family<JobApplication?, String>((ref, jobId) {
      final applications = ref.watch(myApplicationsProvider).value ?? const [];
      return applications.where((a) => a.job.id == jobId).firstOrNull;
    });
