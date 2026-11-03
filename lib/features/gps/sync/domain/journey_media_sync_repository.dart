import 'dart:typed_data';

/// How a remote media operation failed, as classified by a
/// [JourneyMediaSyncRepository] implementation (Journey Phase 1H-E2B).
///
/// Only these three outcomes exist. There is deliberately no "absent" or
/// "deleted" classification: a Storage 404 / NoSuchKey can be an
/// authorization artifact, so it is never evidence of absence and is always
/// [indeterminate].
enum JourneyMediaRemoteFailureKind {
  /// Something already holds this identity (Storage body `409`, PostgREST
  /// `23505`). Proves nothing by itself -- the caller must inspect (download
  /// and compare bytes, or select and compare fields) before trusting it.
  duplicate,

  /// A definitive rejection of this exact payload (e.g. Storage `413`/`415`,
  /// an invalid object key, a PostgREST constraint violation). Retrying the
  /// same request cannot succeed.
  permanent,

  /// No knowledge: network/timeout, auth/session, any Storage `401`/`403`/
  /// `404`, PostgREST `42501` (indistinguishable from a missing session),
  /// `429`, `5xx`, an unexpected or malformed response, or anything
  /// unrecognized. Never changes local state, never triggers a destructive
  /// or compensating action.
  indeterminate,
}

/// Thrown by [JourneyMediaSyncRepository] for every failure. [reason] is a
/// short, sanitized description (codes only -- never tokens, URLs or raw
/// server text), safe for logs and never shown to users.
class JourneyMediaSyncException implements Exception {
  const JourneyMediaSyncException(this.kind, this.reason);
  final JourneyMediaRemoteFailureKind kind;
  final String reason;

  @override
  String toString() => 'JourneyMediaSyncException(${kind.name}): $reason';
}

/// The client-controlled columns of a `route_media` insert. There is no
/// owner field on purpose: the server stamps `owner_id` from `auth.uid()`
/// and `authenticated` has no INSERT privilege on that column.
class JourneyMediaRowPayload {
  const JourneyMediaRowPayload({
    required this.id,
    required this.recordedRouteId,
    required this.waypointId,
    required this.mediaType,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String recordedRouteId;
  final String? waypointId;
  final String mediaType;
  final DateTime capturedAt;

  /// Standalone media only (both or neither). Moment media inherit the
  /// Moment's telemetry and never carry a position.
  final double? latitude;
  final double? longitude;
}

/// A `route_media` row as the server stored it, with `position` already
/// decoded (null when the row has no position).
class JourneyMediaRemoteRow {
  const JourneyMediaRemoteRow({
    required this.id,
    required this.recordedRouteId,
    required this.ownerId,
    required this.waypointId,
    required this.mediaType,
    required this.capturedAt,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String recordedRouteId;
  final String ownerId;
  final String? waypointId;
  final String mediaType;
  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;
}

/// The network boundary for Journey media sync: the private `journey_media`
/// Storage bucket and the immutable `route_media` table. Implementations
/// throw [JourneyMediaSyncException] for every failure and return normally
/// ONLY on positive evidence.
///
/// There is deliberately no delete/remove method: remote media deletion is
/// deferred (D-2) and no E2B code path may delete anything remotely.
abstract interface class JourneyMediaSyncRepository {
  /// Uploads the canonical JPEG to [objectPath] (`<uid>/<routeId>/<id>.jpg`)
  /// with overwrite disabled. Returns only if the service reports the object
  /// created at exactly that key.
  Future<void> uploadObject({
    required String objectPath,
    required Uint8List bytes,
  });

  /// The object's bytes, downloaded with the caller's session.
  Future<Uint8List> downloadObject(String objectPath);

  /// Returns only on a positive 2xx description of exactly [objectPath].
  Future<void> objectInfo(String objectPath);

  /// Inserts one row and returns the row as stored (never an upsert).
  Future<JourneyMediaRemoteRow> insertRow(JourneyMediaRowPayload row);

  /// The caller-visible row with this id, or `null` when the authenticated
  /// select returned no row.
  Future<JourneyMediaRemoteRow?> selectRow(String id);
}
