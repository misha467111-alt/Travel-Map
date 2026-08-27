import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

abstract final class CategoryMarkerIcons {
  static final Map<String, BitmapDescriptor> _icons = {};
  static BitmapDescriptor? _userLocation;

  static Future<void> initialize() async {
    if (_icons.isNotEmpty) return;
    final entries = <String, (Color, IconData)>{
      'general': (const Color(0xFFD4A017), Icons.place),
      'cafe': (const Color(0xFF268BD2), Icons.local_cafe),
      'nature': (const Color(0xFF58A83B), Icons.park),
      'culture': (const Color(0xFFE05A3F), Icons.museum),
      'entertainment': (const Color(0xFF9C56C7), Icons.theater_comedy),
    };
    for (final entry in entries.entries) {
      _icons[entry.key] = await _draw(entry.value.$1, entry.value.$2);
    }
    _userLocation = await _drawUserLocation();
  }

  static BitmapDescriptor forCategory(String category) =>
      _icons[category] ??
      _icons['general'] ??
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

  static BitmapDescriptor? get userLocation => _userLocation;

  static Future<BitmapDescriptor> _draw(Color color, IconData icon) async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(center, 40, Paint()..color = Colors.black38);
    canvas.drawCircle(center, 36, Paint()..color = Colors.white);
    canvas.drawCircle(center, 31, Paint()..color = color);
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 34,
          color: Colors.white,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        width: 30, height: 30);
  }

  static Future<BitmapDescriptor> _drawUserLocation() async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(center, 43, Paint()..color = const Color(0x44EC407A));
    canvas.drawCircle(center, 29, Paint()..color = Colors.white);
    canvas.drawCircle(center, 23, Paint()..color = const Color(0xFFEC407A));
    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        width: 32, height: 32);
  }
}
