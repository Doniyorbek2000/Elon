import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/sharing/share_sheet.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../listings/application/listing_providers.dart';
import '../../listings/domain/listing.dart';
import '../../listings/presentation/listing_detail_screen.dart';
import '../../listings/presentation/widgets/listing_cards.dart';
import '../../monetization/domain/monetization.dart';
import '../../monetization/presentation/promote_sheet.dart';

enum _Tab {
  active('Faol', {ListingStatus.active, ListingStatus.reserved}),
  review('Tekshiruvda', {ListingStatus.draft, ListingStatus.pendingReview, ListingStatus.rejected}),
  archive('Arxiv', {ListingStatus.sold, ListingStatus.expired, ListingStatus.archived});

  const _Tab(this._label, this.statuses);

  final String _label;

  String get label => tr(_label);
  final Set<ListingStatus> statuses;
}

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink();
    final listings = ref.watch(myListingsProvider);

    return DefaultTabController(
      length: _Tab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Mening e’lonlarim')),
          bottom: TabBar(
            tabs: [
              for (final tab in _Tab.values)
                Tab(
                  text: '${tab.label} ${listings.value?.where((l) => tab.statuses.contains(l.status)).length ?? ''}'
                      .trim(),
                ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(AppRoutes.create),
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('Yangi e’lon')),
        ),
        body: listings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(myListingsProvider)),
          data: (items) => TabBarView(
            children: [
              for (final tab in _Tab.values)
                _ListingsTab(items: items.where((l) => tab.statuses.contains(l.status)).toList(), tab: tab),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingsTab extends ConsumerWidget {
  const _ListingsTab({required this.items, required this.tab});

  final List<Listing> items;
  final _Tab tab;

  Future<void> _setStatus(BuildContext context, WidgetRef ref, Listing listing, ListingStatus status) async {
    try {
      await ref.read(listingRepositoryProvider).updateStatus(listing.id, status);
      ref.read(listingsRevisionProvider.notifier).bump();
      if (context.mounted) {
        showAppSnack(context, tr('Holat yangilandi: {label}', {'label': status.label}), icon: Icons.check_rounded);
      }
    } on Object {
      if (context.mounted) showAppSnack(context, tr('Yangilab bo‘lmadi'));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Listing listing) async {
    final confirmed = await confirmDialog(
      context,
      title: tr('E’lon o‘chirilsinmi?'),
      message: tr('Bu amalni qaytarib bo‘lmaydi.'),
      confirmLabel: tr('O‘chirish'),
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(listingRepositoryProvider).delete(listing.id);
    ref.read(listingsRevisionProvider.notifier).bump();
  }

  Future<void> _promote(BuildContext context, WidgetRef ref, Listing listing) async {
    final activated = await showPromoteSheet(
      context,
      target: PromotionTarget.listing,
      targetId: listing.id,
      itemTitle: listing.title,
    );
    if (activated) ref.read(listingsRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canPromote = ref.watch(featureFlagsProvider).canPromoteListings;
    final remote = !ref.watch(appConfigProvider).useDemoData;
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: switch (tab) {
          _Tab.active => tr('Faol e’lonlar yo‘q'),
          _Tab.review => tr('Tekshiruvdagi e’lonlar yo‘q'),
          _Tab.archive => tr('Arxiv bo‘sh'),
        },
        message: tab == _Tab.active ? tr('Birinchi e’loningizni 1 daqiqada joylang.') : null,
        actionLabel: tab == _Tab.active ? tr('E’lon joylash') : null,
        onAction: tab == _Tab.active ? () => context.push(AppRoutes.create) : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 96),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final listing = items[index];
        return ListingTile(
          listing: listing,
          heroPrefix: 'mine',
          trailing: PopupMenuButton<String>(
            tooltip: tr('Amallar'),
            onSelected: (value) => switch (value) {
              'share' => showShareSheet(context, listingSharePayload(ref, listing)),
              'sold' => _setStatus(context, ref, listing, ListingStatus.sold),
              'reserve' => _setStatus(context, ref, listing, ListingStatus.reserved),
              'archive' => _setStatus(context, ref, listing, ListingStatus.archived),
              'activate' => _setStatus(context, ref, listing, ListingStatus.active),
              'promote' => _promote(context, ref, listing),
              'stats' => context.push(AppRoutes.listingStats(listing.id)),
              'delete' => _delete(context, ref, listing),
              _ => null,
            },
            itemBuilder: (_) => [
              if (listing.status == ListingStatus.active) ...[
                PopupMenuItem(value: 'share', child: Text(tr('Ulashish'))),
                if (canPromote) PopupMenuItem(value: 'promote', child: Text(tr('Tezroq sotish (TOP/VIP)'))),
                if (remote) PopupMenuItem(value: 'stats', child: Text(tr('Statistika'))),
                PopupMenuItem(value: 'reserve', child: Text(tr('Band qilindi deb belgilash'))),
                PopupMenuItem(value: 'sold', child: Text(tr('Sotildi deb belgilash'))),
                PopupMenuItem(value: 'archive', child: Text(tr('Arxivlash'))),
              ],
              if (listing.status == ListingStatus.reserved) ...[
                PopupMenuItem(value: 'activate', child: Text(tr('Yana sotuvga qo‘yish'))),
                PopupMenuItem(value: 'sold', child: Text(tr('Sotildi deb belgilash'))),
              ],
              if (const {ListingStatus.sold, ListingStatus.archived, ListingStatus.expired}.contains(listing.status))
                PopupMenuItem(value: 'activate', child: Text(tr('Qayta faollashtirish'))),
              PopupMenuItem(value: 'delete', child: Text(tr('O‘chirish'))),
            ],
          ),
        );
      },
    );
  }
}
