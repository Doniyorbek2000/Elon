import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_icons.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/favorite_button.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../saved/application/saved_items_controller.dart';
import '../../domain/listing.dart';

/// Icon/tone for a listing's category, used by image placeholders.
({IconData icon, AccentTone tone}) listingVisual(WidgetRef ref, String categoryId) {
  final tree = ref.watch(categoryTreeProvider);
  final category = tree.byId(categoryId);
  final root = tree.rootOf(categoryId);
  return (icon: AppIcons.forKey(category?.iconKey ?? root?.iconKey ?? 'grid'), tone: root?.tone ?? AccentTone.slate);
}

class PriceText extends StatelessWidget {
  const PriceText({super.key, required this.listing, this.style});

  final Listing listing;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final price = listing.price;
    final text = price == null ? tr('Kelishiladi') : Formatters.money(price);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (style ?? Theme.of(context).textTheme.titleSmall)?.copyWith(
        color: context.palette.price,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

String _meta(Listing listing, DateTime now, {bool compact = false}) =>
    '${compact ? listing.place.compactLabel : listing.place.shortLabel} · ${Formatters.relativeTime(listing.publishedAt, now)}';

String _semantics(Listing listing, DateTime now) => [
  listing.title,
  listing.price == null ? tr('Narx kelishiladi') : Formatters.money(listing.price!).replaceAll(' ', ' '),
  listing.place.shortLabel,
  Formatters.relativeTime(listing.publishedAt, now),
].join(', ');

/// Grid card: large 4:3 photo, title, price, location · time, favorite.
class ListingCard extends ConsumerWidget {
  const ListingCard({super.key, required this.listing, this.heroPrefix = 'feed'});

  final Listing listing;
  final String heroPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final visual = listingVisual(ref, listing.categoryId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Pressable(
      semanticLabel: _semantics(listing, now),
      onTap: () => context.push(AppRoutes.listing(listing.id), extra: heroPrefix),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadii.lgAll,
          border: Border.all(color: isDark ? palette.border : palette.border.withValues(alpha: 0.6)),
          boxShadow: AppShadows.card(palette, dark: isDark),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: '$heroPrefix-${listing.id}',
                    child: AppImage(image: listing.cover, placeholderIcon: visual.icon, tone: visual.tone),
                  ),
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: FavoriteButton(kind: SavedKind.listing, id: listing.id, onImage: true, size: AppIconSize.sm),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm + 2, AppSpacing.md, AppSpacing.md),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    PriceText(listing: listing, style: text.titleSmall?.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _meta(listing, now, compact: true),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row layout (category/search results): thumbnail left, text right.
class ListingTile extends ConsumerWidget {
  const ListingTile({super.key, required this.listing, this.heroPrefix = 'list', this.trailing});

  final Listing listing;
  final String heroPrefix;

  /// Replaces the favorite button (e.g. owner actions on "My listings").
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final visual = listingVisual(ref, listing.categoryId);
    final thumbWidth = MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 96.0 : 112.0;

    return Pressable(
      semanticLabel: _semantics(listing, now),
      onTap: () => context.push(AppRoutes.listing(listing.id), extra: heroPrefix),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: thumbWidth,
              child: AspectRatio(
                aspectRatio: 4 / 3.3,
                child: Hero(
                  tag: '$heroPrefix-${listing.id}',
                  child: AppImage(
                    image: listing.cover,
                    borderRadius: AppRadii.mdAll,
                    placeholderIcon: visual.icon,
                    tone: visual.tone,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              listing.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      PriceText(listing: listing, style: text.titleSmall?.copyWith(fontSize: 15)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _meta(listing, now),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: palette.textTertiary),
                      ),
                      if (listing.status != ListingStatus.active) ...[
                        const SizedBox(height: AppSpacing.xs),
                        StatusPill(
                          label: listing.status.label,
                          dense: true,
                          style: switch (listing.status) {
                            ListingStatus.pendingReview || ListingStatus.reserved => PillStyle.warning,
                            ListingStatus.rejected || ListingStatus.expired => PillStyle.danger,
                            ListingStatus.sold => PillStyle.success,
                            _ => PillStyle.neutral,
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            trailing ?? FavoriteButton(kind: SavedKind.listing, id: listing.id, size: AppIconSize.sm + 2),
          ],
        ),
      ),
    );
  }
}

class ListingCardSkeleton extends StatelessWidget {
  const ListingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: context.palette.border.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(aspectRatio: 4 / 3, child: SkeletonBox(radius: 0)),
          Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(widthFactor: 0.8),
                SizedBox(height: AppSpacing.sm),
                SkeletonLine(widthFactor: 0.6, height: 14),
                SizedBox(height: AppSpacing.sm),
                SkeletonLine(widthFactor: 0.7, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ListingTileSkeleton extends StatelessWidget {
  const ListingTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, height: 102, child: SkeletonBox(radius: AppRadii.md)),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: AppSpacing.xs),
              SkeletonLine(widthFactor: 0.7, height: 14),
              SizedBox(height: AppSpacing.md),
              SkeletonLine(widthFactor: 0.5, height: 14),
              SizedBox(height: AppSpacing.md),
              SkeletonLine(widthFactor: 0.6, height: 10),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Grid delegate whose tile height follows content (image 4:3 + text block
/// scaled with the user's text size) so cards never overflow.
SliverGridDelegate listingGridDelegate(BuildContext context, double width) {
  final columns = AppBreakpoints.columnsFor(width, minTileWidth: 168, max: 5);
  const spacing = AppSpacing.md;
  final tileWidth = (width - spacing * (columns - 1)) / columns;
  final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
  final textBlock = 20 + 76 * textScale.clamp(1.0, 2.2);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
    mainAxisExtent: tileWidth * 3 / 4 + textBlock,
  );
}
