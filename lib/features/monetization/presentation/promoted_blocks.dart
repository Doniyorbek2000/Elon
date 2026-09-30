import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/widgets/job_cards.dart';
import '../../listings/domain/listing.dart';
import '../../listings/domain/listing_query.dart';
import '../../listings/presentation/widgets/listing_cards.dart';
import '../../services/domain/service_provider.dart';
import '../../services/presentation/widgets/provider_cards.dart';
import '../application/promoted_providers.dart';
import '../data/promoted_repository.dart';

/// Header of every paid block: the "Reklama" label is always visible.
class SponsoredHeader extends StatelessWidget {
  const SponsoredHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: tr('{title}, reklama', {'title': title}),
      excludeSemantics: true,
      child: Row(
        children: [
          Flexible(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(width: AppSpacing.sm),
          StatusPill(label: tr('Reklama'), dense: true),
        ],
      ),
    );
  }
}

class _ListingCarousel extends StatelessWidget {
  const _ListingCarousel({required this.title, required this.listings, required this.gutter, required this.heroPrefix});

  final String title;
  final List<Listing> listings;
  final double gutter;
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.sm),
          child: SponsoredHeader(title: title),
        ),
        SizedBox(
          height: 150 + 82 * textScale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: listings.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, index) => SizedBox(
              width: 176,
              child: ListingCard(listing: listings[index], heroPrefix: heroPrefix),
            ),
          ),
        ),
      ],
    );
  }
}

/// TOP/VIP block for a listing query (same filters as the organic feed).
class PromotedListingsBlock extends ConsumerWidget {
  const PromotedListingsBlock({super.key, required this.query, required this.gutter});

  final ListingQuery query;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(promotedListingsProvider(query)).value ?? const [];
    if (listings.isEmpty) return const SizedBox.shrink();
    return _ListingCarousel(title: tr('TOP e’lonlar'), listings: listings, gutter: gutter, heroPrefix: 'promoted');
  }
}

/// Paid "Tavsiya" placement (home / category / region).
class FeaturedListingsBlock extends ConsumerWidget {
  const FeaturedListingsBlock({
    super.key,
    required this.placement,
    required this.gutter,
    this.regionId,
    this.categoryId,
  });

  final String placement;
  final String? regionId;
  final String? categoryId;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings =
        ref.watch(featuredListingsProvider((placement: placement, regionId: regionId, categoryId: categoryId))).value ??
        const [];
    if (listings.isEmpty) return const SizedBox.shrink();
    return _ListingCarousel(title: tr('Tavsiya etilgan'), listings: listings, gutter: gutter, heroPrefix: 'featured');
  }
}

/// TOP vacancies above organic job results.
class PromotedJobsBlock extends ConsumerWidget {
  const PromotedJobsBlock({super.key, required this.query});

  final JobQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(promotedJobsProvider(query)).value ?? const [];
    if (jobs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SponsoredHeader(title: tr('TOP vakansiyalar')),
          const SizedBox(height: AppSpacing.sm),
          for (final job in jobs)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: JobCard(key: ValueKey('promoted-${job.id}'), job: job),
            ),
        ],
      ),
    );
  }
}

class _ProviderCarousel extends StatelessWidget {
  const _ProviderCarousel({required this.title, required this.providers, required this.gutter});

  final String title;
  final List<ServiceProvider> providers;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xl, gutter, AppSpacing.sm),
          child: SponsoredHeader(title: title),
        ),
        SizedBox(
          height: 196 + 60 * textScale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: providers.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, index) => SizedBox(width: 156, child: ProviderCard(provider: providers[index])),
          ),
        ),
      ],
    );
  }
}

/// Paid provider placements. Rating shown is the provider's real rating;
/// payment never changes it.
class PromotedProvidersBlock extends ConsumerWidget {
  const PromotedProvidersBlock({super.key, required this.gutter, this.categoryId, this.regionId, this.text = ''});

  final String? categoryId;
  final String? regionId;
  final String text;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top =
        ref.watch(promotedProvidersProvider((text: text, categoryId: categoryId, regionId: regionId))).value ??
        const [];
    final featured =
        ref
            .watch(
              featuredProvidersProvider((
                placement: categoryId == null ? 'region' : 'category',
                regionId: regionId,
                categoryId: categoryId,
              )),
            )
            .value ??
        const [];
    final seen = <String>{};
    final providers = [...top, ...featured].where((p) => seen.add(p.id)).toList();
    if (providers.isEmpty) return const SizedBox.shrink();
    return _ProviderCarousel(title: tr('Tavsiya etilgan ustalar'), providers: providers, gutter: gutter);
  }
}

/// Impressions are reported once per ad per app session (server dedupes too).
final _reportedImpressions = <String>{};

/// Native local ad with a visible "Reklama" label.
class AdBanner extends ConsumerWidget {
  const AdBanner({super.key, required this.gutter, this.regionId, this.districtId, this.categoryId});

  final String? regionId;
  final String? districtId;
  final String? categoryId;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(adsProvider((regionId: regionId, districtId: districtId, categoryId: categoryId))).value;
    final ad = ads?.firstOrNull;
    if (ad == null) return const SizedBox.shrink();
    final repository = ref.read(promotedRepositoryProvider);
    if (_reportedImpressions.add(ad.id)) {
      repository.recordAdEvent(ad.id, 'impression').ignore();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, 0),
      child: AdCardView(
        ad: ad,
        onTap: () {
          repository.recordAdEvent(ad.id, 'click').ignore();
          context.push(ad.route);
        },
      ),
    );
  }
}

class AdCardView extends StatelessWidget {
  const AdCardView({super.key, required this.ad, required this.onTap});

  final AdCard ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: tr('Reklama: {title}. {body}', {'title': ad.title, 'body': ad.body}),
      button: true,
      excludeSemantics: true,
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            if (ad.image != null) ...[
              SizedBox(
                width: 72,
                height: 72,
                child: AppImage(
                  image: ad.image,
                  borderRadius: AppRadii.mdAll,
                  placeholderIcon: Icons.campaign_outlined,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusPill(label: tr('Reklama'), dense: true),
                  const SizedBox(height: AppSpacing.xs),
                  Text(ad.title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    ad.body,
                    style: text.bodySmall?.copyWith(color: palette.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }
}
