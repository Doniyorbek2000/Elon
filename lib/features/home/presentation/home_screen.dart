import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paged_sliver.dart';
import '../../../core/widgets/state_views.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/category.dart';
import '../../listings/application/listing_providers.dart';
import '../../listings/domain/listing_query.dart';
import '../../listings/presentation/widgets/listing_feed_slivers.dart';
import '../../location/application/location_controller.dart';
import '../../notifications/application/notifications_providers.dart';

/// Default "nearby" radius when the user hasn't picked one.
const _nearbyRadiusKm = 50;

final homeFeedQueryProvider = Provider<ListingQuery>((ref) {
  final location = ref.watch(locationProvider);
  return ListingQuery(
    regionId: location.regionId,
    districtId: location.districtId,
    radiusKm: location.radiusKm ?? _nearbyRadiusKm,
    sort: ListingSort.nearest,
  );
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(homeFeedQueryProvider);
    final gutter = adaptiveGutter(context);

    return Scaffold(
      body: InfiniteScrollTrigger(
        onLoadMore: () => ref.read(listingFeedProvider(query).notifier).loadMore(),
        child: RefreshIndicator.adaptive(
          onRefresh: () => ref.read(listingFeedProvider(query).notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, 0),
                  sliver: const SliverToBoxAdapter(child: _HomeHeader()),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.lg),
                sliver: SliverToBoxAdapter(
                  child: AppSearchField(
                    readOnly: true,
                    onTap: () => context.go(AppRoutes.search),
                    onFilterTap: () => context.push(AppRoutes.listingsFor()),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: const SliverToBoxAdapter(child: _VerticalTiles()),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xl, gutter, AppSpacing.sm),
                sliver: const SliverToBoxAdapter(child: _CategoryGrid()),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter - AppSpacing.sm, AppSpacing.sm),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(
                    title: tr('Yaqin atrofdagi e’lonlar'),
                    actionLabel: tr('Barchasini ko‘rish'),
                    onAction: () => context.push(AppRoutes.listingsFor(sort: ListingSort.nearest.name)),
                  ),
                ),
              ),
              ListingFeedSlivers(
                query: query,
                gutter: gutter,
                heroPrefix: 'home',
                empty: EmptyState(
                  icon: Icons.location_searching_rounded,
                  title: tr('Yaqin atrofda e’lonlar yo‘q'),
                  message: tr('Hududni kengaytiring yoki birinchi bo‘lib e’lon joylang.'),
                  actionLabel: tr('Hududni o‘zgartirish'),
                  onAction: () => context.push(AppRoutes.location),
                  compact: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final location = ref.watch(locationProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              button: true,
              label: tr('Joylashuv: {label}. O‘zgartirish', {'label': location.label}),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: AppRadii.mdAll,
                onTap: () => context.push(AppRoutes.location),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.minTarget),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_rounded, color: palette.primary, size: AppIconSize.md),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          location.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded, color: palette.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: tr('Bildirishnomalar'),
          onPressed: () => context.push(AppRoutes.notifications),
          icon: CountBadge(count: unread, child: const Icon(Icons.notifications_none_rounded)),
        ),
      ],
    );
  }
}

class _VerticalTiles extends StatelessWidget {
  const _VerticalTiles();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _VerticalTile(
              icon: Icons.storefront_rounded,
              label: tr('Bozor'),
              background: palette.primary,
              foreground: palette.onPrimary,
              iconBackground: Colors.white.withValues(alpha: 0.18),
              onTap: () => context.push(AppRoutes.categories),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _VerticalTile(
              icon: Icons.work_rounded,
              label: tr('Ish'),
              background: palette.tone(AccentTone.green).background,
              foreground: palette.tone(AccentTone.green).foreground,
              iconBackground: palette.tone(AccentTone.green).foreground,
              iconColor: Colors.white,
              onTap: () => context.push(AppRoutes.jobs),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _VerticalTile(
              icon: Icons.handyman_rounded,
              label: tr('Xizmatlar'),
              background: palette.tone(AccentTone.orange).background,
              foreground: palette.tone(AccentTone.orange).foreground,
              iconBackground: palette.tone(AccentTone.orange).foreground,
              iconColor: Colors.white,
              onTap: () => context.push(AppRoutes.services),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalTile extends StatelessWidget {
  const _VerticalTile({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.iconBackground,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color iconBackground;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(color: background, borderRadius: AppRadii.lgAll),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: iconBackground, borderRadius: BorderRadius.circular(AppRadii.sm)),
              child: Icon(icon, color: iconColor ?? foreground, size: AppIconSize.md),
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid();

  void _open(BuildContext context, Category? category) {
    if (category == null) {
      context.push(AppRoutes.categories);
      return;
    }
    switch (category.kind) {
      case CategoryKind.jobs:
        context.push(AppRoutes.jobs);
      case CategoryKind.services:
        context.push(AppRoutes.services);
      case CategoryKind.marketplace:
        context.push(AppRoutes.listingsFor(categoryId: category.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = ref.watch(homeShortcutsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(10) > 14;
        final columns = constraints.maxWidth >= AppBreakpoints.medium ? 6 : (largeText ? 3 : 4);
        final tileWidth = (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.md,
          children: [
            for (final category in shortcuts)
              SizedBox(
                width: tileWidth,
                child: _CategoryTile(
                  label: tr(category.name),
                  icon: AppIcons.forKey(category.iconKey),
                  tone: category.tone,
                  onTap: () => _open(context, category),
                ),
              ),
            SizedBox(
              width: tileWidth,
              child: _CategoryTile(
                label: tr('Barchasi'),
                icon: Icons.grid_view_rounded,
                tone: AccentTone.blue,
                onTap: () => _open(context, null),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.icon, required this.tone, required this.onTap});

  final String label;
  final IconData icon;
  final AccentTone tone;
  final VoidCallback onTap;

  Widget _fitLabel(BuildContext context, Widget text) =>
      label.contains(' ') ? text : FittedBox(fit: BoxFit.scaleDown, child: text);

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: Column(
        children: [
          ToneIcon(icon: icon, tone: tone, size: 54, radius: AppRadii.lg),
          const SizedBox(height: AppSpacing.xs + 2),
          // Long single words (e.g. Russian «Недвижимость») shrink instead of breaking mid-word.
          _fitLabel(
            context,
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: label.contains(' ') ? 2 : 1,
              softWrap: label.contains(' '),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
