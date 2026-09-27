import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// 4-pt spacing scale. Use these instead of raw numbers in layouts.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

abstract final class AppRadii {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 22;
  static const double xxl = 28;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

abstract final class AppIconSize {
  static const double xs = 14;
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 26;
  static const double xl = 32;
}

/// Minimum interactive sizes (Material 48dp / Apple HIG 44pt).
abstract final class AppTouch {
  static const double minTarget = 48;
  static const double buttonHeight = 52;
  static const double compactButtonHeight = 44;
  static const double inputHeight = 50;
}

abstract final class AppBorders {
  static const double hairline = 1;
  static const double focus = 1.5;
}

abstract final class AppMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration shimmer = Duration(milliseconds: 1300);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve spring = Curves.easeOutBack;

  /// Honors the OS "reduce motion" setting.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : duration;

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

enum WindowClass { compact, medium, expanded }

/// Material 3 window size classes, driven by available width rather than device type.
abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;
  static const double contentMaxWidth = 760;
  static const double formMaxWidth = 560;
  static const double wideContentMaxWidth = 1200;

  static WindowClass classify(double width) {
    if (width >= expanded) return WindowClass.expanded;
    if (width >= medium) return WindowClass.medium;
    return WindowClass.compact;
  }

  static WindowClass of(BuildContext context) => classify(MediaQuery.sizeOf(context).width);

  static double pagePadding(BuildContext context) => switch (of(context)) {
    WindowClass.compact => AppSpacing.lg,
    WindowClass.medium => AppSpacing.xxl,
    WindowClass.expanded => AppSpacing.xxxl,
  };

  /// Column count for a grid whose tiles should be roughly [minTileWidth] wide.
  static int columnsFor(double availableWidth, {double minTileWidth = 164, int min = 2, int max = 6}) {
    final columns = (availableWidth / minTileWidth).floor();
    return columns.clamp(min, max);
  }
}

abstract final class AppShadows {
  static List<BoxShadow> card(AppPalette palette, {bool dark = false}) => dark
      ? const []
      : [
          BoxShadow(color: palette.shadow, blurRadius: 18, offset: const Offset(0, 6), spreadRadius: -6),
          BoxShadow(color: palette.shadow.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1)),
        ];

  static List<BoxShadow> floating(AppPalette palette) => [
    BoxShadow(color: palette.shadow, blurRadius: 24, offset: const Offset(0, 10), spreadRadius: -4),
  ];

  static List<BoxShadow> primaryGlow(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -4),
  ];
}
