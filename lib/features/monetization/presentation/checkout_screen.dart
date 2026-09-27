import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../application/monetization_providers.dart';
import '../domain/monetization.dart';

/// Opens the checkout flow for a server-validated request. Returns the
/// final purchase when it was activated (null otherwise).
Future<Purchase?> openCheckout(
  BuildContext context,
  CheckoutRequest request, {
  required String successTitle,
  String? successActionLabel,
  VoidCallback? onSuccessAction,
}) => Navigator.of(context).push<Purchase>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => CheckoutScreen(
      request: request,
      successTitle: successTitle,
      successActionLabel: successActionLabel,
      onSuccessAction: onSuccessAction,
    ),
  ),
);

/// Payment progress. It only mirrors the status the server reports — the
/// server activates the product after verifying the provider's callback.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.request,
    required this.successTitle,
    this.successActionLabel,
    this.onSuccessAction,
  });

  final CheckoutRequest request;
  final String successTitle;
  final String? successActionLabel;
  final VoidCallback? onSuccessAction;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Returning from the provider page: re-check immediately.
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(checkoutControllerProvider.notifier).refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(checkoutControllerProvider.notifier).start(widget.request);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _close() {
    final state = ref.read(checkoutControllerProvider);
    Navigator.of(context).pop(state.phase == CheckoutPhase.succeeded ? state.purchase : null);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkoutControllerProvider);
    final controller = ref.read(checkoutControllerProvider.notifier);
    final waiting = state.phase == CheckoutPhase.awaitingPayment;
    return PopScope(
      canPop: !waiting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && waiting) _confirmLeave(controller);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('To‘lov'),
          leading: IconButton(
            tooltip: 'Yopish',
            icon: const Icon(Icons.close_rounded),
            onPressed: waiting ? () => _confirmLeave(controller) : _close,
          ),
        ),
        body: ContentWidth(
          maxWidth: AppBreakpoints.formMaxWidth,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: switch (state.phase) {
              CheckoutPhase.idle || CheckoutPhase.starting => const _Status(
                icon: null,
                title: 'To‘lov tayyorlanmoqda',
                message: 'Narx va ma’lumotlar server tomonidan tekshirilmoqda…',
              ),
              CheckoutPhase.awaitingPayment => _Waiting(
                purchase: state.purchase,
                canReopen: state.redirect != null,
                onReopen: controller.reopenPayment,
                onCheck: controller.refresh,
                onCancel: () => _confirmLeave(controller),
              ),
              CheckoutPhase.succeeded => _Success(
                title: widget.successTitle,
                purchase: state.purchase,
                actionLabel: widget.successActionLabel,
                onAction: widget.onSuccessAction == null
                    ? null
                    : () {
                        _close();
                        widget.onSuccessAction!();
                      },
                onDone: _close,
              ),
              CheckoutPhase.review => _Status(
                icon: Icons.hourglass_top_rounded,
                title: 'To‘lov tekshirilmoqda',
                message:
                    'To‘lovingiz qabul qilindi, lekin qo‘shimcha tekshiruv talab qilinadi. '
                    'Natija bildirishnoma orqali yuboriladi. Pul yechilgan bo‘lsa va xizmat '
                    'faollashmasa, u qaytariladi.',
                primaryLabel: 'Yopish',
                onPrimary: _close,
              ),
              CheckoutPhase.failed => _Status(
                icon: Icons.error_outline_rounded,
                tone: _Tone.danger,
                title: 'To‘lov amalga oshmadi',
                message: state.failure?.message ?? 'Hech narsa faollashtirilmadi va pul yechilmadi.',
                primaryLabel: 'Qayta urinish',
                onPrimary: () => controller.start(widget.request),
                secondaryLabel: 'Yopish',
                onSecondary: _close,
              ),
              CheckoutPhase.cancelled => _Status(
                icon: Icons.block_rounded,
                title: 'To‘lov bekor qilindi',
                message: 'Hech narsa faollashtirilmadi.',
                primaryLabel: 'Yopish',
                onPrimary: _close,
              ),
              CheckoutPhase.unavailable => _Status(
                icon: Icons.storefront_outlined,
                title: 'Hozircha mavjud emas',
                message:
                    'Bu xizmatni hozircha ushbu qurilmada sotib olib bo‘lmaydi. '
                    'Imkoniyat yoqilganda sizga xabar beramiz.',
                primaryLabel: 'Yopish',
                onPrimary: _close,
              ),
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLeave(CheckoutController controller) async {
    final leave = await confirmDialog(
      context,
      title: 'To‘lov bekor qilinsinmi?',
      message: 'Agar to‘lovni allaqachon amalga oshirgan bo‘lsangiz, bekor qilmang — natija bir necha daqiqada keladi.',
      confirmLabel: 'Bekor qilish',
      destructive: true,
    );
    if (!leave || !mounted) return;
    await controller.cancel();
  }
}

enum _Tone { neutral, success, danger }

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.title,
    required this.message,
    this.tone = _Tone.neutral,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData? icon;
  final String title;
  final String message;
  final _Tone tone;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final (bg, fg) = switch (tone) {
      _Tone.success => (palette.successSoft, palette.success),
      _Tone.danger => (palette.dangerSoft, palette.danger),
      _Tone.neutral => (palette.primarySoft, palette.primary),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: icon == null
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: CircularProgressIndicator(strokeWidth: 3, color: fg),
                  )
                : Icon(icon, size: 44, color: fg),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(title, style: text.titleLarge, textAlign: TextAlign.center),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          style: text.bodyMedium?.copyWith(color: palette.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxl),
        if (primaryLabel != null) FilledButton(onPressed: onPrimary, child: Text(primaryLabel!)),
        if (secondaryLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
        ],
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.purchase,
    required this.canReopen,
    required this.onReopen,
    required this.onCheck,
    required this.onCancel,
  });

  final Purchase? purchase;
  final bool canReopen;
  final VoidCallback onReopen;
  final VoidCallback onCheck;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Status(
          icon: null,
          title: 'To‘lov kutilmoqda',
          message: 'To‘lov sahifasida to‘lovni yakunlang. Tasdiq kelishi bilan xizmat avtomatik faollashadi.',
        ),
        if (purchase != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SurfaceCard(
            child: Row(
              children: [
                Expanded(child: Text(purchase!.title, style: text.titleSmall)),
                Text(Formatters.money(purchase!.total.money), style: text.titleSmall?.copyWith(color: palette.price)),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (canReopen) FilledButton(onPressed: onReopen, child: const Text('To‘lov sahifasini ochish')),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(onPressed: onCheck, child: const Text('Holatni tekshirish')),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onCancel, child: const Text('Bekor qilish')),
      ],
    );
  }
}

class _Success extends ConsumerWidget {
  const _Success({required this.title, required this.purchase, required this.onDone, this.actionLabel, this.onAction});

  final String title;
  final Purchase? purchase;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final until = purchase?.activationExpiresAt ?? purchase?.subscriptionEnd;
    final starts = purchase?.activationStartsAt;
    final lines = [
      if (starts != null && starts.isAfter(now)) 'Boshlanish: ${Formatters.date(starts, now: now)}',
      if (until != null) 'Amal qiladi: ${Formatters.date(until, now: now)} gacha',
      if (purchase != null && purchase!.creditsUsed > 0) '${purchase!.creditsUsed} ta kredit ishlatildi',
      if (purchase != null && purchase!.creditsUsed == 0 && !purchase!.total.isZero)
        'To‘langan: ${Formatters.money(purchase!.total.money)}',
    ];
    return _Status(
      icon: Icons.check_circle_rounded,
      tone: _Tone.success,
      title: title,
      message: lines.isEmpty ? 'Xizmat faollashtirildi.' : lines.join('\n'),
      primaryLabel: actionLabel ?? 'Tayyor',
      onPrimary: onAction ?? onDone,
      secondaryLabel: actionLabel == null ? null : 'Yopish',
      onSecondary: onDone,
    );
  }
}
