import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/clock.dart';
import '../../features/auth/domain/auth.dart';
import '../../features/chat/domain/chat.dart';
import '../../features/jobs/domain/job.dart';
import '../../features/listings/domain/listing.dart';
import '../../features/notifications/domain/app_notification.dart';
import '../../features/services/domain/service_provider.dart';
import '../../features/trust_safety/domain/trust_safety.dart';
import 'demo_seed.dart';

/// Mutable in-memory backing store for demo repositories. Mimics a backend:
/// repositories mutate it, and all of them observe the same state.
class DemoDatabase {
  DemoDatabase({required DateTime now, required this.latency}) : seed = DemoSeed(now), _now = now {
    listings = [...seed.myListings, ...seed.listings];
    jobs = [...seed.jobs];
    candidates = [...seed.candidates];
    providers = [...seed.providers];
    conversations = {for (final c in seed.conversations) c.id: c};
    messages = {
      for (final entry in seed.messages.entries) entry.key: [...entry.value],
    };
    notifications = [...seed.notifications];
    currentUser = seed.currentUser;
    applications = [
      JobApplication(
        id: 'app_frontend',
        job: jobs.firstWhere((j) => j.id == 'j_frontend'),
        appliedAt: seed.ago(days: 1, hours: 3),
        status: ApplicationStatus.viewed,
        message: 'React bo‘yicha 2 yillik tajribam bor.',
      ),
    ];
  }

  final DemoSeed seed;
  final Duration latency;
  final DateTime _now;

  late final List<Listing> listings;
  late final List<Job> jobs;
  late final List<CandidateProfile> candidates;
  late final List<ServiceProvider> providers;
  late final Map<String, Conversation> conversations;
  late final Map<String, List<ChatMessage>> messages;
  late final List<AppNotification> notifications;
  late final List<JobApplication> applications;
  final Set<String> blockedUserIds = {};
  final List<ReportRequest> reports = [];
  CurrentUser? currentUser;

  int _sequence = 0;

  DateTime get seededAt => _now;

  String nextId(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';

  /// Simulated network round-trip so loading states are real in the demo.
  Future<void> roundTrip([double factor = 1]) =>
      latency == Duration.zero ? Future<void>.value() : Future<void>.delayed(latency * factor);

  bool get simulatesPeers => latency > Duration.zero;
}

final demoDatabaseProvider = Provider<DemoDatabase>((ref) {
  return DemoDatabase(now: ref.read(clockProvider)(), latency: ref.read(appConfigProvider).demoLatency);
});
