import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/avatar.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/favorite_button.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../saved/application/saved_items_controller.dart';
import '../../domain/service_provider.dart';

String _semantics(ServiceProvider p) => [
  p.name,
  p.profession,
  'reyting ${p.rating.toStringAsFixed(1)}, ${p.reviewCount} sharh',
  p.place.shortLabel,
  if (p.profile.isOnline) 'onlayn',
  if (p.isTop) 'TOP usta',
].join(', ');

/// Compact vertical card for provider carousels.
class ProviderCard extends ConsumerWidget {
  const ProviderCard({super.key, required this.provider});

  final ServiceProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => context.push(AppRoutes.provider(provider.id)),
      child: Semantics(
        label: _semantics(provider),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: AppAvatar(
                name: provider.name,
                image: provider.profile.avatar,
                size: 72,
                isOnline: provider.profile.isOnline,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Flexible(
                  child: Text(provider.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 3),
                VerifiedBadge(level: provider.profile.verification, size: 14),
              ],
            ),
            Text(provider.profession, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpacing.xs),
            RatingLabel(rating: provider.rating, count: provider.reviewCount, compact: true),
            const SizedBox(height: 2),
            MetaLine(icon: Icons.location_on_outlined, text: provider.place.shortLabel),
            const Spacer(),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (provider.profile.isOnline) const StatusPill(label: 'Onlayn', style: PillStyle.success, dense: true),
                if (provider.promotion case final promotion?) PromotionBadge(type: promotion.type),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width row for provider lists.
class ProviderTile extends ConsumerWidget {
  const ProviderTile({super.key, required this.provider});

  final ServiceProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, 0, AppSpacing.md),
      onTap: () => context.push(AppRoutes.provider(provider.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: provider.name, image: provider.profile.avatar, size: 56, isOnline: provider.profile.isOnline),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Semantics(
              label: _semantics(provider),
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          provider.name,
                          style: text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      VerifiedBadge(level: provider.profile.verification, size: 14),
                      if (provider.promotion case final promotion?) ...[
                        const SizedBox(width: AppSpacing.xs),
                        PromotionBadge(type: promotion.type),
                      ],
                    ],
                  ),
                  Text(provider.profession, style: text.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RatingLabel(rating: provider.rating, count: provider.reviewCount, compact: true),
                      MetaLine(icon: Icons.location_on_outlined, text: provider.place.shortLabel),
                    ],
                  ),
                  if (provider.priceFrom != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${Formatters.money(provider.priceFrom!)} dan${provider.priceUnit == null ? '' : ' / ${provider.priceUnit}'}',
                      style: text.labelMedium?.copyWith(color: palette.price),
                    ),
                  ],
                ],
              ),
            ),
          ),
          FavoriteButton(kind: SavedKind.provider, id: provider.id, size: AppIconSize.sm + 2),
        ],
      ),
    );
  }
}

class ProviderTileSkeleton extends StatelessWidget {
  const ProviderTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const SurfaceCard(
    child: Row(
      children: [
        SkeletonBox(width: 56, height: 56, radius: 28),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLine(widthFactor: 0.5, height: 14),
              SizedBox(height: AppSpacing.sm),
              SkeletonLine(widthFactor: 0.35, height: 10),
              SizedBox(height: AppSpacing.sm),
              SkeletonLine(widthFactor: 0.6, height: 10),
            ],
          ),
        ),
      ],
    ),
  );
}
