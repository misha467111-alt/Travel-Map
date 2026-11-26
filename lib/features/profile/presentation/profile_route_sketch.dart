import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import '../providers/profile_journey_data_provider.dart';

/// Phase 3.4-B1 -- projects the [runs] of a Journey (lat / lon) into [size]
/// preserving the shape (equirectangular, longitude scaled by cos(latitude))
/// with [padding] around it. One list of offsets per run -- runs are kept apart
/// and never joined. Returns an empty list when there is nothing drawable:
/// fewer than 2 points, a box with no room, or a track shorter than
/// [routeSketchMinExtentMeters] (GPS noise around one spot is never stretched
/// to fill the panel). Pure, so it is unit-testable.
List<List<Offset>> projectSketch(List<SketchRun> runs, Size size,
    {double padding = 10}) {
  if (size.isEmpty || isSketchTooSmall(runs)) return const [];
  double? minLat, maxLat, minLon, maxLon;
  for (final run in runs) {
    for (final p in run) {
      minLat = minLat == null ? p.lat : math.min(minLat, p.lat);
      maxLat = maxLat == null ? p.lat : math.max(maxLat, p.lat);
      minLon = minLon == null ? p.lon : math.min(minLon, p.lon);
      maxLon = maxLon == null ? p.lon : math.max(maxLon, p.lon);
    }
  }
  if (minLat == null || maxLat == null || minLon == null || maxLon == null) {
    return const [];
  }
  final lonScale = math.cos((minLat + maxLat) / 2 * math.pi / 180);
  final spanX = (maxLon - minLon) * lonScale;
  final spanY = maxLat - minLat;
  final boxW = size.width - 2 * padding;
  final boxH = size.height - 2 * padding;
  if (boxW <= 0 || boxH <= 0) return const [];

  double scale;
  if (spanX <= 0 && spanY <= 0) {
    return const [];
  } else if (spanX <= 0) {
    scale = boxH / spanY;
  } else if (spanY <= 0) {
    scale = boxW / spanX;
  } else {
    scale = math.min(boxW / spanX, boxH / spanY);
  }
  final left = padding + (boxW - spanX * scale) / 2;
  final top = padding + (boxH - spanY * scale) / 2;
  return [
    for (final run in runs)
      [
        for (final p in run)
          Offset(left + (p.lon - minLon) * lonScale * scale,
              top + (maxLat - p.lat) * scale),
      ],
  ];
}

/// Draws the outline of a Journey: every run as its OWN path (a soft gold glow
/// and the gold line), a light start dot at the beginning of the first run and
/// a gold end dot at the end of the last one. Draws nothing when there is no
/// drawable route.
class RouteSketchPainter extends CustomPainter {
  const RouteSketchPainter(this.runs);

  final List<SketchRun> runs;

  @override
  void paint(Canvas canvas, Size size) {
    final projected = projectSketch(runs, size);
    if (projected.isEmpty) return;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.accent.withValues(alpha: 0.18);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.accent;
    for (final run in projected) {
      if (run.isEmpty) continue;
      if (run.length == 1) {
        canvas.drawCircle(run.first, 2.5, Paint()..color = AppColors.accent);
        continue;
      }
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final o in run.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }
    final nonEmpty = projected.where((run) => run.isNotEmpty);
    canvas.drawCircle(
        nonEmpty.first.first, 3.5, Paint()..color = AppColors.textPrimary);
    canvas.drawCircle(nonEmpty.last.last, 4, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(RouteSketchPainter oldDelegate) =>
      !identical(oldDelegate.runs, runs);
}

/// The route sketch panel of a Journey card: a forest-toned background with the
/// outline of the confirmed track on top, or -- while loading, when the Journey
/// has no confirmed points, or when the track is too short to be a route --
/// just a quiet route icon.
class RouteSketchPanel extends StatelessWidget {
  const RouteSketchPanel({required this.runs, super.key});

  /// `null` = still loading; empty = no confirmed outline available.
  final List<SketchRun>? runs;

  @override
  Widget build(BuildContext context) {
    final data = runs;
    final hasSketch = data != null && !isSketchTooSmall(data);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(AppColors.elevated, AppColors.accent, 0.12)!,
              AppColors.background,
            ],
          ),
        ),
        child: hasSketch
            ? CustomPaint(
                key: const Key('profile_route_sketch'),
                painter: RouteSketchPainter(data),
                child: const SizedBox.expand(),
              )
            : Center(
                child: Icon(Icons.route_outlined,
                    key: const Key('profile_route_sketch_fallback'),
                    color: AppColors.accent.withValues(alpha: 0.55),
                    size: 34),
              ),
      ),
    );
  }
}
