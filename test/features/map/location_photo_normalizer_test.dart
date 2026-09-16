import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_application_1/features/map/domain/location_photo_normalizer.dart';

/// Phase 2.2A1: proves -- with real encoded bytes, not just a description
/// of intent -- that `normalizeLocationPhoto` actually strips EXIF
/// (GPS included), bakes orientation, resizes without ever upscaling,
/// and always outputs valid JPEG bytes regardless of the input format.
void main() {
  test('target constants match the approved spec', () {
    expect(locationPhotoMaxLongEdgePx, 1600);
    expect(locationPhotoJpegQuality, 80);
  });

  test('strips all EXIF including GPS, and bakes EXIF orientation into pixels',
      () {
    final source = img.Image(width: 40, height: 30, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(200, 40, 40));
    // A real GPS fix, exactly the kind of data a phone camera embeds.
    source.exif.gpsIfd.setGpsLocation(latitude: 50.4501, longitude: 30.5234);
    // Orientation 6 = "rotate 90 CW to display correctly" -- baking this
    // physically rotates the pixel buffer, swapping width/height for a
    // 40x30 source.
    source.exif.imageIfd.orientation = 6;
    expect(source.exif.isEmpty, isFalse,
        reason: 'the fixture must actually carry EXIF for this test to '
            'prove anything');
    expect(source.exif.gpsIfd.hasGPSLatitude, isTrue);

    final sourceBytes = Uint8List.fromList(img.encodeJpg(source));
    final normalized = normalizeLocationPhoto(sourceBytes);

    final result = img.decodeJpg(normalized);
    expect(result, isNotNull);
    expect(result!.exif.isEmpty, isTrue,
        reason: 'no EXIF segment at all should survive normalization');
    expect(result.exif.gpsIfd.hasGPSLatitude, isFalse);
    expect(result.exif.gpsIfd.hasGPSLongitude, isFalse);
    expect(result.exif.imageIfd.hasOrientation, isFalse);
    // Orientation was baked into the pixels, not just discarded --
    // width/height swapped from the 40x30 source.
    expect(result.width, 30);
    expect(result.height, 40);
  });

  test('resizes an oversized image down to the max long edge', () {
    final source = img.Image(width: 2000, height: 1000, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(10, 120, 10));
    final sourceBytes = Uint8List.fromList(img.encodeJpg(source));

    final normalized = normalizeLocationPhoto(sourceBytes);
    final result = img.decodeJpg(normalized);

    expect(result, isNotNull);
    expect(result!.width, locationPhotoMaxLongEdgePx);
    expect(result.height, 800, reason: 'aspect ratio must be preserved');
  });

  test('never upscales an already-small image', () {
    final source = img.Image(width: 100, height: 50, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(10, 10, 200));
    final sourceBytes = Uint8List.fromList(img.encodeJpg(source));

    final normalized = normalizeLocationPhoto(sourceBytes);
    final result = img.decodeJpg(normalized);

    expect(result, isNotNull);
    expect(result!.width, 100);
    expect(result.height, 50);
  });

  test('always outputs valid JPEG bytes regardless of the input format', () {
    final source = img.Image(width: 60, height: 40, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(5, 5, 5, 255));
    final pngBytes = Uint8List.fromList(img.encodePng(source));

    final normalized = normalizeLocationPhoto(pngBytes);

    // The JPEG magic number (SOI marker), checked directly on the bytes
    // -- not inferred from any filename/extension.
    expect(normalized.length, greaterThan(2));
    expect(normalized[0], 0xFF);
    expect(normalized[1], 0xD8);
    expect(img.decodeJpg(normalized), isNotNull);
  });

  test('throws for bytes that cannot be decoded as an image at all', () {
    final garbage = Uint8List.fromList(List<int>.filled(32, 0x00));
    expect(
      () => normalizeLocationPhoto(garbage),
      throwsA(isA<UnsupportedLocationPhotoFormat>()),
    );
  });
}
