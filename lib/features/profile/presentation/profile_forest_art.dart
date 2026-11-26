import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';

/// Phase 3.4-B -- the procedural "Premium Forest" artwork of the profile:
/// a mountain / fir-tree skyline drawn with a [CustomPainter] (no image assets,
/// no dependencies) and the hexagonal medal frame. Every colour is derived from
/// the existing [AppColors] tokens; nothing here carries data.

/// Mixes two palette colours so the artwork never introduces a new token.
Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Decorative forest skyline that fills its parent. It is excluded from the
/// semantics tree and is a pure function of its size (it repaints only when the
/// size changes), so it costs nothing while scrolling.
class ForestHeroBackground extends StatelessWidget {
  const ForestHeroBackground({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            key: Key('forest_hero_art'),
            painter: ForestHeroPainter(),
            child: SizedBox.expand(),
          ),
        ),
      );
}

class ForestHeroPainter extends CustomPainter {
  const ForestHeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    // A CustomPaint does not clip: the tree trunks and the trees at the very
    // edges reach past the canvas and would paint over the hero's gold border.
    canvas.clipRect(rect);

    // Dusk sky: a faint gold warmth fading into the elevated surface.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _mix(AppColors.elevated, AppColors.accent, 0.16),
            AppColors.elevated,
            AppColors.surface,
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );

    // Soft glow behind the ridge (a low sun).
    final glowCentre = Offset(w * 0.78, h * 0.34);
    canvas.drawCircle(
      glowCentre,
      math.max(w, h) * 0.42,
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.accent.withValues(alpha: 0.26),
          AppColors.accent.withValues(alpha: 0),
        ]).createShader(
            Rect.fromCircle(center: glowCentre, radius: math.max(w, h) * 0.42)),
    );

    // Two mountain ridges, the far one lighter.
    _ridge(
      canvas,
      size,
      const [
        (0.00, 0.58),
        (0.16, 0.42),
        (0.27, 0.52),
        (0.43, 0.30),
        (0.58, 0.50),
        (0.72, 0.36),
        (0.86, 0.52),
        (1.00, 0.40),
      ],
      _mix(AppColors.surface, AppColors.background, 0.25),
    );
    _ridge(
      canvas,
      size,
      const [
        (0.00, 0.70),
        (0.12, 0.60),
        (0.30, 0.72),
        (0.48, 0.56),
        (0.66, 0.72),
        (0.84, 0.60),
        (1.00, 0.70),
      ],
      _mix(AppColors.surface, AppColors.background, 0.62),
    );

    // Fir-tree line along the bottom: deterministic, so it never flickers.
    final tree = Paint()..color = AppColors.background.withValues(alpha: 0.96);
    final step = math.max(14.0, w / 26);
    var seed = 7;
    for (var x = -step / 2; x < w + step; x += step * 0.78) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final k = (seed % 100) / 100;
      final treeH = h * (0.20 + 0.20 * k);
      _fir(canvas, tree, x, h, treeH, step * (0.62 + 0.18 * k));
    }

    // Keep the lower part dark so text on top stays readable.
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.45, w, h * 0.55),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0),
            AppColors.background.withValues(alpha: 0.5),
          ],
        ).createShader(Rect.fromLTWH(0, h * 0.45, w, h * 0.55)),
    );
  }

  void _ridge(
      Canvas canvas, Size size, List<(double, double)> peaks, Color color) {
    final path = Path()..moveTo(0, size.height);
    for (final (fx, fy) in peaks) {
      path.lineTo(size.width * fx, size.height * fy);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  /// One fir: three stacked triangles rising from [baseY].
  void _fir(Canvas canvas, Paint paint, double cx, double baseY, double height,
      double width) {
    final path = Path();
    for (var tier = 0; tier < 3; tier++) {
      final top = baseY - height + tier * height * 0.26;
      final bottom = baseY - height * (1 - (tier + 1) * 0.30) + height * 0.06;
      final half = width * (0.34 + tier * 0.16);
      path
        ..moveTo(cx, top)
        ..lineTo(cx + half, bottom)
        ..lineTo(cx - half, bottom)
        ..close();
    }
    path
      ..addRect(Rect.fromLTWH(
          cx - width * 0.05, baseY - height * 0.1, width * 0.1, height * 0.12))
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ForestHeroPainter oldDelegate) => false;
}

/// A gold hexagonal medal frame around an achievement [icon]. Only the unlocked
/// look exists: locked achievements are not shown on the profile.
class HexMedal extends StatelessWidget {
  const HexMedal({
    required this.icon,
    this.size = 56,
    this.iconKey,
    super.key,
  });

  final IconData icon;
  final double size;

  /// Key of the inner [Icon] (the profile uses `profile_medal_icon_<key>`).
  final Key? iconKey;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: const HexMedalPainter(),
          child: Center(
            child: Icon(icon,
                key: iconKey, color: AppColors.accent, size: size * 0.46),
          ),
        ),
      );
}

/// The hexagon (pointy-top) path inscribed in [size] with a stroke [inset].
Path hexagonPath(Size size, {double inset = 2}) {
  final centre = size.center(Offset.zero);
  final radius = math.min(size.width, size.height) / 2 - inset;
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final angle = -math.pi / 2 + i * math.pi / 3;
    final p = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

class HexMedalPainter extends CustomPainter {
  const HexMedalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = hexagonPath(size);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.accentTint(0.30), AppColors.accentTint(0.10)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(HexMedalPainter oldDelegate) => false;
}
