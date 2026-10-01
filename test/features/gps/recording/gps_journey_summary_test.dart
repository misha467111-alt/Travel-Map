import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_summary_view.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_summary.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

import '../local/flaky_finish_db.dart';
import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

typedef _P = ({int sec, double lat, double? alt, double? speed});
typedef _E = ({String type, int sec});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 1, 1, 10);
  late GpsLocalDatabase db;

  setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seed({
    String id = 'r1',
    String owner = 'me',
    List<_P> points = const [],
    List<_E> pauseEvents = const [],
    int? finishSec = 600,
    bool discard = false,
  }) async {
    await db.createLocalRecordedRoute(id: id, ownerId: owner, startedAt: t0);
    for (final p in points) {
      await db.appendRoutePoint(
        ownerId: owner,
        recordedRouteId: id,
        latitude: p.lat,
        longitude: 30.0,
        altitude: p.alt,
        speed: p.speed,
        recordedAt: t0.add(Duration(seconds: p.sec)),
      );
    }
    for (final e in pauseEvents) {
      final at = t0.add(Duration(seconds: e.sec));
      if (e.type == 'pause') {
        await db.pauseRecording(ownerId: owner, routeId: id, occurredAt: at);
      } else {
        await db.resumeRecording(ownerId: owner, routeId: id, occurredAt: at);
      }
    }
    if (discard) {
      await db.discardRecording(
          ownerId: owner,
          routeId: id,
          occurredAt: t0.add(const Duration(seconds: 600)));
    } else if (finishSec != null) {
      await db.finishRecordingLocally(
          ownerId: owner,
          routeId: id,
          occurredAt: t0.add(Duration(seconds: finishSec)));
    }
  }

  Future<GpsJourneySummary?> load({String id = 'r1', String owner = 'me'}) =>
      loadGpsJourneySummary(db: db, ownerId: owner, routeId: id, now: t0);

  const List<_P> walk = [
    (sec: 0, lat: 50.000, alt: 100.0, speed: 1.5),
    (sec: 60, lat: 50.001, alt: 110.0, speed: 3.0),
    (sec: 120, lat: 50.002, alt: 105.0, speed: 2.0),
  ];

  group('Summary statistics come from persisted data via Phase 0', () {
    test('E08/E09/E10 matches the canonical engine over persisted rows',
        () async {
      await seed(points: walk);
      final summary = (await load())!;
      final direct = calculateGpsJourneyStatistics(
        points: await db.getRoutePoints(ownerId: 'me', recordedRouteId: 'r1'),
        events: await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1'),
        now: t0,
      );

      expect(
          summary.statistics.totalDistanceMeters, direct.totalDistanceMeters);
      expect(summary.statistics.totalDistanceMeters, closeTo(222, 3));
      expect(summary.statistics.elapsed, const Duration(minutes: 10));
      expect(summary.pointCount, 3);
    });

    test('E11/E12/E13 moving, paused and average speed', () async {
      await seed(points: walk, pauseEvents: const [
        (type: 'pause', sec: 120),
        (type: 'resume', sec: 240),
      ]);
      final s = (await load())!.statistics;

      expect(s.paused, const Duration(minutes: 2));
      expect(s.moving, const Duration(minutes: 8));
      expect(s.averageSpeedMps, closeTo(s.totalDistanceMeters / 480, 1e-9));
    });

    test('E14/E15/E16 max speed and elevation gain/loss', () async {
      await seed(points: walk);
      final s = (await load())!.statistics;

      expect(s.maxSpeedMps, 3.0);
      expect(s.elevationGainMeters, closeTo(10, 1e-9));
      expect(s.elevationLossMeters, closeTo(5, 1e-9));
    });

    test('E17 pace is valid when distance and moving time exist', () async {
      await seed(points: walk);
      final s = (await load())!.statistics;

      expect(s.paceSecondsPerKilometer,
          closeTo(600 / (s.totalDistanceMeters / 1000), 1e-6));
    });

    test('E18/E19 Moment count excludes tombstones; zero Moments is 0',
        () async {
      await seed();
      expect((await load())!.momentCount, 0);

      for (final id in ['m1', 'm2', 'm3']) {
        await db.addWaypoint(
          id: id,
          ownerId: 'me',
          recordedRouteId: 'r1',
          waypointType: 'custom',
          latitude: 50,
          longitude: 30,
          recordedAt: t0,
        );
      }
      expect((await load())!.momentCount, 3);
      await db.deleteWaypoint(ownerId: 'me', recordedRouteId: 'r1', id: 'm3');
      expect((await load())!.momentCount, 2);
    });
  });

  group('Edge cases never crash or yield NaN/Infinity', () {
    String render(GpsJourneyStatistics s) => [
          formatGpsDistance(s.totalDistanceMeters),
          formatGpsDuration(s.elapsed),
          formatGpsDuration(s.moving),
          formatGpsDuration(s.paused),
          formatGpsSpeed(s.averageSpeedMps),
          formatGpsSpeed(s.maxSpeedMps),
          formatGpsElevation(s.elevationGainMeters),
          formatGpsElevation(s.elevationLossMeters),
          formatGpsPace(s.paceSecondsPerKilometer),
        ].join('|');

    void expectClean(String rendered) {
      expect(rendered, isNot(contains('NaN')));
      expect(rendered, isNot(contains('Infinity')));
    }

    test('E20 zero points', () async {
      await seed();
      final s = (await load())!.statistics;

      expect(s.totalDistanceMeters, 0);
      expect(s.maxSpeedMps, isNull);
      expect(s.paceSecondsPerKilometer, isNull);
      expect(formatGpsPace(s.paceSecondsPerKilometer), '—');
      expectClean(render(s));
    });

    test('E21 one point', () async {
      await seed(points: const [(sec: 0, lat: 50.0, alt: 100.0, speed: 1.0)]);
      final summary = (await load())!;

      expect(summary.pointCount, 1);
      expect(summary.statistics.totalDistanceMeters, 0);
      expect(summary.statistics.elevationGainMeters, 0);
      expectClean(render(summary.statistics));
    });

    test('E22 zero distance (identical points) has no pace', () async {
      await seed(points: const [
        (sec: 0, lat: 50.0, alt: null, speed: 0.0),
        (sec: 60, lat: 50.0, alt: null, speed: 0.0),
      ]);
      final s = (await load())!.statistics;

      expect(s.totalDistanceMeters, 0);
      expect(s.paceSecondsPerKilometer, isNull);
      expect(formatGpsDistance(0), '0 м');
      expectClean(render(s));
    });

    test('E23 all-paused journey has zero moving time and no average speed',
        () async {
      await seed(points: walk, pauseEvents: const [(type: 'pause', sec: 0)]);
      final s = (await load())!.statistics;

      expect(s.moving, Duration.zero);
      expect(s.paused, const Duration(minutes: 10));
      expect(s.averageSpeedMps, isNull);
      expect(s.paceSecondsPerKilometer, isNull);
      expectClean(render(s));
    });

    test('E24 null altitude and speed leave optional metrics unavailable',
        () async {
      await seed(points: const [
        (sec: 0, lat: 50.000, alt: null, speed: null),
        (sec: 60, lat: 50.001, alt: null, speed: null),
      ]);
      final s = (await load())!.statistics;

      expect(s.maxSpeedMps, isNull);
      expect(formatGpsSpeed(s.maxSpeedMps), '—');
      expect(s.elevationGainMeters, 0);
      expect(s.totalDistanceMeters, greaterThan(0));
    });

    test('E25 formatters map non-finite input to a dash, never NaN/Infinity',
        () {
      expect(formatGpsDistance(double.nan), '—');
      expect(formatGpsDistance(double.infinity), '—');
      expect(formatGpsSpeed(double.nan), '—');
      expect(formatGpsSpeed(double.infinity), '—');
      expect(formatGpsSpeed(null), '—');
      expect(formatGpsElevation(double.nan), '—');
      expect(formatGpsPace(double.infinity), '—');
      expect(formatGpsPace(0), '—');
      expect(formatGpsDuration(const Duration(seconds: -5)), '0 с');
    });

    test('formatters produce expected human values', () {
      expect(formatGpsDistance(222.4), '222 м');
      expect(formatGpsDistance(12345), '12.35 км');
      expect(formatGpsDuration(const Duration(seconds: 3725)), '1 год 2 хв');
      expect(formatGpsDuration(const Duration(seconds: 125)), '2 хв 5 с');
      expect(formatGpsSpeed(2.0), '7.2 км/год');
      expect(formatGpsPace(375), '6:15 /км');
    });
  });

  group('Summary boundaries (E26/E27/E33)', () {
    test('E26/E27 loads from the local database alone, no network seam',
        () async {
      // loadGpsJourneySummary's only dependency is GpsLocalDatabase: no
      // repository, Supabase client or connectivity object is accepted.
      await seed(points: walk);
      expect(await load(), isNotNull);
    });

    test('E27 Summary sources import no network/sync/Supabase code', () {
      const files = [
        'lib/features/gps/recording/gps_journey_summary.dart',
        'lib/features/gps/presentation/gps_journey_summary_view.dart',
        'lib/features/gps/presentation/gps_finish_confirmation.dart',
      ];
      for (final path in files) {
        final imports = File(path)
            .readAsLinesSync()
            .where((l) => l.startsWith('import '))
            .join('\n')
            .toLowerCase();
        for (final banned in ['supabase', 'sync/', 'http', 'connectivity']) {
          expect(imports, isNot(contains(banned)),
              reason: '$path must stay local-only');
        }
      }
    });

    test('completed routes are immutable; other routes/owners are unaffected',
        () async {
      await seed(id: 'done', points: walk);
      await db.createLocalRecordedRoute(
          id: 'live', ownerId: 'other', startedAt: t0);

      Future<bool> append(String owner, String route) => db.appendRoutePoint(
          ownerId: owner,
          recordedRouteId: route,
          latitude: 51,
          longitude: 30,
          recordedAt: t0.add(const Duration(hours: 1)));

      expect(await append('me', 'done'), isFalse);
      expect(await db.getRoutePoints(ownerId: 'me', recordedRouteId: 'done'),
          hasLength(3));
      expect(await append('other', 'live'), isTrue,
          reason: 'an active route of another owner still records');
      await db.pauseRecording(
          ownerId: 'other', routeId: 'live', occurredAt: t0);
      expect(await append('other', 'live'), isTrue,
          reason: 'paused routes are not blocked by this guard');
      expect(await db.getRoutePoints(ownerId: 'other', recordedRouteId: 'live'),
          hasLength(2));
    });

    test('E33 owner and route isolation', () async {
      await seed(points: walk);
      await seed(id: 'r2', owner: 'other', points: const [
        (sec: 0, lat: 10.0, alt: null, speed: null),
      ]);

      expect(await load(owner: 'other'), isNull,
          reason: 'another owner never sees this route');
      expect((await load())!.pointCount, 3);
      expect((await load(id: 'r2', owner: 'other'))!.pointCount, 1);
      expect(await load(id: 'r2'), isNull);
    });

    test('E07 discarded and still-active routes yield no Summary', () async {
      await seed(discard: true);
      expect(await load(), isNull);

      await seed(id: 'r3', owner: 'o2', finishSec: null);
      expect(await load(id: 'r3', owner: 'o2'), isNull);
    });

    test('E32 completed route keeps existing sync eligibility', () async {
      await seed(points: walk);
      final eligible = await db.getRoutesNeedingAutoSync(ownerId: 'me');

      expect(eligible.map((r) => r.id), contains('r1'));
      final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
      expect(route!.status, RecordedRouteStatus.completed);
      expect(route.syncStatus, RouteSyncStatus.notSynced);
    });
  });

  group('Finish lifecycle through the controller', () {
    late FlakyFinishDb fdb;
    late FakeLocationSource source;
    late GpsRecordingController controller;

    setUp(() {
      fdb = FlakyFinishDb(NativeDatabase.memory());
      source = FakeLocationSource()..permission = LocationPermission.whileInUse;
      controller = GpsRecordingController(
        ownerId: 'me',
        db: fdb,
        locationSource: source,
        notificationPermissionSource: FakeNotificationPermissionSource(),
      );
    });

    tearDown(() async {
      controller.dispose();
      await fdb.close();
      await source.dispose();
    });

    Future<void> settle() => pumpEventQueue();

    test('E03/E04 confirmed finish completes the Journey and stops recording',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      source.emitPosition(testPosition());
      await settle();

      expect(await controller.finish(), isTrue);

      expect(controller.state.status, GpsRecordingStatus.completed);
      expect(source.activeSubscriptionCount, 0);
      final summary = await loadGpsJourneySummary(
          db: fdb, ownerId: 'me', routeId: routeId, now: DateTime.now());
      expect(summary, isNotNull);
      expect(summary!.pointCount, 1);
    });

    test('E05 finish while paused does not resume and counts trailing pause',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      await controller.pause();
      await settle();

      expect(await controller.finish(), isTrue);

      final events =
          await fdb.getRouteEvents(ownerId: 'me', recordedRouteId: routeId);
      expect(events.map((e) => e.eventType), [
        RouteEventType.start,
        RouteEventType.pause,
        RouteEventType.finish,
      ]);
      expect(source.activeSubscriptionCount, 0);
      final s = (await loadGpsJourneySummary(
              db: fdb, ownerId: 'me', routeId: routeId, now: DateTime.now()))!
          .statistics;
      expect(s.paused + s.moving, s.elapsed);
    });

    test('E06/E34 a completed Journey is not recoverable after restart',
        () async {
      await controller.start();
      await settle();
      await controller.finish();
      await settle();

      expect(await fdb.getRecoverableRecording('me'), isNull);
      final restarted = GpsRecordingController(
        ownerId: 'me',
        db: fdb,
        locationSource: source,
        notificationPermissionSource: FakeNotificationPermissionSource(),
      );
      addTearDown(restarted.dispose);
      await settle();

      expect(restarted.state.status, GpsRecordingStatus.idle);
    });

    test('E07 discard returns to idle and never completes the Journey',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      await controller.discard();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.idle);
      expect(
          await loadGpsJourneySummary(
              db: fdb, ownerId: 'me', routeId: routeId, now: DateTime.now()),
          isNull);
    });

    test('E28 failed finalization keeps the Journey active and recording',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      fdb.failFinish = true;

      expect(await controller.finish(), isFalse);
      await settle();

      expect(controller.state.status, GpsRecordingStatus.recording);
      expect(source.activeSubscriptionCount, 1,
          reason: 'sampling resumes so no data is silently lost');
      final route = await fdb.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route!.status, RecordedRouteStatus.recording);
      source.emitPosition(testPosition());
      await settle();
      expect(await fdb.getRoutePoints(ownerId: 'me', recordedRouteId: routeId),
          hasLength(1));

      fdb.failFinish = false;
      expect(await controller.finish(), isTrue);
      expect(controller.state.status, GpsRecordingStatus.completed);
    });

    test('E28 failed finish while paused stays paused', () async {
      await controller.start();
      await settle();
      await controller.pause();
      fdb.failFinish = true;

      expect(await controller.finish(), isFalse);

      expect(controller.state.status, GpsRecordingStatus.paused);
      expect(source.activeSubscriptionCount, 0);
    });

    test('failed finish of a recoverable Journey keeps it recoverable',
        () async {
      await fdb.createLocalRecordedRoute(
          id: 'rec1', ownerId: 'me', startedAt: t0);
      final recovered = GpsRecordingController(
        ownerId: 'me',
        db: fdb,
        locationSource: source,
        notificationPermissionSource: FakeNotificationPermissionSource(),
      );
      addTearDown(recovered.dispose);
      await settle();
      expect(recovered.state.status, GpsRecordingStatus.recoverable);
      final emitted = <GpsRecordingStatus>[];
      final sub = recovered.stateStream.listen((s) => emitted.add(s.status));
      addTearDown(sub.cancel);

      fdb.failFinish = true;
      expect(await recovered.finishRecoverableRecording(), isFalse);
      await settle();

      expect(recovered.state.status, GpsRecordingStatus.recoverable);
      expect(emitted, isNot(contains(GpsRecordingStatus.completed)));
      final route = await fdb.getRecordedRoute(ownerId: 'me', id: 'rec1');
      expect(route!.status, RecordedRouteStatus.recording);
      expect(
          await loadGpsJourneySummary(
              db: fdb, ownerId: 'me', routeId: 'rec1', now: t0),
          isNull,
          reason: 'no Summary for an uncompleted route');
      expect(source.activeSubscriptionCount, 0);

      fdb.failFinish = false;
      expect(await recovered.finishRecoverableRecording(), isTrue,
          reason: 'retry remains possible');
      expect(recovered.state.status, GpsRecordingStatus.completed);
    });

    test('a failed finish never leaves two position subscriptions', () async {
      await controller.start();
      await settle();
      fdb.failFinish = true;

      for (var i = 0; i < 3; i++) {
        expect(await controller.finish(), isFalse);
        await settle();
        expect(source.activeSubscriptionCount, 1);
      }
      expect(controller.state.status, GpsRecordingStatus.recording);
    });

    test('dismissCompleted preserves the completed route and sync eligibility',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      source.emitPosition(testPosition());
      await settle();
      await controller.finish();
      controller.dismissCompleted();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.idle);
      final route = await fdb.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route!.status, RecordedRouteStatus.completed);
      expect(route.syncStatus, RouteSyncStatus.notSynced);
      expect(
          (await fdb.getRoutesNeedingAutoSync(ownerId: 'me')).map((r) => r.id),
          contains(routeId));
      expect(await fdb.getRecoverableRecording('me'), isNull);
      expect(await fdb.getRoutePoints(ownerId: 'me', recordedRouteId: routeId),
          hasLength(1));
      expect(source.activeSubscriptionCount, 0);
    });

    test(
        'RACE a point in flight when Finish begins is never written after '
        'completion', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      source.emitPosition(testPosition(latitude: 50.1));
      await settle();
      expect(controller.state.pointCount, 1, reason: 'normal append works');

      // Second sample: accepted by the controller, its write is held open.
      final gate = fdb.appendGate = Completer<void>();
      source.emitPosition(testPosition(latitude: 50.2));
      await settle();

      expect(await controller.finish(), isTrue);
      expect(controller.state.status, GpsRecordingStatus.completed);
      expect((await fdb.getRecordedRoute(ownerId: 'me', id: routeId))!.status,
          RecordedRouteStatus.completed);

      // The delayed write now proceeds against the completed route.
      fdb.appendGate = null;
      gate.complete();
      await settle();

      final points =
          await fdb.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, hasLength(1),
          reason: 'only the pre-finish point exists; the late one is rejected');
      expect(points.single.latitude, 50.1);
      expect(controller.state.pointCount, 1,
          reason: 'a rejected sample is not counted');
      expect(controller.state.status, GpsRecordingStatus.completed);
    });

    test('RACE a point in flight during a FAILED finish is still kept',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      final gate = fdb.appendGate = Completer<void>();
      source.emitPosition(testPosition());
      await settle();

      fdb.failFinish = true;
      expect(await controller.finish(), isFalse);
      expect(controller.state.status, GpsRecordingStatus.recording);
      fdb.appendGate = null;
      gate.complete();
      await settle();

      expect(await fdb.getRoutePoints(ownerId: 'me', recordedRouteId: routeId),
          hasLength(1),
          reason: 'route never completed, so the sample is legitimate');
      expect(controller.state.pointCount, 1);
      expect(source.activeSubscriptionCount, 1);

      fdb.failFinish = false;
      expect(await controller.finish(), isTrue, reason: 'retry works');
      expect(source.activeSubscriptionCount, 0);
    });

    test('a paused Journey stays paused until Finish completes it', () async {
      await controller.start();
      await settle();
      await controller.pause();
      source.emitPosition(testPosition());
      await settle();
      expect(controller.state.status, GpsRecordingStatus.paused);
      expect(source.activeSubscriptionCount, 0);

      expect(await controller.finish(), isTrue);
      expect(controller.state.status, GpsRecordingStatus.completed);
      expect(
          await fdb.getRoutePoints(
              ownerId: 'me', recordedRouteId: controller.state.routeId!),
          isEmpty);
    });

    test('E29 duplicate finish submissions finalize exactly once', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      final results = await Future.wait([
        controller.finish(),
        controller.finish(),
        controller.finish(),
      ]);

      expect(results.where((r) => r), hasLength(1));
      expect(fdb.finishCalls, 1);
      final events =
          await fdb.getRouteEvents(ownerId: 'me', recordedRouteId: routeId);
      expect(events.where((e) => e.eventType == RouteEventType.finish),
          hasLength(1));
    });

    test('E30/E31 no points or Moments after completion', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      await controller.finish();
      await settle();

      source.emitPosition(testPosition());
      await settle();

      expect(await fdb.getRoutePoints(ownerId: 'me', recordedRouteId: routeId),
          isEmpty);
      expect(await controller.addWaypoint(waypointType: 'custom'), isFalse);
      expect(await fdb.getWaypoints(ownerId: 'me', recordedRouteId: routeId),
          isEmpty);
    });

    test('dismissCompleted returns to idle only from completed', () async {
      await controller.start();
      await settle();
      controller.dismissCompleted();
      expect(controller.state.status, GpsRecordingStatus.recording);

      await controller.finish();
      controller.dismissCompleted();
      expect(controller.state.status, GpsRecordingStatus.idle);
    });
  });
}
