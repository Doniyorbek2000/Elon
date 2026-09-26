import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/widgets/state_views.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/widgets/job_cards.dart';
import '../../listings/application/listing_providers.dart';
import '../../listings/domain/listing.dart';
import '../../listings/presentation/widgets/listing_cards.dart';
import '../../saved/application/saved_items_controller.dart';
import '../../services/application/services_providers.dart';
import '../../services/domain/service_provider.dart';
import '../../services/presentation/widgets/provider_cards.dart';

final _savedListingsProvider = FutureProvider.autoDispose<List<Listing>>((ref) {
  ref.watch(savedItemsProvider);
  final ids = ref.read(savedItemsProvider.notifier).idsOf(SavedKind.listing);
  return ids.isEmpty ? Future.value(const []) : ref.watch(listingRepositoryProvider).getByIds(ids);
});

final _savedJobsProvider = FutureProvider.autoDispose<List<Job>>((ref) async {
  ref.watch(savedItemsProvider);
  final ids = ref.read(savedItemsProvider.notifier).idsOf(SavedKind.job);
  final repository = ref.watch(jobRepositoryProvider);
  final jobs = await Future.wait(ids.map((id) => repository.getJob(id).then<Job?>((j) => j, onError: (_) => null)));
  return jobs.whereType<Job>().toList();
});

final _savedProvidersProvider = FutureProvider.autoDispose<List<ServiceProvider>>((ref) async {
  ref.watch(savedItemsProvider);
  final ids = ref.read(savedItemsProvider.notifier).idsOf(SavedKind.provider);
  final repository = ref.watch(servicesRepositoryProvider);
  final providers = await Future.wait(
    ids.map((id) => repository.getProvider(id).then<ServiceProvider?>((p) => p, onError: (_) => null)),
  );
  return providers.whereType<ServiceProvider>().toList();
});

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saqlanganlar'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'E’lonlar'),
              Tab(text: 'Ishlar'),
              Tab(text: 'Ustalar'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SavedTab<Listing>(
              provider: _savedListingsProvider,
              emptyTitle: 'Saqlangan e’lonlar yo‘q',
              builder: (l) => ListingTile(listing: l, heroPrefix: 'saved'),
              browseRoute: AppRoutes.home,
            ),
            _SavedTab<Job>(
              provider: _savedJobsProvider,
              emptyTitle: 'Saqlangan vakansiyalar yo‘q',
              builder: (j) => JobCard(job: j),
              browseRoute: AppRoutes.jobs,
            ),
            _SavedTab<ServiceProvider>(
              provider: _savedProvidersProvider,
              emptyTitle: 'Saqlangan ustalar yo‘q',
              builder: (p) => ProviderTile(provider: p),
              browseRoute: AppRoutes.services,
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedTab<T> extends ConsumerWidget {
  const _SavedTab({required this.provider, required this.emptyTitle, required this.builder, required this.browseRoute});

  final ProviderListenable<AsyncValue<List<T>>> provider;
  final String emptyTitle;
  final Widget Function(T) builder;
  final String browseRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(provider)
        .when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => FailureView(error: error),
          data: (items) => items.isEmpty
              ? EmptyState(
                  icon: Icons.favorite_border_rounded,
                  tone: AccentTone.red,
                  title: emptyTitle,
                  message: 'Yoqqan narsalarni ♥ belgisi bilan saqlang — ular shu yerda turadi.',
                  actionLabel: 'Ko‘rib chiqish',
                  onAction: () => browseRoute == AppRoutes.home ? context.go(browseRoute) : context.push(browseRoute),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, index) => builder(items[index]),
                ),
        );
  }
}
