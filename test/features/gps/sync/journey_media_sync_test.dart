import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:image/image.dart' as img;
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_storage.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';
import 'package:flutter_application_1/features/gps/sync/data/supabase_journey_media_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/domain/journey_media_sync_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:flutter_application_1/features/gps/sync/journey_media_sync.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';
import 'fake_journey_media_remote.dart';

/// Lets a test hold [finishRecordingLocally] open (to observe `finishing`),
/// make the next [markJourneyMediaSynced] throw once (a crash between the
/// remote proof and the local acknowledgement), run an awaited hook right
/// after an acknowledgement committed ([afterAck], e.g. an account switch or
/// a recording starting between two items), and suspend a photo's local
/// preflight deterministically ([onMediaRead], awaited at the start of every
/// [getJourneyMediaItem]; [mediaReads] records every id read, [ackCalls]
/// counts every [markJourneyMediaSynced] attempt).
class _GatedDb extends GpsLocalDatabase {
  _GatedDb(super.executor) : super.forTesting();
  Completer<void>? finishGate;
  bool failNextAck = false;
  FutureOr<void> Function()? afterAck;
  Future<void> Function(String id)? onMediaRead;
  final mediaReads = <String>[];
  int ackCalls = 0;

  @override
  Future<LocalJourneyMediaItem?> getJourneyMediaItem({
    required String ownerId,
    required String recordedRouteId,
    required String id,
  }) async {
    mediaReads.add(id);
    final hook = onMediaRead;
    if (hook != null) await hook(id);
    return super.getJourneyMediaItem(
        ownerId: ownerId, recordedRouteId: recordedRouteId, id: id);
  }

  @override
  Future<void> finishRecordingLocally({
    required String ownerId,
    required String routeId,
    required DateTime occurredAt,
  }) async {
    final gate = finishGate;
    if (gate != null) await gate.future;
    return super.finishRecordingLocally(
        ownerId: ownerId, routeId: routeId, occurredAt: occurredAt);
  }

  @override
  Future<bool> markJourneyMediaSynced({
    required String ownerId,
    required String recordedRouteId,
    required String id,
  }) {
    ackCalls++;
    if (failNextAck) {
      failNextAck = false;
      return Future.error(Exception('process died before the local ack'));
    }
    return super
        .markJourneyMediaSynced(
            ownerId: ownerId, recordedRouteId: recordedRouteId, id: id)
        .then((acknowledged) async {
      await afterAck?.call();
      return acknowledged;
    });
  }
}

String uuid(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

Uint8List jpeg({int seed = 1}) {
  final image = img.Image(width: 12, height: 10, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(seed * 30 % 255, 90, 160));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final owner = uuid(900);
  final t0 = DateTime.utc(2026, 3, 1, 9);
  late Directory root;
  late _GatedDb db;
  late JourneyMediaStorage storage;
  late FakeJourneyMediaRemote remote;
  late JourneyMediaSync sync;
  String? liveUid;

  setUp(() async {
    liveUid = owner;
    root = await Directory.systemTemp.createTemp('journey_media_sync_test_');
    db = _GatedDb(NativeDatabase.memory());
    storage = JourneyMediaStorage(rootDirectory: () async => root);
    remote = FakeJourneyMediaRemote(liveUid: () => liveUid);
    sync = JourneyMediaSync(db: db, storage: storage, repository: remote);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<JourneyMediaPhaseResult> runPhaseResult({
    Iterable<String>? routeIds,
    bool Function()? shouldYield,
    JourneyMediaSync? using,
    String? Function()? identity,
  }) =>
      (using ?? sync).runPhase(
        ownerId: owner,
        currentUserId: identity ?? () => liveUid,
        routeIds: routeIds,
        shouldYield: shouldYield,
      );

  Future<JourneyMediaPhaseOutcome> runPhase({
    Iterable<String>? routeIds,
    bool Function()? shouldYield,
    JourneyMediaSync? using,
    String? Function()? identity,
  }) async =>
      (await runPhaseResult(
              routeIds: routeIds,
              shouldYield: shouldYield,
              using: using,
              identity: identity))
          .outcome;

  Future<void> startRoute(String routeId) =>
      db.createLocalRecordedRoute(id: routeId, ownerId: owner, startedAt: t0);

  Future<void> addMoment(String routeId, String id,
      {bool synced = true}) async {
    await db.addWaypoint(
      id: id,
      ownerId: owner,
      recordedRouteId: routeId,
      waypointType: 'viewpoint',
      latitude: 50.1,
      longitude: 30.2,
      recordedAt: t0,
    );
    if (synced) await db.markWaypointSynced(ownerId: owner, id: id);
  }

  Future<LocalJourneyMediaItem> addMedia(
    String routeId,
    String id, {
    String? waypointId,
    double? lat = 50.4501,
    double? lng = 30.5234,
    Uint8List? bytes,
    bool writeFile = true,
    DateTime? capturedAt,
  }) async {
    final path = JourneyMediaStorage.relativePathFor(
        recordedRouteId: routeId, mediaId: id);
    if (writeFile) await storage.writeNew(path, bytes ?? jpeg());
    return db.insertJourneyMedia(
      id: id,
      ownerId: owner,
      recordedRouteId: routeId,
      waypointId: waypointId,
      capturedAt: capturedAt ?? t0,
      latitude: waypointId == null ? lat : null,
      longitude: waypointId == null ? lng : null,
      localRelativePath: path,
    );
  }

  Future<void> finish(String routeId,
      {String routeSync = RouteSyncStatus.synced}) async {
    await db.finishRecordingLocally(
        ownerId: owner, routeId: routeId, occurredAt: t0);
    await db.recordRouteSyncOutcome(
        ownerId: owner, routeId: routeId, syncStatus: routeSync);
  }

  /// One completed + synced Journey with one standalone pending photo.
  Future<LocalJourneyMediaItem> oneSyncedJourneyPhoto(
      {String route = '',
      int media = 1,
      Uint8List? bytes,
      bool writeFile = true}) async {
    final routeId = route.isEmpty ? uuid(1) : route;
    await startRoute(routeId);
    final item = await addMedia(routeId, uuid(100 + media),
        bytes: bytes, writeFile: writeFile);
    await finish(routeId);
    return item;
  }

  Future<String?> status(LocalJourneyMediaItem item) async =>
      (await db.getJourneyMediaItem(
              ownerId: owner,
              recordedRouteId: item.recordedRouteId,
              id: item.id))
          ?.syncStatus;

  String pathOf(LocalJourneyMediaItem item) => JourneyMediaSync.objectPathFor(
      ownerId: owner, recordedRouteId: item.recordedRouteId, mediaId: item.id);

  JourneyMediaRowPayload payloadOf(LocalJourneyMediaItem item) =>
      JourneyMediaRowPayload(
        id: item.id,
        recordedRouteId: item.recordedRouteId,
        waypointId: item.waypointId,
        mediaType: item.mediaType,
        capturedAt: item.capturedAt,
        latitude: item.latitude,
        longitude: item.longitude,
      );

  Future<Uint8List> localBytes(LocalJourneyMediaItem item) async =>
      (await storage.existingFile(item.localRelativePath))!.readAsBytes();

  void seedObject(LocalJourneyMediaItem item, Uint8List bytes) =>
      remote.objects[pathOf(item)] = Uint8List.fromList(bytes);

  void seedRow(LocalJourneyMediaItem item, {DateTime? capturedAt}) {
    final row = FakeJourneyMediaRemote.rowFor(payloadOf(item), ownerId: owner);
    remote.rows[item.id] = capturedAt == null
        ? row
        : JourneyMediaRemoteRow(
            id: row.id,
            recordedRouteId: row.recordedRouteId,
            ownerId: row.ownerId,
            waypointId: row.waypointId,
            mediaType: row.mediaType,
            capturedAt: capturedAt,
            latitude: row.latitude,
            longitude: row.longitude,
          );
  }

  const indeterminate = JourneyMediaSyncException(
      JourneyMediaRemoteFailureKind.indeterminate, 'scripted');
  const permanent = JourneyMediaSyncException(
      JourneyMediaRemoteFailureKind.permanent, 'scripted');

  // -------------------------------------------------------------------
  // Eligibility (S01-S08)
  // -------------------------------------------------------------------

  test(
      'S01 standalone photo (P1): object at <uid>/<route>/<id>.jpg, row with '
      'position, owner server-stamped, local synced', () async {
    final item = await oneSyncedJourneyPhoto();

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);

    expect(remote.objects[pathOf(item)], await localBytes(item));
    expect(pathOf(item), '$owner/${item.recordedRouteId}/${item.id}.jpg');
    final payload = remote.insertedPayloads.single;
    expect(payload.latitude, 50.4501);
    expect(payload.longitude, 30.5234);
    expect(payload.waypointId, isNull);
    expect(remote.rows[item.id]!.ownerId, owner,
        reason: 'owner is stamped by the server, never sent');
    expect(await status(item), JourneyMediaSyncStatus.synced);
  });

  test('S02 Moment photo (P1): waypoint_id sent, no position, synced',
      () async {
    final routeId = uuid(1);
    await startRoute(routeId);
    await addMoment(routeId, uuid(50));
    final item = await addMedia(routeId, uuid(101), waypointId: uuid(50));
    await finish(routeId);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);

    final payload = remote.insertedPayloads.single;
    expect(payload.waypointId, uuid(50));
    expect(payload.latitude, isNull);
    expect(payload.longitude, isNull);
    expect(await status(item), JourneyMediaSyncStatus.synced);
  });

  test(
      'S03 a Moment photo whose waypoint is not synced yet is left pending '
      'with zero calls', () async {
    final routeId = uuid(1);
    await startRoute(routeId);
    await addMoment(routeId, uuid(50), synced: false);
    final item = await addMedia(routeId, uuid(101), waypointId: uuid(50));
    await finish(routeId);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, isEmpty);
    expect(await status(item), JourneyMediaSyncStatus.pending);
  });

  test('S04 recording and paused routes get zero calls', () async {
    final routeId = uuid(1);
    await startRoute(routeId);
    final item = await addMedia(routeId, uuid(101));
    await db.recordRouteSyncOutcome(
        ownerId: owner, routeId: routeId, syncStatus: RouteSyncStatus.synced);

    // The route itself is active, so the whole phase is deferred (P2-4).
    expect(
        await runPhase(), JourneyMediaPhaseOutcome.deferredForActiveRecording);
    expect(await runPhase(routeIds: [routeId]),
        JourneyMediaPhaseOutcome.deferredForActiveRecording);
    await db.pauseRecording(ownerId: owner, routeId: routeId, occurredAt: t0);
    expect(await runPhase(routeIds: [routeId]),
        JourneyMediaPhaseOutcome.deferredForActiveRecording);

    expect(remote.calls, isEmpty);
    expect(await status(item), JourneyMediaSyncStatus.pending);
  });

  test('S05 a completed route whose route sync is not synced gets zero calls',
      () async {
    final a = uuid(1), b = uuid(2);
    await startRoute(a);
    final itemA = await addMedia(a, uuid(101));
    await finish(a, routeSync: RouteSyncStatus.notSynced);
    await startRoute(b);
    final itemB = await addMedia(b, uuid(102));
    await finish(b, routeSync: RouteSyncStatus.failed);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(await runPhase(routeIds: [a, b]), JourneyMediaPhaseOutcome.clean);

    expect(remote.calls, isEmpty);
    expect(await status(itemA), JourneyMediaSyncStatus.pending);
    expect(await status(itemB), JourneyMediaSyncStatus.pending);
  });

  test('S06 a discarded route gets zero calls', () async {
    final routeId = uuid(1);
    await startRoute(routeId);
    final item = await addMedia(routeId, uuid(101));
    await db.discardRecording(ownerId: owner, routeId: routeId, occurredAt: t0);
    await db.recordRouteSyncOutcome(
        ownerId: owner, routeId: routeId, syncStatus: RouteSyncStatus.synced);

    expect(await runPhase(routeIds: [routeId]), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, isEmpty);
    expect(await status(item), JourneyMediaSyncStatus.pending);
  });

  test('S07 signed out or another account signed in -> not run, zero calls',
      () async {
    final item = await oneSyncedJourneyPhoto();

    liveUid = null;
    expect(await runPhase(), JourneyMediaPhaseOutcome.notRun);
    liveUid = uuid(901);
    expect(await runPhase(), JourneyMediaPhaseOutcome.notRun);

    expect(remote.calls, isEmpty);
    expect(await status(item), JourneyMediaSyncStatus.pending);
  });

  test('S08 the live uid changing mid-item is INDETERMINATE: nothing changes',
      () async {
    final item = await oneSyncedJourneyPhoto();
    remote.onCall = (op) {
      if (op == 'upload') liveUid = uuid(901);
    };

    expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate);
    expect(remote.calls, ['upload'], reason: 'no insert after identity change');
    expect(await status(item), JourneyMediaSyncStatus.pending);
  });

  // -------------------------------------------------------------------
  // Reconciliation matrix, local file present (S09-S15 = P1-P7)
  // -------------------------------------------------------------------

  test('S09 P1 neither remote exists: upload -> insert -> synced', () async {
    final item = await oneSyncedJourneyPhoto();
    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['upload', 'insert']);
    expect(await status(item), JourneyMediaSyncStatus.synced);
  });

  test(
      'S10 P2 matching row but no object: re-upload from local bytes, '
      'duplicate row verified -> synced', () async {
    final item = await oneSyncedJourneyPhoto();
    seedRow(item);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['upload', 'insert', 'select']);
    expect(remote.objects[pathOf(item)], await localBytes(item));
    expect(await status(item), JourneyMediaSyncStatus.synced);
  });

  test(
      'S11 P3 mismatched or foreign row -> failed; our object stays, '
      'nothing deleted', () async {
    final item = await oneSyncedJourneyPhoto(media: 1);
    seedRow(item, capturedAt: t0.add(const Duration(seconds: 1)));

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['upload', 'insert', 'select']);
    expect(remote.objects.containsKey(pathOf(item)), isTrue);
    expect(remote.rows[item.id]!.capturedAt, t0.add(const Duration(seconds: 1)),
        reason: 'never repaired by UPDATE');
    expect(await status(item), JourneyMediaSyncStatus.failed);

    // Variant: a row with this id owned by another account (invisible).
    final other = await oneSyncedJourneyPhoto(route: uuid(2), media: 2);
    remote.hiddenRowIds.add(other.id);
    remote.calls.clear();
    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['upload', 'insert', 'select']);
    expect(await status(other), JourneyMediaSyncStatus.failed);
  });

  test(
      'S12 P4 same object already uploaded, no row: duplicate + byte-equal '
      'download -> insert -> synced', () async {
    final item = await oneSyncedJourneyPhoto();
    seedObject(item, await localBytes(item));

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['upload', 'download', 'insert']);
    expect(remote.objectWrites, 0, reason: 'never overwritten');
    expect(await status(item), JourneyMediaSyncStatus.synced);
  });

  test('S13 P5 both already exist and match -> synced', () async {
    final item = await oneSyncedJourneyPhoto();
    seedObject(item, await localBytes(item));
    seedRow(item);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['upload', 'download', 'insert', 'select']);
    expect(await status(item), JourneyMediaSyncStatus.synced);
  });

  test('S14 P6 same object, mismatched row -> failed', () async {
    final item = await oneSyncedJourneyPhoto();
    seedObject(item, await localBytes(item));
    seedRow(item, capturedAt: t0.add(const Duration(minutes: 1)));

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(await status(item), JourneyMediaSyncStatus.failed);
  });

  test('S15 P7 different remote bytes -> failed, no insert, no overwrite',
      () async {
    final item = await oneSyncedJourneyPhoto();
    final foreign = jpeg(seed: 7);
    seedObject(item, foreign);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['upload', 'download']);
    expect(remote.objects[pathOf(item)], foreign);
    expect(remote.objectWrites, 0);
    expect(await status(item), JourneyMediaSyncStatus.failed);
  });

  // -------------------------------------------------------------------
  // Local file missing (S16-S19 = P8-P11): never upload, never insert
  // -------------------------------------------------------------------

  test('S16 P8 missing local file and no remote row -> failed (select only)',
      () async {
    final item = await oneSyncedJourneyPhoto(writeFile: false);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['select']);
    expect(await status(item), JourneyMediaSyncStatus.failed);
  });

  test('S17 P9 missing local file and a mismatched or foreign row -> failed',
      () async {
    final item = await oneSyncedJourneyPhoto(writeFile: false);
    seedRow(item, capturedAt: t0.add(const Duration(hours: 1)));
    final other =
        await oneSyncedJourneyPhoto(route: uuid(2), media: 2, writeFile: false);
    remote.hiddenRowIds.add(other.id);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['select', 'select']);
    expect(await status(item), JourneyMediaSyncStatus.failed);
    expect(await status(other), JourneyMediaSyncStatus.failed);
  });

  test(
      'S18 P10 missing local file but a verified remote pair -> synced '
      '(no upload, no insert, no retry loop)', () async {
    final item = await oneSyncedJourneyPhoto(writeFile: false);
    seedRow(item);
    seedObject(item, jpeg());

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, ['select', 'info']);
    expect(await status(item), JourneyMediaSyncStatus.synced);

    remote.calls.clear();
    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, isEmpty, reason: 'synced is terminal');
  });

  test(
      'S19 P11 missing local file, matching row, objectInfo 404 -> stays '
      'pending (never failed), phase stops; a later 2xx -> synced', () async {
    final item = await oneSyncedJourneyPhoto(writeFile: false);
    seedRow(item);
    final later = await oneSyncedJourneyPhoto(route: uuid(2), media: 2);

    expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate);
    expect(remote.calls, ['select', 'info'],
        reason: 'the phase stops: the next item is untouched');
    expect(await status(item), JourneyMediaSyncStatus.pending);
    expect(await status(later), JourneyMediaSyncStatus.pending);
    expect(remote.insertedPayloads, isEmpty);
    expect(remote.objectWrites, 0);

    seedObject(item, jpeg());
    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(await status(item), JourneyMediaSyncStatus.synced);
    expect(await status(later), JourneyMediaSyncStatus.synced);
  });

  // -------------------------------------------------------------------
  // Preflight and classification (S20-S23)
  // -------------------------------------------------------------------

  test('S20 local preflight failures -> failed with zero network calls',
      () async {
    final routeId = uuid(1);
    await startRoute(routeId);
    final big = Uint8List(JourneyMediaSync.maxImageBytes + 1)
      ..[0] = 0xFF
      ..[1] = 0xD8
      ..[2] = 0xFF;
    big[big.length - 2] = 0xFF;
    big[big.length - 1] = 0xD9;
    final tooBig = await addMedia(routeId, uuid(101), bytes: big);
    final empty = await addMedia(routeId, uuid(102), bytes: Uint8List(0));
    final notJpeg = await addMedia(routeId, uuid(103),
        bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]));
    final truncated = await addMedia(routeId, uuid(104),
        bytes: Uint8List.sublistView(jpeg(), 0, 40));
    final upper =
        await addMedia(routeId, 'ABCDEF00-0000-4000-8000-00000000010F');
    await finish(routeId);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, isEmpty);
    for (final item in [tooBig, empty, notJpeg, truncated, upper]) {
      expect(await status(item), JourneyMediaSyncStatus.failed,
          reason: item.id);
    }
  });

  test(
      'S21 every INDETERMINATE outcome leaves state unchanged and stops the '
      'phase', () async {
    for (final op in ['upload', 'download', 'insert', 'select']) {
      await db.delete(db.localJourneyMedia).go();
      remote
        ..objects.clear()
        ..rows.clear()
        ..calls.clear();
      final routeId =
          uuid(10 + ['upload', 'download', 'insert', 'select'].indexOf(op));
      await startRoute(routeId);
      final first = await addMedia(routeId, uuid(201));
      final second = await addMedia(routeId, uuid(202));
      await finish(routeId);
      if (op == 'download') seedObject(first, await localBytes(first));
      if (op == 'select') seedRow(first);
      remote.failBefore = (called) => called == op ? indeterminate : null;

      expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate,
          reason: op);
      expect(await status(first), JourneyMediaSyncStatus.pending, reason: op);
      expect(await status(second), JourneyMediaSyncStatus.pending, reason: op);
      expect(remote.calls.last, op, reason: 'nothing after the failure ($op)');
      remote.failBefore = null;
    }
  });

  test(
      'S22 every PERMANENT write outcome marks only that item failed and the '
      'phase continues', () async {
    for (final op in ['upload', 'insert']) {
      await db.delete(db.localJourneyMedia).go();
      remote
        ..objects.clear()
        ..rows.clear()
        ..calls.clear();
      final routeId = uuid(20 + (op == 'upload' ? 0 : 1));
      await startRoute(routeId);
      final first = await addMedia(routeId, uuid(301));
      final second = await addMedia(routeId, uuid(302));
      await finish(routeId);
      var failed = false;
      remote.failBefore = (called) {
        if (called == op && !failed) {
          failed = true;
          return permanent;
        }
        return null;
      };

      expect(await runPhase(), JourneyMediaPhaseOutcome.clean, reason: op);
      expect(await status(first), JourneyMediaSyncStatus.failed, reason: op);
      expect(await status(second), JourneyMediaSyncStatus.synced, reason: op);
      remote.failBefore = null;
    }
  });

  test('S23 a PERMANENT outcome after the uid changed is INDETERMINATE',
      () async {
    final item = await oneSyncedJourneyPhoto();
    remote.onCall = (op) {
      if (op == 'insert') liveUid = null; // signed out mid-item
    };
    remote.failBefore = (op) => op == 'insert' ? permanent : null; // e.g. 42501

    expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate);
    expect(await status(item), JourneyMediaSyncStatus.pending);
  });

  // -------------------------------------------------------------------
  // Crash windows and local races (S24-S27)
  // -------------------------------------------------------------------

  test('S24 every crash window converges on the next pass without overwrite',
      () async {
    // (a) object committed, response lost.
    final a = await oneSyncedJourneyPhoto(route: uuid(1), media: 1);
    remote.failAfter = (op) => op == 'upload' ? indeterminate : null;
    expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate);
    expect(await status(a), JourneyMediaSyncStatus.pending);
    remote.failAfter = null;
    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(await status(a), JourneyMediaSyncStatus.synced);

    // (b) row committed, response lost.
    final b = await oneSyncedJourneyPhoto(route: uuid(2), media: 2);
    remote.failAfter = (op) => op == 'insert' ? indeterminate : null;
    expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate);
    expect(await status(b), JourneyMediaSyncStatus.pending);
    remote.failAfter = null;
    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(await status(b), JourneyMediaSyncStatus.synced);

    // (c) both remote legs proven, process died before the local ack.
    final c = await oneSyncedJourneyPhoto(route: uuid(3), media: 3);
    db.failNextAck = true;
    expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate);
    expect(await status(c), JourneyMediaSyncStatus.pending);
    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(await status(c), JourneyMediaSyncStatus.synced);

    expect(remote.objectWrites, 3, reason: 'each object created exactly once');
    for (final item in [a, b, c]) {
      expect(remote.objects[pathOf(item)], await localBytes(item));
    }
  });

  test(
      'S25 a row that became a tombstone before the ack is never '
      'acknowledged and gets no further calls', () async {
    final item = await oneSyncedJourneyPhoto();
    // The tombstone is COMMITTED while the insert is held open (the gate is
    // awaited), i.e. strictly before the acknowledgement is attempted. An
    // implementation that acknowledged anyway would overwrite it to synced.
    remote.gate = (op) async {
      if (op == 'insert') {
        await (db.update(db.localJourneyMedia)
              ..where((t) => t.id.equals(item.id)))
            .write(const LocalJourneyMediaCompanion(
                syncStatus: Value(JourneyMediaSyncStatus.pendingDelete)));
      }
    };

    final result = await runPhaseResult();

    expect(result.outcome, JourneyMediaPhaseOutcome.clean);
    expect(result.synced, 0, reason: 'the acknowledgement was rejected');
    expect(result.settled, 0);
    expect(remote.calls, ['upload', 'insert']);
    expect(await status(item), JourneyMediaSyncStatus.pendingDelete);
  });

  test(
      'S25b P3-6 a row parked or settled elsewhere before the ack is not '
      'reported as synced by this phase and is never overwritten', () async {
    final parked = await oneSyncedJourneyPhoto(route: uuid(1), media: 1);
    remote.gate = (op) async {
      if (op == 'insert') {
        await db.markJourneyMediaFailed(
            ownerId: owner,
            recordedRouteId: parked.recordedRouteId,
            id: parked.id);
      }
    };
    var result = await runPhaseResult();
    expect(result.outcome, JourneyMediaPhaseOutcome.clean);
    expect(result.synced, 0);
    expect(await status(parked), JourneyMediaSyncStatus.failed,
        reason: 'failed is never overwritten by a late acknowledgement');

    // Another worker acknowledged first: this phase must not count it.
    final settled = await oneSyncedJourneyPhoto(route: uuid(2), media: 2);
    remote.gate = (op) async {
      if (op == 'insert') {
        await db.markJourneyMediaSynced(
            ownerId: owner,
            recordedRouteId: settled.recordedRouteId,
            id: settled.id);
      }
    };
    result = await runPhaseResult();
    expect(result.synced, 0);
    expect(await status(settled), JourneyMediaSyncStatus.synced);
  });

  test('S26 pendingDelete rows get zero remote calls and are never purged',
      () async {
    final item = await oneSyncedJourneyPhoto();
    await (db.update(db.localJourneyMedia)..where((t) => t.id.equals(item.id)))
        .write(const LocalJourneyMediaCompanion(
            syncStatus: Value(JourneyMediaSyncStatus.pendingDelete)));

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(await runPhase(routeIds: [item.recordedRouteId]),
        JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, isEmpty);
    expect(await status(item), JourneyMediaSyncStatus.pendingDelete);
  });

  test('S27 failed rows get zero calls on automatic passes', () async {
    final item = await oneSyncedJourneyPhoto();
    await db.markJourneyMediaFailed(
        ownerId: owner, recordedRouteId: item.recordedRouteId, id: item.id);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, isEmpty);
    expect(await status(item), JourneyMediaSyncStatus.failed);
  });

  // -------------------------------------------------------------------
  // Bounds (S28-S30)
  // -------------------------------------------------------------------

  test(
      'S28 at most 50 items per pass; the rest go on the next pass; a '
      'yield request stops after the current photo', () async {
    final routeId = uuid(1);
    await startRoute(routeId);
    final items = <LocalJourneyMediaItem>[];
    for (var i = 0; i < 60; i++) {
      items.add(await addMedia(routeId, uuid(1000 + i),
          capturedAt: t0.add(Duration(seconds: i))));
    }
    await finish(routeId);

    expect(await runPhase(), JourneyMediaPhaseOutcome.capped);
    var synced = 0;
    for (final item in items) {
      if (await status(item) == JourneyMediaSyncStatus.synced) synced++;
    }
    expect(synced, 50);

    expect(await runPhase(shouldYield: () => true),
        JourneyMediaPhaseOutcome.yielded);
    synced = 0;
    for (final item in items) {
      if (await status(item) == JourneyMediaSyncStatus.synced) synced++;
    }
    expect(synced, 51, reason: 'a yielding phase still completes one photo');

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    for (final item in items) {
      expect(await status(item), JourneyMediaSyncStatus.synced);
    }
  });

  test('S29 exactly one remote call is ever in flight', () async {
    final routeId = uuid(1);
    await startRoute(routeId);
    for (var i = 0; i < 5; i++) {
      await addMedia(routeId, uuid(400 + i));
    }
    await finish(routeId);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls.length, 10);
    expect(remote.maxInFlight, 1);
  });

  test('S30 synced rows are never re-processed', () async {
    await oneSyncedJourneyPhoto();
    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    remote.calls.clear();

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(remote.calls, isEmpty);
    expect(await db.getRouteIdsWithActionableMedia(ownerId: owner), isEmpty);
  });

  // -------------------------------------------------------------------
  // Tripwires for the deferred delete machine (D-2): W01-W02
  // -------------------------------------------------------------------

  // -------------------------------------------------------------------
  // Review remediation: bounded calls (P2-1), identity before each item
  // (P2-2), 42501 (P2-3), no uploads during a recording (P2-4).
  // -------------------------------------------------------------------

  group('P2-1 every remote call is bounded', () {
    /// The stalled operation never completes; only its own bound is zero, so
    /// the timeout fires deterministically (no sleep, no real wait) while
    /// every other call keeps the production bound.
    JourneyMediaSync stalling(String op, JourneyMediaTimeouts timeouts) {
      remote.gate = (called) =>
          called == op ? Completer<void>().future : Future<void>.value();
      return JourneyMediaSync(
          db: db, storage: storage, repository: remote, timeouts: timeouts);
    }

    test('T01 a stalled upload times out: pending + INDETERMINATE', () async {
      final item = await oneSyncedJourneyPhoto();
      final bounded =
          stalling('upload', const JourneyMediaTimeouts(upload: Duration.zero));

      expect(await runPhase(using: bounded),
          JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.calls, ['upload']);
      expect(await status(item), JourneyMediaSyncStatus.pending);
    });

    test('T02 a stalled download (duplicate proof) times out', () async {
      final item = await oneSyncedJourneyPhoto();
      seedObject(item, await localBytes(item));
      final bounded = stalling(
          'download', const JourneyMediaTimeouts(download: Duration.zero));

      expect(await runPhase(using: bounded),
          JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.calls, ['upload', 'download']);
      expect(await status(item), JourneyMediaSyncStatus.pending);
    });

    test('T03 a stalled objectInfo (missing local file) times out', () async {
      final item = await oneSyncedJourneyPhoto(writeFile: false);
      seedRow(item);
      final bounded =
          stalling('info', const JourneyMediaTimeouts(info: Duration.zero));

      expect(await runPhase(using: bounded),
          JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.calls, ['select', 'info']);
      expect(await status(item), JourneyMediaSyncStatus.pending);
    });

    test('T04 a stalled route_media insert times out', () async {
      final item = await oneSyncedJourneyPhoto();
      final bounded =
          stalling('insert', const JourneyMediaTimeouts(insert: Duration.zero));

      expect(await runPhase(using: bounded),
          JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.calls, ['upload', 'insert']);
      expect(await status(item), JourneyMediaSyncStatus.pending);
    });

    test('T05 a stalled route_media select (duplicate proof) times out',
        () async {
      final item = await oneSyncedJourneyPhoto();
      seedRow(item);
      final bounded =
          stalling('select', const JourneyMediaTimeouts(select: Duration.zero));

      expect(await runPhase(using: bounded),
          JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.calls, ['upload', 'insert', 'select']);
      expect(await status(item), JourneyMediaSyncStatus.pending);
    });

    test(
        'T06 an upload that committed but timed out converges on retry '
        '(duplicate + byte proof, never an overwrite)', () async {
      final item = await oneSyncedJourneyPhoto();
      remote.stallAfter = (op) =>
          op == 'upload' ? Completer<void>().future : Future<void>.value();
      final bounded = JourneyMediaSync(
          db: db,
          storage: storage,
          repository: remote,
          timeouts: const JourneyMediaTimeouts(upload: Duration.zero));

      expect(await runPhase(using: bounded),
          JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.objects.containsKey(pathOf(item)), isTrue,
          reason: 'the abandoned upload did commit');
      expect(await status(item), JourneyMediaSyncStatus.pending);

      remote
        ..stallAfter = null
        ..calls.clear();
      expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
      expect(remote.calls, ['upload', 'download', 'insert']);
      expect(remote.objectWrites, 1);
      expect(await status(item), JourneyMediaSyncStatus.synced);
    });

    test(
        'T07 a route_media insert that committed but timed out converges on '
        'retry (duplicate + authenticated read-back)', () async {
      final item = await oneSyncedJourneyPhoto();
      remote.stallAfter = (op) =>
          op == 'insert' ? Completer<void>().future : Future<void>.value();
      final bounded = JourneyMediaSync(
          db: db,
          storage: storage,
          repository: remote,
          timeouts: const JourneyMediaTimeouts(insert: Duration.zero));

      expect(await runPhase(using: bounded),
          JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.rows.containsKey(item.id), isTrue,
          reason: 'the abandoned insert did commit');
      expect(await status(item), JourneyMediaSyncStatus.pending);

      remote
        ..stallAfter = null
        ..calls.clear();
      expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
      expect(remote.calls, ['upload', 'download', 'insert', 'select']);
      expect(remote.insertedPayloads, hasLength(1));
      expect(await status(item), JourneyMediaSyncStatus.synced);
    });

    /// Runs [body] in a guarded zone and returns every error that escaped to
    /// the zone as UNHANDLED (an abandoned future that fails after nobody
    /// listens would show up here). Failures of [body] itself propagate.
    Future<List<Object>> uncaughtAsyncErrors(
        Future<void> Function() body) async {
      final escaped = <Object>[];
      final finished = Completer<void>();
      runZonedGuarded(() async {
        try {
          await body();
          finished.complete();
        } catch (error, stack) {
          finished.completeError(error, stack);
        }
      }, (error, stack) => escaped.add(error));
      await finished.future;
      return escaped;
    }

    test('T10 the unhandled-error probe is not vacuous: a leaked error is seen',
        () async {
      final escaped = await uncaughtAsyncErrors(() async {
        unawaited(Future<void>(() => throw StateError('nobody listens')));
        await pumpEventQueue();
      });

      expect(escaped, hasLength(1));
      expect(escaped.single, isA<StateError>());
    });

    test(
        'T08 an abandoned upload that finally SUCCEEDS after the retry '
        'already synced the photo changes nothing: no second '
        'acknowledgement, no regression, no unhandled error', () async {
      final item = await oneSyncedJourneyPhoto();
      // Created INSIDE the guarded zone (below): a completer from another
      // zone would leak its late error to the test zone -- a test artifact,
      // not production behavior (everything there runs in one zone).
      late final Completer<void> lateResponse;
      var stalled = false;
      remote.stallAfter = (op) {
        if (op == 'upload' && !stalled) {
          stalled = true;
          return lateResponse.future;
        }
        return Future<void>.value();
      };
      final bounded = JourneyMediaSync(
          db: db,
          storage: storage,
          repository: remote,
          timeouts: const JourneyMediaTimeouts(upload: Duration.zero));

      final escaped = await uncaughtAsyncErrors(() async {
        lateResponse = Completer<void>();
        expect(await runPhase(using: bounded),
            JourneyMediaPhaseOutcome.indeterminate);
        expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
        expect(await status(item), JourneyMediaSyncStatus.synced);
        expect(db.ackCalls, 1);
        final callsBefore = List.of(remote.calls);

        lateResponse.complete(); // the abandoned upload finally "succeeds"
        await pumpEventQueue();

        expect(remote.calls, callsBefore);
      });

      expect(escaped, isEmpty);
      expect(db.ackCalls, 1, reason: 'no second acknowledgement');
      expect(await status(item), JourneyMediaSyncStatus.synced);
      expect(remote.objectWrites, 1);
      expect(remote.insertedPayloads, hasLength(1));
    });

    test(
        'T09 an abandoned route_media insert that finally FAILS after the '
        'retry already synced the photo changes nothing: no second '
        'acknowledgement, no failed/pending regression, no unhandled error',
        () async {
      final item = await oneSyncedJourneyPhoto();
      // Created INSIDE the guarded zone (below): a completer from another
      // zone would leak its late error to the test zone -- a test artifact,
      // not production behavior (everything there runs in one zone).
      late final Completer<void> lateResponse;
      var stalled = false;
      remote.stallAfter = (op) {
        if (op == 'insert' && !stalled) {
          stalled = true;
          return lateResponse.future;
        }
        return Future<void>.value();
      };
      final bounded = JourneyMediaSync(
          db: db,
          storage: storage,
          repository: remote,
          timeouts: const JourneyMediaTimeouts(insert: Duration.zero));

      final escaped = await uncaughtAsyncErrors(() async {
        lateResponse = Completer<void>();
        expect(await runPhase(using: bounded),
            JourneyMediaPhaseOutcome.indeterminate);
        expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
        expect(await status(item), JourneyMediaSyncStatus.synced);
        expect(db.ackCalls, 1);
        final callsBefore = List.of(remote.calls);

        // A PERMANENT-looking late failure is the strongest regression
        // probe: if it ever reached the item logic it would try to park it.
        lateResponse.completeError(const JourneyMediaSyncException(
            JourneyMediaRemoteFailureKind.permanent, 'late failure'));
        await pumpEventQueue();

        expect(remote.calls, callsBefore);
      });

      expect(escaped, isEmpty);
      expect(db.ackCalls, 1, reason: 'no second acknowledgement');
      expect(await status(item), JourneyMediaSyncStatus.synced);
      expect(remote.insertedPayloads, hasLength(1));
    });
  });

  group(
      'P2-1 (final) identity is re-checked right before the first remote '
      'request, after the local preflight', () {
    /// Photo with a remote row matching it, local file present or missing.
    Future<LocalJourneyMediaItem> photo({required bool fileMissing}) async {
      final item = await oneSyncedJourneyPhoto(writeFile: !fileMissing);
      seedRow(item);
      return item;
    }

    for (final fileMissing in [true, false]) {
      test(
          'F01 the account switches while the local preflight is suspended '
          '(${fileMissing ? "missing-file branch" : "upload branch"}): zero '
          'remote calls, pending, INDETERMINATE', () async {
        final item = await photo(fileMissing: fileMissing);
        final suspended = Completer<void>();
        final release = Completer<void>();
        db.onMediaRead = (id) {
          db.onMediaRead = null;
          suspended.complete();
          return release.future;
        };

        final phase = runPhaseResult();
        await suspended.future; // the item passed its first identity check
        liveUid = uuid(901); // ...and THEN the account switches
        release.complete();
        final result = await phase;

        expect(result.outcome, JourneyMediaPhaseOutcome.indeterminate);
        expect(remote.calls, isEmpty);
        expect(await status(item), JourneyMediaSyncStatus.pending);
      });
    }
  });

  group('P2-2 (final) a Journey starting mid-phase stops new media work', () {
    /// Starts a new Journey for the owner, optionally paused.
    Future<void> beginJourney({bool paused = false}) async {
      await db.createLocalRecordedRoute(
          id: uuid(9), ownerId: owner, startedAt: t0);
      if (paused) {
        await db.pauseRecording(
            ownerId: owner, routeId: uuid(9), occurredAt: t0);
      }
    }

    for (final paused in [false, true]) {
      final state = paused ? 'paused' : 'recording';

      test(
          'R01 a Journey is $state between photo A and photo B: B starts '
          'zero remote calls and not even its local preflight', () async {
        final routeId = uuid(1);
        await startRoute(routeId);
        final a = await addMedia(routeId, uuid(101));
        final b = await addMedia(routeId, uuid(102),
            capturedAt: t0.add(const Duration(seconds: 1)));
        await finish(routeId);
        db.afterAck = () async {
          db.afterAck = null;
          await beginJourney(paused: paused);
        };

        final result = await runPhaseResult();
        final bReads = db.mediaReads.where((id) => id == b.id).length;

        expect(result.outcome,
            JourneyMediaPhaseOutcome.deferredForActiveRecording);
        expect(result.synced, 1, reason: 'photo A, already running, finished');
        expect(remote.calls, ['upload', 'insert'], reason: 'photo A only');
        expect(bReads, 0, reason: 'B never even started its local preflight');
        expect(await status(a), JourneyMediaSyncStatus.synced);
        expect(await status(b), JourneyMediaSyncStatus.pending);

        // Once the Journey ends, the leftover photo uploads again.
        await db.discardRecording(
            ownerId: owner, routeId: uuid(9), occurredAt: t0);
        expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
        expect(await status(b), JourneyMediaSyncStatus.synced);
      });

      for (final fileMissing in [false, true]) {
        test(
            'R02 a Journey is $state while photo B waits for its local '
            'preflight (${fileMissing ? "missing file" : "file present"}): '
            'B starts zero remote calls', () async {
          final routeId = uuid(1);
          await startRoute(routeId);
          final a = await addMedia(routeId, uuid(101));
          final b = await addMedia(routeId, uuid(102),
              writeFile: !fileMissing,
              capturedAt: t0.add(const Duration(seconds: 1)));
          await finish(routeId);
          if (fileMissing) seedRow(b);
          final suspended = Completer<void>();
          final release = Completer<void>();
          db.onMediaRead = (id) {
            if (id != b.id) return Future<void>.value();
            db.onMediaRead = null;
            suspended.complete();
            return release.future;
          };

          final phase = runPhaseResult();
          await suspended.future; // A is done; B passed the per-item check
          await beginJourney(paused: paused);
          release.complete();
          final result = await phase;

          expect(result.outcome,
              JourneyMediaPhaseOutcome.deferredForActiveRecording);
          expect(remote.calls, ['upload', 'insert'], reason: 'photo A only');
          expect(await status(a), JourneyMediaSyncStatus.synced);
          expect(await status(b), JourneyMediaSyncStatus.pending);
        });
      }
    }
  });

  group('P2-2 identity is checked before every item', () {
    test(
        'I01 an account switch between photo A and photo B: B makes zero '
        'remote calls, stays pending, the phase is INDETERMINATE', () async {
      final routeId = uuid(1);
      await startRoute(routeId);
      final a = await addMedia(routeId, uuid(101));
      final b = await addMedia(routeId, uuid(102),
          capturedAt: t0.add(const Duration(seconds: 1)));
      await finish(routeId);
      db.afterAck = () {
        db.afterAck = null;
        liveUid = uuid(901);
      };

      final result = await runPhaseResult();

      expect(result.outcome, JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.calls, ['upload', 'insert'], reason: 'photo A only');
      expect(await status(a), JourneyMediaSyncStatus.synced);
      expect(await status(b), JourneyMediaSyncStatus.pending);
    });

    test(
        'I03 same switch when photo B has no local file: its first call '
        '(the metadata select) is never made', () async {
      final routeId = uuid(1);
      await startRoute(routeId);
      final a = await addMedia(routeId, uuid(101));
      final b = await addMedia(routeId, uuid(102),
          writeFile: false, capturedAt: t0.add(const Duration(seconds: 1)));
      await finish(routeId);
      db.afterAck = () {
        db.afterAck = null;
        liveUid = uuid(901);
      };

      expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.calls, ['upload', 'insert'], reason: 'photo A only');
      expect(await status(a), JourneyMediaSyncStatus.synced);
      expect(await status(b), JourneyMediaSyncStatus.pending);
    });

    test(
        'I02 an identity change before the first item makes zero remote '
        'calls', () async {
      final item = await oneSyncedJourneyPhoto();
      var reads = 0;

      final outcome =
          await runPhase(identity: () => reads++ == 0 ? owner : uuid(901));

      expect(outcome, JourneyMediaPhaseOutcome.indeterminate);
      expect(remote.calls, isEmpty);
      expect(await status(item), JourneyMediaSyncStatus.pending);
    });
  });

  test(
      'P2-3 a PostgREST 42501 (real classifier) never parks the photo: '
      'pending + INDETERMINATE, then recovers automatically', () async {
    final item = await oneSyncedJourneyPhoto();
    var first = true;
    remote.failBefore = (op) {
      if (op != 'insert' || !first) return null;
      first = false;
      return SupabaseJourneyMediaSyncRepository.classify(
          const PostgrestException(
              message: 'permission denied for table route_media',
              code: '42501'));
    };

    expect(await runPhase(), JourneyMediaPhaseOutcome.indeterminate);
    expect(await status(item), JourneyMediaSyncStatus.pending);

    expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
    expect(await status(item), JourneyMediaSyncStatus.synced);
  });

  group('P2-4 no media upload while a Journey is being recorded', () {
    late FakeLocationSource source;
    late GpsRecordingController controller;
    late LocalJourneyMediaItem old;

    setUp(() async {
      // An older Journey, completed and remotely finalized, with a photo.
      old = await oneSyncedJourneyPhoto();
      source = FakeLocationSource()..permission = LocationPermission.whileInUse;
      controller = GpsRecordingController(
        ownerId: owner,
        db: db,
        locationSource: source,
        notificationPermissionSource: FakeNotificationPermissionSource(),
        mediaStorage: storage,
      );
      await controller.start();
      await pumpEventQueue();
      expect(controller.state.status, GpsRecordingStatus.recording);
    });

    tearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    test(
        'A01 while recording: deferred, zero calls, the old photo stays '
        'pending, no new location subscription', () async {
      final subscriptions = source.subscribeCallCount;

      expect(await runPhase(),
          JourneyMediaPhaseOutcome.deferredForActiveRecording);
      expect(await runPhase(routeIds: [old.recordedRouteId]),
          JourneyMediaPhaseOutcome.deferredForActiveRecording);

      expect(remote.calls, isEmpty);
      expect(await status(old), JourneyMediaSyncStatus.pending);
      expect(source.subscribeCallCount, subscriptions);
    });

    test('A02 while paused: deferred, zero calls', () async {
      await controller.pause();
      expect(controller.state.status, GpsRecordingStatus.paused);

      expect(await runPhase(),
          JourneyMediaPhaseOutcome.deferredForActiveRecording);
      expect(remote.calls, isEmpty);
      expect(await status(old), JourneyMediaSyncStatus.pending);
    });

    test('A03 once the active Journey completes, the old photo uploads',
        () async {
      final subscriptions = source.subscribeCallCount;
      expect(await controller.finish(), isTrue);

      expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
      expect(await status(old), JourneyMediaSyncStatus.synced);
      expect(source.subscribeCallCount, subscriptions,
          reason: 'media sync never subscribes to location');
    });

    test('A04 once the active Journey is discarded, the old photo uploads',
        () async {
      await controller.discard();

      expect(await runPhase(), JourneyMediaPhaseOutcome.clean);
      expect(await status(old), JourneyMediaSyncStatus.synced);
    });
  });

  group('tripwires: no production path can tombstone completed-Journey media',
      () {
    test(
        'W01 every production entry point that can create a media '
        'tombstone is exactly the known, gated set', () {
      // Every way a media row can become `pendingDelete` today:
      //  - JourneyMediaService.deleteMedia -> GpsLocalDatabase.deleteJourneyMedia
      //  - (GpsLocalDatabase.)deleteWaypoint / deleteWaypointCollectingMediaPaths
      //    (a Moment's media is retired with it)
      //  - the single `Value(JourneyMediaSyncStatus.pendingDelete)` write
      //    (`_retireMediaRow`).
      // `deleteWaypoint(` also names the REMOTE waypoint API (sync
      // repository/coordinator) -- listed explicitly, it creates no media
      // tombstone. Any new call site fails this test: a completed-Journey
      // deletion path needs the deferred delete machine (D-2) first.
      final patterns = {
        'deleteMedia': RegExp(r'\bdeleteMedia\('),
        'deleteJourneyMedia': RegExp(r'\bdeleteJourneyMedia\('),
        'deleteWaypoint': RegExp(r'\bdeleteWaypoint\('),
        'deleteWaypointCollectingMediaPaths':
            RegExp(r'\bdeleteWaypointCollectingMediaPaths\('),
        'pendingDeleteWrite':
            RegExp(r'Value\(JourneyMediaSyncStatus\.pendingDelete\)'),
      };
      const allowed = {
        'lib/features/gps/media/journey_media_service.dart': {
          'deleteMedia': 1, // definition (no lib/ caller)
          'deleteJourneyMedia': 1, // the service delegating to the DB
        },
        'lib/features/gps/local/gps_local_database.dart': {
          'deleteJourneyMedia': 1, // definition
          'deleteWaypoint': 1, // definition
          'deleteWaypointCollectingMediaPaths':
              2, // definition + deleteWaypoint
          'pendingDeleteWrite': 1, // _retireMediaRow
        },
        'lib/features/gps/recording/gps_recording_controller.dart': {
          'deleteWaypoint': 1, // gated to recording/paused (W02)
          'deleteWaypointCollectingMediaPaths': 1, // inside that gated method
        },
        'lib/features/gps/presentation/gps_recording_map_screen.dart': {
          'deleteWaypoint': 1, // calls the gated controller method
        },
        'lib/features/gps/sync/domain/gps_sync_repository.dart': {
          'deleteWaypoint': 1, // remote waypoint API, no media
        },
        'lib/features/gps/sync/data/supabase_gps_sync_repository.dart': {
          'deleteWaypoint': 1, // remote waypoint API, no media
        },
        'lib/features/gps/sync/gps_sync_coordinator.dart': {
          'deleteWaypoint': 1, // pushes a waypoint tombstone remotely
        },
      };
      final offenders = <String>[];
      final seen = <String, Map<String, int>>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.endsWith('.g.dart')) continue;
        final source = entity.readAsStringSync();
        for (final entry in patterns.entries) {
          final count = entry.value.allMatches(source).length;
          if (count == 0) continue;
          (seen[path] ??= {})[entry.key] = count;
          if (count > (allowed[path]?[entry.key] ?? 0)) {
            offenders.add('$path ${entry.key} x$count');
          }
        }
      }
      // The allow-list is exact, not merely an upper bound: a removed or
      // renamed site must be re-reviewed too.
      expect(seen, allowed);
      expect(offenders, isEmpty,
          reason: 'a production caller can now tombstone media after '
              'completion: implement the deferred delete machine (D-2) first');
    });

    group('W02 Moment deletion is rejected once Finish has started', () {
      late FakeLocationSource source;
      late GpsRecordingController controller;
      final routeOwner = owner;

      setUp(() async {
        source = FakeLocationSource()
          ..permission = LocationPermission.whileInUse;
        controller = GpsRecordingController(
          ownerId: routeOwner,
          db: db,
          locationSource: source,
          notificationPermissionSource: FakeNotificationPermissionSource(),
          mediaStorage: storage,
        );
        await controller.start();
        await pumpEventQueue();
        await db.addWaypoint(
          id: uuid(50),
          ownerId: routeOwner,
          recordedRouteId: controller.state.routeId!,
          waypointType: 'custom',
          latitude: 50,
          longitude: 30,
          recordedAt: t0,
        );
        await addMedia(controller.state.routeId!, uuid(101),
            waypointId: uuid(50));
      });

      tearDown(() async {
        controller.dispose();
        await source.dispose();
      });

      Future<void> expectUntouched(String routeId) async {
        expect(
            (await db.getWaypoints(
                    ownerId: routeOwner, recordedRouteId: routeId))
                .map((w) => w.id),
            [uuid(50)]);
        final media = await db.getJourneyMedia(
            ownerId: routeOwner, recordedRouteId: routeId);
        expect(media.single.syncStatus, JourneyMediaSyncStatus.pending);
        expect(
            await db.getTombstonedJourneyMedia(
                ownerId: routeOwner, recordedRouteId: routeId),
            isEmpty);
      }

      test('while finishing', () async {
        final routeId = controller.state.routeId!;
        db.finishGate = Completer<void>();
        final finishing = controller.finish();
        expect(controller.state.status, GpsRecordingStatus.finishing);

        expect(await controller.deleteWaypoint(waypointId: uuid(50)), isFalse);
        await expectUntouched(routeId);

        db.finishGate!.complete();
        expect(await finishing, isTrue);
      });

      test('once completed', () async {
        final routeId = controller.state.routeId!;
        expect(await controller.finish(), isTrue);
        expect(controller.state.status, GpsRecordingStatus.completed);

        expect(await controller.deleteWaypoint(waypointId: uuid(50)), isFalse);
        await expectUntouched(routeId);
      });
    });
  });
}
