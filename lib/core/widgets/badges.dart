import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_tokens.dart';
import '../domain/promotion.dart';
import '../domain/public_profile.dart';

/// Rendered only for server-asserted verification — never inferred locally.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({
    super.key,
    required this.level,
    this.size = 16,
    this.showLabel = false,
  });

  final VerificationLevel level;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (!level.isVerified) return const SizedBox.shrink();
    final palette = context.palette;
    final color = level == VerificationLevel.business
        ? palette.vip
        : palette.primary;
    final icon = Icon(
      level == VerificationLevel.business
          ? Icons.workspace_premium_rounded
          : Icons.verified_rounded,
      size: size,
      color: color,
    );
    if (!showLabel) {
      return Semantics(
        label: level.label,
        child: ExcludeSemantics(child: icon),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            level.label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

enum PillStyle { primary, success, warning, danger, vip, neutral }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.style = PillStyle.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final PillStyle style;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = switch (style) {
      PillStyle.primary => (p.primarySoft, p.primary),
      PillStyle.success => (p.successSoft, p.success),
      PillStyle.warning => (p.warningSoft, p.warning),
      PillStyle.danger => (p.dangerSoft, p.danger),
      PillStyle.vip => (p.vipSoft, p.vip),
      PillStyle.neutral => (p.surfaceMuted, p.textSecondary),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : AppSpacing.sm,
        vertical: dense ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadii.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: fg, fontSize: dense ? 10.5 : null),
            ),
          ),
        ],
      ),
    );
  }
}

class PromotionBadge extends StatelessWidget {
  const PromotionBadge({super.key, required this.type, this.dense = true});

  final PromotionType type;
  final bool dense;

  @override
  Widget build(BuildContext context) => StatusPill(
    label: type.badge,
    dense: dense,
    style: switch (type) {
      PromotionType.vip || PromotionType.premiumVacancy => PillStyle.vip,
      PromotionType.top || PromotionType.featured => PillStyle.warning,
      PromotionType.bump => PillStyle.primary,
    },
    icon: type == PromotionType.vip ? Icons.diamond_rounded : null,
  );
}

/// Small red counter for tabs/icons. Hidden at zero.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: context.palette.danger,
      label: Text(count > 9 ? '9+' : '$count'),
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      child: child,
    );
  }
}

class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key, this.size = 10});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.palette.online,
      shape: BoxShape.circle,
      border: Border.all(color: context.palette.surface, width: size * 0.2),
    ),
  );
}
