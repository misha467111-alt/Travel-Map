import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';

void main() {
  late GpsLocalDatabase db;

  setUp(() {
    db = GpsLocalDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('createLocalRecordedRoute', () {
    test('creates a standalone recording (tripId = null)', () async {
      final route = await db.createLocalRecordedRoute(
        id: 'r1',
        ownerId: 'me',
        startedAt: DateTime.utc(2026, 1, 1, 10),
      );
      expect(route.tripId, isNull);
      expect(route.status, RecordedRouteStatus.recording);
    });

    test('preserves the client-generated UUID as-is', () async {
      final route = await db.createLocalRecordedRoute(
        id: 'client-uuid-1234',
        ownerId: 'me',
        startedAt: DateTime.utc(2026, 1, 1, 10),
      );
      expect(route.id, 'client-uuid-1234');
    });

    test('atomically creates the route AND a start event', () async {
      await db.createLocalRecordedRoute(
        id: 'r1',
        ownerId: 'me',
        startedAt: DateTime.utc(2026, 1, 1, 10),
      );
      final events = await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1');
      expect(events, hasLength(1));
      expect(events.single.eventType, RouteEventType.start);
      expect(events.single.seq, 1);
    });

    test('throws ActiveRecordingExistsException for a second active route '
        'under the same owner', () async {
      await db.createLocalRecordedRoute(
        id: 'r1',
        ownerId: 'me',
        startedAt: DateTime.utc(2026, 1, 1, 10),
      );
      expect(
        () => db.createLocalRecordedRoute(
          id: 'r2',
          ownerId: 'me',
          startedAt: DateTime.utc(2026, 1, 1, 11),
        ),
        throwsA(isA<ActiveRecordingExistsException>()),
      );
    });

    test('the partial unique index enforces this at the database level too, '
        'independent of the application-level check', () async {
      // Bypass createLocalRecordedRoute's own guard by inserting directly,
      // proving the constraint is real and not just app-level discipline.
      final now = DateTime.utc(2026, 1, 1);
      await db.into(db.localRecordedRoutes).insert(
            LocalRecordedRoutesCompanion.insert(
              id: 'r1',
              ownerId: 'me',
              startedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      expect(
        () => db.into(db.localRecordedRoutes).insert(
              LocalRecordedRoutesCompanion.insert(
                id: 'r2',
                ownerId: 'me',
                startedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(anything),
      );
    });

    test('does not block a second active route for a DIFFERENT owner',
        () async {
      await db.createLocalRecordedRoute(
        id: 'r1',
        ownerId: 'accountA',
        startedAt: DateTime.utc(2026, 1, 1),
      );
      final route = await db.createLocalRecordedRoute(
        id: 'r2',
        ownerId: 'accountB',
        startedAt: DateTime.utc(2026, 1, 1),
      );
      expect(route.id, 'r2');
    });
  });

  group('appendRoutePoint', () {
    test('assigns deterministic, monotonically increasing seq', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      for (var i = 0; i < 3; i++) {
        await db.appendRoutePoint(
          ownerId: 'me',
          recordedRouteId: 'r1',
          latitude: 50.4 + i * 0.01,
          longitude: 30.5,
          recordedAt: DateTime.utc(2026, 1, 1, 10, i),
        );
      }
      final points = await db.getRoutePoints(ownerId: 'me', recordedRouteId: 'r1');
      expect(points.map((p) => p.seq), [1, 2, 3]);
    });

    test('duplicate (recordedRouteId, seq) is rejected by the primary key',
        () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      final now = DateTime.utc(2026, 1, 1, 10);
      await db.into(db.localRoutePoints).insert(
            LocalRoutePointsCompanion.insert(
              recordedRouteId: 'r1',
              seq: 1,
              ownerId: 'me',
              latitude: 50.4,
              longitude: 30.5,
              recordedAt: now,
            ),
          );
      expect(
        () => db.into(db.localRoutePoints).insert(
              LocalRoutePointsCompanion.insert(
                recordedRouteId: 'r1',
                seq: 1,
                ownerId: 'me',
                latitude: 50.5,
                longitude: 30.6,
                recordedAt: now,
              ),
            ),
        throwsA(anything),
      );
    });

    test('each recording gets its own independent seq sequence', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.appendRoutePoint(
          ownerId: 'me',
          recordedRouteId: 'r1',
          latitude: 50.4,
          longitude: 30.5,
          recordedAt: DateTime.utc(2026, 1, 1));

      final route2 = await db.createLocalRecordedRoute(
          id: 'r2', ownerId: 'accountB', startedAt: DateTime.utc(2026, 1, 1));
      await db.appendRoutePoint(
          ownerId: 'accountB',
          recordedRouteId: route2.id,
          latitude: 51.4,
          longitude: 31.5,
          recordedAt: DateTime.utc(2026, 1, 1));

      final r2Points = await db.getRoutePoints(ownerId: 'accountB', recordedRouteId: 'r2');
      expect(r2Points.single.seq, 1);
    });
  });

  group('pause / resume transactions', () {
    test('pause is atomic: status -> paused and a pause event appended together',
        () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1, 10));
      await db.pauseRecording(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 10, 5),
      );
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      final events = await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1');
      expect(route!.status, RecordedRouteStatus.paused);
      expect(events.map((e) => e.eventType), [RouteEventType.start, RouteEventType.pause]);
    });

    test('resume is atomic: status -> recording and a resume event appended together',
        () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1, 10));
      await db.pauseRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 10, 5));
      await db.resumeRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 10, 8));
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      final events = await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1');
      expect(route!.status, RecordedRouteStatus.recording);
      expect(events.map((e) => e.eventType),
          [RouteEventType.start, RouteEventType.pause, RouteEventType.resume]);
    });
  });

  group('waypoints work regardless of recording/paused state', () {
    test('waypoint can be added while recording', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.addWaypoint(
        id: 'wp1',
        ownerId: 'me',
        recordedRouteId: 'r1',
        waypointType: 'viewpoint',
        latitude: 50.4,
        longitude: 30.5,
        recordedAt: DateTime.utc(2026, 1, 1, 10),
      );
      final waypoints = await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1');
      expect(waypoints, hasLength(1));
    });

    test('waypoint can be added while paused', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.pauseRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 10));
      await db.addWaypoint(
        id: 'wp1',
        ownerId: 'me',
        recordedRouteId: 'r1',
        waypointType: 'campsite',
        latitude: 50.4,
        longitude: 30.5,
        recordedAt: DateTime.utc(2026, 1, 1, 10, 1),
      );
      final waypoints = await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1');
      expect(waypoints, hasLength(1));
      expect(waypoints.single.waypointType, 'campsite');
    });

    test('updating a waypoint resets its syncStatus to pending', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.addWaypoint(
        id: 'wp1',
        ownerId: 'me',
        recordedRouteId: 'r1',
        waypointType: 'viewpoint',
        latitude: 50.4,
        longitude: 30.5,
        recordedAt: DateTime.utc(2026, 1, 1),
      );
      await db.markWaypointSynced(ownerId: 'me', id: 'wp1');
      await db.updateWaypointMetadata(
          ownerId: 'me', id: 'wp1', title: const Value('Nice view'));
      final waypoints = await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1');
      expect(waypoints.single.syncStatus, WaypointSyncStatus.pending);
      expect(waypoints.single.title, 'Nice view');
    });

    test('deleteWaypoint removes it', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.addWaypoint(
        id: 'wp1',
        ownerId: 'me',
        recordedRouteId: 'r1',
        waypointType: 'danger',
        latitude: 50.4,
        longitude: 30.5,
        recordedAt: DateTime.utc(2026, 1, 1),
      );
      await db.deleteWaypoint(ownerId: 'me', id: 'wp1');
      final waypoints = await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1');
      expect(waypoints, isEmpty);
    });

    test('getUnsyncedWaypoints returns only pending ones', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.addWaypoint(
        id: 'wp1',
        ownerId: 'me',
        recordedRouteId: 'r1',
        waypointType: 'rest',
        latitude: 50.4,
        longitude: 30.5,
        recordedAt: DateTime.utc(2026, 1, 1),
      );
      await db.addWaypoint(
        id: 'wp2',
        ownerId: 'me',
        recordedRouteId: 'r1',
        waypointType: 'water',
        latitude: 50.5,
        longitude: 30.6,
        recordedAt: DateTime.utc(2026, 1, 1, 1),
      );
      await db.markWaypointSynced(ownerId: 'me', id: 'wp1');

      final unsynced = await db.getUnsyncedWaypoints(ownerId: 'me', recordedRouteId: 'r1');
      expect(unsynced.map((w) => w.id), ['wp2']);
    });
  });

  group('finish transaction', () {
    test('appends a finish event, sets endedAt, and completes the route atomically',
        () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1, 10));
      await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: DateTime.utc(2026, 1, 1, 11),
      );
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      final events = await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1');
      expect(route!.status, RecordedRouteStatus.completed);
      expect(route.endedAt, DateTime.utc(2026, 1, 1, 11));
      expect(events.map((e) => e.eventType), [RouteEventType.start, RouteEventType.finish]);
    });

    test('can finish directly from paused', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1, 10));
      await db.pauseRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 10, 30));
      await db.finishRecordingLocally(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 11));
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.status, RecordedRouteStatus.completed);
    });
  });

  group('invalid status transitions are rejected', () {
    Future<void> expectInvalid(
      GpsLocalDatabase db, {
      required String routeId,
      required String newStatus,
    }) {
      return expectLater(
        db.updateRouteStatus(ownerId: 'me', routeId: routeId, newStatus: newStatus),
        throwsA(isA<InvalidRouteStatusTransition>()),
      );
    }

    test('completed -> recording is rejected', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.finishRecordingLocally(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      await expectInvalid(db, routeId: 'r1', newStatus: RecordedRouteStatus.recording);
    });

    test('completed -> paused is rejected', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.finishRecordingLocally(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      await expectInvalid(db, routeId: 'r1', newStatus: RecordedRouteStatus.paused);
    });

    test('discarded -> recording is rejected', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.discardRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      await expectInvalid(db, routeId: 'r1', newStatus: RecordedRouteStatus.recording);
    });

    test('discarded -> paused is rejected', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.discardRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      await expectInvalid(db, routeId: 'r1', newStatus: RecordedRouteStatus.paused);
    });

    test('updateRouteStatus can never directly set completed', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await expectInvalid(db, routeId: 'r1', newStatus: RecordedRouteStatus.completed);
    });

    test('setting the same status again is a harmless no-op', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.updateRouteStatus(
          ownerId: 'me', routeId: 'r1', newStatus: RecordedRouteStatus.recording);
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.status, RecordedRouteStatus.recording);
    });
  });

  group('crash/restart recovery', () {
    test('getRecoverableRecording finds a recording-status route', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      final recoverable = await db.getRecoverableRecording('me');
      expect(recoverable?.id, 'r1');
    });

    test('getRecoverableRecording finds a paused-status route', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.pauseRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      final recoverable = await db.getRecoverableRecording('me');
      expect(recoverable?.id, 'r1');
    });

    test('a completed route is not recoverable', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.finishRecordingLocally(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      final recoverable = await db.getRecoverableRecording('me');
      expect(recoverable, isNull);
    });

    test('a discarded route is not recoverable', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.discardRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      final recoverable = await db.getRecoverableRecording('me');
      expect(recoverable, isNull);
    });

    test('no recoverable recording returns null, not an error', () async {
      final recoverable = await db.getRecoverableRecording('nobody');
      expect(recoverable, isNull);
    });
  });

  group('account isolation', () {
    test('account A local GPS data is invisible to account B', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'accountA', startedAt: DateTime.utc(2026, 1, 1));
      await db.appendRoutePoint(
        ownerId: 'accountA',
        recordedRouteId: 'r1',
        latitude: 50.4,
        longitude: 30.5,
        recordedAt: DateTime.utc(2026, 1, 1),
      );
      await db.addWaypoint(
        id: 'wp1',
        ownerId: 'accountA',
        recordedRouteId: 'r1',
        waypointType: 'parking',
        latitude: 50.4,
        longitude: 30.5,
        recordedAt: DateTime.utc(2026, 1, 1),
      );

      expect(await db.getRecordedRoute(ownerId: 'accountB', id: 'r1'), isNull);
      expect(
          await db.getRoutePoints(ownerId: 'accountB', recordedRouteId: 'r1'), isEmpty);
      expect(await db.getWaypoints(ownerId: 'accountB', recordedRouteId: 'r1'), isEmpty);
      expect(await db.getRecoverableRecording('accountB'), isNull);
    });
  });

  group('sync cursor progression', () {
    test('point sync cursor advances monotonically', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.advancePointSyncCursor(ownerId: 'me', recordedRouteId: 'r1', newLastSyncedSeq: 5);
      var route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.lastSyncedPointSeq, 5);

      // A smaller/equal value never regresses the cursor.
      await db.advancePointSyncCursor(ownerId: 'me', recordedRouteId: 'r1', newLastSyncedSeq: 3);
      route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.lastSyncedPointSeq, 5);

      await db.advancePointSyncCursor(ownerId: 'me', recordedRouteId: 'r1', newLastSyncedSeq: 9);
      route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.lastSyncedPointSeq, 9);
    });

    test('event sync cursor advances monotonically', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.advanceEventSyncCursor(ownerId: 'me', recordedRouteId: 'r1', newLastSyncedSeq: 2);
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.lastSyncedEventSeq, 2);
    });

    test('unsynced point batch returns the correct ordered subset', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      for (var i = 0; i < 5; i++) {
        await db.appendRoutePoint(
          ownerId: 'me',
          recordedRouteId: 'r1',
          latitude: 50.4,
          longitude: 30.5,
          recordedAt: DateTime.utc(2026, 1, 1, 10, i),
        );
      }
      await db.advancePointSyncCursor(ownerId: 'me', recordedRouteId: 'r1', newLastSyncedSeq: 2);

      final batch =
          await db.getUnsyncedPointBatch(ownerId: 'me', recordedRouteId: 'r1', batchSize: 10);
      expect(batch.map((p) => p.seq), [3, 4, 5]);
    });

    test('unsynced batch respects batchSize', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      for (var i = 0; i < 5; i++) {
        await db.appendRoutePoint(
          ownerId: 'me',
          recordedRouteId: 'r1',
          latitude: 50.4,
          longitude: 30.5,
          recordedAt: DateTime.utc(2026, 1, 1, 10, i),
        );
      }
      final batch =
          await db.getUnsyncedPointBatch(ownerId: 'me', recordedRouteId: 'r1', batchSize: 2);
      expect(batch.map((p) => p.seq), [1, 2]);
    });

    test('unsynced event batch returns the correct ordered subset', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await db.pauseRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      await db.resumeRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 2));
      // 3 events total: start(1), pause(2), resume(3).
      await db.advanceEventSyncCursor(ownerId: 'me', recordedRouteId: 'r1', newLastSyncedSeq: 1);
      final batch =
          await db.getUnsyncedEventBatch(ownerId: 'me', recordedRouteId: 'r1', batchSize: 10);
      expect(batch.map((e) => e.eventType), [RouteEventType.pause, RouteEventType.resume]);
    });
  });

  group('reactive queries', () {
    test('watchActiveRecordedRoute emits null then the created route', () async {
      final emissions = <String?>[];
      final sub = db.watchActiveRecordedRoute('me').listen((r) => emissions.add(r?.id));
      await pumpEventQueue();
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      await pumpEventQueue();
      expect(emissions, [null, 'r1']);
      await sub.cancel();
    });

    test('watchActiveRecordedRoute emits null again once finished', () async {
      final emissions = <String?>[];
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      final sub = db.watchActiveRecordedRoute('me').listen((r) => emissions.add(r?.id));
      await pumpEventQueue();
      await db.finishRecordingLocally(
          ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
      await pumpEventQueue();
      expect(emissions, ['r1', null]);
      await sub.cancel();
    });

    test('watchRoutePoints re-emits on each appended point', () async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
      final emissions = <int>[];
      final sub = db
          .watchRoutePoints(ownerId: 'me', recordedRouteId: 'r1')
          .listen((points) => emissions.add(points.length));
      await pumpEventQueue();
      await db.appendRoutePoint(
        ownerId: 'me',
        recordedRouteId: 'r1',
        latitude: 50.4,
        longitude: 30.5,
        recordedAt: DateTime.utc(2026, 1, 1, 10),
      );
      await pumpEventQueue();
      expect(emissions, [0, 1]);
      await sub.cancel();
    });
  });
}
