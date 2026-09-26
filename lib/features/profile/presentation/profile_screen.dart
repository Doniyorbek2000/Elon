import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/auth.dart';
import '../../chat/application/chat_providers.dart';
import '../../listings/application/listing_providers.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../saved/application/saved_items_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Sozlamalar',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push(AppRoutes.settings),
        ),
        title: const Text('Profil'),
        actions: [
          IconButton(
            tooltip: 'Bildirishnomalar',
            onPressed: () => context.push(AppRoutes.notifications),
            icon: CountBadge(count: unread, child: const Icon(Icons.notifications_none_rounded)),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxxl),
          children: [
            if (user == null) const _GuestCard() else _UserHeader(user: user),
            const SizedBox(height: AppSpacing.xl),
            _Menu(signedIn: user != null),
          ],
        ),
      ),
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const BrandMark(size: 56),
          const SizedBox(height: AppSpacing.md),
          Text('Bozor.uz’ga xush kelibsiz', style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'E’lon joylash, chat va ariza topshirish uchun telefon raqamingiz bilan kiring.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => context.push(AppRoutes.verifyPhone), child: const Text('Kirish')),
          ),
        ],
      ),
    );
  }
}

class _UserHeader extends ConsumerWidget {
  const _UserHeader({required this.user});

  final CurrentUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final myListings = ref.watch(sellerListingsProvider(user.id)).value ?? const [];
    final savedCount = ref.watch(savedItemsProvider).length;
    final views = myListings.fold<int>(0, (sum, l) => sum + l.views);

    return Column(
      children: [
        Row(
          children: [
            AppAvatar(name: user.name, image: user.avatar, size: 76),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(user.name, style: text.titleLarge, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      VerifiedBadge(level: user.verification, size: 18),
                    ],
                  ),
                  Text('ID: ${user.displayId}', style: text.bodySmall),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      ActionChip(
                        label: const Text('Profilni tahrirlash'),
                        labelStyle: text.labelMedium?.copyWith(color: palette.primary),
                        backgroundColor: palette.primarySoft,
                        onPressed: () => context.push(AppRoutes.editProfile),
                      ),
                      if (!user.isPhoneVerified)
                        ActionChip(
                          avatar: Icon(Icons.warning_amber_rounded, size: 16, color: palette.warning),
                          label: const Text('Raqamni tasdiqlang'),
                          onPressed: () => context.push(AppRoutes.verifyPhone),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _Stat(
                  value: '${myListings.length}',
                  label: 'Mening e’lonlarim',
                  onTap: () => context.push(AppRoutes.myListings),
                ),
                VerticalDivider(color: palette.border),
                _Stat(value: '$savedCount', label: 'Saqlanganlar', onTap: () => context.push(AppRoutes.saved)),
                VerticalDivider(color: palette.border),
                _Stat(value: Formatters.compactCount(views), label: 'Ko‘rishlar'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Semantics(
        button: onTap != null,
        label: '$label: $value',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.mdAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Column(
              children: [
                Text(value, style: text.titleLarge),
                const SizedBox(height: 2),
                Text(label, style: text.bodySmall, textAlign: TextAlign.center, maxLines: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadChats = ref.watch(unreadChatsCountProvider);
    final palette = context.palette;
    final items = <(IconData, AccentTone, String, VoidCallback, int)>[
      if (signedIn)
        (Icons.list_alt_rounded, AccentTone.blue, 'Mening e’lonlarim', () => context.push(AppRoutes.myListings), 0),
      if (signedIn)
        (
          Icons.assignment_outlined,
          AccentTone.teal,
          'Mening arizalarim',
          () => context.push(AppRoutes.applications),
          0,
        ),
      (Icons.favorite_border_rounded, AccentTone.red, 'Saqlanganlar', () => context.push(AppRoutes.saved), 0),
      if (signedIn)
        (
          Icons.chat_bubble_outline_rounded,
          AccentTone.indigo,
          'Chatlar',
          () => context.go(AppRoutes.chats),
          unreadChats,
        ),
      (Icons.receipt_long_outlined, AccentTone.amber, 'To‘lovlar va tariflar', () => context.push(AppRoutes.plans), 0),
      (Icons.settings_outlined, AccentTone.slate, 'Sozlamalar', () => context.push(AppRoutes.settings), 0),
      (Icons.help_outline_rounded, AccentTone.green, 'Yordam', () => context.push(AppRoutes.help), 0),
    ];
    return Column(
      children: [
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (final (icon, tone, label, onTap, badge) in items)
                ListTile(
                  leading: ToneIcon(icon: icon, tone: tone, size: 36, radius: AppRadii.sm),
                  title: Text(label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (badge > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: palette.danger, borderRadius: AppRadii.pillAll),
                          child: Text(
                            '$badge',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
                          ),
                        ),
                      Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
                    ],
                  ),
                  onTap: onTap,
                ),
            ],
          ),
        ),
        if (signedIn) ...[
          const SizedBox(height: AppSpacing.lg),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: ListTile(
              leading: const ToneIcon(icon: Icons.logout_rounded, tone: AccentTone.red, size: 36, radius: AppRadii.sm),
              title: Text('Chiqish', style: TextStyle(color: palette.danger)),
              onTap: () async {
                final confirmed = await confirmDialog(
                  context,
                  title: 'Hisobdan chiqasizmi?',
                  message: 'Saqlangan e’lonlar va qoralamalar shu qurilmada qoladi.',
                  confirmLabel: 'Chiqish',
                  destructive: true,
                );
                if (confirmed) await ref.read(sessionProvider.notifier).signOut();
              },
            ),
          ),
        ],
      ],
    );
  }
}
