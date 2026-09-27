import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/sharing/share_service.dart';
import '../../../core/sharing/share_sheet.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/contact_sheet.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../chat/domain/chat.dart';
import '../../chat/presentation/start_chat.dart';
import '../../saved/application/saved_items_controller.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../../trust_safety/presentation/report_sheet.dart';
import '../application/listing_providers.dart';
import '../domain/listing.dart';
import 'widgets/listing_cards.dart';
import 'widgets/photo_gallery.dart';

SharePayload listingSharePayload(WidgetRef ref, Listing listing) => SharePayload(
  target: ShareTarget.listing,
  id: listing.id,
  title: listing.title,
  subtitle: listing.price == null ? 'Kelishiladi' : Formatters.money(listing.price!).replaceAll(' ', ' '),
  location: listing.place.shortLabel,
  image: listing.cover,
  url: ref.read(deepLinksProvider).web(ShareTarget.listing, listing.id),
);

class ListingDetailScreen extends ConsumerWidget {
  const ListingDetailScreen({super.key, required this.listingId, this.heroPrefix});

  final String listingId;
  final String? heroPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(listingDetailProvider(listingId));
    return detail.when(
      data: (listing) => _ListingDetailView(listing: listing, heroPrefix: heroPrefix ?? 'detail'),
      loading: () => const _DetailSkeleton(),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: FailureView(error: error, onRetry: () => ref.invalidate(listingDetailProvider(listingId))),
      ),
    );
  }
}

class _ListingDetailView extends ConsumerWidget {
  const _ListingDetailView({required this.listing, required this.heroPrefix});

  final Listing listing;
  final String heroPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final visual = listingVisual(ref, listing.categoryId);
    final category = ref.watch(categoryTreeProvider).byId(listing.categoryId);
    final isMine = ref.watch(sessionProvider)?.id == listing.seller.id;
    final width = MediaQuery.sizeOf(context).width;
    final galleryHeight = math.min(width * 3 / 4, 460.0);
    final gutter = AppBreakpoints.pagePadding(context);

    final attributes = [
      ...listing.attributes.map((a) => (a.label, a.value)),
      if (listing.condition != null) ('Holati', listing.condition!.label),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: galleryHeight,
            backgroundColor: palette.surface,
            automaticallyImplyLeading: false,
            leadingWidth: AppTouch.minTarget + AppSpacing.sm,
            leading: Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
              child: CircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Orqaga',
                onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
              ),
            ),
            actions: [
              CircleIconButton(
                icon: Icons.ios_share_rounded,
                tooltip: 'Ulashish',
                onPressed: () => showShareSheet(context, listingSharePayload(ref, listing)),
              ),
              FavoriteButton(kind: SavedKind.listing, id: listing.id, onImage: true),
              const SizedBox(width: AppSpacing.xs),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: PhotoGallery(
                images: listing.images,
                heroTag: '$heroPrefix-${listing.id}',
                placeholderIcon: visual.icon,
                tone: visual.tone,
                semanticTitle: listing.title,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xl, gutter, AppSpacing.huge),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (category != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Text(category.name, style: text.labelMedium?.copyWith(color: palette.primary)),
                      ),
                    Text(listing.title, style: text.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Flexible(
                          child: PriceText(listing: listing, style: text.headlineSmall?.copyWith(fontSize: 24)),
                        ),
                        if (listing.negotiable) ...[
                          const SizedBox(width: AppSpacing.sm),
                          const StatusPill(label: 'Kelishiladi', style: PillStyle.success),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.lg,
                      runSpacing: AppSpacing.sm,
                      children: [
                        MetaLine(icon: Icons.location_on_outlined, text: listing.place.shortLabel),
                        MetaLine(icon: Icons.schedule_rounded, text: Formatters.relativeTime(listing.publishedAt, now)),
                        MetaLine(
                          icon: Icons.visibility_outlined,
                          text: '${Formatters.compactCount(listing.views)} ko‘rish',
                        ),
                        MetaLine(icon: Icons.favorite_border_rounded, text: '${listing.favorites} ta saqlangan'),
                      ],
                    ),
                    if (listing.status != ListingStatus.active) ...[
                      const SizedBox(height: AppSpacing.md),
                      StatusPill(
                        label: listing.status.label,
                        style: PillStyle.warning,
                        icon: Icons.info_outline_rounded,
                      ),
                    ],
                    if (attributes.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      SurfaceCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                        color: palette.surfaceMuted,
                        borderColor: Colors.transparent,
                        child: _AttributeGrid(attributes: attributes),
                      ),
                    ],
                    DetailSection(
                      title: 'Tavsif',
                      child: ExpandableText(listing.description, style: text.bodyMedium?.copyWith(height: 1.55)),
                    ),
                    DetailSection(
                      title: isMine ? 'Siz joylagan e’lon' : 'Sotuvchi',
                      child: _SellerCard(seller: listing.seller),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const SafetyTipsCard(),
                    DetailSection(
                      title: 'Manzil',
                      child: SurfaceCard(
                        child: Row(
                          children: [
                            const ToneIcon(icon: Icons.map_rounded, tone: AccentTone.teal, size: 40),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: Text(listing.place.fullLabel, style: text.bodyMedium)),
                            if (listing.distanceKm != null)
                              StatusPill(label: Formatters.distance(listing.distanceKm!), style: PillStyle.primary),
                          ],
                        ),
                      ),
                    ),
                    _SimilarListings(listing: listing),
                    const SizedBox(height: AppSpacing.xl),
                    if (!isMine)
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: palette.danger),
                        onPressed: () => showReportSheet(context, type: ReportTargetType.listing, targetId: listing.id),
                        icon: const Icon(Icons.flag_outlined, size: AppIconSize.sm),
                        label: const Text('E’lon ustidan shikoyat qilish'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMine
          ? StickyActionBar(
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.myListings),
                  icon: const Icon(Icons.list_alt_rounded),
                  label: const Text('E’lonlarim'),
                ),
                FilledButton.icon(
                  onPressed: () => showShareSheet(context, listingSharePayload(ref, listing)),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Ulashish'),
                ),
              ],
            )
          : StickyActionBar(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: palette.success),
                  onPressed: () => showContactSheet(
                    context,
                    person: listing.seller,
                    loadPhone: () => ref.read(listingRepositoryProvider).revealPhone(listing.id),
                  ),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Qo‘ng‘iroq'),
                ),
                FilledButton.icon(
                  onPressed: () => startChat(
                    context,
                    ref,
                    peer: listing.seller,
                    subject: ConversationContext(
                      subject: ConversationSubject.listing,
                      refId: listing.id,
                      title: listing.title,
                      subtitle: listing.price == null ? 'Kelishiladi' : Formatters.money(listing.price!),
                      image: listing.cover,
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_rounded),
                  label: const Text('Chat'),
                ),
              ],
            ),
    );
  }
}

class _AttributeGrid extends StatelessWidget {
  const _AttributeGrid({required this.attributes});

  final List<(String, String)> attributes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(10) > 14;
        final columns = constraints.maxWidth > 420 ? 4 : (largeText ? 2 : 3);
        final width = (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final (label, value) in attributes)
              SizedBox(
                width: width,
                child: InfoTile(label: label, value: value),
              ),
          ],
        );
      },
    );
  }
}

class _SellerCard extends ConsumerWidget {
  const _SellerCard({required this.seller});

  final PublicProfile seller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final now = ref.watch(clockProvider)();
    final presence = Formatters.presence(isOnline: seller.isOnline, lastActiveAt: seller.lastActiveAt, now: now);
    return SurfaceCard(
      onTap: () => context.push(AppRoutes.seller(seller.id)),
      child: Column(
        children: [
          Row(
            children: [
              AppAvatar(name: seller.name, image: seller.avatar, size: 52, isOnline: seller.isOnline),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(seller.name, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        VerifiedBadge(level: seller.verification),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(presence, style: text.bodySmall?.copyWith(color: seller.isOnline ? palette.success : null)),
                    Text('${Formatters.monthYear(seller.memberSince)} dan beri', style: text.bodySmall),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  foregroundColor: palette.primary,
                  side: BorderSide(color: palette.primary),
                ),
                onPressed: () => context.push(AppRoutes.seller(seller.id)),
                child: const Text('Profil'),
              ),
            ],
          ),
          if (seller.rating != null || seller.responseTimeMinutes != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.sm,
                children: [
                  if (seller.rating != null) RatingLabel(rating: seller.rating!, count: seller.reviewCount),
                  if (seller.responseTimeMinutes != null)
                    MetaLine(icon: Icons.bolt_rounded, text: '~${seller.responseTimeMinutes} daqiqada javob'),
                  MetaLine(icon: Icons.inventory_2_outlined, text: '${seller.activeListings} ta e’lon'),
                ],
              ),
            ),
          ],
          if (!seller.verification.isVerified) ...[
            const SizedBox(height: AppSpacing.md),
            const StatusPill(
              label: 'Sotuvchi hali tasdiqlanmagan',
              style: PillStyle.warning,
              icon: Icons.info_outline_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _SimilarListings extends ConsumerWidget {
  const _SimilarListings({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similar = ref.watch(similarListingsProvider(listing));
    final items = similar.value ?? const <Listing>[];
    if (similar.hasError || (similar.hasValue && items.isEmpty)) return const SizedBox.shrink();
    const cardWidth = 172.0;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final height = cardWidth * 3 / 4 + 20 + 76 * textScale.clamp(1.0, 2.2);
    return DetailSection(
      title: 'O‘xshash e’lonlar',
      child: SizedBox(
        height: height,
        child: similar.isLoading
            ? Shimmer(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 3,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                  itemBuilder: (_, _) => const SizedBox(width: cardWidth, child: ListingCardSkeleton()),
                ),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
                itemBuilder: (_, index) => SizedBox(
                  width: cardWidth,
                  child: ListingCard(listing: items[index], heroPrefix: 'similar-${listing.id}'),
                ),
              ),
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: Shimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            SizedBox(height: math.min(width * 3 / 4, 460), child: const SkeletonBox(radius: 0)),
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(widthFactor: 0.6, height: 22),
                  SizedBox(height: AppSpacing.md),
                  SkeletonLine(widthFactor: 0.45, height: 22),
                  SizedBox(height: AppSpacing.lg),
                  SkeletonLine(widthFactor: 0.8),
                  SizedBox(height: AppSpacing.xl),
                  SkeletonBox(height: 120, radius: AppRadii.lg),
                  SizedBox(height: AppSpacing.xl),
                  SkeletonLine(),
                  SizedBox(height: AppSpacing.sm),
                  SkeletonLine(widthFactor: 0.9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
