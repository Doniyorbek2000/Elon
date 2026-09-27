import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_colors.dart';
import '../design/app_tokens.dart';
import '../domain/media_image.dart';
import 'skeleton.dart';

/// Disabled in widget tests (no network/plugins); renders placeholders instead.
final networkImagesEnabledProvider = Provider<bool>((ref) => true);

/// The only widget that renders content images. It:
/// * picks the smallest CDN rendition covering the laid-out size × DPR,
/// * decodes at that size (`memCacheWidth`) to bound memory,
/// * caches to disk, shows a skeleton while loading,
/// * degrades to a tinted icon placeholder on error or missing image.
class AppImage extends ConsumerWidget {
  const AppImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.image_outlined,
    this.tone = AccentTone.slate,
    this.semanticLabel,
    this.variant,
  });

  final MediaImage? image;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;
  final AccentTone tone;
  final String? semanticLabel;

  /// Force a variant (e.g. `original` in the zoom viewer).
  final ImageVariant? variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkEnabled = ref.watch(networkImagesEnabledProvider);
    final child = LayoutBuilder(
      builder: (context, constraints) {
        final media = image;
        final placeholder = _Placeholder(icon: placeholderIcon, tone: tone);
        if (media == null) return placeholder;

        final dpr = MediaQuery.devicePixelRatioOf(context);
        final logicalWidth = constraints.hasBoundedWidth ? constraints.maxWidth : 400.0;
        final cacheWidth = (logicalWidth * dpr).round().clamp(64, 2400);

        if (media.localPath != null) {
          return Image.file(
            File(media.localPath!),
            fit: fit,
            cacheWidth: cacheWidth,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
          );
        }
        final url = media.url(variant ?? ImageVariant.forPixelWidth(logicalWidth * dpr));
        if (url == null || !networkEnabled) return placeholder;
        return CachedNetworkImage(
          imageUrl: url,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: cacheWidth,
          fadeInDuration: AppMotion.of(context, AppMotion.fast),
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => const SkeletonBox(radius: 0),
          errorWidget: (_, _, _) => placeholder,
        );
      },
    );
    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: ClipRRect(borderRadius: borderRadius ?? BorderRadius.zero, child: child),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.tone});

  final IconData icon;
  final AccentTone tone;

  @override
  Widget build(BuildContext context) {
    final pair = context.palette.tone(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pair.background, Color.lerp(pair.background, pair.foreground, 0.12)!],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = (constraints.biggest.shortestSide * 0.36).clamp(16.0, 56.0);
          return Center(
            child: Icon(icon, size: size, color: pair.foreground.withValues(alpha: 0.55)),
          );
        },
      ),
    );
  }
}
