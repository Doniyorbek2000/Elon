import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/common.dart';
import '../../settings/application/settings_controller.dart';

/// Single-screen onboarding: brand, promise, the three verticals, one CTA.
/// Understandable in ~5 seconds; no carousel to swipe through.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _entrance.value = 1;
    } else if (_entrance.status == AnimationStatus.dismissed) {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Widget _staggered(int index, Widget child) {
    final start = (index * 0.1).clamp(0.0, 0.6);
    final animation = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, start + 0.4, curve: AppMotion.standard),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(animation),
        child: child,
      ),
    );
  }

  Future<void> _start() async {
    unawaited(HapticFeedback.mediumImpact());
    final router = GoRouter.of(context);
    router.go(AppRoutes.locationPicker(onboarding: true));
    await ref.read(onboardingCompletedProvider.notifier).complete();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillars = [
      (Icons.storefront_rounded, tr('E’lonlar'), tr('Sotish va sotib olish'), AccentTone.orange),
      (Icons.work_rounded, tr('Ish'), tr('Yaqin joydagi ishlar'), AccentTone.indigo),
      (Icons.handyman_rounded, tr('Xizmatlar'), tr('Ustalar va xizmatlar'), AccentTone.blue),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: LandscapeBackdrop()),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppBreakpoints.formMaxWidth),
                  child: CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                          child: Column(
                            children: [
                              const SizedBox(height: AppSpacing.huge),
                              _staggered(0, const BrandMark(size: 84)),
                              const SizedBox(height: AppSpacing.lg),
                              _staggered(1, const Wordmark()),
                              const SizedBox(height: AppSpacing.sm),
                              _staggered(
                                2,
                                Text(
                                  tr('Hududingizdagi hamma narsa\nbitta ilovada'),
                                  textAlign: TextAlign.center,
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? palette.textSecondary : const Color(0xFF1E2A4A),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const SizedBox(height: AppSpacing.xxxl),
                              for (final (index, (icon, title, subtitle, tone)) in pillars.indexed) ...[
                                _staggered(
                                  3 + index,
                                  _PillarCard(icon: icon, title: title, subtitle: subtitle, tone: tone),
                                ),
                                const SizedBox(height: AppSpacing.md),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              _staggered(
                                6,
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _start,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(AppTouch.buttonHeight + 4),
                                      shape: const StadiumBorder(),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(tr('Boshlash')),
                                        const SizedBox(width: AppSpacing.sm),
                                        const Icon(Icons.arrow_forward_rounded, size: AppIconSize.md),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                tr('Bepul. Ro‘yxatdan o‘tmasdan ko‘rishingiz mumkin.'),
                                textAlign: TextAlign.center,
                                style: text.bodySmall,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillarCard extends StatelessWidget {
  const _PillarCard({required this.icon, required this.title, required this.subtitle, required this.tone});

  final IconData icon;
  final String title;
  final String subtitle;
  final AccentTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.9 : 0.94),
          borderRadius: AppRadii.lgAll,
          border: Border.all(color: palette.border.withValues(alpha: 0.7)),
          boxShadow: AppShadows.card(palette, dark: Theme.of(context).brightness == Brightness.dark),
        ),
        child: Row(
          children: [
            ToneIcon(icon: icon, tone: tone),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
