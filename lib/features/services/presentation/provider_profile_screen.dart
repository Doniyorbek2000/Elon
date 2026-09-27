import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/sharing/share_service.dart';
import '../../../core/sharing/share_sheet.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/contact_sheet.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/state_views.dart';
import '../../chat/domain/chat.dart';
import '../../chat/presentation/start_chat.dart';
import '../../listings/presentation/widgets/photo_gallery.dart';
import '../../saved/application/saved_items_controller.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../../trust_safety/presentation/report_sheet.dart';
import '../application/services_providers.dart';
import '../domain/service_provider.dart';

class ProviderProfileScreen extends ConsumerWidget {
  const ProviderProfileScreen({super.key, required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(providerDetailProvider(providerId))
        .when(
          data: (provider) => _ProviderView(provider: provider),
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(),
            body: FailureView(
              error: error,
              onRetry: () => ref.invalidate(providerDetailProvider(providerId)),
            ),
          ),
        );
  }
}

class _ProviderView extends ConsumerWidget {
  const _ProviderView({required this.provider});

  final ServiceProvider provider;

  void _openPortfolio(BuildContext context, int index) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) =>
            PhotoViewer(images: provider.portfolio, initialIndex: index),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final profile = provider.profile;
    final gutter = AppBreakpoints.pagePadding(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(provider.profession),
        actions: [
          IconButton(
            tooltip: 'Ulashish',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => showShareSheet(
              context,
              SharePayload(
                target: ShareTarget.provider,
                id: provider.id,
                title: '${provider.name} — ${provider.profession}',
                subtitle: provider.priceFrom == null
                    ? null
                    : '${Formatters.money(provider.priceFrom!).replaceAll(' ', ' ')} dan',
                location: provider.place.shortLabel,
                image: profile.avatar,
                url: ref
                    .read(deepLinksProvider)
                    .web(ShareTarget.provider, provider.id),
              ),
            ),
          ),
          FavoriteButton(kind: SavedKind.provider, id: provider.id),
          PopupMenuButton<String>(
            tooltip: 'Ko‘proq',
            onSelected: (value) {
              if (value == 'report')
                showReportSheet(
                  context,
                  type: ReportTargetType.provider,
                  targetId: provider.id,
                );
              if (value == 'block')
                confirmAndBlock(
                  context,
                  ref,
                  userId: profile.id,
                  name: provider.name,
                );
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Shikoyat qilish')),
              PopupMenuItem(value: 'block', child: Text('Bloklash')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          AppSpacing.lg,
          gutter,
          AppSpacing.huge,
        ),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppAvatar(
                      name: provider.name,
                      image: profile.avatar,
                      size: 84,
                      isOnline: profile.isOnline,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  provider.name,
                                  style: text.titleLarge,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              VerifiedBadge(
                                level: profile.verification,
                                size: 18,
                              ),
                            ],
                          ),
                          Text(
                            provider.profession,
                            style: text.bodyMedium?.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          RatingLabel(
                            rating: provider.rating,
                            count: provider.reviewCount,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            Formatters.presence(
                              isOnline: profile.isOnline,
                              lastActiveAt: profile.lastActiveAt,
                              now: now,
                            ),
                            style: text.bodySmall?.copyWith(
                              color: profile.isOnline ? palette.success : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (profile.verification.isVerified) ...[
                  const SizedBox(height: AppSpacing.md),
                  VerifiedBadge(level: profile.verification, showLabel: true),
                ],
                const SizedBox(height: AppSpacing.xl),
                SurfaceCard(
                  color: palette.surfaceMuted,
                  borderColor: Colors.transparent,
                  child: Row(
                    children: [
                      Expanded(
                        child: InfoTile(
                          label: 'Tajriba',
                          value: '${provider.experienceYears} yil',
                        ),
                      ),
                      Expanded(
                        child: InfoTile(
                          label: 'Bajarilgan',
                          value: '${provider.completedJobs} ta ish',
                        ),
                      ),
                      Expanded(
                        child: InfoTile(
                          label: 'Narx',
                          value: provider.priceFrom == null
                              ? 'Kelishiladi'
                              : '${Formatters.money(provider.priceFrom!)} dan',
                        ),
                      ),
                    ],
                  ),
                ),
                DetailSection(
                  title: 'Xizmat haqida',
                  child: ExpandableText(provider.description),
                ),
                DetailSection(
                  title: 'Xizmat hududi',
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final area in provider.serviceArea)
                        StatusPill(
                          label: area,
                          icon: Icons.location_on_outlined,
                          style: PillStyle.primary,
                        ),
                    ],
                  ),
                ),
                if (provider.portfolio.isNotEmpty)
                  DetailSection(
                    title: 'Portfolio',
                    child: _PortfolioGrid(
                      images: provider.portfolio,
                      onOpen: (i) => _openPortfolio(context, i),
                    ),
                  ),
                DetailSection(
                  title: 'Sharhlar',
                  trailing: RatingLabel(
                    rating: provider.rating,
                    count: provider.reviewCount,
                  ),
                  child: provider.reviews.isEmpty
                      ? Text('Hali sharhlar yo‘q', style: text.bodySmall)
                      : Column(
                          children: [
                            for (final review in provider.reviews)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.md,
                                ),
                                child: _ReviewCard(review: review, now: now),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                const SafetyTipsCard(
                  tips: [
                    'Ish hajmi va narxni oldindan kelishib oling.',
                    'To‘liq to‘lovni ish tugagach qiling.',
                    'Ish tugagach, ustaga sharh qoldiring.',
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: StickyActionBar(
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: palette.success),
            onPressed: () => showContactSheet(
              context,
              person: profile,
              loadPhone: () =>
                  ref.read(servicesRepositoryProvider).revealPhone(provider.id),
            ),
            icon: const Icon(Icons.call_rounded),
            label: const Text('Qo‘ng‘iroq'),
          ),
          FilledButton.icon(
            onPressed: () => startChat(
              context,
              ref,
              peer: profile,
              subject: ConversationContext(
                subject: ConversationSubject.service,
                refId: provider.id,
                title: '${provider.name} — ${provider.profession}',
                subtitle: provider.priceFrom == null
                    ? null
                    : '${Formatters.money(provider.priceFrom!)} dan',
                image: profile.avatar,
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

class _PortfolioGrid extends StatelessWidget {
  const _PortfolioGrid({required this.images, required this.onOpen});

  final List<MediaImage> images;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 480 ? 4 : 3;
        final size =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (index, image) in images.indexed)
              Semantics(
                button: true,
                label: 'Portfolio rasmi ${index + 1}',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onOpen(index),
                  child: SizedBox.square(
                    dimension: size,
                    child: AppImage(
                      image: image,
                      borderRadius: AppRadii.mdAll,
                      placeholderIcon: Icons.handyman_outlined,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.now});

  final Review review;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                name: review.authorName,
                image: review.authorAvatar,
                size: 32,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(review.authorName, style: text.titleSmall)),
              Semantics(
                label: '${review.rating} yulduz',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Icon(
                        i < review.rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 16,
                        color: const Color(0xFFF5B400),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(review.text, style: text.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            Formatters.relativeTime(review.createdAt, now),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
