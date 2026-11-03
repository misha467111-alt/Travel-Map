import 'package:drift/drift.dart' show Value, Variable;
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

  // -------------------------------------------------------------------
  // Journey Phase 1H-E2B -- media sync DAO (D01-D05)
  // -------------------------------------------------------------------

  group('Journey media sync DAO', () {
    final t0 = DateTime.utc(2026, 1, 1, 10);

    Future<void> setMediaStatus(String id, String status) =>
        (db.update(db.localJourneyMedia)..where((t) => t.id.equals(id)))
            .write(LocalJourneyMediaCompanion(syncStatus: Value(status)));

    Future<String?> mediaStatus(String id) async =>
        (await (db.select(db.localJourneyMedia)..where((t) => t.id.equals(id)))
                .getSingleOrNull())
            ?.syncStatus;

    /// Creates a route, adds media in the given statuses while it is active,
    /// then moves the route to [routeStatus] with route sync [routeSync].
    Future<void> seedRoute(
      String routeId, {
      String owner = 'me',
      Map<String, String> media = const {},
      String routeStatus = RecordedRouteStatus.completed,
      String routeSync = RouteSyncStatus.synced,
    }) async {
      await db.createLocalRecordedRoute(
          id: routeId, ownerId: owner, startedAt: t0);
      for (final id in media.keys) {
        await db.insertJourneyMedia(
          id: id,
          ownerId: owner,
          recordedRouteId: routeId,
          capturedAt: t0,
          localRelativePath: 'journey_media/$routeId/$id.jpg',
        );
        if (media[id] != JourneyMediaSyncStatus.pending) {
          await setMediaStatus(id, media[id]!);
        }
      }
      if (routeStatus == RecordedRouteStatus.completed) {
        await db.finishRecordingLocally(
            ownerId: owner, routeId: routeId, occurredAt: t0);
      } else if (routeStatus == RecordedRouteStatus.discarded) {
        await db.discardRecording(
            ownerId: owner, routeId: routeId, occurredAt: t0);
      } else if (routeStatus == RecordedRouteStatus.paused) {
        await db.pauseRecording(
            ownerId: owner, routeId: routeId, occurredAt: t0);
      }
      await db.recordRouteSyncOutcome(
          ownerId: owner, routeId: routeId, syncStatus: routeSync);
    }

    test(
        'D01 actionable query returns only this owner\'s completed + synced '
        'routes that still have pending media', () async {
      await seedRoute('rA', media: {
        'a1': JourneyMediaSyncStatus.pending,
        'a2': JourneyMediaSyncStatus.synced,
      });
      await seedRoute('rB', media: {
        'b1': JourneyMediaSyncStatus.synced,
        'b2': JourneyMediaSyncStatus.failed,
        'b3': JourneyMediaSyncStatus.pendingDelete,
      });
      await seedRoute('rC',
          media: {'c1': JourneyMediaSyncStatus.pending},
          routeSync: RouteSyncStatus.notSynced);
      await seedRoute('rD',
          media: {'d1': JourneyMediaSyncStatus.pending},
          routeSync: RouteSyncStatus.failed);
      await seedRoute('rF',
          media: {'f1': JourneyMediaSyncStatus.pending},
          routeStatus: RecordedRouteStatus.discarded);
      await seedRoute('rG',
          owner: 'other', media: {'g1': JourneyMediaSyncStatus.pending});
      await seedRoute('rI', media: {'i1': JourneyMediaSyncStatus.pending});
      // Still active (paused) -- seeded last: one active route per owner.
      await seedRoute('rH',
          media: {'h1': JourneyMediaSyncStatus.pending},
          routeStatus: RecordedRouteStatus.paused);

      expect(
          await db.getRouteIdsWithActionableMedia(ownerId: 'me'), ['rA', 'rI']);
      expect(await db.getRouteIdsWithActionableMedia(ownerId: 'other'), ['rG']);
      expect(
          await db.getRouteIdsWithActionableMedia(ownerId: 'nobody'), isEmpty);

      // Once everything is uploaded, nothing is actionable any more.
      await db.markJourneyMediaSynced(
          ownerId: 'me', recordedRouteId: 'rA', id: 'a1');
      await db.markJourneyMediaFailed(
          ownerId: 'me', recordedRouteId: 'rI', id: 'i1');
      expect(await db.getRouteIdsWithActionableMedia(ownerId: 'me'), isEmpty);
    });

    test(
        'D02 EXPLAIN QUERY PLAN: the actionable query is served by '
        'local_journey_media_actionable_idx, never a media-history scan',
        () async {
      await seedRoute('rA', media: {
        'a1': JourneyMediaSyncStatus.pending,
        'a2': JourneyMediaSyncStatus.synced,
      });
      final plan = await db.customSelect(
        'EXPLAIN QUERY PLAN ${GpsLocalDatabase.actionableMediaRoutesSql}',
        variables: [Variable.withString('me')],
      ).get();
      final details = plan.map((r) => r.read<String>('detail')).toList();
      // ignore: avoid_print
      print('D02 query plan: $details');

      expect(
          details.any((d) => d.contains('local_journey_media_actionable_idx')),
          isTrue,
          reason: 'plan: $details');
      expect(
          details.any(
              (d) => RegExp(r'^SCAN (m|local_journey_media)\b').hasMatch(d)),
          isFalse,
          reason: 'the media table must never be full-scanned; plan: $details');
    });

    test(
        'D03 markJourneyMediaSynced is conditional on pending and still '
        'rejects a tombstone', () async {
      await seedRoute('rA', media: {
        'p': JourneyMediaSyncStatus.pending,
        's': JourneyMediaSyncStatus.synced,
        'f': JourneyMediaSyncStatus.failed,
        't': JourneyMediaSyncStatus.pendingDelete,
      });

      expect(
          await db.markJourneyMediaSynced(
              ownerId: 'me', recordedRouteId: 'rA', id: 'p'),
          isTrue);
      expect(await mediaStatus('p'), JourneyMediaSyncStatus.synced);
      expect(
          await db.markJourneyMediaSynced(
              ownerId: 'me', recordedRouteId: 'rA', id: 'p'),
          isFalse,
          reason: 'repeating the acknowledgement is a no-op');
      expect(
          await db.markJourneyMediaSynced(
              ownerId: 'me', recordedRouteId: 'rA', id: 'f'),
          isFalse);
      expect(await mediaStatus('f'), JourneyMediaSyncStatus.failed);
      expect(
          await db.markJourneyMediaSynced(
              ownerId: 'me', recordedRouteId: 'rA', id: 'missing'),
          isFalse);
      expect(
          await db.markJourneyMediaSynced(
              ownerId: 'other', recordedRouteId: 'rA', id: 's'),
          isFalse,
          reason: 'owner-scoped');
      await expectLater(
          db.markJourneyMediaSynced(
              ownerId: 'me', recordedRouteId: 'rA', id: 't'),
          throwsStateError);
      expect(await mediaStatus('t'), JourneyMediaSyncStatus.pendingDelete);
    });

    test('D04 markJourneyMediaFailed only ever moves a pending row', () async {
      await seedRoute('rA', media: {
        'p': JourneyMediaSyncStatus.pending,
        's': JourneyMediaSyncStatus.synced,
        't': JourneyMediaSyncStatus.pendingDelete,
      });

      expect(
          await db.markJourneyMediaFailed(
              ownerId: 'other', recordedRouteId: 'rA', id: 'p'),
          isFalse,
          reason: 'owner-scoped');
      expect(await mediaStatus('p'), JourneyMediaSyncStatus.pending);
      expect(
          await db.markJourneyMediaFailed(
              ownerId: 'me', recordedRouteId: 'rA', id: 'p'),
          isTrue);
      expect(await mediaStatus('p'), JourneyMediaSyncStatus.failed);
      for (final id in ['s', 't']) {
        expect(
            await db.markJourneyMediaFailed(
                ownerId: 'me', recordedRouteId: 'rA', id: id),
            isFalse);
      }
      expect(await mediaStatus('s'), JourneyMediaSyncStatus.synced);
      expect(await mediaStatus('t'), JourneyMediaSyncStatus.pendingDelete);
    });

    test(
        'D05 requeueFailedJourneyMedia is owner- and route-scoped and only '
        'touches failed rows', () async {
      await seedRoute('rA', media: {
        'a_failed': JourneyMediaSyncStatus.failed,
        'a_failed2': JourneyMediaSyncStatus.failed,
        'a_synced': JourneyMediaSyncStatus.synced,
        'a_tomb': JourneyMediaSyncStatus.pendingDelete,
      });
      await seedRoute('rB', media: {'b_failed': JourneyMediaSyncStatus.failed});
      await seedRoute('rO',
          owner: 'other', media: {'o_failed': JourneyMediaSyncStatus.failed});

      expect(
          await db.requeueFailedJourneyMedia(
              ownerId: 'other', recordedRouteId: 'rA'),
          0);
      expect(
          await db.requeueFailedJourneyMedia(
              ownerId: 'me', recordedRouteId: 'rA'),
          2);
      expect(await mediaStatus('a_failed'), JourneyMediaSyncStatus.pending);
      expect(await mediaStatus('a_failed2'), JourneyMediaSyncStatus.pending);
      expect(await mediaStatus('a_synced'), JourneyMediaSyncStatus.synced);
      expect(await mediaStatus('a_tomb'), JourneyMediaSyncStatus.pendingDelete);
      expect(await mediaStatus('b_failed'), JourneyMediaSyncStatus.failed);
      expect(await mediaStatus('o_failed'), JourneyMediaSyncStatus.failed);
    });
  });
}
