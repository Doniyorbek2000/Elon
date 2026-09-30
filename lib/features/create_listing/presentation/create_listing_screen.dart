import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/sharing/share_service.dart';
import '../../../core/sharing/share_sheet.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/sheets.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../application/create_listing_controller.dart';
import '../domain/listing_draft.dart';
import 'steps/details_step.dart';
import 'steps/photos_step.dart';
import 'steps/review_step.dart';

class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key, this.initialCategoryId});

  final String? initialCategoryId;

  @override
  ConsumerState<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  Map<String, String> _errors = const {};
  bool _publishing = false;
  PublishedItem? _published;

  CreateListingController get _controller => ref.read(createListingProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final draft = ref.read(createListingProvider);
      if (widget.initialCategoryId != null && draft.categoryId == null) {
        _controller.setCategory(widget.initialCategoryId!);
      }
      if (draft.restored && draft.hasContent) {
        _controller.acknowledgeRestore();
        showAppSnack(
          context,
          tr('Qoralama tiklandi'),
          icon: Icons.restore_rounded,
          action: SnackBarAction(label: tr('Yangidan'), onPressed: () => _controller.discard()),
        );
      }
    });
  }

  void _next() {
    FocusScope.of(context).unfocus();
    final errors = _controller.next();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.heavyImpact();
      showAppSnack(context, errors.values.first, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _publish() async {
    final errors = _controller.validate(CreateStep.review);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      _controller.goTo(errors.containsKey(DraftField.photos) ? CreateStep.photos : CreateStep.details);
      showAppSnack(context, errors.values.first, icon: Icons.error_outline_rounded);
      return;
    }
    if (_controller.riskSignals().any((s) => s.severity == RiskSeverity.blocking)) {
      showAppSnack(context, tr('E’londan karta raqamini olib tashlang'), icon: Icons.gpp_bad_outlined);
      return;
    }
    if (ref.read(createListingProvider).uploadsPending) {
      showAppSnack(context, tr('Rasmlar yuklanmoqda, biroz kuting…'), icon: Icons.cloud_upload_outlined);
      return;
    }
    setState(() => _publishing = true);
    try {
      final item = await _controller.publish();
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(() {
        _publishing = false;
        _published = item;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _publishing = false);
      final failure = error.asFailure();
      showAppSnack(context, failure.message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _close() async {
    final draft = ref.read(createListingProvider);
    if (_published != null || !draft.hasContent) {
      if (mounted) _leave();
      return;
    }
    final choice = await showAppSheet<_CloseChoice>(
      context,
      builder: (context) => SheetScaffold(
        title: tr('Chiqishdan oldin'),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
          child: Text(
            tr('Kiritgan ma’lumotlaringiz qoralama sifatida saqlanadi. Keyin davom ettirishingiz mumkin.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        actions: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => Navigator.pop(context, _CloseChoice.save),
              child: Text(tr('Saqlash va chiqish')),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: context.palette.danger),
              onPressed: () => Navigator.pop(context, _CloseChoice.discard),
              child: Text(tr('Qoralamani o‘chirish')),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _CloseChoice.discard) {
      await _controller.discard();
    } else {
      await _controller.saveNow();
    }
    if (mounted) _leave();
  }

  /// Opened from a deep link there may be nothing underneath to pop to.
  void _leave() => context.canPop() ? context.pop() : context.go(AppRoutes.home);

  @override
  Widget build(BuildContext context) {
    final published = _published;
    if (published != null) return _PublishedView(item: published);

    final step = ref.watch(createListingProvider.select((d) => d.step));
    final isLast = step == CreateStep.review;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (step.index > 0) {
          _controller.back();
        } else {
          _close();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: tr('Yopish'), icon: const Icon(Icons.close_rounded), onPressed: _close),
          title: Text(tr('Yangi e’lon')),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(76),
            child: _StepIndicator(current: step, onTap: _controller.goTo),
          ),
        ),
        body: ContentWidth(
          maxWidth: AppBreakpoints.formMaxWidth + 80,
          child: AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.medium),
            switchInCurve: AppMotion.standard,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(step),
              child: switch (step) {
                CreateStep.details => DetailsStep(errors: _errors),
                CreateStep.photos => PhotosStep(errors: _errors),
                CreateStep.review => const ReviewStep(),
              },
            ),
          ),
        ),
        bottomNavigationBar: StickyActionBar(
          children: [
            if (step.index > 0)
              OutlinedButton(onPressed: _publishing ? null : _controller.back, child: Text(tr('Orqaga'))),
            FilledButton(
              onPressed: _publishing ? null : (isLast ? _publish : _next),
              child: _publishing
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            isLast ? tr('E’lonni joylash') : tr('Davom etish'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(isLast ? Icons.check_rounded : Icons.arrow_forward_rounded, size: AppIconSize.md),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CloseChoice { save, discard }

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.onTap});

  final CreateStep current;
  final ValueChanged<CreateStep> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in CreateStep.values) ...[
            if (step.index > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: AnimatedContainer(
                    duration: AppMotion.of(context, AppMotion.medium),
                    height: 2,
                    color: step.index <= current.index ? palette.primary : palette.border,
                  ),
                ),
              ),
            Semantics(
              label: tr('{p0}-qadam: {label}{p2}', {
                'p0': step.index + 1,
                'label': step.label,
                'p2': step == current ? tr(', joriy') : '',
              }),
              button: step.index < current.index,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: step.index < current.index ? () => onTap(step) : null,
                child: SizedBox(
                  width: 84,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: AppMotion.of(context, AppMotion.medium),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: step.index <= current.index ? palette.primary : palette.surface,
                          border: Border.all(
                            color: step.index <= current.index ? palette.primary : palette.borderStrong,
                            width: 1.5,
                          ),
                          boxShadow: step == current ? AppShadows.primaryGlow(palette.primary) : null,
                        ),
                        child: Center(
                          child: step.index < current.index
                              ? Icon(Icons.check_rounded, size: 18, color: palette.onPrimary)
                              : Text(
                                  '${step.index + 1}',
                                  textScaler: TextScaler.noScaling,
                                  style: text.labelMedium?.copyWith(
                                    color: step == current ? palette.onPrimary : palette.textSecondary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        step.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
                        style: text.labelSmall?.copyWith(
                          color: step == current ? palette.textPrimary : palette.textSecondary,
                          fontWeight: step == current ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Celebration + next actions after publishing; the share CTA feeds the
/// Telegram growth loop.
class _PublishedView extends ConsumerStatefulWidget {
  const _PublishedView({required this.item});

  final PublishedItem item;

  @override
  ConsumerState<_PublishedView> createState() => _PublishedViewState();
}

class _PublishedViewState extends ConsumerState<_PublishedView> with SingleTickerProviderStateMixin {
  late final AnimationController _check = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _check.value = 1;
    } else if (_check.isDismissed) {
      _check.forward();
    }
  }

  @override
  void dispose() {
    _check.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final pending = item.pendingReview;
    final color = pending ? palette.warning : palette.success;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppBreakpoints.formMaxWidth),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: CurvedAnimation(parent: _check, curve: Curves.elasticOut),
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: pending ? palette.warningSoft : palette.successSoft,
                      ),
                      child: Icon(
                        pending ? Icons.hourglass_top_rounded : Icons.check_rounded,
                        size: 56,
                        color: color,
                        semanticLabel: pending ? tr('Tekshiruvga yuborildi') : tr('Joylandi'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    pending ? tr('E’lon tekshiruvga yuborildi') : tr('E’loningiz joylandi!'),
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    pending
                        ? tr('Moderator tekshiruvidan so‘ng e’lon hammaga ko‘rinadi. Sizga bildirishnoma yuboramiz.')
                        : tr('Ko‘proq xaridor topish uchun e’lonni Telegram guruhlaringizda ulashing.'),
                    style: text.bodyMedium?.copyWith(color: palette.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF229ED9)),
                      onPressed: () => showShareSheet(
                        context,
                        SharePayload(
                          target: item.target,
                          id: item.id,
                          title: item.title,
                          subtitle: item.subtitle?.replaceAll('\u00A0', ' '),
                          location: item.place.shortLabel,
                          image: item.image,
                          url: ref.read(deepLinksProvider).web(item.target, item.id),
                        ),
                      ),
                      icon: const Icon(Icons.send_rounded),
                      label: Text(tr('Telegram’da ulashish')),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => context.pushReplacement(
                        item.target == ShareTarget.job ? AppRoutes.job(item.id) : AppRoutes.listing(item.id),
                      ),
                      child: Text(item.target == ShareTarget.job ? tr('Vakansiyani ko‘rish') : tr('E’lonni ko‘rish')),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(onPressed: () => context.go(AppRoutes.home), child: Text(tr('Bosh sahifaga qaytish'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
