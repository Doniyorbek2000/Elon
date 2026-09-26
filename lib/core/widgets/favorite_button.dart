import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/saved/application/saved_items_controller.dart';
import '../design/app_colors.dart';
import '../design/app_tokens.dart';

/// Heart toggle with a spring pop + haptic. Rebuilds only for its own item.
class FavoriteButton extends ConsumerStatefulWidget {
  const FavoriteButton({
    super.key,
    required this.kind,
    required this.id,
    this.onImage = false,
    this.size = AppIconSize.md,
  });

  final SavedKind kind;
  final String id;

  /// Draws a white circular backdrop for legibility over photos.
  final bool onImage;
  final double size;

  @override
  ConsumerState<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<FavoriteButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(vsync: this, duration: AppMotion.medium);
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 60),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _toggle() {
    final saved = ref.read(savedItemsProvider.notifier).toggle(widget.kind, widget.id);
    HapticFeedback.lightImpact();
    if (saved && !AppMotion.reduced(context)) _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(isSavedProvider((widget.kind, widget.id)));
    final palette = context.palette;
    final icon = ScaleTransition(
      scale: _scale,
      child: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.fast),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: Icon(
          saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(saved),
          size: widget.size,
          color: saved ? palette.danger : (widget.onImage ? palette.textPrimary : palette.textTertiary),
        ),
      ),
    );
    return Semantics(
      button: true,
      toggled: saved,
      label: saved ? 'Saqlanganlardan olib tashlash' : 'Saqlash',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: AppTouch.minTarget,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: _toggle,
            radius: AppTouch.minTarget / 2,
            child: Center(
              child: widget.onImage
                  ? Container(
                      width: widget.size + 14,
                      height: widget.size + 14,
                      decoration: BoxDecoration(
                        color: palette.surface.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.floating(palette),
                      ),
                      child: Center(child: icon),
                    )
                  : icon,
            ),
          ),
        ),
      ),
    );
  }
}
