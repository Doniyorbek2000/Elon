import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../application/notifications_providers.dart';
import '../domain/app_notification.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Bildirishnomalar')),
        actions: [
          if (unread > 0)
            IconButton(
              tooltip: tr('Hammasini o‘qilgan deb belgilash'),
              onPressed: () => ref.read(notificationsProvider.notifier).markAllRead(),
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(notificationsProvider)),
        data: (paged) => paged.items.isEmpty
            ? EmptyState(
                icon: Icons.notifications_none_rounded,
                title: tr('Bildirishnomalar yo‘q'),
                message: tr('Yangi xabarlar va narx o‘zgarishlari shu yerda paydo bo‘ladi.'),
              )
            : RefreshIndicator.adaptive(
                onRefresh: () => ref.refresh(notificationsProvider.future),
                child: ContentWidth(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 400) {
                        ref.read(notificationsProvider.notifier).loadMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: paged.items.length + 1,
                      separatorBuilder: (_, _) => const Divider(indent: 72),
                      itemBuilder: (_, index) => index == paged.items.length
                          ? LoadMoreFooter(
                              isLoading: paged.isLoadingMore,
                              hasMore: paged.hasMore,
                              error: paged.loadMoreError,
                              onRetry: () => ref.read(notificationsProvider.notifier).loadMore(),
                            )
                          : _NotificationTile(notification: paged.items[index]),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final (icon, tone) = switch (notification.kind) {
      NotificationKind.message => (Icons.chat_bubble_rounded, AccentTone.blue),
      NotificationKind.priceDrop => (Icons.trending_down_rounded, AccentTone.green),
      NotificationKind.application => (Icons.assignment_turned_in_rounded, AccentTone.teal),
      NotificationKind.listingApproved => (Icons.verified_rounded, AccentTone.indigo),
      NotificationKind.system => (Icons.shield_rounded, AccentTone.amber),
    };
    return Material(
      color: notification.isRead ? Colors.transparent : palette.primarySoft.withValues(alpha: 0.5),
      child: InkWell(
        onTap: () {
          if (!notification.isRead) ref.read(notificationsProvider.notifier).markRead(notification.id).ignore();
          final link = notification.deepLink;
          if (link != null) context.push(link);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToneIcon(icon: icon, tone: tone, size: 42),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notification.title, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(notification.body, style: text.bodySmall?.copyWith(color: palette.textSecondary)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      Formatters.relativeTime(notification.createdAt, now),
                      style: text.labelSmall?.copyWith(color: palette.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
