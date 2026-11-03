import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/journey_media_sync_repository.dart';

/// Journey Phase 1H-E2B -- talks to the private `journey_media` Storage
/// bucket and the immutable `route_media` table (applied in
/// `202609180001_journey_media_backend.sql`) with the signed-in user's own
/// session. Never uses a service key, never overwrites an object, never
/// updates or upserts a row, and has no delete path at all.
///
/// Every method returns normally only on positive evidence; everything else
/// is a [JourneyMediaSyncException] classified by [classify].
class SupabaseJourneyMediaSyncRepository implements JourneyMediaSyncRepository {
  const SupabaseJourneyMediaSyncRepository(this._client);
  final SupabaseClient _client;

  static const bucket = 'journey_media';
  static const _table = 'route_media';
  static const _columns =
      'id,recorded_route_id,owner_id,waypoint_id,media_type,captured_at,position';

  @override
  Future<void> uploadObject({
    required String objectPath,
    required Uint8List bytes,
  }) async {
    final String key;
    try {
      key = await _client.storage.from(bucket).uploadBinary(
            objectPath,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: false),
            retryAttempts: 0,
          );
    } catch (error) {
      throw classify(error);
    }
    // A bare 2xx is not proof: the service must report exactly our key.
    if (key != '$bucket/$objectPath') {
      throw const JourneyMediaSyncException(
          JourneyMediaRemoteFailureKind.indeterminate,
          'upload returned an unexpected key');
    }
  }

  @override
  Future<Uint8List> downloadObject(String objectPath) async {
    try {
      return await _client.storage.from(bucket).download(objectPath);
    } catch (error) {
      throw classify(error);
    }
  }

  @override
  Future<void> objectInfo(String objectPath) async {
    final FileObjectV2 info;
    try {
      info = await _client.storage.from(bucket).info(objectPath);
    } catch (error) {
      throw classify(error);
    }
    // Exact identity only: `name` is the object's full key in the bucket
    // (storage.objects.name). Anything else proves nothing.
    if (info.bucketId != bucket || info.name != objectPath) {
      throw const JourneyMediaSyncException(
          JourneyMediaRemoteFailureKind.indeterminate,
          'object info described a different object');
    }
  }

  @override
  Future<JourneyMediaRemoteRow> insertRow(JourneyMediaRowPayload row) async {
    final payload = <String, dynamic>{
      'id': row.id,
      'recorded_route_id': row.recordedRouteId,
      'media_type': row.mediaType,
      'captured_at': row.capturedAt.toUtc().toIso8601String(),
      if (row.waypointId != null) 'waypoint_id': row.waypointId,
      if (row.latitude != null && row.longitude != null)
        'position': 'SRID=4326;POINT(${row.longitude} ${row.latitude})',
    };
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client.from(_table).insert(payload).select(_columns);
    } catch (error) {
      throw classify(error);
    }
    // Success without the stored row is not proof of anything.
    if (rows.length != 1) {
      throw JourneyMediaSyncException(
          JourneyMediaRemoteFailureKind.indeterminate,
          'insert returned ${rows.length} rows');
    }
    return parseRow(rows.single);
  }

  @override
  Future<JourneyMediaRemoteRow?> selectRow(String id) async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _client.from(_table).select(_columns).eq('id', id);
    } catch (error) {
      throw classify(error);
    }
    if (rows.isEmpty) return null;
    if (rows.length != 1) {
      throw JourneyMediaSyncException(
          JourneyMediaRemoteFailureKind.indeterminate,
          'select returned ${rows.length} rows');
    }
    return parseRow(rows.single);
  }

  /// Maps any failure onto the three outcome classes. Storage errors are
  /// classified by [StorageException.statusCode], which the installed
  /// storage client takes from the response BODY (`statusCode`), so an outer
  /// HTTP 400 wrapping 403/409/413/415 is classified by its inner code.
  /// Anything not positively recognized is [indeterminate] -- never a reason
  /// to change local state. Reasons carry codes only, never raw server text.
  static JourneyMediaSyncException classify(Object error) {
    if (error is JourneyMediaSyncException) return error;
    if (error is TimeoutException) {
      return const JourneyMediaSyncException(
          JourneyMediaRemoteFailureKind.indeterminate, 'timed out');
    }
    if (error is StorageException) {
      final code = error.statusCode;
      switch (code) {
        case '409':
          return const JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.duplicate,
              'storage statusCode=409');
        case '413':
        case '415':
          return JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.permanent,
              'storage statusCode=$code');
        case '400':
          if (_isInvalidKey(error)) {
            return const JourneyMediaSyncException(
                JourneyMediaRemoteFailureKind.permanent,
                'storage statusCode=400 invalid key');
          }
          return const JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.indeterminate,
              'storage statusCode=400');
        default:
          // 401/403 (expired token and RLS denial are not reliably
          // distinguishable), 404/NoSuchKey (can hide authorization), 429,
          // 5xx, and non-HTTP failures wrapped by the client.
          return JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.indeterminate,
              'storage statusCode=$code');
      }
    }
    if (error is PostgrestException) {
      final code = error.code;
      switch (code) {
        case '23505':
          return const JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.duplicate, 'postgrest code=23505');
        case '23514': // check violation
        case '22023': // invalid parameter value
        case '22P02': // invalid text representation
        case '23503': // foreign key violation
          return JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.permanent, 'postgrest code=$code');
        // 42501 is deliberately NOT permanent: with no session the installed
        // client's AuthHttpClient sends the anon key, and `route_media`
        // (no anon privileges) then answers 42501 -- the same code as a
        // genuine policy/trigger rejection. Like Storage 403, it is
        // indistinguishable from an auth/session problem, so it never parks
        // an item as failed.
        default:
          return JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.indeterminate,
              'postgrest code=$code');
      }
    }
    return JourneyMediaSyncException(
        JourneyMediaRemoteFailureKind.indeterminate,
        'unclassified ${error.runtimeType}');
  }

  static bool _isInvalidKey(StorageException error) =>
      error.error == 'InvalidKey' ||
      error.message.toLowerCase().contains('invalid key');

  /// Parses a stored row. Any unexpected shape is [indeterminate]: a row the
  /// client cannot read cannot be proven to match.
  static JourneyMediaRemoteRow parseRow(Map<String, dynamic> json) {
    try {
      final position = json['position'];
      final (double, double)? coordinates =
          position == null ? null : _decodePoint(position);
      return JourneyMediaRemoteRow(
        id: json['id'] as String,
        recordedRouteId: json['recorded_route_id'] as String,
        ownerId: json['owner_id'] as String,
        waypointId: json['waypoint_id'] as String?,
        mediaType: json['media_type'] as String,
        capturedAt: DateTime.parse(json['captured_at'] as String).toUtc(),
        longitude: coordinates?.$1,
        latitude: coordinates?.$2,
      );
    } catch (_) {
      throw const JourneyMediaSyncException(
          JourneyMediaRemoteFailureKind.indeterminate,
          'route_media row has an unexpected shape');
    }
  }

  /// `(longitude, latitude)` from PostgREST's geography output: hex EWKB
  /// (the default) or GeoJSON. A private copy, because the map feature's
  /// parser is private to `LocationModel`.
  static (double, double) _decodePoint(Object value) {
    if (value is Map && value['coordinates'] is List) {
      final c = value['coordinates'] as List;
      return ((c[0] as num).toDouble(), (c[1] as num).toDouble());
    }
    if (value is! String ||
        value.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
      throw const FormatException('unsupported point encoding');
    }
    final bytes = Uint8List(value.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
    }
    if (bytes.length < 21) throw const FormatException('EWKB too short');
    final data = ByteData.sublistView(bytes);
    final endian = bytes[0] == 0 ? Endian.big : Endian.little;
    final type = data.getUint32(1, endian);
    if (type & 0xFF != 1) throw const FormatException('EWKB is not a point');
    final offset = (type & 0x20000000) != 0 ? 9 : 5;
    if (bytes.length < offset + 16) {
      throw const FormatException('EWKB point has no coordinates');
    }
    return (
      data.getFloat64(offset, endian),
      data.getFloat64(offset + 8, endian),
    );
  }
}
