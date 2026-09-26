import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/sharing/share_sheet.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../listings/application/listing_providers.dart';
import '../../listings/domain/listing.dart';
import '../../listings/presentation/listing_detail_screen.dart';
import '../../listings/presentation/widgets/listing_cards.dart';
import '../../monetization/application/monetization_providers.dart';

enum _Tab {
  active('Faol', {ListingStatus.active}),
  review('Tekshiruvda', {ListingStatus.pendingReview, ListingStatus.rejected}),
  archive('Arxiv', {ListingStatus.sold, ListingStatus.archived});

  const _Tab(this.label, this.statuses);

  final String label;
  final Set<ListingStatus> statuses;
}

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink();
    final listings = ref.watch(sellerListingsProvider(user.id));

    return DefaultTabController(
      length: _Tab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mening e’lonlarim'),
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
          label: const Text('Yangi e’lon'),
        ),
        body: listings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              FailureView(error: error, onRetry: () => ref.invalidate(sellerListingsProvider(user.id))),
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
      if (context.mounted) showAppSnack(context, 'Holat yangilandi: ${status.label}', icon: Icons.check_rounded);
    } on Object {
      if (context.mounted) showAppSnack(context, 'Yangilab bo‘lmadi');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Listing listing) async {
    final confirmed = await confirmDialog(
      context,
      title: 'E’lon o‘chirilsinmi?',
      message: 'Bu amalni qaytarib bo‘lmaydi.',
      confirmLabel: 'O‘chirish',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(listingRepositoryProvider).delete(listing.id);
    ref.read(listingsRevisionProvider.notifier).bump();
  }

  Future<void> _promote(BuildContext context, WidgetRef ref, Listing listing) async {
    await showAppSheet<void>(context, builder: (_) => _PromoteSheet(listing: listing));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canPromote = ref.watch(featureFlagsProvider).canSellPromotions;
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: switch (tab) {
          _Tab.active => 'Faol e’lonlar yo‘q',
          _Tab.review => 'Tekshiruvdagi e’lonlar yo‘q',
          _Tab.archive => 'Arxiv bo‘sh',
        },
        message: tab == _Tab.active ? 'Birinchi e’loningizni 1 daqiqada joylang.' : null,
        actionLabel: tab == _Tab.active ? 'E’lon joylash' : null,
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
            tooltip: 'Amallar',
            onSelected: (value) => switch (value) {
              'share' => showShareSheet(context, listingSharePayload(ref, listing)),
              'sold' => _setStatus(context, ref, listing, ListingStatus.sold),
              'archive' => _setStatus(context, ref, listing, ListingStatus.archived),
              'activate' => _setStatus(context, ref, listing, ListingStatus.active),
              'promote' => _promote(context, ref, listing),
              'delete' => _delete(context, ref, listing),
              _ => null,
            },
            itemBuilder: (_) => [
              if (listing.status == ListingStatus.active) ...[
                const PopupMenuItem(value: 'share', child: Text('Ulashish')),
                if (canPromote) const PopupMenuItem(value: 'promote', child: Text('Reklama qilish')),
                const PopupMenuItem(value: 'sold', child: Text('Sotildi deb belgilash')),
                const PopupMenuItem(value: 'archive', child: Text('Arxivlash')),
              ],
              if (listing.status == ListingStatus.sold || listing.status == ListingStatus.archived)
                const PopupMenuItem(value: 'activate', child: Text('Qayta faollashtirish')),
              const PopupMenuItem(value: 'delete', child: Text('O‘chirish')),
            ],
          ),
        );
      },
    );
  }
}

/// Paid promotion picker — reachable only when `canSellPromotions` is on.
class _PromoteSheet extends ConsumerWidget {
  const _PromoteSheet({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(promotionProductsProvider(PromotionTarget.listing)).value ?? const [];
    final text = Theme.of(context).textTheme;
    return SheetScaffold(
      title: 'E’lonni ko‘tarish',
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        children: [
          Text(listing.title, style: text.bodySmall),
          const SizedBox(height: AppSpacing.md),
          for (final product in products)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SurfaceCard(
                onTap: () {
                  Navigator.pop(context);
                  showAppSnack(context, 'To‘lov tizimi ulanganidan so‘ng faollashadi');
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${product.title} · ${product.durationDays} kun', style: text.titleSmall),
                          Text(product.description, style: text.bodySmall),
                        ],
                      ),
                    ),
                    Text(Formatters.money(product.price), style: text.titleSmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
