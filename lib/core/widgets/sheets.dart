import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_tokens.dart';

/// Opens a modal bottom sheet that respects safe areas, keyboard insets and
/// tablet widths (sheet is capped and centered on large screens).
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool expand = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: expand
          ? SizedBox(height: MediaQuery.sizeOf(context).height * 0.88, child: builder(context))
          : builder(context),
    ),
  );
}

/// Standard sheet layout: title row, scrollable body, pinned action bar.
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({super.key, required this.title, required this.body, this.actions, this.trailing});

  final String title;
  final Widget body;
  final Widget? actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.sm, AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
              ),
              ?trailing,
            ],
          ),
        ),
        Flexible(child: body),
        if (actions != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(top: BorderSide(color: palette.border)),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.sm),
                child: actions,
              ),
            ),
          ),
      ],
    );
  }
}

/// Bottom bar pinned above the gesture area with primary actions
/// (Qo‘ng‘iroq / Chat on detail pages).
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({super.key, required this.children});

  final List<Widget> children;

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
        minimum: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
          child: ContentRow(children: children),
        ),
      ),
    );
  }
}

class ContentRow extends StatelessWidget {
  const ContentRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // With very large text, side-by-side buttons would wrap labels; stack them.
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 24 && children.length > 1;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentMaxWidth),
        child: stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    children[i],
                  ],
                ],
              )
            : Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.md),
                    Expanded(child: children[i]),
                  ],
                ],
              ),
      ),
    );
  }
}
