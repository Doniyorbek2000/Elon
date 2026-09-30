import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/sharing/share_service.dart';
import '../../../core/sharing/share_sheet.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paged_sliver.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../listings/domain/listing_query.dart';
import '../../listings/presentation/widgets/listing_feed_slivers.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../../trust_safety/presentation/report_sheet.dart';
import '../application/profile_providers.dart';

/// Public seller / business storefront: trust signals + active listings.
class SellerProfileScreen extends ConsumerWidget {
  const SellerProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(publicProfileProvider(userId))
        .when(
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(),
            body: FailureView(error: error, onRetry: () => ref.invalidate(publicProfileProvider(userId))),
          ),
          data: (profile) => _SellerView(profile: profile),
        );
  }
}

class _SellerView extends ConsumerWidget {
  const _SellerView({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final now = ref.watch(clockProvider)();
    final isMe = ref.watch(sessionProvider)?.id == profile.id;
    final gutter = adaptiveGutter(context);
    final business = profile.accountType == AccountType.business;

    return Scaffold(
      appBar: AppBar(
        title: Text(business ? tr('Do‘kon') : tr('Sotuvchi')),
        actions: [
          IconButton(
            tooltip: tr('Ulashish'),
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => showShareSheet(
              context,
              SharePayload(
                target: ShareTarget.seller,
                id: profile.id,
                title: tr('{name} — Bozor.uz', {'name': profile.name}),
                subtitle: tr('{activeListings} ta e’lon', {'activeListings': profile.activeListings}),
                image: profile.avatar,
                url: ref.read(deepLinksProvider).web(ShareTarget.seller, profile.id),
              ),
            ),
          ),
          if (!isMe)
            PopupMenuButton<String>(
              tooltip: tr('Ko‘proq'),
              onSelected: (value) {
                if (value == 'report') showReportSheet(context, type: ReportTargetType.user, targetId: profile.id);
                if (value == 'block') confirmAndBlock(context, ref, userId: profile.id, name: profile.name);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'report', child: Text(tr('Shikoyat qilish'))),
                PopupMenuItem(value: 'block', child: Text(tr('Bloklash'))),
              ],
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpacing.lg, gutter, AppSpacing.md),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  AppAvatar(name: profile.name, image: profile.avatar, size: 88, isOnline: profile.isOnline),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(profile.name, style: text.titleLarge, textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      VerifiedBadge(level: profile.verification, size: 20),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    Formatters.presence(isOnline: profile.isOnline, lastActiveAt: profile.lastActiveAt, now: now),
                    style: text.bodySmall?.copyWith(color: profile.isOnline ? palette.success : null),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  profile.verification.isVerified
                      ? VerifiedBadge(level: profile.verification, showLabel: true)
                      : StatusPill(label: tr('Tasdiqlanmagan'), icon: Icons.info_outline_rounded),
                  const SizedBox(height: AppSpacing.xl),
                  SurfaceCard(
                    color: palette.surfaceMuted,
                    borderColor: Colors.transparent,
                    child: Wrap(
                      alignment: WrapAlignment.spaceAround,
                      spacing: AppSpacing.lg,
                      runSpacing: AppSpacing.md,
                      children: [
                        InfoTile(
                          label: tr('A’zo'),
                          value: tr('{p0} dan', {'p0': Formatters.monthYear(profile.memberSince)}),
                        ),
                        InfoTile(label: tr('Faol e’lonlar'), value: '${profile.activeListings}'),
                        if (profile.rating != null)
                          InfoTile(
                            label: tr('Reyting'),
                            value: '★ ${profile.rating!.toStringAsFixed(1)} (${profile.reviewCount})',
                          ),
                        if (profile.responseRate != null)
                          InfoTile(label: tr('Javob beradi'), value: '${(profile.responseRate! * 100).round()}%'),
                        if (profile.responseTimeMinutes != null)
                          InfoTile(
                            label: tr('Javob vaqti'),
                            value: tr('~{responseTimeMinutes} daq', {
                              'responseTimeMinutes': profile.responseTimeMinutes,
                            }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SectionHeader(title: tr('E’lonlar')),
                  ),
                ],
              ),
            ),
          ),
          ListingFeedSlivers(
            query: ListingQuery(sellerId: profile.id),
            gutter: gutter,
            heroPrefix: 'seller-${profile.id}',
            empty: EmptyState(icon: Icons.inventory_2_outlined, title: tr('Faol e’lonlar yo‘q'), compact: true),
          ),
          const SliverSafeArea(
            top: false,
            sliver: SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
          ),
        ],
      ),
    );
  }
}
