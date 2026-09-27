import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// Vector brand mark (shopping bag, green→blue). Painted so it stays crisp at
/// every density and needs no raster assets.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Bozor.uz logotipi',
    image: true,
    child: CustomPaint(
      size: Size.square(size),
      painter: _BagPainter(context.palette),
    ),
  );
}

class _BagPainter extends CustomPainter {
  _BagPainter(this.palette);

  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final handle = Paint()
      ..color = const Color(0xFF1E40AF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(w * 0.3, h * 0.04, w * 0.4, h * 0.42),
      3.3,
      2.82,
      false,
      handle,
    );

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.1, h * 0.26, w * 0.8, h * 0.7),
      Radius.circular(w * 0.16),
    );
    canvas.drawRRect(
      body.shift(Offset(0, h * 0.03)),
      Paint()
        ..color = const Color(0xFF2456F5).withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.05),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22C55E), Color(0xFF14B8A6), Color(0xFF2456F5)],
          stops: [0.0, 0.45, 1.0],
        ).createShader(body.outerRect),
    );
    // Diagonal fold highlight.
    final fold = Path()
      ..moveTo(body.left + w * 0.02, body.bottom - h * 0.12)
      ..lineTo(body.right - w * 0.02, body.top + h * 0.1)
      ..lineTo(body.right, body.bottom - body.brRadiusY)
      ..quadraticBezierTo(
        body.right,
        body.bottom,
        body.right - body.brRadiusX,
        body.bottom,
      )
      ..lineTo(body.left + body.blRadiusX, body.bottom)
      ..quadraticBezierTo(
        body.left,
        body.bottom,
        body.left,
        body.bottom - body.blRadiusY,
      )
      ..close();
    canvas.drawPath(
      fold,
      Paint()..color = const Color(0xFF1D4ED8).withValues(alpha: 0.35),
    );
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(Offset(w * 0.34, h * 0.42), w * 0.04, dot);
    canvas.drawCircle(Offset(w * 0.66, h * 0.42), w * 0.04, dot);
  }

  @override
  bool shouldRepaint(_BagPainter oldDelegate) => false;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.fontSize = 40});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = Theme.of(context).textTheme.displaySmall?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      color: Theme.of(context).brightness == Brightness.dark
          ? palette.textPrimary
          : const Color(0xFF0B1B4D),
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Bozor'),
          TextSpan(
            text: '.uz',
            style: TextStyle(color: palette.primary),
          ),
        ],
      ),
      style: base,
      semanticsLabel: 'Bozor.uz',
    );
  }
}

/// Stylized Fergana-valley landscape (sky, sun, ridges, hills) behind onboarding.
class LandscapeBackdrop extends StatelessWidget {
  const LandscapeBackdrop({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      painter: _LandscapePainter(
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _LandscapePainter extends CustomPainter {
  _LandscapePainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sky = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0B1330), Color(0xFF16224A), Color(0xFF0A1020)]
              : const [Color(0xFFBFD7FF), Color(0xFFE9F1FF), Color(0xFFF7FAFF)],
          stops: const [0, 0.45, 1],
        ).createShader(sky),
    );
    final sunCenter = Offset(w * 0.86, h * 0.06);
    canvas.drawCircle(
      sunCenter,
      w * 0.28,
      Paint()
        ..shader = RadialGradient(
          colors: dark
              ? [
                  const Color(0xFF5B87FF).withValues(alpha: 0.25),
                  Colors.transparent,
                ]
              : [
                  const Color(0xFFFFF4D6).withValues(alpha: 0.7),
                  Colors.transparent,
                ],
        ).createShader(Rect.fromCircle(center: sunCenter, radius: w * 0.28)),
    );

    void ridge(double baseY, List<double> peaks, Color color) {
      final path = Path()..moveTo(0, h);
      path.lineTo(0, h * baseY);
      final step = w / (peaks.length - 1);
      for (var i = 0; i < peaks.length; i++) {
        final x = step * i;
        final y = h * peaks[i];
        if (i == 0) {
          path.lineTo(x, y);
        } else {
          final prevX = step * (i - 1);
          final prevY = h * peaks[i - 1];
          path.quadraticBezierTo(
            (prevX + x) / 2,
            (prevY < y ? prevY : y) - h * 0.015,
            x,
            y,
          );
        }
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    if (dark) {
      ridge(0.42, [
        0.40,
        0.30,
        0.36,
        0.24,
        0.33,
        0.28,
        0.38,
      ], const Color(0xFF1C2A55));
      ridge(0.48, [
        0.47,
        0.40,
        0.44,
        0.37,
        0.42,
        0.46,
      ], const Color(0xFF16224A));
      ridge(0.56, [0.55, 0.51, 0.54, 0.50, 0.53], const Color(0xFF111A36));
    } else {
      ridge(0.42, [
        0.40,
        0.30,
        0.36,
        0.24,
        0.33,
        0.28,
        0.38,
      ], const Color(0xFFB9C8EE));
      ridge(0.48, [
        0.47,
        0.40,
        0.44,
        0.37,
        0.42,
        0.46,
      ], const Color(0xFF9DB3E3));
      ridge(0.56, [0.55, 0.51, 0.54, 0.50, 0.53], const Color(0xFF8FC3A1));
    }
    final ground = Rect.fromLTWH(0, h * 0.58, w, h * 0.42);
    canvas.drawRect(
      ground,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF111A36), Color(0xFF0A1020)]
              : const [Color(0xFF9ED0AE), Color(0xFFF4F6FB)],
          stops: const [0, 0.55],
        ).createShader(ground),
    );
  }

  @override
  bool shouldRepaint(_LandscapePainter oldDelegate) => oldDelegate.dark != dark;
}
