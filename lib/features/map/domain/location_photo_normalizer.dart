import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Phase 2.2A1: every location photo is normalized before it ever reaches
/// [LocationsRepository.createLocation]/Supabase Storage. This exists
/// because the picker's own native output (see
/// `ios/Runner`/`android/app`'s `image_picker` plugin -- already
/// confirmed by reading its installed source, not assumed) already
/// re-encodes everything to JPEG, but does **not** strip EXIF -- on both
/// platforms the plugin explicitly re-embeds the original photo's EXIF
/// (including GPS, if the phone recorded it) into its output. Since the
/// `location_images` Storage bucket is fully publicly readable with no
/// per-object access check, any surviving GPS EXIF would be publicly
/// exposed. This module removes that risk entirely, independent of
/// anything the native plugin does.
///
/// Deliberately pure Dart (the `image` package), not a native-compression
/// plugin: this makes the whole pipeline -- resize, orientation bake, EXIF
/// strip, JPEG re-encode -- directly unit-testable in plain `flutter
/// test`/`dart test` with real bytes, with no platform-channel mocking.
/// It also keeps behavior identical across Android/iOS by construction,
/// since it's the same Dart code either way.
///
/// Runs on bytes [ImagePicker] already returned with `imageQuality: 85,
/// maxWidth: 1920` applied (see `create_location_screen.dart`), so the
/// decode step here always operates on an already-bounded-size image
/// (long edge already <= 1920px), never a raw multi-megapixel phone
/// original -- keeping peak decode memory well within a few megabytes of
/// pixel buffer on any device, not a concern specific to mid-range
/// hardware.
const int locationPhotoMaxLongEdgePx = 1600;
const int locationPhotoJpegQuality = 80;

/// Thrown when [sourceBytes] cannot be decoded as an image at all.
class UnsupportedLocationPhotoFormat implements Exception {
  const UnsupportedLocationPhotoFormat();

  @override
  String toString() => 'UnsupportedLocationPhotoFormat: '
      'could not decode the picked photo as an image.';
}

/// Decodes [sourceBytes] (format auto-detected -- never assumed from a
/// filename/extension, per the audit's own finding that extension-based
/// sniffing is unreliable), bakes any EXIF orientation into the actual
/// pixels (so display is correct even for a viewer that ignores EXIF
/// orientation), resizes so its long edge is at most
/// [locationPhotoMaxLongEdgePx] (never upscales a smaller source), strips
/// **all** EXIF metadata (not just GPS -- "no unnecessary EXIF metadata"),
/// and re-encodes as JPEG at [locationPhotoJpegQuality]. The original
/// bytes are never uploaded; this is always what gets written to Storage.
Uint8List normalizeLocationPhoto(Uint8List sourceBytes) {
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const UnsupportedLocationPhotoFormat();
  }

  final isLandscape = decoded.width >= decoded.height;
  final longEdge = isLandscape ? decoded.width : decoded.height;
  final targetLongEdge = longEdge > locationPhotoMaxLongEdgePx
      ? locationPhotoMaxLongEdgePx
      : longEdge;

  // copyResize itself bakes EXIF orientation into the output pixels
  // before resizing (confirmed by reading image 4.9.2's own
  // copy_resize.dart), so this single call handles both the resize and
  // the orientation correction -- there is no separate "still need to
  // bake orientation" branch for the already-small-enough case, since
  // copyResize always runs (even when the target size equals the
  // source size) and always applies that same orientation check first.
  final resized = img.copyResize(
    decoded,
    width: isLandscape ? targetLongEdge : null,
    height: isLandscape ? null : targetLongEdge,
  );

  // Strip every EXIF tag -- GPS included -- rather than only the
  // orientation tag copyResize already cleared. An empty ExifData makes
  // the JPEG encoder skip writing an EXIF segment entirely (confirmed by
  // reading JpegEncoder._writeExif: it returns immediately when
  // `exif.isEmpty`), so the output file carries no EXIF block at all.
  resized.exif = img.ExifData();

  return Uint8List.fromList(
    img.encodeJpg(resized, quality: locationPhotoJpegQuality),
  );
}
