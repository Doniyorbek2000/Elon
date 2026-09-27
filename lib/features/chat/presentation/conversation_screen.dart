import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_image.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/contact_sheet.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../create_listing/data/media_services.dart';
import '../../jobs/application/job_providers.dart';
import '../../listings/application/listing_providers.dart';
import '../../services/application/services_providers.dart';
import '../../trust_safety/application/trust_safety_providers.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../../trust_safety/presentation/report_sheet.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _input = TextEditingController();
  bool _safetyDismissed = false;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  DateTime? _typingSentAt;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(chatRepositoryProvider).markRead(widget.conversationId).ignore();
    });
  }

  @override
  void dispose() {
    _input
      ..removeListener(_onInputChanged)
      ..dispose();
    super.dispose();
  }

  /// Throttled typing signal: at most one event every 3 s while composing.
  void _onInputChanged() {
    final repository = ref.read(chatRepositoryProvider);
    if (_input.text.isEmpty) {
      if (_typingSentAt != null) repository.sendTyping(widget.conversationId, isTyping: false);
      _typingSentAt = null;
      return;
    }
    final now = DateTime.now();
    if (_typingSentAt == null || now.difference(_typingSentAt!) > const Duration(seconds: 3)) {
      _typingSentAt = now;
      repository.sendTyping(widget.conversationId, isTyping: true);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final more = await ref.read(chatRepositoryProvider).loadOlder(widget.conversationId);
      if (mounted) setState(() => _hasOlder = more);
    } on Object {
      // Offline: the user can scroll again to retry.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _retry(ChatMessage message) async {
    try {
      await ref.read(chatRepositoryProvider).retry(widget.conversationId, message);
    } on Object catch (error) {
      if (mounted) showAppSnack(context, error.asFailure().message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final guard = ref.read(messageGuardProvider(widget.conversationId));
    final now = ref.read(clockProvider)();
    final check = guard.check(text, now);
    if (check.verdict == MessageVerdict.throttle) {
      showAppSnack(context, check.message!, icon: Icons.timer_outlined);
      return;
    }
    if (check.verdict == MessageVerdict.warn) {
      final proceed = await confirmDialog(
        context,
        title: 'Ehtiyot bo‘ling',
        message: check.message!,
        confirmLabel: 'Baribir yuborish',
      );
      if (!proceed || !mounted) return;
    }
    guard.recordSent(now);
    _input.clear();
    unawaited(HapticFeedback.lightImpact());
    try {
      await ref.read(chatRepositoryProvider).sendText(widget.conversationId, text);
    } on Object {
      if (!mounted) return;
      _input.text = text;
      showAppSnack(context, 'Xabar yuborilmadi. Qayta urinib ko‘ring.', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _sendPhoto() async {
    try {
      final paths = await ref.read(photoPickerProvider).pickFromGallery(limit: 1);
      if (paths.isEmpty) return;
      await ref
          .read(chatRepositoryProvider)
          .sendImage(
            widget.conversationId,
            MediaImage.local('chat_${DateTime.now().microsecondsSinceEpoch}', paths.first),
          );
    } on Object {
      if (mounted) showAppSnack(context, 'Rasm yuborilmadi');
    }
  }

  void _openContext(ConversationContext subject) {
    final route = switch (subject.subject) {
      ConversationSubject.listing => AppRoutes.listing(subject.refId),
      ConversationSubject.job =>
        subject.refId.startsWith('cv_') ? AppRoutes.candidate(subject.refId) : AppRoutes.job(subject.refId),
      ConversationSubject.candidate => AppRoutes.candidate(subject.refId),
      ConversationSubject.service => AppRoutes.provider(subject.refId),
      ConversationSubject.direct => null,
    };
    if (route != null) context.push(route);
  }

  /// Phone numbers are released per context (the peer's own privacy setting
  /// is enforced server-side); there is no generic "user phone" endpoint.
  Future<String> _revealPeerPhone(Conversation conversation) {
    final subject = conversation.context;
    return switch (subject?.subject) {
      ConversationSubject.listing => ref.read(listingRepositoryProvider).revealPhone(subject!.refId),
      ConversationSubject.job => ref.read(jobRepositoryProvider).revealJobPhone(subject!.refId),
      ConversationSubject.candidate => ref.read(jobRepositoryProvider).revealCandidatePhone(subject!.refId),
      ConversationSubject.service => ref.read(servicesRepositoryProvider).revealPhone(subject!.refId),
      _ => Future.error(const NotFoundFailure('Raqam yashirilgan. Chat orqali yozing.')),
    };
  }

  Future<void> _toggleBlock(Conversation conversation) async {
    if (conversation.isBlocked) {
      await ref.read(chatRepositoryProvider).setBlocked(conversation.id, blocked: false);
      await ref.read(blockedUsersProvider.notifier).unblock(conversation.peer.id);
      return;
    }
    final blocked = await confirmAndBlock(context, ref, userId: conversation.peer.id, name: conversation.peer.name);
    if (blocked) await ref.read(chatRepositoryProvider).setBlocked(conversation.id, blocked: true);
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(conversationProvider(widget.conversationId));
    return conversation.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: FailureView(error: error),
      ),
      data: _buildConversation,
    );
  }

  Widget _buildConversation(Conversation conversation) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final typing = ref.watch(peerTypingProvider(conversation.id)).value ?? false;
    final messages = ref.watch(messagesProvider(conversation.id));
    final peer = conversation.peer;
    final status = typing
        ? 'yozmoqda…'
        : Formatters.presence(isOnline: peer.isOnline, lastActiveAt: peer.lastActiveAt, now: now);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: InkWell(
          borderRadius: AppRadii.mdAll,
          onTap: () => context.push(AppRoutes.seller(peer.id)),
          child: Row(
            children: [
              AppAvatar(name: peer.name, image: peer.avatar, size: 40, isOnline: peer.isOnline),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peer.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        status,
                        style: text.bodySmall?.copyWith(color: typing || peer.isOnline ? palette.success : null),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Qo‘ng‘iroq',
            icon: Icon(Icons.call_rounded, color: palette.primary),
            onPressed: () => showContactSheet(context, person: peer, loadPhone: () => _revealPeerPhone(conversation)),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ko‘proq',
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  context.push(AppRoutes.seller(peer.id));
                case 'block':
                  _toggleBlock(conversation);
                case 'report':
                  showReportSheet(context, type: ReportTargetType.conversation, targetId: conversation.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'profile', child: Text('Profilni ko‘rish')),
              PopupMenuItem(value: 'block', child: Text(conversation.isBlocked ? 'Blokdan chiqarish' : 'Bloklash')),
              const PopupMenuItem(value: 'report', child: Text('Shikoyat qilish')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (conversation.context != null) _ContextCard(subject: conversation.context!, onTap: _openContext),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  FailureView(error: error, onRetry: () => ref.invalidate(messagesProvider(conversation.id))),
              data: (items) => _MessageList(
                messages: items,
                myId: ref.watch(sessionProvider)?.id ?? '',
                typing: typing,
                showSafety: !_safetyDismissed && items.length < 8,
                onDismissSafety: () => setState(() => _safetyDismissed = true),
                loadingOlder: _loadingOlder,
                onLoadOlder: _loadOlder,
                onRetry: _retry,
              ),
            ),
          ),
          if (conversation.isBlocked)
            _BlockedBar(onUnblock: () => _toggleBlock(conversation))
          else
            _Composer(controller: _input, onSend: _send, onAttach: _sendPhoto),
        ],
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.subject, required this.onTap});

  final ConversationContext subject;
  final ValueChanged<ConversationContext> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Material(
      color: palette.surface,
      child: InkWell(
        onTap: () => onTap(subject),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 48,
                child: AppImage(
                  image: subject.image,
                  borderRadius: AppRadii.smAll,
                  placeholderIcon: switch (subject.subject) {
                    ConversationSubject.job => Icons.work_outline_rounded,
                    ConversationSubject.service => Icons.handyman_outlined,
                    _ => Icons.sell_outlined,
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.title, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subject.subtitle != null)
                      Text(
                        subject.subtitle!,
                        style: text.labelMedium?.copyWith(color: palette.price, fontWeight: FontWeight.w800),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

sealed class _Row {}

class _DayRow extends _Row {
  _DayRow(this.label);

  final String label;
}

class _MessageRow extends _Row {
  _MessageRow(this.message, {required this.isMine, required this.groupedWithNext});

  final ChatMessage message;
  final bool isMine;
  final bool groupedWithNext;
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.messages,
    required this.myId,
    required this.typing,
    required this.showSafety,
    required this.onDismissSafety,
    required this.loadingOlder,
    required this.onLoadOlder,
    required this.onRetry,
  });

  final List<ChatMessage> messages;
  final String myId;
  final bool typing;
  final bool showSafety;
  final VoidCallback onDismissSafety;
  final bool loadingOlder;
  final VoidCallback onLoadOlder;
  final ValueChanged<ChatMessage> onRetry;

  List<_Row> _rows(DateTime now) {
    final rows = <_Row>[];
    DateTime? day;
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final messageDay = DateTime(message.sentAt.year, message.sentAt.month, message.sentAt.day);
      if (day != messageDay) {
        rows.add(_DayRow(Formatters.dayLabel(message.sentAt, now)));
        day = messageDay;
      }
      final next = i + 1 < messages.length ? messages[i + 1] : null;
      rows.add(
        _MessageRow(
          message,
          isMine: message.senderId == myId,
          groupedWithNext:
              next != null && next.senderId == message.senderId && next.sentAt.difference(message.sentAt).inMinutes < 3,
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final rows = _rows(now).reversed.toList();
    final gutter = AppBreakpoints.pagePadding(context);
    final extra = (typing ? 1 : 0);

    // Reverse list: the oldest message is at the far end; nearing it loads
    // the previous page from the server.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) onLoadOlder();
        return false;
      },
      child: ListView.builder(
        reverse: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.md),
        itemCount: rows.length + extra + (showSafety ? 1 : 0) + (loadingOlder ? 1 : 0),
        itemBuilder: (context, index) {
          if (typing && index == 0) return const _TypingBubble();
          final rowIndex = index - extra;
          if (rowIndex == rows.length) {
            if (loadingOlder) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            return _SafetyBanner(onDismiss: onDismissSafety);
          }
          if (rowIndex > rows.length) return _SafetyBanner(onDismiss: onDismissSafety);
          return switch (rows[rowIndex]) {
            _DayRow(:final label) => _DaySeparator(label: label),
            final _MessageRow row => GestureDetector(
              onTap: row.isMine && row.message.delivery == DeliveryState.failed ? () => onRetry(row.message) : null,
              child: _Bubble(message: row.message, isMine: row.isMine, grouped: row.groupedWithNext),
            ),
          };
        },
      ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: context.palette.surfaceMuted, borderRadius: AppRadii.pillAll),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.palette.textSecondary),
        ),
      ),
    ),
  );
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, 0, AppSpacing.sm),
      decoration: BoxDecoration(color: palette.warningSoft, borderRadius: AppRadii.mdAll),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: palette.warning, size: AppIconSize.md),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Oldindan to‘lov qilmang va karta ma’lumotlarini yubormang. Shubhali xabarlar haqida xabar bering.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textPrimary),
            ),
          ),
          IconButton(
            tooltip: 'Yopish',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: AppIconSize.sm),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isMine, required this.grouped});

  final ChatMessage message;
  final bool isMine;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final background = isMine ? palette.primary : palette.surface;
    final foreground = isMine ? palette.onPrimary : palette.textPrimary;
    final meta = isMine ? palette.onPrimary.withValues(alpha: 0.75) : palette.textTertiary;
    const radius = Radius.circular(AppRadii.lg);
    const tail = Radius.circular(AppRadii.xs);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;

    final (tickIcon, tickLabel) = switch (message.delivery) {
      DeliveryState.sending => (Icons.schedule_rounded, 'yuborilmoqda'),
      DeliveryState.sent => (Icons.check_rounded, 'yuborildi'),
      DeliveryState.delivered => (Icons.done_all_rounded, 'yetkazildi'),
      DeliveryState.read => (Icons.done_all_rounded, 'o‘qildi'),
      DeliveryState.failed => (Icons.error_outline_rounded, 'yuborilmadi'),
    };

    final footer = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Formatters.clock(message.sentAt),
          style: text.labelSmall?.copyWith(color: meta, fontWeight: FontWeight.w500, fontSize: 10.5),
        ),
        if (isMine) ...[
          const SizedBox(width: 3),
          Icon(tickIcon, size: 14, color: message.delivery == DeliveryState.read ? const Color(0xFF7DD3FC) : meta),
        ],
      ],
    );

    return Semantics(
      label:
          '${isMine ? 'Siz' : 'Suhbatdosh'}: ${message.preview}, ${Formatters.clock(message.sentAt)}${isMine ? ', $tickLabel' : ''}',
      excludeSemantics: true,
      child: Align(
        alignment: isMine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Container(
          margin: EdgeInsets.only(bottom: grouped ? 3 : AppSpacing.sm),
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: message.kind == MessageKind.image
              ? const EdgeInsets.all(AppSpacing.xs)
              : const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm - 2),
          decoration: BoxDecoration(
            color: background,
            border: isMine ? null : Border.all(color: palette.border),
            borderRadius: BorderRadiusDirectional.only(
              topStart: radius,
              topEnd: radius,
              bottomStart: isMine || grouped ? radius : tail,
              bottomEnd: isMine && !grouped ? tail : radius,
            ).resolve(Directionality.of(context)),
          ),
          child: message.kind == MessageKind.image
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: AppImage(image: message.image, borderRadius: BorderRadius.circular(AppRadii.md)),
                    ),
                    Padding(padding: const EdgeInsets.fromLTRB(0, 4, 6, 2), child: footer),
                  ],
                )
              : Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: AppSpacing.sm,
                  children: [
                    Text(message.text ?? '', style: text.bodyMedium?.copyWith(color: foreground)),
                    Padding(padding: const EdgeInsets.only(top: 4), child: footer),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.reduced(context) && !_controller.isAnimating) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: 'Suhbatdosh yozmoqda',
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.border),
            borderRadius: AppRadii.lgAll,
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.textTertiary.withValues(
                        alpha: 0.35 + 0.65 * (1 - ((_controller.value * 3 - i) % 3 - 0.5).abs().clamp(0.0, 1.0)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend, required this.onAttach});

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(tooltip: 'Rasm yuborish', onPressed: onAttach, icon: const Icon(Icons.attach_file_rounded)),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: 'Xabar yozing...',
                    border: OutlineInputBorder(borderRadius: AppRadii.xlAll, borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: AppRadii.xlAll, borderSide: BorderSide.none),
                    contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final enabled = value.text.trim().isNotEmpty;
                  return AnimatedScale(
                    duration: AppMotion.of(context, AppMotion.fast),
                    scale: enabled ? 1 : 0.9,
                    child: IconButton.filled(
                      tooltip: 'Yuborish',
                      onPressed: enabled ? onSend : null,
                      style: IconButton.styleFrom(
                        backgroundColor: palette.primary,
                        disabledBackgroundColor: palette.border,
                        minimumSize: const Size(AppTouch.minTarget, AppTouch.minTarget),
                      ),
                      icon: Icon(Icons.send_rounded, color: enabled ? palette.onPrimary : palette.textTertiary),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedBar extends StatelessWidget {
  const _BlockedBar({required this.onUnblock});

  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.block_rounded, color: palette.danger),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: Text('Siz bu foydalanuvchini bloklagansiz')),
              TextButton(onPressed: onUnblock, child: const Text('Blokdan chiqarish')),
            ],
          ),
        ),
      ),
    );
  }
}
