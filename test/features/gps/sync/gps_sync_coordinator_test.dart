import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/sync/domain/gps_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/gps_sync_coordinator.dart';

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
    await db.deleteWaypoint(ownerId: 'me', id: 'w1'); // becomes a tombstone

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
  // 36-38 -- static source scans: no Activity Events / XP / invite wiring
  // anywhere in the GPS sync feature, mirroring this repo's existing
  // Node/SQL static-contract-test convention.
  // -------------------------------------------------------------------

  group('static source scan (no Activity Events / XP / invite wiring)', () {
    final sources = [
      'lib/features/gps/sync/gps_sync_coordinator.dart',
      'lib/features/gps/sync/domain/gps_sync_repository.dart',
      'lib/features/gps/sync/data/supabase_gps_sync_repository.dart',
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
