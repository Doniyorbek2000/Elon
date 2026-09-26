import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider) != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Chatlar'), centerTitle: false, automaticallyImplyLeading: false),
      body: !signedIn
          ? EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Chatlar uchun tizimga kiring',
              message: 'Sotuvchilar, ish beruvchilar va ustalar bilan xavfsiz yozishing.',
              actionLabel: 'Kirish',
              onAction: () => context.push(AppRoutes.verifyPhone),
            )
          : ref
                .watch(conversationsProvider)
                .when(
                  loading: () => Shimmer(
                    child: ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(
                        6,
                        (_) => const ListTile(
                          leading: SkeletonBox(width: 52, height: 52, radius: 26),
                          title: SkeletonLine(widthFactor: 0.5),
                          subtitle: Padding(
                            padding: EdgeInsets.only(top: AppSpacing.sm),
                            child: SkeletonLine(widthFactor: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(conversationsProvider)),
                  data: (conversations) => conversations.isEmpty
                      ? EmptyState(
                          icon: Icons.forum_outlined,
                          title: 'Hali chatlar yo‘q',
                          message: 'E’lon, vakansiya yoki usta sahifasidagi «Chat» tugmasi orqali yozing.',
                          actionLabel: 'E’lonlarni ko‘rish',
                          onAction: () => context.go(AppRoutes.home),
                        )
                      : ContentWidth(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                            itemCount: conversations.length,
                            separatorBuilder: (_, _) => const Divider(indent: 84),
                            itemBuilder: (_, index) => _ConversationTile(conversation: conversations[index]),
                          ),
                        ),
                ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final unread = conversation.unreadCount > 0;
    final context0 = conversation.context;

    return Semantics(
      button: true,
      label: [
        conversation.peer.name,
        if (context0 != null) context0.title,
        conversation.lastMessagePreview ?? '',
        if (unread) '${conversation.unreadCount} ta yangi xabar',
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push(AppRoutes.chat(conversation.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 56,
                child: Stack(
                  children: [
                    AppAvatar(
                      name: conversation.peer.name,
                      image: conversation.peer.avatar,
                      size: 52,
                      isOnline: conversation.peer.isOnline,
                    ),
                    if (context0?.image != null)
                      PositionedDirectional(
                        end: 0,
                        bottom: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: palette.surface, width: 2),
                          ),
                          child: AppImage(image: context0!.image, borderRadius: BorderRadius.circular(5)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  conversation.peer.name,
                                  style: text.titleSmall?.copyWith(
                                    fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              VerifiedBadge(level: conversation.peer.verification, size: 14),
                            ],
                          ),
                        ),
                        Text(
                          Formatters.chatStamp(conversation.updatedAt, now),
                          style: text.bodySmall?.copyWith(color: unread ? palette.primary : palette.textTertiary),
                        ),
                      ],
                    ),
                    if (context0 != null)
                      Text(
                        context0.title,
                        style: text.labelSmall?.copyWith(color: palette.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (conversation.isBlocked) ...[
                          Icon(Icons.block_rounded, size: 14, color: palette.danger),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Expanded(
                          child: Text(
                            conversation.isBlocked
                                ? 'Bloklangan'
                                : conversation.lastMessagePreview ?? 'Suhbatni boshlang',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: unread ? palette.textPrimary : palette.textSecondary,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: palette.primary, borderRadius: AppRadii.pillAll),
                            child: Text(
                              '${conversation.unreadCount}',
                              textAlign: TextAlign.center,
                              style: text.labelSmall?.copyWith(color: palette.onPrimary),
                            ),
                          ),
                        ],
                      ],
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
