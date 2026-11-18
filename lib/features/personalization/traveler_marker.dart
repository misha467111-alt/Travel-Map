import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Traveler marker customization V1: the user's own location marker on the
/// main map. Pure presentation + a local preference; no schema, no network.

enum TravelerMarkerStyle {
  dot('Класична точка', 'Точка'),
  arrow('Навігаційна стрілка', 'Стрілка'),
  traveler('Мандрівник з рюкзаком', 'Мандрівник');

  const TravelerMarkerStyle(this.label, this.shortLabel);
  final String label;

  /// The compact name used on the selection cards.
  final String shortLabel;
}

enum TravelerMarkerColor {
  gold('Золотий', Color(0xFFD4A017)),
  pink('Рожевий', Color(0xFFEC407A)),
  blue('Синій', Color(0xFF2196F3)),
  green('Зелений', Color(0xFF43A047)),
  purple('Фіолетовий', Color(0xFF8E24AA)),
  orange('Помаранчевий', Color(0xFFFB8C00));

  const TravelerMarkerColor(this.label, this.color);
  final String label;
  final Color color;
}

/// The current choice. The default (classic dot, pink) is exactly the marker
/// the map has always shown.
@immutable
class TravelerMarkerSettings {
  const TravelerMarkerSettings({
    this.style = TravelerMarkerStyle.dot,
    this.color = TravelerMarkerColor.pink,
  });

  static const defaults = TravelerMarkerSettings();

  final TravelerMarkerStyle style;
  final TravelerMarkerColor color;

  TravelerMarkerSettings copyWith(
          {TravelerMarkerStyle? style, TravelerMarkerColor? color}) =>
      TravelerMarkerSettings(
          style: style ?? this.style, color: color ?? this.color);

  @override
  bool operator ==(Object other) =>
      other is TravelerMarkerSettings &&
      other.style == style &&
      other.color == color;

  @override
  int get hashCode => Object.hash(style, color);

  String get cacheKey => '${style.name}_${color.name}';
}

/// Persistence in the existing `shared_preferences` store (a local
/// per-device preference). Unknown or missing values fall back to the
/// defaults, so a corrupt value can never break the map.
abstract final class TravelerMarkerStore {
  static const styleKey = 'traveler_marker_style';
  static const colorKey = 'traveler_marker_color';

  static Future<TravelerMarkerSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final style = TravelerMarkerStyle.values
          .where((v) => v.name == prefs.getString(styleKey))
          .firstOrNull;
      final color = TravelerMarkerColor.values
          .where((v) => v.name == prefs.getString(colorKey))
          .firstOrNull;
      return TravelerMarkerSettings(
        style: style ?? TravelerMarkerSettings.defaults.style,
        color: color ?? TravelerMarkerSettings.defaults.color,
      );
    } catch (_) {
      return TravelerMarkerSettings.defaults;
    }
  }

  static Future<void> save(TravelerMarkerSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(styleKey, settings.style.name);
      await prefs.setString(colorKey, settings.color.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

class TravelerMarkerNotifier extends Notifier<TravelerMarkerSettings> {
  bool _changedByUser = false;

  @override
  TravelerMarkerSettings build() {
    _load();
    return TravelerMarkerSettings.defaults;
  }

  Future<void> _load() async {
    final loaded = await TravelerMarkerStore.load();
    // A choice made before the stored value arrived wins.
    if (ref.mounted && !_changedByUser) state = loaded;
  }

  Future<void> select(
      {TravelerMarkerStyle? style, TravelerMarkerColor? color}) {
    _changedByUser = true;
    state = state.copyWith(style: style, color: color);
    return TravelerMarkerStore.save(state);
  }
}

final travelerMarkerProvider =
    NotifierProvider<TravelerMarkerNotifier, TravelerMarkerSettings>(
        TravelerMarkerNotifier.new);

/// Paints the marker on a [size]-square canvas (the bitmap and the live
/// preview use this same function, so the preview is what the map shows).
void paintTravelerMarker(
  Canvas canvas,
  double size, {
  required TravelerMarkerStyle style,
  required Color color,
}) {
  final scale = size / 96;
  canvas.save();
  canvas.scale(scale);
  const center = Offset(48, 48);
  final halo = Paint()..color = color.withValues(alpha: 0.27);
  final white = Paint()..color = Colors.white;
  final fill = Paint()..color = color;
  switch (style) {
    case TravelerMarkerStyle.dot:
      canvas.drawCircle(center, 43, halo);
      canvas.drawCircle(center, 29, white);
      canvas.drawCircle(center, 23, fill);
    case TravelerMarkerStyle.arrow:
      canvas.drawCircle(center, 43, halo);
      canvas.drawCircle(center, 34, white);
      final arrow = Path()
        ..moveTo(48, 17)
        ..lineTo(69, 71)
        ..lineTo(48, 59)
        ..lineTo(27, 71)
        ..close();
      canvas.drawPath(arrow, fill);
    case TravelerMarkerStyle.traveler:
      canvas.drawCircle(center, 43, halo);
      canvas.drawCircle(center, 38, white);
      final dark = Paint()..color = Color.lerp(color, Colors.black, 0.35)!;
      // Backpack behind the body, then body, head and legs.
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(55, 41, 13, 24), const Radius.circular(5)),
          dark);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(37, 39, 21, 28), const Radius.circular(8)),
          fill);
      canvas.drawCircle(const Offset(47.5, 28), 9.5, fill);
      final leg = Paint()
        ..color = color
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(43, 66), const Offset(41, 80), leg);
      canvas.drawLine(const Offset(53, 66), const Offset(55, 80), leg);
  }
  canvas.restore();
}

/// Bitmap cache: one `BitmapDescriptor` per style/colour combination
/// (at most 18), drawn on first use and never regenerated afterwards.
abstract final class TravelerMarkerIcons {
  static final Map<String, Future<BitmapDescriptor>> _cache = {};

  /// Number of bitmaps drawn so far (diagnostics and tests).
  static int get renderedCount => _cache.length;

  static Future<BitmapDescriptor> iconFor(TravelerMarkerSettings settings) =>
      _cache.putIfAbsent(settings.cacheKey, () => _render(settings));

  static void clearForTest() => _cache.clear();

  static Future<BitmapDescriptor> _render(TravelerMarkerSettings s) async {
    const px = 96;
    final recorder = ui.PictureRecorder();
    paintTravelerMarker(Canvas(recorder), px.toDouble(),
        style: s.style, color: s.color.color);
    final image = await recorder.endRecording().toImage(px, px);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    // The classic dot keeps its familiar 32 dp; the richer shapes need a
    // little more room to stay legible.
    final dp = s.style == TravelerMarkerStyle.dot ? 32.0 : 40.0;
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        width: dp, height: dp);
  }
}

/// The marker bitmap for the current settings; `null` while it is drawn
/// (the map then keeps its default marker, never an empty one).
final travelerMarkerIconProvider = FutureProvider<BitmapDescriptor>(
    (ref) => TravelerMarkerIcons.iconFor(ref.watch(travelerMarkerProvider)));

/// A live preview drawn by the very same painter as the map bitmap.
class TravelerMarkerPreview extends StatelessWidget {
  const TravelerMarkerPreview({
    super.key,
    required this.style,
    required this.color,
    this.size = 96,
  });

  final TravelerMarkerStyle style;
  final TravelerMarkerColor color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${style.label}, ${color.label}',
        image: true,
        child: CustomPaint(
          size: Size.square(size),
          painter: _MarkerPainter(style, color.color),
        ),
      );
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.style, this.color);
  final TravelerMarkerStyle style;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      paintTravelerMarker(canvas, size.width, style: style, color: color);

  @override
  bool shouldRepaint(_MarkerPainter old) =>
      old.style != style || old.color != color;
}
