import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../design/app_colors.dart';
import '../domain/media_image.dart';
import 'app_image.dart';
import 'badges.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.image,
    this.size = 44,
    this.isOnline = false,
    this.tone = AccentTone.blue,
  });

  final String name;
  final MediaImage? image;
  final double size;
  final bool isOnline;
  final AccentTone tone;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final pair = context.palette.tone(tone);
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: image == null
            ? ColoredBox(
                color: pair.background,
                child: Center(
                  child: Text(
                    _initials,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: pair.foreground),
                  ),
                ),
              )
            : AppImage(image: image, placeholderIcon: Icons.person_rounded, tone: tone),
      ),
    );
    return Semantics(
      label: isOnline ? tr('{name}, onlayn', {'name': name}) : name,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            if (isOnline) PositionedDirectional(end: 0, bottom: 0, child: OnlineDot(size: size * 0.26)),
          ],
        ),
      ),
    );
  }
}
