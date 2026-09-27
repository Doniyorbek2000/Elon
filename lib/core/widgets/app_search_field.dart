import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_tokens.dart';
import 'badges.dart';

/// Pill search field with optional trailing filter button (with active count).
/// In [readOnly] mode the whole field is a button that opens search.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint = 'Nima qidiryapsiz?',
    this.readOnly = false,
    this.autofocus = false,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.onFilterTap,
    this.activeFilters = 0,
    this.onClear,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final bool readOnly;
  final bool autofocus;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onFilterTap;
  final int activeFilters;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final field = readOnly
        ? Semantics(
            button: true,
            label: hint,
            excludeSemantics: true,
            child: Material(
              color: palette.surfaceMuted,
              borderRadius: AppRadii.mdAll,
              child: InkWell(
                borderRadius: AppRadii.mdAll,
                onTap: onTap,
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppTouch.inputHeight,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: palette.textTertiary,
                        size: AppIconSize.md,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : controller == null
        ? _input(showClear: false)
        : ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller!,
            builder: (context, value, _) =>
                _input(showClear: value.text.isNotEmpty),
          );

    if (onFilterTap == null) return field;
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: AppSpacing.sm),
        CountBadge(
          count: activeFilters,
          child: Material(
            color: activeFilters > 0
                ? palette.primarySoft
                : palette.surfaceMuted,
            borderRadius: AppRadii.mdAll,
            child: InkWell(
              borderRadius: AppRadii.mdAll,
              onTap: onFilterTap,
              child: SizedBox.square(
                dimension: AppTouch.inputHeight,
                child: Icon(
                  Icons.tune_rounded,
                  semanticLabel: 'Filtrlar',
                  color: activeFilters > 0
                      ? palette.primary
                      : palette.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _input({required bool showClear}) => TextField(
    controller: controller,
    focusNode: focusNode,
    autofocus: autofocus,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: !showClear
          ? null
          : IconButton(
              tooltip: 'Tozalash',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                controller?.clear();
                onChanged?.call('');
                onClear?.call();
              },
            ),
    ),
  );
}
