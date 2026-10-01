import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_details.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

typedef _P = ({int sec, double lat, double? alt, double? speed});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime at(int sec) => t0.add(Duration(seconds: sec));
  late GpsLocalDatabase db;

  setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> journey(
    String id, {
    String owner = 'me',
    List<_P> points = const [],
    List<({String type, int sec})> pauses = const [],
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
        recordedAt: at(p.sec),
      );
    }
    for (final e in pauses) {
      if (e.type == 'pause') {
        await db.pauseRecording(
            ownerId: owner, routeId: id, occurredAt: at(e.sec));
      } else {
        await db.resumeRecording(
            ownerId: owner, routeId: id, occurredAt: at(e.sec));
      }
    }
    if (discard) {
      await db.discardRecording(
          ownerId: owner, routeId: id, occurredAt: at(600));
    } else if (finishSec != null) {
      await db.finishRecordingLocally(
          ownerId: owner, routeId: id, occurredAt: at(finishSec));
    }
  }

  Future<void> moment(String id, int sec,
      {String route = 'r1', String owner = 'me', String? title, String? note}) {
    return db.addWaypoint(
      id: id,
      ownerId: owner,
      recordedRouteId: route,
      waypointType: 'viewpoint',
      title: title,
      note: note,
      latitude: 50.0005,
      longitude: 30.0,
      recordedAt: at(sec),
    );
  }

  Future<GpsJourneyDetails?> load({String id = 'r1', String owner = 'me'}) =>
      loadGpsJourneyDetails(db: db, ownerId: owner, routeId: id, now: t0);

  const List<_P> walk = [
    (sec: 0, lat: 50.000, alt: 100.0, speed: 1.5),
    (sec: 60, lat: 50.001, alt: 110.0, speed: 3.0),
    (sec: 120, lat: 50.002, alt: 105.0, speed: 2.0),
  ];

  group('Details loading', () {
    test('D01/D06 a completed Journey loads with its route identity', () async {
      await journey('r1', points: walk);
      final d = (await load())!;

      expect(d.route.id, 'r1');
      expect(d.route.ownerId, 'me');
      expect(d.route.status, RecordedRouteStatus.completed);
    });

    test('D02/D03/D04 recording, paused and discarded are rejected', () async {
      await journey('rec', owner: 'o1', finishSec: null);
      await journey('pau', owner: 'o2', finishSec: null);
      await db.pauseRecording(ownerId: 'o2', routeId: 'pau', occurredAt: at(5));
      await journey('dis', owner: 'o3', discard: true);

      expect(await load(id: 'rec', owner: 'o1'), isNull);
      expect(await load(id: 'pau', owner: 'o2'), isNull);
      expect(await load(id: 'dis', owner: 'o3'), isNull);
    });

    test('D05/D22 owner isolation; unknown route is safely null', () async {
      await journey('r1', points: walk);

      expect(await load(owner: 'intruder'), isNull);
      expect(await load(id: 'missing'), isNull);
    });

    test('D07 points come back in canonical seq order, unmodified', () async {
      await journey('r1', points: walk);
      final d = (await load())!;

      expect(d.points.map((p) => p.seq), [1, 2, 3]);
      expect(d.points.map((p) => p.latitude), [50.000, 50.001, 50.002]);
      expect(d.points.map((p) => p.recordedAt), [at(0), at(60), at(120)]);
    });

    test('D08/D28/D29 zero points: safe, no altitude or pace', () async {
      await journey('r1');
      final d = (await load())!;

      expect(d.points, isEmpty);
      expect(d.statistics.totalDistanceMeters, 0);
      expect(d.statistics.elevationGainMeters, 0);
      expect(d.statistics.paceSecondsPerKilometer, isNull);
      expect(d.timeline.map((e) => e.kind), [
        GpsTimelineEntryKind.started,
        GpsTimelineEntryKind.finished,
      ]);
    });

    test('D09 statistics equal the canonical Phase 0 engine', () async {
      await journey('r1', points: walk, pauses: const [
        (type: 'pause', sec: 120),
        (type: 'resume', sec: 240),
      ]);
      final d = (await load())!;
      final direct = calculateGpsJourneyStatistics(
        points: await db.getRoutePoints(ownerId: 'me', recordedRouteId: 'r1'),
        events: await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1'),
        now: t0,
      );

      expect(d.statistics.totalDistanceMeters, direct.totalDistanceMeters);
      expect(d.statistics.moving, direct.moving);
      expect(d.statistics.paused, const Duration(minutes: 2));
      expect(d.statistics.maxSpeedMps, 3.0);
      expect(d.statistics.elevationGainMeters, closeTo(10, 1e-9));
    });

    test('D10/D26 Moment count excludes tombstones; zero Moments is empty',
        () async {
      await journey('r1');
      expect((await load())!.moments, isEmpty);

      await moment('m1', 30);
      await moment('m2', 40);
      await moment('m3', 50);
      await db.deleteWaypoint(ownerId: 'me', recordedRouteId: 'r1', id: 'm3');

      final d = (await load())!;
      expect(d.moments.map((m) => m.id), ['m1', 'm2']);
      expect(d.timeline.where((e) => e.kind == GpsTimelineEntryKind.moment),
          hasLength(2));
    });
  });

  group('Timeline', () {
    test('D11-D16 start, pause, resume, Moment and finish in time order',
        () async {
      await journey('r1', pauses: const [
        (type: 'pause', sec: 100),
        (type: 'resume', sec: 200),
      ]);
      await moment('m', 150, title: 'Привал');

      final t = (await load())!.timeline;

      expect(t.map((e) => e.kind), [
        GpsTimelineEntryKind.started,
        GpsTimelineEntryKind.paused,
        GpsTimelineEntryKind.moment,
        GpsTimelineEntryKind.resumed,
        GpsTimelineEntryKind.finished,
      ]);
      expect(t.map((e) => e.timestamp),
          [at(0), at(100), at(150), at(200), at(600)]);
      expect(t[2].moment!.title, 'Привал');
      expect(t.map((e) => e.id).toSet(), hasLength(t.length));
      expect(t.first.id, startsWith('event_'));
      expect(t[2].id, 'moment_m');
    });

    test('D19/D27 no pause or resume entries are fabricated', () async {
      await journey('r1', points: walk);
      final kinds = (await load())!.timeline.map((e) => e.kind).toList();

      expect(kinds, [
        GpsTimelineEntryKind.started,
        GpsTimelineEntryKind.finished,
      ]);
    });

    test('D18 several Moments order by time regardless of insertion order',
        () async {
      await journey('r1');
      await moment('c', 300);
      await moment('a', 100);
      await moment('b', 200);

      final ids = (await load())!
          .timeline
          .where((e) => e.kind == GpsTimelineEntryKind.moment)
          .map((e) => e.moment!.id)
          .toList();

      expect(ids, ['a', 'b', 'c']);
    });

    test('D17 equal timestamps order deterministically', () async {
      // Everything at the same instant: start < pause/resume (by seq) <
      // Moments (by id) < finish, whatever the insertion order.
      await db.createLocalRecordedRoute(id: 'r1', ownerId: 'me', startedAt: t0);
      await db.pauseRecording(ownerId: 'me', routeId: 'r1', occurredAt: t0);
      await db.resumeRecording(ownerId: 'me', routeId: 'r1', occurredAt: t0);
      await moment('z', 0);
      await moment('a', 0);
      await db.finishRecordingLocally(
          ownerId: 'me', routeId: 'r1', occurredAt: t0);

      final labels = (await load())!
          .timeline
          .map((e) => e.moment?.id ?? e.kind.name)
          .toList();

      expect(labels, ['started', 'paused', 'resumed', 'a', 'z', 'finished']);
      expect((await load())!.timeline.map((e) => e.id).toList(),
          (await load())!.timeline.map((e) => e.id).toList(),
          reason: 'stable across loads');
    });

    test('the builder is independent of input order', () async {
      await journey('r1', pauses: const [
        (type: 'pause', sec: 10),
        (type: 'resume', sec: 20),
      ]);
      await moment('m1', 15);
      final events =
          await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1');
      final moments =
          await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1');

      final forward = buildGpsJourneyTimeline(events: events, moments: moments);
      final reversed = buildGpsJourneyTimeline(
          events: events.reversed.toList(), moments: moments.reversed.toList());

      expect(reversed.map((e) => e.id), forward.map((e) => e.id));
    });

    test('D20 Moment entries expose persisted telemetry unchanged', () async {
      await journey('r1');
      await moment('m', 30, title: 'T', note: 'N');
      final entry = (await load())!
          .timeline
          .firstWhere((e) => e.kind == GpsTimelineEntryKind.moment);

      expect(entry.moment!.latitude, 50.0005);
      expect(entry.moment!.longitude, 30.0);
      expect(entry.moment!.recordedAt, at(30));
      expect(entry.moment!.note, 'N');
      expect(entry.timestamp, entry.moment!.recordedAt);
    });
  });

  group('Boundaries', () {
    test('D34/D35 a new controller/provider layer still opens the Journey',
        () async {
      final source = FakeLocationSource()
        ..permission = LocationPermission.whileInUse;
      addTearDown(source.dispose);
      final first = GpsRecordingController(
        ownerId: 'me',
        db: db,
        locationSource: source,
        notificationPermissionSource: FakeNotificationPermissionSource(),
      );
      await first.start();
      await pumpEventQueue();
      final routeId = first.state.routeId!;
      await first.finish();
      first.dismissCompleted();
      first.dispose();

      final second = GpsRecordingController(
        ownerId: 'me',
        db: db,
        locationSource: source,
        notificationPermissionSource: FakeNotificationPermissionSource(),
      );
      addTearDown(second.dispose);
      await pumpEventQueue();

      expect((await load(id: routeId))!.route.id, routeId);
      expect(second.state.status, GpsRecordingStatus.idle);
      expect(await db.getRecoverableRecording('me'), isNull);
    });

    test('D38 loading Details never weakens the completed-route guard',
        () async {
      await journey('r1', points: walk);
      await load();

      final appended = await db.appendRoutePoint(
          ownerId: 'me',
          recordedRouteId: 'r1',
          latitude: 1,
          longitude: 1,
          recordedAt: at(900));

      expect(appended, isFalse);
      expect((await load())!.points, hasLength(3));
    });

    test(
        'D36/D33/D09 Details sources have no network, recording or formula '
        'dependencies', () {
      const files = [
        'lib/features/gps/recording/gps_journey_details.dart',
        'lib/features/gps/presentation/gps_journey_details_view.dart',
      ];
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final imports = source
            .split('\n')
            .where((l) => l.startsWith('import '))
            .join('\n')
            .toLowerCase();
        for (final banned in [
          'supabase',
          'sync/',
          'http',
          'connectivity',
          'gps_recording_controller',
          'location_source',
        ]) {
          expect(imports, isNot(contains(banned)), reason: path);
        }
        expect(source, isNot(contains('distanceBetween')), reason: path);
        expect(source, isNot(contains('appendRoutePoint')), reason: path);
        expect(source, isNot(contains('updateWaypoint')), reason: path);
        expect(source, isNot(contains('deleteWaypoint')), reason: path);
      }
    });
  });
}
