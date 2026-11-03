import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_storage.dart';
import 'package:flutter_application_1/features/gps/sync/data/supabase_journey_media_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/domain/gps_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/domain/journey_media_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/gps_sync_coordinator.dart';
import 'package:flutter_application_1/features/gps/sync/journey_media_sync.dart';
import 'package:flutter_application_1/features/map/providers/network_provider.dart';

import 'fake_journey_media_remote.dart';

/// Hand-rolled fake, matching this codebase's established
/// `CheckInRepository`/`_RecordingCheckInRepository` convention (no
/// mocking library is used anywhere in this project). Records every
/// call for "no network call" assertions, and every method's behavior
/// is independently scriptable so a single fake instance can drive every
/// success/failure/mismatch scenario the coordinator needs to handle.
class _FakeGpsSyncRepository implements GpsSyncRepository {
  final calls = <String>[]; // method names, in call order
  final shellRouteIds = <String>[];
  final pointBatches = <List<LocalRoutePoint>>[];
  final eventBatches = <List<LocalRouteEvent>>[];
  final upsertedWaypoints = <LocalWaypoint>[];
  final deletedWaypointIds = <String>[];
  final finalizeCalls = <String>[];

  Object? Function()? ensureRouteShellError;
  int Function(List<LocalRoutePoint> points)? syncPointsHandler;
  int Function(List<LocalRouteEvent> events)? syncEventsHandler;
  Object? Function(LocalWaypoint waypoint)? upsertWaypointError;
  Object? Function(String waypointId)? deleteWaypointError;
  GpsFinalizeResponse Function(String routeId)? finalizeHandler;

  @override
  Future<void> ensureRouteShell({
    required String routeId,
    String? tripId,
    String? title,
    required String transportMode,
    required String visibility,
    required DateTime startedAt,
  }) async {
    calls.add('ensureRouteShell');
    shellRouteIds.add(routeId);
    final error = ensureRouteShellError?.call();
    if (error != null) throw error;
  }

  @override
  Future<int> syncPoints({
    required String routeId,
    required List<LocalRoutePoint> points,
  }) async {
    calls.add('syncPoints');
    pointBatches.add(points);
    if (syncPointsHandler != null) return syncPointsHandler!(points);
    return points.last.seq;
  }

  @override
  Future<int> syncEvents({
    required String routeId,
    required List<LocalRouteEvent> events,
  }) async {
    calls.add('syncEvents');
    eventBatches.add(events);
    if (syncEventsHandler != null) return syncEventsHandler!(events);
    return events.last.seq;
  }

  @override
  Future<void> upsertWaypoint(LocalWaypoint waypoint) async {
    calls.add('upsertWaypoint');
    final error = upsertWaypointError?.call(waypoint);
    if (error != null) throw error;
    upsertedWaypoints.add(waypoint);
  }

  @override
  Future<void> deleteWaypoint(String waypointId) async {
    calls.add('deleteWaypoint');
    final error = deleteWaypointError?.call(waypointId);
    if (error != null) throw error;
    deletedWaypointIds.add(waypointId);
  }

  @override
  Future<GpsFinalizeResponse> finalizeRoute(String routeId) async {
    calls.add('finalizeRoute');
    finalizeCalls.add(routeId);
    if (finalizeHandler != null) return finalizeHandler!(routeId);
    return GpsFinalizeResponse(id: routeId, status: 'completed');
  }
}

void main() {
  // GpsSyncCoordinator registers itself as a WidgetsBindingObserver (for
  // app-foreground/resume-triggered sync), which needs
  // WidgetsBinding.instance to exist -- automatic in testWidgets(), not
  // in plain test(), so it's initialized explicitly here, same as
  // gps_recording_controller_test.dart does for GpsRecordingController.
  TestWidgetsFlutterBinding.ensureInitialized();

  late GpsLocalDatabase db;
  late _FakeGpsSyncRepository repo;

  setUp(() {
    db = GpsLocalDatabase.forTesting(NativeDatabase.memory());
    repo = _FakeGpsSyncRepository();
  });

  tearDown(() => db.close());

  GpsSyncCoordinator coordinatorFor(String ownerId,
      {String? currentUserId = 'me'}) {
    return GpsSyncCoordinator(
      ownerId: ownerId,
      db: db,
      repository: repo,
      currentUserId: () => currentUserId,
      // Every numbered scenario below drives sync passes explicitly via
      // syncNow()/retryRoute() for a deterministic single pass per call;
      // the constructor's own auto-fire-on-init behavior is covered
      // separately (see "00 constructing with default settings...").
      autoSyncOnInit: false,
    );
  }

  Future<LocalRecordedRoute> createRoute({
    String id = 'r1',
    String owner = 'me',
  }) {
    return db.createLocalRecordedRoute(
      id: id,
      ownerId: owner,
      startedAt: DateTime.utc(2026, 1, 1, 10),
    );
  }

  Future<void> addPoints(String routeId, int count,
      {String owner = 'me'}) async {
    for (var i = 1; i <= count; i++) {
      await db.appendRoutePoint(
        ownerId: owner,
        recordedRouteId: routeId,
        latitude: 50.0 + i * 0.001,
        longitude: 30.0 + i * 0.001,
        recordedAt: DateTime.utc(2026, 1, 1, 10, 0, i),
      );
    }
  }

  Future<void> addEvents(String routeId, List<String> types,
      {String owner = 'me'}) async {
    for (final type in types) {
      await db.appendRouteEvent(
        ownerId: owner,
        recordedRouteId: routeId,
        eventType: type,
        occurredAt: DateTime.utc(2026, 1, 1, 10, 5),
      );
    }
  }

  // -------------------------------------------------------------------
  // 00 -- coordinator/app initialization trigger (every numbered test
  // below disables this via autoSyncOnInit: false for deterministic
  // single-pass control; this is the one place the real default
  // production behavior -- an automatic pass fires on construction,
  // with no explicit syncNow() call needed -- is itself verified).
  // -------------------------------------------------------------------

  test(
      '00 constructing with default settings triggers an initial '
      'opportunistic sync automatically, with no explicit call', () async {
    await createRoute();
    final coordinator = GpsSyncCoordinator(
      ownerId: 'me',
      db: db,
      repository: repo,
      currentUserId: () => 'me',
      // autoSyncOnInit deliberately left at its true default here.
    );
    await coordinator.pendingSync; // awaits the auto-fired pass itself
    expect(repo.calls, contains('ensureRouteShell'));
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 01 / 02 / 03 -- owner safety
  // -------------------------------------------------------------------

  test('01 owner matches -> route is eligible and synced (network is used)',
      () async {
    await createRoute();
    final coordinator = coordinatorFor('me', currentUserId: 'me');
    await coordinator.syncNow();
    expect(repo.calls, contains('ensureRouteShell'));
    coordinator.dispose();
  });

  test('02 owner mismatch -> zero repository network calls', () async {
    // Local data is owned by 'userA'; the live authenticated session is
    // a different user -- the coordinator must re-check this live, not
    // trust the ownerId it was constructed with.
    await createRoute(id: 'r1', owner: 'userA');
    final coordinator = coordinatorFor('userA', currentUserId: 'userB');
    await coordinator.syncNow();
    expect(repo.calls, isEmpty);
    final route = await db.getRecordedRoute(ownerId: 'userA', id: 'r1');
    expect(route!.syncStatus, RouteSyncStatus.notSynced); // untouched
    coordinator.dispose();
  });

  test('03 signed out -> zero repository network calls, route left pending',
      () async {
    await createRoute();
    final coordinator = coordinatorFor('me', currentUserId: null);
    await coordinator.syncNow();
    expect(repo.calls, isEmpty);
    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.syncStatus, RouteSyncStatus.notSynced);
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 04 / 24 -- stale syncing recovery
  // -------------------------------------------------------------------

  test(
      '04 stale syncing route is normalized to notSynced on coordinator '
      'startup', () async {
    await createRoute();
    await db.markRouteSyncing(ownerId: 'me', routeId: 'r1');
    expect((await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!.syncStatus,
        RouteSyncStatus.syncing);

    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.syncStatus, isNot(RouteSyncStatus.syncing));
    coordinator.dispose();
  });

  test(
      '24 app restart: stale syncing is reset and the route makes real '
      'progress on the next pass', () async {
    await createRoute();
    await addPoints('r1', 2);
    await db.markRouteSyncing(
        ownerId: 'me', routeId: 'r1'); // simulate a killed process

    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.pointBatches, isNotEmpty);
    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.lastSyncedPointSeq, 2);
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 05 / 06 / 07 -- route shell contract
  // -------------------------------------------------------------------

  test(
      '05 route shell uses the local UUID directly as the server id, '
      'never a replacement', () async {
    await createRoute(id: 'local-client-generated-uuid');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();
    expect(repo.shellRouteIds, ['local-client-generated-uuid']);
    coordinator.dispose();
  });

  test(
      '06 / 07 a completed local route never sends status=completed or '
      'endedAt through the shell call -- structurally impossible: '
      'ensureRouteShell has no such parameters at all', () async {
    await createRoute();
    await db.finishRecordingLocally(
      ownerId: 'me',
      routeId: 'r1',
      occurredAt: DateTime.utc(2026, 1, 1, 10, 30),
    );
    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.status, RecordedRouteStatus.completed);
    expect(route.endedAt, isNotNull);

    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    // The shell call happened (route id captured), and nothing about it
    // could have carried status/endedAt -- confirmed by the interface
    // itself (see GpsSyncRepository.ensureRouteShell's doc) and by the
    // fact finalize is the only place 'completed' is ever sent.
    expect(repo.shellRouteIds, contains('r1'));
    expect(repo.finalizeCalls, ['r1']);
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 08-14 -- point sync
  // -------------------------------------------------------------------

  test(
      '08 point first batch is uploaded and the cursor advances to its max seq',
      () async {
    await createRoute();
    await addPoints('r1', 3);
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.pointBatches, hasLength(1));
    expect(repo.pointBatches.single.map((p) => p.seq), [1, 2, 3]);
    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.lastSyncedPointSeq, 3);
    coordinator.dispose();
  });

  test(
      '09 point exact retry: a batch that never confirmed success is '
      'resubmitted identically on the next pass, then succeeds', () async {
    await createRoute();
    await addPoints('r1', 2);
    var attempt = 0;
    repo.syncPointsHandler = (points) {
      attempt++;
      if (attempt == 1) {
        throw GpsSyncException(GpsSyncErrorKind.retryable, 'dropped response');
      }
      return points.last.seq;
    };

    final coordinator = coordinatorFor('me');
    await coordinator.syncNow(); // fails
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedPointSeq,
        isNull);

    await coordinator.syncNow(); // retried
    expect(repo.pointBatches, hasLength(2));
    expect(repo.pointBatches[0].map((p) => p.seq),
        repo.pointBatches[1].map((p) => p.seq)); // identical batch resubmitted
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedPointSeq,
        2);
    coordinator.dispose();
  });

  test('10 point cursor advances only after RPC success', () async {
    await createRoute();
    await addPoints('r1', 2);
    repo.syncPointsHandler = (_) =>
        throw GpsSyncException(GpsSyncErrorKind.retryable, 'network down');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedPointSeq,
        isNull);
    coordinator.dispose();
  });

  test('11 point failure leaves the cursor unchanged', () async {
    await createRoute();
    await addPoints('r1', 3);
    // First batch succeeds normally via syncNow, then a second point is
    // added and the next sync fails -- cursor must stay at the last
    // confirmed value, not regress or partially advance.
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedPointSeq,
        3);

    await addPoints('r1', 1); // seq 4
    repo.syncPointsHandler = (_) =>
        throw GpsSyncException(GpsSyncErrorKind.retryable, 'network down');
    await coordinator.syncNow();
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedPointSeq,
        3); // unchanged
    coordinator.dispose();
  });

  test(
      '12 point RPC returned cursor inconsistent with the submitted batch '
      '-> treated as an integrity failure, cursor not advanced, route failed',
      () async {
    await createRoute();
    await addPoints('r1', 3);
    repo.syncPointsHandler =
        (points) => points.last.seq - 1; // wrong on purpose
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.lastSyncedPointSeq, isNull);
    expect(route.syncStatus, RouteSyncStatus.failed);
    coordinator.dispose();
  });

  test('13 point multi-batch progression respects the configured batch size',
      () async {
    await createRoute();
    await addPoints('r1', 7);
    final coordinator = GpsSyncCoordinator(
      ownerId: 'me',
      db: db,
      repository: repo,
      currentUserId: () => 'me',
      pointBatchSize: 3,
      autoSyncOnInit: false,
    );
    await coordinator.syncNow();

    expect(repo.pointBatches.map((b) => b.length), [3, 3, 1]);
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedPointSeq,
        7);
    coordinator.dispose();
  });

  test(
      '14 point batches are passed through from the local DAO exactly as-is '
      '-- never reordered or reconstructed, even for a hypothetically '
      'non-contiguous local batch', () async {
    await createRoute();
    // Deliberately bypass appendRoutePoint (which is always gapless) to
    // simulate a hypothetical corrupted/non-contiguous local table, and
    // confirm the coordinator still just forwards whatever the DAO's
    // own ordered query returns, unmodified -- it never tries to "fix"
    // gaps client-side.
    await db.into(db.localRoutePoints).insert(LocalRoutePointsCompanion.insert(
          recordedRouteId: 'r1',
          seq: 1,
          ownerId: 'me',
          latitude: 1,
          longitude: 1,
          recordedAt: DateTime.utc(2026, 1, 1, 10, 0, 1),
        ));
    await db.into(db.localRoutePoints).insert(LocalRoutePointsCompanion.insert(
          recordedRouteId: 'r1',
          seq: 5,
          ownerId: 'me',
          latitude: 2,
          longitude: 2,
          recordedAt: DateTime.utc(2026, 1, 1, 10, 0, 5),
        ));

    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.pointBatches.single.map((p) => p.seq),
        [1, 5]); // gap preserved, not fabricated
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 15-18 -- event sync
  // -------------------------------------------------------------------

  test('15 event first batch is uploaded and the cursor advances', () async {
    await createRoute();
    await addEvents(
        'r1', ['pause', 'resume']); // seq 2, 3 (seq 1 is the auto 'start')
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.eventBatches.single.map((e) => e.seq), [1, 2, 3]);
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedEventSeq,
        3);
    coordinator.dispose();
  });

  test('16 event cursor advances only after RPC success', () async {
    await createRoute();
    repo.syncEventsHandler = (_) =>
        throw GpsSyncException(GpsSyncErrorKind.retryable, 'network down');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedEventSeq,
        isNull);
    coordinator.dispose();
  });

  test('17 event failure leaves the cursor unchanged', () async {
    await createRoute();
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow(); // start event syncs, cursor -> 1
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedEventSeq,
        1);

    await db.pauseRecording(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 10));
    repo.syncEventsHandler = (_) =>
        throw GpsSyncException(GpsSyncErrorKind.retryable, 'network down');
    await coordinator.syncNow();
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedEventSeq,
        1); // unchanged
    coordinator.dispose();
  });

  test(
      '18 event RPC returned cursor inconsistent with the submitted batch '
      '-> integrity failure, cursor not advanced', () async {
    await createRoute();
    repo.syncEventsHandler = (events) => events.last.seq + 1; // wrong
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.lastSyncedEventSeq, isNull);
    expect(route.syncStatus, RouteSyncStatus.failed);
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 19-21 -- waypoint sync
  // -------------------------------------------------------------------

  test('19 waypoint new upload marks it synced', () async {
    await createRoute();
    await db.addWaypoint(
      id: 'w1',
      ownerId: 'me',
      recordedRouteId: 'r1',
      waypointType: 'viewpoint',
      latitude: 50,
      longitude: 30,
      recordedAt: DateTime.utc(2026, 1, 1, 10, 5),
    );
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.upsertedWaypoints.map((w) => w.id), ['w1']);
    final waypoints =
        await db.getUnsyncedWaypoints(ownerId: 'me', recordedRouteId: 'r1');
    expect(waypoints, isEmpty); // no longer pending
    coordinator.dispose();
  });

  test('19b an offline edit of a synced waypoint enters the pending flow',
      () async {
    await createRoute();
    await db.addWaypoint(
      id: 'w1',
      ownerId: 'me',
      recordedRouteId: 'r1',
      waypointType: 'viewpoint',
      title: 'Before',
      latitude: 50,
      longitude: 30,
      recordedAt: DateTime.utc(2026, 1, 1, 10, 5),
    );
    await db.markWaypointSynced(ownerId: 'me', id: 'w1');
    await db.updateWaypointMetadata(
      ownerId: 'me',
      recordedRouteId: 'r1',
      id: 'w1',
      waypointType: const Value('danger'),
      title: const Value('After'),
      note: const Value('Offline edit'),
    );

    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.upsertedWaypoints, hasLength(1));
    expect(repo.upsertedWaypoints.single.id, 'w1');
    expect(repo.upsertedWaypoints.single.waypointType, 'danger');
    expect(repo.upsertedWaypoints.single.title, 'After');
    expect(repo.upsertedWaypoints.single.note, 'Offline edit');
    expect(await db.getUnsyncedWaypoints(ownerId: 'me', recordedRouteId: 'r1'),
        isEmpty);
    coordinator.dispose();
  });

  test(
      '20 waypoint retry: a failed upload leaves it pending and it is '
      'retried on the next pass', () async {
    await createRoute();
    await db.addWaypoint(
      id: 'w1',
      ownerId: 'me',
      recordedRouteId: 'r1',
      waypointType: 'viewpoint',
      latitude: 50,
      longitude: 30,
      recordedAt: DateTime.utc(2026, 1, 1, 10, 5),
    );
    var attempt = 0;
    repo.upsertWaypointError = (_) {
      attempt++;
      return attempt == 1
          ? GpsSyncException(GpsSyncErrorKind.retryable, 'network down')
          : null;
    };

    final coordinator = coordinatorFor('me');
    await coordinator.syncNow(); // fails
    expect(await db.getUnsyncedWaypoints(ownerId: 'me', recordedRouteId: 'r1'),
        hasLength(1));

    await coordinator.syncNow(); // retried, succeeds
    expect(repo.upsertedWaypoints.map((w) => w.id), ['w1']);
    expect(await db.getUnsyncedWaypoints(ownerId: 'me', recordedRouteId: 'r1'),
        isEmpty);
    coordinator.dispose();
  });

  test(
      '21 waypoint tombstone: never purged locally until the server delete '
      'is proven to have succeeded', () async {
    await createRoute();
    await db.addWaypoint(
      id: 'w1',
      ownerId: 'me',
      recordedRouteId: 'r1',
      waypointType: 'viewpoint',
      latitude: 50,
      longitude: 30,
      recordedAt: DateTime.utc(2026, 1, 1, 10, 5),
    );
    await db.markWaypointSynced(
        ownerId: 'me', id: 'w1'); // simulate already synced
    await db.deleteWaypoint(
        ownerId: 'me', recordedRouteId: 'r1', id: 'w1'); // becomes a tombstone

    repo.deleteWaypointError =
        (_) => GpsSyncException(GpsSyncErrorKind.retryable, 'network down');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow(); // delete fails
    expect(
        await db.getTombstonedWaypoints(ownerId: 'me', recordedRouteId: 'r1'),
        hasLength(1)); // preserved

    repo.deleteWaypointError = null;
    await coordinator.syncNow(); // delete succeeds
    expect(repo.deletedWaypointIds, ['w1']);
    expect(
        await db.getTombstonedWaypoints(ownerId: 'me', recordedRouteId: 'r1'),
        isEmpty); // purged only now
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 22 / 23 -- resume from persisted cursor
  // -------------------------------------------------------------------

  test(
      '22 partial point sync resumes from the persisted cursor, never '
      're-sending already-confirmed points', () async {
    await createRoute();
    await addPoints('r1', 6);
    final coordinator = GpsSyncCoordinator(
      ownerId: 'me',
      db: db,
      repository: repo,
      currentUserId: () => 'me',
      pointBatchSize: 3,
      autoSyncOnInit: false,
    );
    var batchNumber = 0;
    repo.syncPointsHandler = (points) {
      batchNumber++;
      if (batchNumber == 2) {
        throw GpsSyncException(GpsSyncErrorKind.retryable, 'network down');
      }
      return points.last.seq;
    };
    await coordinator.syncNow(); // first batch (1-3) ok, second (4-6) fails
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedPointSeq,
        3);

    repo.pointBatches.clear();
    repo.syncPointsHandler = (points) => points.last.seq; // now succeeds
    await coordinator.syncNow();
    expect(repo.pointBatches, hasLength(1));
    expect(repo.pointBatches.single.map((p) => p.seq),
        [4, 5, 6]); // only the remainder
    coordinator.dispose();
  });

  test('23 partial event sync resumes from the persisted cursor', () async {
    await createRoute();
    await addEvents('r1', ['pause', 'resume', 'pause']); // seq 2,3,4 + start=1
    final coordinator = GpsSyncCoordinator(
      ownerId: 'me',
      db: db,
      repository: repo,
      currentUserId: () => 'me',
      eventBatchSize: 2,
      autoSyncOnInit: false,
    );
    var batchNumber = 0;
    repo.syncEventsHandler = (events) {
      batchNumber++;
      if (batchNumber == 2) {
        throw GpsSyncException(GpsSyncErrorKind.retryable, 'network down');
      }
      return events.last.seq;
    };
    await coordinator.syncNow(); // first batch (1-2) ok, second (3-4) fails
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
            .lastSyncedEventSeq,
        2);

    repo.eventBatches.clear();
    repo.syncEventsHandler = (events) => events.last.seq;
    await coordinator.syncNow();
    expect(repo.eventBatches.single.map((e) => e.seq), [3, 4]);
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 25-27 -- retry classification and data preservation
  // -------------------------------------------------------------------

  test('25 a retryable failure leaves the route notSynced, not failed',
      () async {
    await createRoute();
    repo.ensureRouteShellError =
        () => GpsSyncException(GpsSyncErrorKind.retryable, 'timeout');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.syncStatus, RouteSyncStatus.notSynced);
    expect(route.lastSyncError, contains('timeout'));
    coordinator.dispose();
  });

  test('26 a terminal integrity failure marks the route failed', () async {
    await createRoute();
    repo.ensureRouteShellError =
        () => GpsSyncException(GpsSyncErrorKind.integrityConflict, 'conflict');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.syncStatus, RouteSyncStatus.failed);
    coordinator.dispose();
  });

  test(
      '27 local point/event/waypoint data is preserved regardless of sync '
      'outcome', () async {
    await createRoute();
    await addPoints('r1', 2);
    await db.addWaypoint(
      id: 'w1',
      ownerId: 'me',
      recordedRouteId: 'r1',
      waypointType: 'viewpoint',
      latitude: 50,
      longitude: 30,
      recordedAt: DateTime.utc(2026, 1, 1, 10, 5),
    );
    repo.ensureRouteShellError =
        () => GpsSyncException(GpsSyncErrorKind.integrityConflict, 'boom');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(await db.getRoutePoints(ownerId: 'me', recordedRouteId: 'r1'),
        hasLength(2));
    expect(await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1'),
        hasLength(1));
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 28-33 -- finalization gating
  // -------------------------------------------------------------------

  test(
      '28 a still-recording route uploads incrementally but is never '
      'finalized', () async {
    await createRoute();
    await addPoints('r1', 2);
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.pointBatches, isNotEmpty);
    expect(repo.finalizeCalls, isEmpty);
    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.status, RecordedRouteStatus.recording);
    expect(route.syncStatus, RouteSyncStatus.notSynced);
    coordinator.dispose();
  });

  test('29 a paused route uploads incrementally but is never finalized',
      () async {
    await createRoute();
    await addPoints('r1', 2);
    await db.pauseRecording(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 10));
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.finalizeCalls, isEmpty);
    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.status, RecordedRouteStatus.paused);
    expect(route.syncStatus, RouteSyncStatus.notSynced);
    coordinator.dispose();
  });

  test(
      '30 a completed route finalizes only after points/waypoints/events '
      'have all been uploaded (call order)', () async {
    await createRoute();
    await addPoints('r1', 2);
    await db.addWaypoint(
      id: 'w1',
      ownerId: 'me',
      recordedRouteId: 'r1',
      waypointType: 'viewpoint',
      latitude: 50,
      longitude: 30,
      recordedAt: DateTime.utc(2026, 1, 1, 10, 5),
    );
    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 30));

    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final finalizeIndex = repo.calls.indexOf('finalizeRoute');
    expect(finalizeIndex, greaterThan(-1));
    expect(
        repo.calls.sublist(0, finalizeIndex),
        containsAll([
          'ensureRouteShell',
          'syncPoints',
          'upsertWaypoint',
          'syncEvents'
        ]));
    expect(repo.calls.where((c) => c == 'finalizeRoute'), hasLength(1));
    coordinator.dispose();
  });

  test('31 finalize success transitions the route to synced', () async {
    await createRoute();
    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 30));
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.syncStatus, RouteSyncStatus.synced);
    coordinator.dispose();
  });

  test('32a finalize retryable failure leaves the route notSynced', () async {
    await createRoute();
    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 30));
    repo.finalizeHandler =
        (_) => throw GpsSyncException(GpsSyncErrorKind.retryable, 'timeout');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.syncStatus, RouteSyncStatus.notSynced);
    coordinator.dispose();
  });

  test('32b finalize returning an unexpected row marks the route failed',
      () async {
    await createRoute();
    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 30));
    repo.finalizeHandler = (id) =>
        GpsFinalizeResponse(id: id, status: 'recording'); // not 'completed'
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.syncStatus, RouteSyncStatus.failed);
    coordinator.dispose();
  });

  test(
      '33 finalize exact retry is supported: retrying an already-synced '
      'route calls finalize again safely', () async {
    await createRoute();
    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 30));
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();
    expect((await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!.syncStatus,
        RouteSyncStatus.synced);

    await coordinator.retryRoute('r1');
    expect(repo.finalizeCalls, ['r1', 'r1']);
    expect((await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!.syncStatus,
        RouteSyncStatus.synced);
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 34 / 35 -- discarded routes / cross-account safety
  // -------------------------------------------------------------------

  test('34 a discarded route is never uploaded or finalized', () async {
    await createRoute();
    await addPoints('r1', 2);
    await db.discardRecording(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 15));
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    expect(repo.calls, isEmpty);
    coordinator.dispose();
  });

  test('35 User A pending route + a User B live session -> zero uploads',
      () async {
    await createRoute(id: 'rA', owner: 'userA');
    await addPoints('rA', 3, owner: 'userA');
    final coordinator = GpsSyncCoordinator(
      ownerId: 'userA',
      db: db,
      repository: repo,
      currentUserId: () => 'userB', // different user is now signed in
      autoSyncOnInit: false,
    );
    await coordinator.syncNow();
    expect(repo.calls, isEmpty);
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 39 -- batch size bound
  // -------------------------------------------------------------------

  test(
      '39 batch size is bounded -- the full track is never loaded/sent in '
      'one call', () async {
    await createRoute();
    await addPoints('r1', 5);
    final coordinator = GpsSyncCoordinator(
      ownerId: 'me',
      db: db,
      repository: repo,
      currentUserId: () => 'me',
      pointBatchSize: 2,
      autoSyncOnInit: false,
    );
    await coordinator.syncNow();
    for (final batch in repo.pointBatches) {
      expect(batch.length, lessThanOrEqualTo(2));
    }
    expect(repo.pointBatches.length, greaterThan(1));
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // 40 -- never synced before finalize success
  // -------------------------------------------------------------------

  test(
      '40 the route is never marked synced unless finalize actually '
      'succeeded', () async {
    await createRoute();
    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 30));
    repo.finalizeHandler = (_) =>
        throw GpsSyncException(GpsSyncErrorKind.integrityConflict, 'boom');
    final coordinator = coordinatorFor('me');
    await coordinator.syncNow();

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.syncStatus, isNot(RouteSyncStatus.synced));
    coordinator.dispose();
  });

  // -------------------------------------------------------------------
  // Journey Phase 1H-E2B -- the media phase inside the serialized pass
  // (C01-C10). Media ids/owner are canonical lowercase UUIDs, as in
  // production.
  // -------------------------------------------------------------------

  group('Journey media phase', () {
    const owner = '00000000-0000-4000-8000-000000000900';
    String uuid(int n) =>
        '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
    final t0 = DateTime.utc(2026, 3, 1, 9);
    final jpeg = Uint8List.fromList(img.encodeJpg(img
        .fill(img.Image(width: 8, height: 8), color: img.ColorRgb8(9, 9, 9))));

    late Directory root;
    late JourneyMediaStorage storage;
    late FakeJourneyMediaRemote remote;
    late List<String> log; // route-repo + media calls, interleaved
    String? live;
    late DateTime now;

    setUp(() async {
      live = owner;
      now = DateTime.utc(2026, 3, 2, 12);
      root = await Directory.systemTemp.createTemp('coordinator_media_test_');
      storage = JourneyMediaStorage(rootDirectory: () async => root);
      remote = FakeJourneyMediaRemote(liveUid: () => live);
      log = [];
      remote.onCall = (op) => log.add('media:$op');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    JourneyMediaSync newMediaSync() =>
        JourneyMediaSync(db: db, storage: storage, repository: remote);

    GpsSyncCoordinator mediaCoordinator({
      bool withMedia = true,
      Stream<NetworkStatus>? online,
      JourneyMediaSync? sync,
    }) =>
        GpsSyncCoordinator(
          ownerId: owner,
          db: db,
          repository: repo,
          currentUserId: () => live,
          autoSyncOnInit: false,
          mediaSync: withMedia ? (sync ?? newMediaSync()) : null,
          clock: () => now,
          onlineStatusStream: online,
        );

    /// A locally completed Journey with [photos] pending standalone photos,
    /// whose route sync is [routeSync].
    Future<List<LocalJourneyMediaItem>> journey(
      String routeId, {
      int photos = 1,
      int firstMedia = 100,
      String routeSync = RouteSyncStatus.notSynced,
    }) async {
      await db.createLocalRecordedRoute(
          id: routeId, ownerId: owner, startedAt: t0);
      final items = <LocalJourneyMediaItem>[];
      for (var i = 0; i < photos; i++) {
        final id = uuid(firstMedia + i);
        final path = JourneyMediaStorage.relativePathFor(
            recordedRouteId: routeId, mediaId: id);
        await storage.writeNew(path, jpeg);
        items.add(await db.insertJourneyMedia(
          id: id,
          ownerId: owner,
          recordedRouteId: routeId,
          capturedAt: t0.add(Duration(seconds: i)),
          latitude: 50.45,
          longitude: 30.52,
          localRelativePath: path,
        ));
      }
      await db.finishRecordingLocally(
          ownerId: owner, routeId: routeId, occurredAt: t0);
      await db.recordRouteSyncOutcome(
          ownerId: owner, routeId: routeId, syncStatus: routeSync);
      return items;
    }

    Future<String?> status(LocalJourneyMediaItem item) async =>
        (await db.getJourneyMediaItem(
                ownerId: owner,
                recordedRouteId: item.recordedRouteId,
                id: item.id))
            ?.syncStatus;

    const indeterminate = JourneyMediaSyncException(
        JourneyMediaRemoteFailureKind.indeterminate, 'scripted');

    test('C01 the media phase runs after remote finalize in the same pass',
        () async {
      final items = await journey(uuid(1));
      final coordinator = mediaCoordinator();
      repo.calls.clear();

      await coordinator.syncNow();

      final route = await db.getRecordedRoute(ownerId: owner, id: uuid(1));
      expect(route!.syncStatus, RouteSyncStatus.synced);
      expect(repo.calls.last, 'finalizeRoute');
      expect(log, ['media:upload', 'media:insert']);
      expect(await status(items.single), JourneyMediaSyncStatus.synced);
      coordinator.dispose();
    });

    test(
        'C02 a media failure never changes route sync and never re-runs '
        'finalize', () async {
      final items = await journey(uuid(1));
      remote.failBefore = (op) => op == 'upload' ? indeterminate : null;
      final coordinator = mediaCoordinator();

      await coordinator.syncNow();
      now = now.add(const Duration(hours: 1)); // past any backoff
      await coordinator.syncNow();

      final route = await db.getRecordedRoute(ownerId: owner, id: uuid(1));
      expect(route!.syncStatus, RouteSyncStatus.synced);
      expect(repo.finalizeCalls, hasLength(1));
      expect(log.where((c) => c == 'media:upload'), hasLength(2));
      expect(await status(items.single), JourneyMediaSyncStatus.pending);
      coordinator.dispose();
    });

    test(
        'C03 an already-synced Journey with pending media is found again by '
        'the actionable query (no route re-sync)', () async {
      final items = await journey(uuid(1), routeSync: RouteSyncStatus.synced);
      final coordinator = mediaCoordinator();
      repo.calls.clear();

      await coordinator.syncNow();

      expect(repo.calls, isEmpty, reason: 'the route itself is not revisited');
      expect(await status(items.single), JourneyMediaSyncStatus.synced);
      coordinator.dispose();
    });

    test(
        'C04 retryRoute requeues only that route\'s failed media; syncNow '
        'never does', () async {
      final a = await journey(uuid(1),
          firstMedia: 100, routeSync: RouteSyncStatus.synced);
      final b = await journey(uuid(2),
          firstMedia: 200, routeSync: RouteSyncStatus.synced);
      for (final item in [...a, ...b]) {
        await db.markJourneyMediaFailed(
            ownerId: owner, recordedRouteId: item.recordedRouteId, id: item.id);
      }
      final coordinator = mediaCoordinator();

      await coordinator.syncNow();
      expect(log, isEmpty);

      await coordinator.retryRoute(uuid(1));
      expect(await status(a.single), JourneyMediaSyncStatus.synced);
      expect(await status(b.single), JourneyMediaSyncStatus.failed);
      expect(remote.objects.keys.single, contains(uuid(1)));
      coordinator.dispose();
    });

    test(
        'C05 concurrent triggers run strictly one pass at a time and upload '
        'each photo exactly once', () async {
      final items =
          await journey(uuid(1), photos: 4, routeSync: RouteSyncStatus.synced);
      final release = Completer<void>();
      var first = true;
      remote.gate = (op) async {
        if (first) {
          first = false;
          await release.future;
        }
      };
      final coordinator = mediaCoordinator();

      final passes = [
        coordinator.syncNow(),
        coordinator.syncNow(),
        coordinator.retryRoute(uuid(1)),
        coordinator.syncNow(),
      ];
      await pumpEventQueue();
      release.complete();
      await Future.wait(passes);

      expect(remote.maxInFlight, 1);
      expect(remote.objectWrites, 4);
      expect(log.where((c) => c == 'media:upload'), hasLength(4));
      for (final item in items) {
        expect(await status(item), JourneyMediaSyncStatus.synced);
      }
      coordinator.dispose();
    });

    test(
        'C06 a queued pass makes the media phase yield after the current '
        'photo; the queued pass continues the work', () async {
      final items =
          await journey(uuid(1), photos: 2, routeSync: RouteSyncStatus.synced);
      final coordinator = mediaCoordinator();
      Future<void>? queued;
      remote.onCall = (op) {
        log.add('media:$op');
        if (op == 'upload' && queued == null) queued = coordinator.syncNow();
      };

      await coordinator.syncNow();
      expect(await status(items[0]), JourneyMediaSyncStatus.synced);
      expect(await status(items[1]), JourneyMediaSyncStatus.pending,
          reason: 'yielded after the current photo');

      await queued;
      expect(await status(items[1]), JourneyMediaSyncStatus.synced);
      coordinator.dispose();
    });

    test(
        'C07 media backoff: automatic triggers wait (route sync does not); '
        'reconnect and retryRoute bypass; only a clean unrestricted phase '
        'that settled an item resets it', () async {
      final items = await journey(uuid(1), routeSync: RouteSyncStatus.synced);
      remote.failBefore = (op) => op == 'upload' ? indeterminate : null;
      final online = StreamController<NetworkStatus>.broadcast();
      final coordinator = mediaCoordinator(online: online.stream);
      final start = now;

      await coordinator.syncNow();
      expect(coordinator.mediaBackoffUntil,
          start.add(const Duration(seconds: 30)));
      expect(log, hasLength(1));

      // Inside the window: media skipped, route sync still runs.
      await journey(uuid(2), photos: 0);
      now = start.add(const Duration(seconds: 10));
      repo.calls.clear();
      await coordinator.syncNow();
      expect(log, hasLength(1));
      expect(repo.calls, contains('finalizeRoute'));

      // After the window: retried, fails again, the window doubles.
      now = start.add(const Duration(seconds: 31));
      await coordinator.syncNow();
      expect(log, hasLength(2));
      expect(
          coordinator.mediaBackoffUntil, now.add(const Duration(seconds: 60)));

      // Reconnect bypasses the window.
      online
        ..add(NetworkStatus.offline)
        ..add(NetworkStatus.online);
      await pumpEventQueue();
      await coordinator.pendingSync;
      expect(log, hasLength(3));

      // An explicit retry bypasses it too -- but a single-route retry never
      // clears the backoff (P3-1): it did not re-attempt everything.
      remote.failBefore = null;
      final window = coordinator.mediaBackoffUntil;
      await coordinator.retryRoute(uuid(1));
      expect(await status(items.single), JourneyMediaSyncStatus.synced);
      expect(coordinator.mediaBackoffUntil, window);

      // A clean, unrestricted phase that settled an item clears it.
      final next = await journey(uuid(3),
          firstMedia: 300, routeSync: RouteSyncStatus.synced);
      now = window!.add(const Duration(seconds: 1));
      await coordinator.syncNow();
      expect(await status(next.single), JourneyMediaSyncStatus.synced);
      expect(coordinator.mediaBackoffUntil, isNull);

      // The cap: repeated failures never exceed 15 minutes.
      final capped = await journey(uuid(4),
          firstMedia: 400, routeSync: RouteSyncStatus.synced);
      remote.failBefore = (op) => op == 'upload' ? indeterminate : null;
      for (var i = 0; i < 8; i++) {
        now = now.add(const Duration(hours: 1));
        await coordinator.syncNow();
      }
      expect(
          coordinator.mediaBackoffUntil, now.add(const Duration(minutes: 15)));
      expect(await status(capped.single), JourneyMediaSyncStatus.pending);
      await online.close();
      coordinator.dispose();
    });

    test(
        'C08 two coordinators racing on the same photo converge: synced, one '
        'object, one row', () async {
      final items = await journey(uuid(1), routeSync: RouteSyncStatus.synced);
      // Hold the first upload until the second coordinator's upload has
      // started, so both genuinely race on the same object and row.
      final bothUploading = Completer<void>();
      var uploads = 0;
      remote.onCall = (op) {
        log.add('media:$op');
        if (op == 'upload' && ++uploads == 2) bothUploading.complete();
      };
      remote.gate =
          (op) => op == 'upload' ? bothUploading.future : Future<void>.value();
      final first = mediaCoordinator();
      final second = mediaCoordinator();

      await Future.wait([first.syncNow(), second.syncNow()]);

      expect(await status(items.single), JourneyMediaSyncStatus.synced);
      expect(remote.objectWrites, 1);
      expect(remote.rows, hasLength(1));
      expect(remote.insertedPayloads, hasLength(1));
      // The loser converged through the duplicate proofs, not by luck.
      expect(log.where((c) => c == 'media:upload'), hasLength(2));
      expect(log, contains('media:download'),
          reason: 'object duplicate -> byte comparison');
      expect(log.where((c) => c == 'media:insert'), hasLength(2));
      expect(log, contains('media:select'),
          reason: 'row duplicate -> authenticated read-back');
      first.dispose();
      second.dispose();
    });

    test(
        'C11 P2-1 a stalled upload times out: the pass ends, the photo stays '
        'pending, backoff starts, and a later pass can finalize a route',
        () async {
      final items = await journey(uuid(1), routeSync: RouteSyncStatus.synced);
      remote.gate = (op) =>
          op == 'upload' ? Completer<void>().future : Future<void>.value();
      final coordinator = mediaCoordinator(
          sync: JourneyMediaSync(
              db: db,
              storage: storage,
              repository: remote,
              timeouts: const JourneyMediaTimeouts(upload: Duration.zero)));

      await coordinator.syncNow(); // completes despite the stalled upload
      expect(await status(items.single), JourneyMediaSyncStatus.pending);
      expect(
          coordinator.mediaBackoffUntil, now.add(const Duration(seconds: 30)));

      await journey(uuid(2), photos: 0);
      repo.calls.clear();
      await coordinator.syncNow();
      expect(repo.finalizeCalls.last, uuid(2));
      expect(
          (await db.getRecordedRoute(ownerId: owner, id: uuid(2)))!.syncStatus,
          RouteSyncStatus.synced);
      coordinator.dispose();
    });

    test(
        'C12 P2-3 a 42501 (real classifier) never parks the photo; it backs '
        'off and recovers automatically', () async {
      final items = await journey(uuid(1), routeSync: RouteSyncStatus.synced);
      var first = true;
      remote.failBefore = (op) {
        if (op != 'insert' || !first) return null;
        first = false;
        return SupabaseJourneyMediaSyncRepository.classify(
            const PostgrestException(message: 'denied', code: '42501'));
      };
      final coordinator = mediaCoordinator();

      await coordinator.syncNow();
      expect(await status(items.single), JourneyMediaSyncStatus.pending);
      final window = coordinator.mediaBackoffUntil;
      expect(window, now.add(const Duration(seconds: 30)));

      now = window!.add(const Duration(seconds: 1));
      await coordinator.syncNow();
      expect(await status(items.single), JourneyMediaSyncStatus.synced);
      expect(coordinator.mediaBackoffUntil, isNull);
      coordinator.dispose();
    });

    for (final (label, end) in [
      ('completes', RecordedRouteStatus.completed),
      ('is discarded', RecordedRouteStatus.discarded),
    ]) {
      test(
          'C13 P2-4 no media calls while another Journey records or is '
          'paused (no backoff); the old photo uploads once it $label',
          () async {
        final old = await journey(uuid(1), routeSync: RouteSyncStatus.synced);
        final coordinator = mediaCoordinator();
        await db.createLocalRecordedRoute(
            id: uuid(9), ownerId: owner, startedAt: t0);

        await coordinator.syncNow();
        expect(log, isEmpty);
        expect(coordinator.mediaBackoffUntil, isNull);
        expect(repo.shellRouteIds, contains(uuid(9)),
            reason: 'route sync of the active Journey is unaffected');

        await db.pauseRecording(
            ownerId: owner, routeId: uuid(9), occurredAt: t0);
        await coordinator.syncNow();
        expect(log, isEmpty);
        expect(await status(old.single), JourneyMediaSyncStatus.pending);

        if (end == RecordedRouteStatus.completed) {
          await db.finishRecordingLocally(
              ownerId: owner, routeId: uuid(9), occurredAt: t0);
        } else {
          await db.discardRecording(
              ownerId: owner, routeId: uuid(9), occurredAt: t0);
        }
        await coordinator.syncNow();
        expect(await status(old.single), JourneyMediaSyncStatus.synced);
        coordinator.dispose();
      });
    }

    test(
        'C14 P3-1 backoff isolation: an unrelated single-route retry, a '
        'yielded phase and a capped phase never clear an active backoff',
        () async {
      final items =
          await journey(uuid(1), photos: 2, routeSync: RouteSyncStatus.synced);
      await journey(uuid(2), photos: 0, routeSync: RouteSyncStatus.synced);
      remote.failBefore = (op) => op == 'upload' ? indeterminate : null;
      final online = StreamController<NetworkStatus>.broadcast();
      final coordinator = mediaCoordinator(online: online.stream);

      await coordinator.syncNow();
      final window = coordinator.mediaBackoffUntil;
      expect(window, isNotNull);
      remote.failBefore = null;

      // (a) A retry of a route with no eligible media: unchanged.
      await coordinator.retryRoute(uuid(2));
      expect(coordinator.mediaBackoffUntil, window);

      // (b) A bypassing, unrestricted phase that yields after one photo:
      // the other (previously failed) photo was not re-attempted.
      Future<void>? queued;
      remote.onCall = (op) {
        log.add('media:$op');
        if (op == 'upload' && queued == null) queued = coordinator.syncNow();
      };
      online
        ..add(NetworkStatus.offline)
        ..add(NetworkStatus.online);
      await pumpEventQueue();
      await coordinator.pendingSync;
      await queued;
      expect(await status(items[0]), JourneyMediaSyncStatus.synced);
      expect(await status(items[1]), JourneyMediaSyncStatus.pending);
      expect(coordinator.mediaBackoffUntil, window);
      await online.close();
      coordinator.dispose();

      // (c) A bypassing, unrestricted phase stopped by the cap (cap 1) with
      // photos left: unchanged.
      remote.onCall = (op) => log.add('media:$op');
      final more = await journey(uuid(3),
          photos: 2, firstMedia: 300, routeSync: RouteSyncStatus.synced);
      final reconnect = StreamController<NetworkStatus>.broadcast();
      final cappedCoordinator = mediaCoordinator(
          online: reconnect.stream,
          sync: JourneyMediaSync(
              db: db,
              storage: storage,
              repository: remote,
              maxItemsPerPass: 1));
      remote.failBefore = (op) => op == 'upload' ? indeterminate : null;
      await cappedCoordinator.syncNow(); // items[1] fails -> backoff
      final cappedWindow = cappedCoordinator.mediaBackoffUntil;
      expect(cappedWindow, isNotNull);
      remote.failBefore = null;
      reconnect
        ..add(NetworkStatus.offline)
        ..add(NetworkStatus.online);
      await pumpEventQueue();
      await cappedCoordinator.pendingSync;
      expect(await status(items[1]), JourneyMediaSyncStatus.synced);
      expect(await status(more[0]), JourneyMediaSyncStatus.pending,
          reason: 'the cap stopped the phase');
      expect(cappedCoordinator.mediaBackoffUntil, cappedWindow);
      await reconnect.close();
      cappedCoordinator.dispose();
    });

    test('C09 without a media helper, route sync behaves exactly as before',
        () async {
      final items = await journey(uuid(1));
      await db.markJourneyMediaFailed(
          ownerId: owner,
          recordedRouteId: items.single.recordedRouteId,
          id: items.single.id);
      final coordinator = mediaCoordinator(withMedia: false);

      await coordinator.syncNow();
      await coordinator.retryRoute(uuid(1));

      final route = await db.getRecordedRoute(ownerId: owner, id: uuid(1));
      expect(route!.syncStatus, RouteSyncStatus.synced);
      expect(log, isEmpty);
      expect(await status(items.single), JourneyMediaSyncStatus.failed,
          reason: 'no requeue without a media phase');
      coordinator.dispose();
    });

    test(
        'C15 P2-2 a Journey starting mid-pass defers the remaining photos '
        'WITHOUT touching backoff; route sync continues; they upload after '
        'it ends', () async {
      final items =
          await journey(uuid(1), photos: 2, routeSync: RouteSyncStatus.synced);
      var started = false;
      remote.gate = (op) async {
        if (op == 'insert' && !started) {
          started = true; // the user starts a new Journey during photo A
          await db.createLocalRecordedRoute(
              id: uuid(9), ownerId: owner, startedAt: t0);
        }
      };
      final coordinator = mediaCoordinator();

      await coordinator.syncNow();
      expect(await status(items[0]), JourneyMediaSyncStatus.synced,
          reason: 'the photo already in flight finished');
      expect(await status(items[1]), JourneyMediaSyncStatus.pending);
      expect(log.where((c) => c == 'media:upload'), hasLength(1));
      expect(coordinator.mediaBackoffUntil, isNull,
          reason: 'a recording is not an error');

      // Ordinary route sync of the active Journey continues; media does not.
      repo.calls.clear();
      await coordinator.syncNow();
      expect(repo.shellRouteIds, contains(uuid(9)));
      expect(log.where((c) => c == 'media:upload'), hasLength(1));
      expect(coordinator.mediaBackoffUntil, isNull);

      await db.discardRecording(
          ownerId: owner, routeId: uuid(9), occurredAt: t0);
      await coordinator.syncNow();
      expect(await status(items[1]), JourneyMediaSyncStatus.synced);
      coordinator.dispose();
    });

    test(
        'C15b P2-2 a deferral never changes an ACTIVE backoff (neither '
        'clears nor extends it)', () async {
      final items = await journey(uuid(1), routeSync: RouteSyncStatus.synced);
      remote.failBefore = (op) => op == 'upload' ? indeterminate : null;
      final coordinator = mediaCoordinator();
      await coordinator.syncNow();
      final window = coordinator.mediaBackoffUntil;
      expect(window, now.add(const Duration(seconds: 30)));

      remote.failBefore = null;
      await db.createLocalRecordedRoute(
          id: uuid(9), ownerId: owner, startedAt: t0);
      now = window!.add(const Duration(minutes: 5)); // window long expired
      await coordinator.syncNow();

      expect(coordinator.mediaBackoffUntil, window);
      expect(await status(items.single), JourneyMediaSyncStatus.pending);
      expect(log.where((c) => c == 'media:upload'), hasLength(1),
          reason: 'only the first, failed attempt');
      coordinator.dispose();
    });

    test(
        'C10 the media sync sources add no timer, polling, GPS/location or '
        'connectivity dependency', () {
      for (final path in [
        'lib/features/gps/sync/journey_media_sync.dart',
        'lib/features/gps/sync/domain/journey_media_sync_repository.dart',
        'lib/features/gps/sync/data/supabase_journey_media_sync_repository.dart',
        'lib/features/gps/sync/gps_sync_coordinator.dart',
      ]) {
        final source = File(path).readAsStringSync();
        for (final banned in [
          'Timer(',
          'Timer.periodic',
          'Stream.periodic',
          'geolocator',
          'getPositionStream',
          'location_source',
          'connectivity_plus',
          'Workmanager',
          'BackgroundFetch',
        ]) {
          expect(source.contains(banned), isFalse,
              reason: '$path contains $banned');
        }
      }
    });
  });

  // -------------------------------------------------------------------
  // 36-38 -- static source scans: no Activity Events / XP / invite wiring
  // anywhere in the GPS sync feature, mirroring this repo's existing
  // Node/SQL static-contract-test convention.
  // -------------------------------------------------------------------

  group('static source scan (no Activity Events / XP / invite wiring)', () {
    final sources = [
      'lib/features/gps/sync/gps_sync_coordinator.dart',
      'lib/features/gps/sync/domain/gps_sync_repository.dart',
      'lib/features/gps/sync/data/supabase_gps_sync_repository.dart',
      // Journey Phase 1H-E2B media sync sources (C10).
      'lib/features/gps/sync/journey_media_sync.dart',
      'lib/features/gps/sync/domain/journey_media_sync_repository.dart',
      'lib/features/gps/sync/data/supabase_journey_media_sync_repository.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    test('36 no Activity Event call anywhere in the GPS sync feature', () {
      expect(sources.contains('_record_activity_event'), isFalse);
      expect(sources.contains('ROUTE_RECORDED_COMPLETED'), isFalse);
      expect(sources.contains("from('activity_events')"), isFalse);
    });

    test('37 no XP mutation anywhere in the GPS sync feature', () {
      expect(sources.contains("'xp'"), isFalse);
      expect(sources.contains('.xp'), isFalse);
      expect(sources.contains("from('profiles')"), isFalse);
    });

    test('38 no invite mutation anywhere in the GPS sync feature', () {
      expect(sources.contains('invite_balance'), isFalse);
      expect(sources.contains('invited_by'), isFalse);
    });
  });
}
