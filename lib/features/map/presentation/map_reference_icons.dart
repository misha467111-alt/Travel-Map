import 'package:flutter/material.dart';

enum MapReferenceGlyph { layers, dice, map, compass, adventure, route, profile }

/// Small vector artwork for the map chrome, independent of navigation state.
class MapReferenceIcon extends StatelessWidget {
  const MapReferenceIcon(this.glyph,
      {this.size = 22, this.color = const Color(0xFFD4A017), super.key});
  final MapReferenceGlyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MapReferencePainter(glyph, color)));
}

class _MapReferencePainter extends CustomPainter {
  const _MapReferencePainter(this.glyph, this.color);
  final MapReferenceGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    void line(List<Offset> points, {bool close = false}) {
      final path = Path()..addPolygon(points, close);
      canvas.drawPath(path, pen);
    }

    switch (glyph) {
      case MapReferenceGlyph.layers:
        line(const [
          Offset(12, 2),
          Offset(21, 7),
          Offset(21, 17),
          Offset(12, 22),
          Offset(3, 17),
          Offset(3, 7)
        ], close: true);
        line(const [Offset(3, 7), Offset(12, 12), Offset(21, 7)]);
        line(const [Offset(12, 12), Offset(12, 22)]);
        line(const [Offset(7, 5), Offset(16, 10), Offset(16, 19)]);
        line(const [Offset(7, 10), Offset(7, 14), Offset(10, 16)]);
      case MapReferenceGlyph.dice:
        line(const [
          Offset(12, 2),
          Offset(21, 7),
          Offset(21, 17),
          Offset(12, 22),
          Offset(3, 17),
          Offset(3, 7)
        ], close: true);
        line(const [Offset(3, 7), Offset(12, 12), Offset(21, 7)]);
        line(const [Offset(12, 12), Offset(12, 22)]);
        final pip = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(16.5, 9.5), 1.05, pip);
        canvas.drawCircle(const Offset(7.5, 11), 1.05, pip);
        canvas.drawCircle(const Offset(7.5, 16.5), 1.05, pip);
        canvas.drawCircle(const Offset(16.5, 14.5), 1.05, pip);
        canvas.drawCircle(const Offset(16.5, 19.5), 1.05, pip);
      case MapReferenceGlyph.map:
        line(const [
          Offset(3, 4),
          Offset(9, 2),
          Offset(15, 5),
          Offset(21, 3),
          Offset(21, 20),
          Offset(15, 22),
          Offset(9, 19),
          Offset(3, 21)
        ], close: true);
        line(const [Offset(9, 2), Offset(9, 19)]);
        line(const [Offset(15, 5), Offset(15, 22)]);
      case MapReferenceGlyph.compass:
        canvas.drawCircle(const Offset(12, 12), 9.5, pen);
        line(const [
          Offset(16, 7),
          Offset(13, 13),
          Offset(8, 17),
          Offset(11, 11)
        ], close: true);
      case MapReferenceGlyph.adventure:
        canvas.drawCircle(const Offset(12, 5.5), 3, pen);
        line(const [
          Offset(8, 10),
          Offset(6, 14),
          Offset(8, 15),
          Offset(4, 21),
          Offset(20, 21),
          Offset(16, 15),
          Offset(18, 14),
          Offset(16, 10)
        ]);
      case MapReferenceGlyph.route:
        canvas.drawCircle(const Offset(5, 18), 2.5, pen);
        canvas.drawCircle(const Offset(19, 5), 2.5, pen);
        line(const [
          Offset(7.5, 18),
          Offset(15, 18),
          Offset(15, 12),
          Offset(9, 12),
          Offset(9, 5),
          Offset(16.5, 5)
        ]);
      case MapReferenceGlyph.profile:
        canvas.drawCircle(const Offset(12, 6), 3.5, pen);
        canvas.drawPath(
            Path()
              ..moveTo(4, 21)
              ..lineTo(4, 18)
              ..cubicTo(4, 12, 20, 12, 20, 18)
              ..lineTo(20, 21)
              ..close(),
            pen);
    }
  }

  @override
  bool shouldRepaint(_MapReferencePainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}

class MapCategoryArtwork extends StatelessWidget {
  const MapCategoryArtwork(
      {required this.category,
      required this.icon,
      required this.color,
      super.key});
  final String category;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (category == 'nature' || category == 'all') {
      return SizedBox.square(
          dimension: 22,
          child: CustomPaint(painter: _CategoryPainter(category)));
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(color, Colors.white, .3)!,
          color,
          Color.lerp(color, Colors.black, .18)!
        ],
      ).createShader(bounds),
      child: Icon(icon, size: 21, color: Colors.white),
    );
  }
}

class _CategoryPainter extends CustomPainter {
  const _CategoryPainter(this.category);
  final String category;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..isAntiAlias = true;
    if (category == 'all') {
      paint
        ..color = const Color(0xFFE6C375)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25;
      for (final offset in const [
        Offset(4, 4),
        Offset(14, 4),
        Offset(4, 14),
        Offset(14, 14)
      ]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                offset & const Size(6, 6), const Radius.circular(1)),
            paint);
      }
      return;
    }
    paint.color = const Color(0xFF677D46);
    canvas.drawOval(const Rect.fromLTWH(2, 18, 20, 4), paint);
    paint.color = const Color(0xFFBEA978);
    canvas.drawRect(const Rect.fromLTWH(11, 15, 2, 8), paint);
    for (final (top, base, halfWidth, color) in const [
      (8.0, 19.0, 8.0, Color(0xFF73A948)),
      (5.0, 14.5, 6.5, Color(0xFF97C064)),
      (1.0, 10.0, 4.5, Color(0xFFC2D594)),
    ]) {
      paint.color = color;
      canvas.drawPath(
          Path()
            ..moveTo(12, top)
            ..lineTo(12 + halfWidth, base)
            ..quadraticBezierTo(12, base + 2, 12 - halfWidth, base)
            ..close(),
          paint);
    }
  }

  @override
  bool shouldRepaint(_CategoryPainter oldDelegate) =>
      category != oldDelegate.category;
}
