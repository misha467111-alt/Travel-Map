import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../map/domain/location_photo_normalizer.dart';
import '../local/gps_local_database.dart';
import '../local/gps_local_database_provider.dart';
import 'journey_media_storage.dart';

/// Journey Phase 1H-B -- local, offline-first Journey media operations:
///
///     future UI -> JourneyMediaService -> app-owned file + Drift row
///
/// No network, no Supabase, no upload: a successful add leaves a normalized
/// app-owned file and a `pending` [LocalJourneyMediaItem], readable at once.
/// Image bytes are normalized by the one existing implementation,
/// [normalizeLocationPhoto] (orientation baked in, long edge <= 1600 px,
/// JPEG q80, all EXIF/GPS stripped) -- there is no second compressor.
class JourneyMediaService {
  JourneyMediaService({
    required GpsLocalDatabase db,
    required JourneyMediaStorage storage,
    String Function()? newMediaId,
    DateTime Function()? clock,
    Uint8List Function(Uint8List)? normalizer,
  })  : _db = db,
        _storage = storage,
        _newMediaId = newMediaId ?? (() => const Uuid().v4()),
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _normalizer = normalizer ?? normalizeLocationPhoto,
        _usesCanonicalNormalizer = normalizer == null;

  final GpsLocalDatabase _db;
  final JourneyMediaStorage _storage;
  final String Function() _newMediaId;
  final DateTime Function() _clock;
  final Uint8List Function(Uint8List) _normalizer;
  final bool _usesCanonicalNormalizer;

  /// Adds one image from raw [sourceBytes] (e.g. a picker result).
  ///
  /// Ordering is chosen so a failure never leaves an orphan row or an
  /// unintended canonical file:
  ///   1. validate the target (route/Moment for this owner) -- nothing
  ///      written if it is invalid;
  ///   2. normalize -- a non-image throws [UnsupportedLocationPhotoFormat]
  ///      with nothing written;
  ///   3. write the file atomically (new path only, never overwrites);
  ///   4. insert the row; if that fails, delete exactly the file created in
  ///      step 3 and rethrow.
  /// Crash window: a process death between steps 3 and 4 leaves one
  /// unreferenced file under `journey_media/` (no row, so nothing breaks);
  /// the reverse failure -- a row without a file -- cannot be produced by
  /// this ordering.
  ///
  /// [latitude]/[longitude] are for standalone media only (both or neither);
  /// media attached to a Moment ([waypointId]) must not carry a position and
  /// never alters the Moment.
  Future<LocalJourneyMediaItem> addImageBytes({
    required String ownerId,
    required String recordedRouteId,
    required Uint8List sourceBytes,
    String? waypointId,
    DateTime? capturedAt,
    double? latitude,
    double? longitude,
  }) async {
    await _db.assertJourneyMediaTarget(
      ownerId: ownerId,
      recordedRouteId: recordedRouteId,
      waypointId: waypointId,
      latitude: latitude,
      longitude: longitude,
    );
    final Uint8List normalized;
    try {
      normalized = _normalizer(sourceBytes);
    } on UnsupportedLocationPhotoFormat {
      rethrow;
    } on img.ImageException {
      // Decoder-reported malformed/unsupported image data gets the public
      // normalization error. Unrelated programming errors are not hidden.
      throw const UnsupportedLocationPhotoFormat();
    } on RangeError {
      // image 4.9.2 can surface truncated data as RangeError. Only translate
      // that known decoder path for the canonical normalizer; an injected
      // normalizer's RangeError remains visible as a programming failure.
      if (!_usesCanonicalNormalizer) rethrow;
      throw const UnsupportedLocationPhotoFormat();
    }

    final mediaId = _newMediaId();
    final relativePath = JourneyMediaStorage.relativePathFor(
        recordedRouteId: recordedRouteId, mediaId: mediaId);
    await _storage.writeNew(relativePath, normalized);
    try {
      return await _db.insertJourneyMedia(
        id: mediaId,
        ownerId: ownerId,
        recordedRouteId: recordedRouteId,
        waypointId: waypointId,
        capturedAt: (capturedAt ?? _clock()).toUtc(),
        latitude: latitude,
        longitude: longitude,
        localRelativePath: relativePath,
      );
    } catch (_) {
      await _storage.deleteFile(relativePath);
      rethrow;
    }
  }

  /// [addImageBytes] for a source file (e.g. a gallery/camera temp file).
  /// The source is only read: the canonical file is always a separate,
  /// normalized copy, so deleting or moving the source later changes
  /// nothing. A missing/unreadable source throws with nothing written.
  Future<LocalJourneyMediaItem> addImageFile({
    required String ownerId,
    required String recordedRouteId,
    required File source,
    String? waypointId,
    DateTime? capturedAt,
    double? latitude,
    double? longitude,
  }) async {
    final bytes = await source.readAsBytes();
    return addImageBytes(
      ownerId: ownerId,
      recordedRouteId: recordedRouteId,
      sourceBytes: bytes,
      waypointId: waypointId,
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Deletes one media item through the shared lifecycle: never-synced media
  /// is removed (row, then file); possibly-synced media becomes a
  /// `pendingDelete` tombstone. The local file is deleted in both cases --
  /// the user removed it, and a future remote deletion needs only the ids.
  /// The file is removed only AFTER the database transaction commits, so a
  /// crash in between can only leave a harmless unreferenced file.
  Future<JourneyMediaDeleteOutcome> deleteMedia({
    required String ownerId,
    required String recordedRouteId,
    required String mediaId,
  }) async {
    final item = await _db.getJourneyMediaItem(
        ownerId: ownerId, recordedRouteId: recordedRouteId, id: mediaId);
    if (item == null) return JourneyMediaDeleteOutcome.notFound;
    final outcome = await _db.deleteJourneyMedia(
        ownerId: ownerId, recordedRouteId: recordedRouteId, id: mediaId);
    if (outcome != JourneyMediaDeleteOutcome.notFound) {
      await _storage.deleteFile(item.localRelativePath);
    }
    return outcome;
  }

  /// The item's file under the CURRENT documents root, or `null` if it is
  /// missing/invalid. Never deletes the row and never throws for a missing
  /// file, so a UI can show an "unavailable" placeholder.
  Future<File?> resolveFile(LocalJourneyMediaItem item) =>
      _storage.existingFile(item.localRelativePath);
}

final journeyMediaServiceProvider = Provider<JourneyMediaService>((ref) {
  return JourneyMediaService(
    db: ref.watch(gpsLocalDatabaseProvider),
    storage: ref.watch(journeyMediaStorageProvider),
  );
});
