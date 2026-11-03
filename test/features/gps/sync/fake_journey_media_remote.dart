import 'dart:typed_data';

import 'package:flutter_application_1/features/gps/sync/domain/journey_media_sync_repository.dart';

/// Hand-rolled, STATEFUL fake of the remote media backend (this project uses
/// no mocking library). It behaves like the hosted contract the design
/// relies on: an object path can be created once (a second upload is a
/// duplicate, never an overwrite), a `route_media` id can be inserted once
/// (a second insert is a duplicate), the server stamps `owner_id` from the
/// live session, and a missing object reads as INDETERMINATE (a 404 is never
/// absence). Every call is logged; scripted hooks inject failures, side
/// effects and identity changes deterministically.
class FakeJourneyMediaRemote implements JourneyMediaSyncRepository {
  FakeJourneyMediaRemote({required this.liveUid});

  /// The server's view of `auth.uid()` (stamped into inserted rows).
  final String? Function() liveUid;

  final objects = <String, Uint8List>{};
  final rows = <String, JourneyMediaRemoteRow>{};

  /// Row ids that exist but belong to another account: inserting one is a
  /// duplicate, selecting one returns nothing (RLS).
  final hiddenRowIds = <String>{};

  /// `op` or `op:<key>` entries in call order (`upload`, `download`, `info`,
  /// `insert`, `select`).
  final calls = <String>[];
  final insertedPayloads = <JourneyMediaRowPayload>[];
  int objectWrites = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  /// Called first on every operation (e.g. to flip the live uid, or to
  /// change local state "concurrently").
  void Function(String op)? onCall;

  /// Thrown before the operation has any effect.
  JourneyMediaSyncException? Function(String op)? failBefore;

  /// Thrown AFTER the operation took effect -- a lost response / crash
  /// right after the server committed.
  JourneyMediaSyncException? Function(String op)? failAfter;

  /// Optional gate held open inside every operation (concurrency tests).
  Future<void> Function(String op)? gate;

  /// Optional hold AFTER the operation took effect -- a request that
  /// committed remotely but whose response never arrives (timeout tests).
  Future<void> Function(String op)? stallAfter;

  static const notFound = JourneyMediaSyncException(
      JourneyMediaRemoteFailureKind.indeterminate, 'storage statusCode=404');

  Future<T> _op<T>(String op, String key, T Function() body) async {
    calls.add(op);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      onCall?.call(op);
      await Future<void>.delayed(Duration.zero);
      if (gate != null) await gate!(op);
      final before = failBefore?.call(op);
      if (before != null) throw before;
      final result = body();
      if (stallAfter != null) await stallAfter!(op);
      final after = failAfter?.call(op);
      if (after != null) throw after;
      return result;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<void> uploadObject({
    required String objectPath,
    required Uint8List bytes,
  }) =>
      _op('upload', objectPath, () {
        if (objects.containsKey(objectPath)) {
          throw const JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.duplicate,
              'storage statusCode=409');
        }
        objects[objectPath] = Uint8List.fromList(bytes);
        objectWrites++;
      });

  @override
  Future<Uint8List> downloadObject(String objectPath) =>
      _op('download', objectPath, () {
        final bytes = objects[objectPath];
        if (bytes == null) throw notFound;
        return Uint8List.fromList(bytes);
      });

  @override
  Future<void> objectInfo(String objectPath) => _op('info', objectPath, () {
        if (!objects.containsKey(objectPath)) throw notFound;
      });

  @override
  Future<JourneyMediaRemoteRow> insertRow(JourneyMediaRowPayload row) =>
      _op('insert', row.id, () {
        if (rows.containsKey(row.id) || hiddenRowIds.contains(row.id)) {
          throw const JourneyMediaSyncException(
              JourneyMediaRemoteFailureKind.duplicate, 'postgrest code=23505');
        }
        insertedPayloads.add(row);
        final stored = JourneyMediaRemoteRow(
          id: row.id,
          recordedRouteId: row.recordedRouteId,
          ownerId: liveUid() ?? 'anon',
          waypointId: row.waypointId,
          mediaType: row.mediaType,
          capturedAt: row.capturedAt.toUtc(),
          latitude: row.latitude,
          longitude: row.longitude,
        );
        rows[row.id] = stored;
        return stored;
      });

  @override
  Future<JourneyMediaRemoteRow?> selectRow(String id) =>
      _op('select', id, () => rows[id]);

  /// A remote row equal to what a correct insert of [payload] by [ownerId]
  /// would have stored -- for seeding pre-existing remote state.
  static JourneyMediaRemoteRow rowFor(
    JourneyMediaRowPayload payload, {
    required String ownerId,
  }) =>
      JourneyMediaRemoteRow(
        id: payload.id,
        recordedRouteId: payload.recordedRouteId,
        ownerId: ownerId,
        waypointId: payload.waypointId,
        mediaType: payload.mediaType,
        capturedAt: payload.capturedAt.toUtc(),
        latitude: payload.latitude,
        longitude: payload.longitude,
      );
}
