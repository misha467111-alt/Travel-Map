import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';

void main() {
  late GpsLocalDatabase db;

  setUp(() {
    db = GpsLocalDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<LocalRecordedRoute> createRoute(
      {String id = 'r1', String owner = 'me'}) {
    return db.createLocalRecordedRoute(
      id: id,
      ownerId: owner,
      startedAt: DateTime.utc(2026, 1, 1, 10),
    );
  }

  group('markRouteSyncing / recordRouteSyncOutcome', () {
    test('markRouteSyncing sets syncStatus=syncing and records an attempt time',
        () async {
      await createRoute();
      await db.markRouteSyncing(ownerId: 'me', routeId: 'r1');
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.syncStatus, RouteSyncStatus.syncing);
      expect(route.lastSyncAttemptAt, isNotNull);
    });

    test(
        'recordRouteSyncOutcome sets the given status and clears the error on success',
        () async {
      await createRoute();
      await db.recordRouteSyncOutcome(
        ownerId: 'me',
        routeId: 'r1',
        syncStatus: RouteSyncStatus.failed,
        lastSyncError: 'boom',
      );
      var route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.syncStatus, RouteSyncStatus.failed);
      expect(route.lastSyncError, 'boom');

      await db.recordRouteSyncOutcome(
        ownerId: 'me',
        routeId: 'r1',
        syncStatus: RouteSyncStatus.synced,
      );
      route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.syncStatus, RouteSyncStatus.synced);
      expect(route.lastSyncError, isNull);
    });
  });

  group('normalizeStaleSyncingRoutes', () {
    test('resets a stuck syncing route back to notSynced', () async {
      await createRoute();
      await db.markRouteSyncing(ownerId: 'me', routeId: 'r1');
      expect((await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!.syncStatus,
          RouteSyncStatus.syncing);

      await db.normalizeStaleSyncingRoutes(ownerId: 'me');

      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.syncStatus, RouteSyncStatus.notSynced);
    });

    test(
        'preserves cursors, lastSyncAttemptAt, and lastSyncError -- only '
        'syncStatus changes', () async {
      await createRoute();
      await db.appendRoutePoint(
        ownerId: 'me',
        recordedRouteId: 'r1',
        latitude: 1,
        longitude: 1,
        recordedAt: DateTime.utc(2026, 1, 1, 10, 0, 1),
      );
      await db.advancePointSyncCursor(
          ownerId: 'me', recordedRouteId: 'r1', newLastSyncedSeq: 1);
      await db.recordRouteSyncOutcome(
        ownerId: 'me',
        routeId: 'r1',
        syncStatus: RouteSyncStatus.failed,
        lastSyncError: 'previous failure',
      );
      await db.markRouteSyncing(ownerId: 'me', routeId: 'r1');
      final beforeAttempt =
          (await db.getRecordedRoute(ownerId: 'me', id: 'r1'))!
              .lastSyncAttemptAt;

      await db.normalizeStaleSyncingRoutes(ownerId: 'me');

      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.syncStatus, RouteSyncStatus.notSynced);
      expect(route.lastSyncedPointSeq, 1);
      expect(route.lastSyncAttemptAt, beforeAttempt);
    });

    test('does not touch a route that is not currently syncing', () async {
      await createRoute();
      await db.recordRouteSyncOutcome(
        ownerId: 'me',
        routeId: 'r1',
        syncStatus: RouteSyncStatus.failed,
        lastSyncError: 'terminal',
      );
      await db.normalizeStaleSyncingRoutes(ownerId: 'me');
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.syncStatus, RouteSyncStatus.failed);
      expect(route.lastSyncError, 'terminal');
    });

    test('only affects the given owner', () async {
      await createRoute(id: 'r1', owner: 'a');
      await createRoute(id: 'r2', owner: 'b');
      await db.markRouteSyncing(ownerId: 'a', routeId: 'r1');
      await db.markRouteSyncing(ownerId: 'b', routeId: 'r2');

      await db.normalizeStaleSyncingRoutes(ownerId: 'a');

      expect((await db.getRecordedRoute(ownerId: 'a', id: 'r1'))!.syncStatus,
          RouteSyncStatus.notSynced);
      expect((await db.getRecordedRoute(ownerId: 'b', id: 'r2'))!.syncStatus,
          RouteSyncStatus.syncing);
    });
  });

  group('getRoutesNeedingAutoSync', () {
    test('includes a notSynced route', () async {
      await createRoute();
      final routes = await db.getRoutesNeedingAutoSync(ownerId: 'me');
      expect(routes.map((r) => r.id), ['r1']);
    });

    test('excludes a discarded route', () async {
      await createRoute();
      await db.discardRecording(
          ownerId: 'me',
          routeId: 'r1',
          occurredAt: DateTime.utc(2026, 1, 1, 11));
      final routes = await db.getRoutesNeedingAutoSync(ownerId: 'me');
      expect(routes, isEmpty);
    });

    test('excludes an already-synced route', () async {
      await createRoute();
      await db.recordRouteSyncOutcome(
          ownerId: 'me', routeId: 'r1', syncStatus: RouteSyncStatus.synced);
      final routes = await db.getRoutesNeedingAutoSync(ownerId: 'me');
      expect(routes, isEmpty);
    });

    test(
        'excludes a failed route -- automatic passes never retry a terminal '
        'failure; only an explicit retry may', () async {
      await createRoute();
      await db.recordRouteSyncOutcome(
        ownerId: 'me',
        routeId: 'r1',
        syncStatus: RouteSyncStatus.failed,
        lastSyncError: 'terminal',
      );
      final routes = await db.getRoutesNeedingAutoSync(ownerId: 'me');
      expect(routes, isEmpty);
    });

    test('excludes a syncing route (caller is expected to normalize first)',
        () async {
      await createRoute();
      await db.markRouteSyncing(ownerId: 'me', routeId: 'r1');
      final routes = await db.getRoutesNeedingAutoSync(ownerId: 'me');
      expect(routes, isEmpty);
    });
  });
}
