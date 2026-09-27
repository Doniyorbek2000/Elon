import 'package:flutter/material.dart';

/// Semantic accent tones used for category tiles, badges and illustrations.
///
/// Domain/config objects reference tones by name so data never carries
/// Flutter colors directly.
enum AccentTone {
  blue,
  green,
  orange,
  red,
  purple,
  pink,
  teal,
  amber,
  indigo,
  slate,
}

/// Background/foreground pair for a tinted surface.
@immutable
class TonePair {
  const TonePair(this.background, this.foreground);

  final Color background;
  final Color foreground;

  static TonePair lerp(TonePair a, TonePair b, double t) => TonePair(
    Color.lerp(a.background, b.background, t)!,
    Color.lerp(a.foreground, b.foreground, t)!,
  );
}

/// Brand palette exposed as a [ThemeExtension] so every widget resolves
/// colors from the active theme (light/dark) instead of hardcoding them.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.primarySoft,
    required this.price,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.online,
    required this.vip,
    required this.vipSoft,
    required this.shadow,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.scrim,
    required this.tones,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color primaryPressed;
  final Color onPrimary;
  final Color primarySoft;
  final Color price;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color online;
  final Color vip;
  final Color vipSoft;
  final Color shadow;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color scrim;
  final Map<AccentTone, TonePair> tones;

  TonePair tone(AccentTone tone) => tones[tone]!;

  static const light = AppPalette(
    background: Color(0xFFF4F6FB),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F4F9),
    surfaceElevated: Color(0xFFFFFFFF),
    border: Color(0xFFE5E9F2),
    borderStrong: Color(0xFFCBD3E1),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF5B6478),
    textTertiary: Color(0xFF8A93A6),
    primary: Color(0xFF2456F5),
    primaryPressed: Color(0xFF1B45D1),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFE8EEFF),
    price: Color(0xFF12A150),
    success: Color(0xFF16A34A),
    successSoft: Color(0xFFE3F7EA),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFFF3DC),
    danger: Color(0xFFE11D48),
    dangerSoft: Color(0xFFFFE8EE),
    online: Color(0xFF22C55E),
    vip: Color(0xFFB7791F),
    vipSoft: Color(0xFFFFF4D6),
    shadow: Color(0x140F172A),
    skeletonBase: Color(0xFFE9EDF4),
    skeletonHighlight: Color(0xFFF6F8FC),
    scrim: Color(0x8C0F172A),
    tones: {
      AccentTone.blue: TonePair(Color(0xFFE6EEFF), Color(0xFF2456F5)),
      AccentTone.green: TonePair(Color(0xFFE2F7EA), Color(0xFF16A34A)),
      AccentTone.orange: TonePair(Color(0xFFFFEEDD), Color(0xFFEA6A0C)),
      AccentTone.red: TonePair(Color(0xFFFFE6E8), Color(0xFFE5343F)),
      AccentTone.purple: TonePair(Color(0xFFF0E8FF), Color(0xFF7C3AED)),
      AccentTone.pink: TonePair(Color(0xFFFFE6F3), Color(0xFFDB2777)),
      AccentTone.teal: TonePair(Color(0xFFDDF6F3), Color(0xFF0D9488)),
      AccentTone.amber: TonePair(Color(0xFFFFF3D6), Color(0xFFD08700)),
      AccentTone.indigo: TonePair(Color(0xFFE7E9FF), Color(0xFF4F46E5)),
      AccentTone.slate: TonePair(Color(0xFFEDF0F5), Color(0xFF475569)),
    },
  );

  /// Dark palette is designed on deep navy surfaces (not inverted greys):
  /// elevation reads through lighter surfaces instead of shadows, and accent
  /// colors are lifted in luminance to keep WCAG AA contrast on dark cards.
  static const dark = AppPalette(
    background: Color(0xFF0A1020),
    surface: Color(0xFF121A2C),
    surfaceMuted: Color(0xFF1A2338),
    surfaceElevated: Color(0xFF1B2540),
    border: Color(0xFF243049),
    borderStrong: Color(0xFF34425F),
    textPrimary: Color(0xFFE8EDF7),
    textSecondary: Color(0xFFA3AEC4),
    textTertiary: Color(0xFF76829A),
    primary: Color(0xFF5B87FF),
    primaryPressed: Color(0xFF4570EE),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFF1D2B52),
    price: Color(0xFF3DDC84),
    success: Color(0xFF34D399),
    successSoft: Color(0xFF123328),
    warning: Color(0xFFFBBF24),
    warningSoft: Color(0xFF3A2E12),
    danger: Color(0xFFFB7185),
    dangerSoft: Color(0xFF3B1621),
    online: Color(0xFF34D399),
    vip: Color(0xFFF5C451),
    vipSoft: Color(0xFF3A2F14),
    shadow: Color(0x66000000),
    skeletonBase: Color(0xFF1A2338),
    skeletonHighlight: Color(0xFF243049),
    scrim: Color(0xB3000000),
    tones: {
      AccentTone.blue: TonePair(Color(0xFF1B2A55), Color(0xFF7FA2FF)),
      AccentTone.green: TonePair(Color(0xFF123526), Color(0xFF4ADE80)),
      AccentTone.orange: TonePair(Color(0xFF3A2413), Color(0xFFFB9A4B)),
      AccentTone.red: TonePair(Color(0xFF3A171D), Color(0xFFFB7185)),
      AccentTone.purple: TonePair(Color(0xFF2A1D4A), Color(0xFFB794F6)),
      AccentTone.pink: TonePair(Color(0xFF3A1730), Color(0xFFF472B6)),
      AccentTone.teal: TonePair(Color(0xFF0F332F), Color(0xFF2DD4BF)),
      AccentTone.amber: TonePair(Color(0xFF3A2E12), Color(0xFFFBBF24)),
      AccentTone.indigo: TonePair(Color(0xFF221F4D), Color(0xFFA5B4FC)),
      AccentTone.slate: TonePair(Color(0xFF1E2638), Color(0xFFB6C0D4)),
    },
  );

  @override
  AppPalette copyWith({Color? primary, Color? background, Color? surface}) =>
      AppPalette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceMuted: surfaceMuted,
        surfaceElevated: surfaceElevated,
        border: border,
        borderStrong: borderStrong,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textTertiary: textTertiary,
        primary: primary ?? this.primary,
        primaryPressed: primaryPressed,
        onPrimary: onPrimary,
        primarySoft: primarySoft,
        price: price,
        success: success,
        successSoft: successSoft,
        warning: warning,
        warningSoft: warningSoft,
        danger: danger,
        dangerSoft: dangerSoft,
        online: online,
        vip: vip,
        vipSoft: vipSoft,
        shadow: shadow,
        skeletonBase: skeletonBase,
        skeletonHighlight: skeletonHighlight,
        scrim: scrim,
        tones: tones,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceElevated: l(surfaceElevated, other.surfaceElevated),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      primary: l(primary, other.primary),
      primaryPressed: l(primaryPressed, other.primaryPressed),
      onPrimary: l(onPrimary, other.onPrimary),
      primarySoft: l(primarySoft, other.primarySoft),
      price: l(price, other.price),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      online: l(online, other.online),
      vip: l(vip, other.vip),
      vipSoft: l(vipSoft, other.vipSoft),
      shadow: l(shadow, other.shadow),
      skeletonBase: l(skeletonBase, other.skeletonBase),
      skeletonHighlight: l(skeletonHighlight, other.skeletonHighlight),
      scrim: l(scrim, other.scrim),
      tones: {
        for (final tone in AccentTone.values)
          tone: TonePair.lerp(tones[tone]!, other.tones[tone]!, t),
      },
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
