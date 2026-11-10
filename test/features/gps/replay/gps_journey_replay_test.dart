import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';

/// Journey Phase 1I-A -- the pure replay timeline. Every fixture is built
/// directly from the persisted data classes (the same approach as the
/// statistics tests); the loader test additionally runs the real Drift
/// readers on an in-memory database.
void main() {
  const owner = 'owner-1';
  const routeId = 'r1';
  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime s(num seconds) =>
      t0.add(Duration(microseconds: (seconds * 1000000).round()));
  Duration sec(num seconds) =>
      Duration(microseconds: (seconds * 1000000).round());
  final farFuture = s(100000);

  LocalRecordedRoute route(
          {String status = RecordedRouteStatus.completed,
          String ownerId = owner}) =>
      LocalRecordedRoute(
        id: routeId,
        ownerId: ownerId,
        transportMode: 'walking',
        status: status,
        visibility: 'private',
        startedAt: t0,
        createdAt: t0,
        updatedAt: t0,
        syncStatus: RouteSyncStatus.synced,
      );

  LocalRoutePoint pt(int seq, double lat, double lng, DateTime at,
          {String ownerId = owner, String route = routeId}) =>
      LocalRoutePoint(
        recordedRouteId: route,
        seq: seq,
        ownerId: ownerId,
        latitude: lat,
        longitude: lng,
        recordedAt: at,
      );

  LocalRouteEvent ev(int seq, String type, DateTime at,
          {String ownerId = owner, String route = routeId}) =>
      LocalRouteEvent(
        recordedRouteId: route,
        seq: seq,
        ownerId: ownerId,
        eventType: type,
        occurredAt: at,
      );

  LocalWaypoint moment(String id, DateTime at,
          {double lat = 50.0,
          double lng = 30.0,
          String ownerId = owner,
          String route = routeId,
          String syncStatus = WaypointSyncStatus.synced}) =>
      LocalWaypoint(
        id: id,
        recordedRouteId: route,
        ownerId: ownerId,
        waypointType: 'viewpoint',
        latitude: lat,
        longitude: lng,
        recordedAt: at,
        createdAt: at,
        updatedAt: at,
        syncStatus: syncStatus,
      );

  LocalJourneyMediaItem photo(String id, DateTime at,
          {String? waypointId,
          double? lat,
          double? lng,
          String ownerId = owner,
          String route = routeId,
          String syncStatus = JourneyMediaSyncStatus.synced}) =>
      LocalJourneyMediaItem(
        id: id,
        ownerId: ownerId,
        recordedRouteId: route,
        waypointId: waypointId,
        mediaType: JourneyMediaType.image,
        capturedAt: at,
        latitude: lat,
        longitude: lng,
        localRelativePath: 'journey_media/$route/$id.jpg',
        syncStatus: syncStatus,
        createdAt: at,
        updatedAt: at,
      );

  /// start@0 .. finish@[finishAt], optionally with pause/resume pairs.
  List<LocalRouteEvent> events(num finishAt,
      {List<(String, num)> between = const []}) {
    var seq = 1;
    return [
      ev(seq++, RouteEventType.start, s(0)),
      for (final (type, at) in between) ev(seq++, type, s(at)),
      ev(seq++, RouteEventType.finish, s(finishAt)),
    ];
  }

  GpsReplayTimeline build({
    List<LocalRoutePoint> points = const [],
    List<LocalRouteEvent>? eventLog,
    List<LocalWaypoint> moments = const [],
    List<LocalJourneyMediaItem> media = const [],
    LocalRecordedRoute? forRoute,
  }) =>
      GpsReplayTimeline.build(
        route: forRoute ?? route(),
        points: points,
        events: eventLog ?? events(100),
        moments: moments,
        media: media,
        now: farFuture,
      );

  group('time axis', () {
    test('T01 an empty route has a clock but no position', () {
      final tl = build(eventLog: events(60));

      expect(tl.elapsed, sec(60));
      expect(tl.activeDuration, sec(60));
      expect(tl.pausedDuration, Duration.zero);
      expect(tl.sampleCount, 0);
      expect(tl.markers, isEmpty);
      for (final t in [-5, 0, 30, 60, 999]) {
        final p = tl.positionAt(sec(t));
        expect(p.kind, GpsReplayPositionKind.unavailable);
        expect(p.hasCoordinates, isFalse);
        expect(p.recordedAt, isNull);
      }
      expect(tl.positionAt(sec(-5)).playbackTime, Duration.zero);
      expect(tl.positionAt(sec(999)).playbackTime, sec(60));
    });

    test('T02 clamping before the beginning and after the end', () {
      final tl = build(points: [
        pt(1, 50.0, 30.0, s(10)),
        pt(2, 50.001, 30.0, s(30)),
      ]);

      final before = tl.positionAt(sec(-100));
      expect(before.playbackTime, Duration.zero);
      expect(before.kind, GpsReplayPositionKind.leading);
      expect(before.latitude, 50.0);

      final after = tl.positionAt(sec(100000));
      expect(after.playbackTime, tl.activeDuration);
      expect(after.kind, GpsReplayPositionKind.held);
      expect(after.latitude, 50.001);
      expect(after.recordedAt, s(30));
    });

    test('T03 the canonical totals are exposed and consistent', () {
      final log = events(100, between: [
        (RouteEventType.pause, 20),
        (RouteEventType.resume, 50),
      ]);
      final canonical = calculateGpsJourneyStatistics(
          points: const [], events: log, now: farFuture);
      final tl = build(eventLog: log);

      expect(tl.elapsed, canonical.elapsed);
      expect(tl.pausedDuration, canonical.paused);
      expect(tl.activeDuration, canonical.moving);
      expect(tl.activeDuration, sec(70));
      expect(tl.elapsed - tl.pausedDuration, tl.activeDuration);
      expect(tl.isConsistentWithStatistics, isTrue);
      expect(tl.startedAt, s(0));
      expect(tl.finishedAt, s(100));
    });

    test('T04 pause: playback time stands still while the recording is paused',
        () {
      final tl = build(
          eventLog: events(100, between: [
        (RouteEventType.pause, 20),
        (RouteEventType.resume, 50),
      ]));

      expect(tl.playbackTimeAtRecordedTime(s(10)), sec(10));
      expect(tl.playbackTimeAtRecordedTime(s(20)), sec(20));
      expect(tl.playbackTimeAtRecordedTime(s(35)), sec(20));
      expect(tl.playbackTimeAtRecordedTime(s(50)), sec(20));
      expect(tl.playbackTimeAtRecordedTime(s(60)), sec(30));
      expect(tl.playbackTimeAtRecordedTime(s(100)), sec(70));
      // Outside the window: clamped.
      expect(tl.playbackTimeAtRecordedTime(s(-10)), Duration.zero);
      expect(tl.playbackTimeAtRecordedTime(s(500)), sec(70));
      // Inverse: the earliest recorded instant with that playback time.
      expect(tl.recordedTimeAtPlaybackTime(Duration.zero), s(0));
      expect(tl.recordedTimeAtPlaybackTime(sec(20)), s(20));
      expect(tl.recordedTimeAtPlaybackTime(sec(25)), s(55));
      expect(tl.recordedTimeAtPlaybackTime(sec(70)), s(100));
      expect(tl.recordedTimeAtPlaybackTime(sec(9999)), s(100));
      expect(tl.recordedTimeAtPlaybackTime(sec(-3)), s(0));
    });

    test('T05 multiple pauses', () {
      final tl = build(
          eventLog: events(60, between: [
        (RouteEventType.pause, 10),
        (RouteEventType.resume, 20),
        (RouteEventType.pause, 40),
        (RouteEventType.resume, 45),
      ]));

      expect(tl.pausedDuration, sec(15));
      expect(tl.activeDuration, sec(45));
      expect(tl.playbackTimeAtRecordedTime(s(5)), sec(5));
      expect(tl.playbackTimeAtRecordedTime(s(15)), sec(10));
      expect(tl.playbackTimeAtRecordedTime(s(30)), sec(20));
      expect(tl.playbackTimeAtRecordedTime(s(42)), sec(30));
      expect(tl.playbackTimeAtRecordedTime(s(50)), sec(35));
      expect(tl.playbackTimeAtRecordedTime(s(60)), sec(45));
      expect(tl.recordedTimeAtPlaybackTime(sec(10)), s(10));
      expect(tl.recordedTimeAtPlaybackTime(sec(30)), s(40));
      expect(tl.recordedTimeAtPlaybackTime(sec(33)), s(48));
    });

    test(
        'T06 unmatched / repeated pause and resume follow the canonical '
        'collapse rules', () {
      final log = events(60, between: [
        (RouteEventType.resume, 5), // resume with no pause: no-op
        (RouteEventType.pause, 10),
        (RouteEventType.pause, 12), // repeated pause: no-op
        (RouteEventType.resume, 30),
        (RouteEventType.resume, 35), // repeated resume: no-op
        (RouteEventType.pause, 50), // trailing pause, closed by the finish
      ]);
      final canonical = calculateGpsJourneyStatistics(
          points: const [], events: log, now: farFuture);
      final tl = build(eventLog: log);

      expect(canonical.paused, sec(30));
      expect(tl.pausedDuration, sec(30));
      expect(tl.activeDuration, sec(30));
      expect(tl.isConsistentWithStatistics, isTrue);
      expect(tl.playbackTimeAtRecordedTime(s(5)), sec(5));
      expect(tl.playbackTimeAtRecordedTime(s(10)), sec(10));
      expect(tl.playbackTimeAtRecordedTime(s(20)), sec(10));
      expect(tl.playbackTimeAtRecordedTime(s(30)), sec(10));
      expect(tl.playbackTimeAtRecordedTime(s(35)), sec(15));
      expect(tl.playbackTimeAtRecordedTime(s(50)), sec(30));
      expect(tl.playbackTimeAtRecordedTime(s(55)), sec(30));
      expect(tl.playbackTimeAtRecordedTime(s(60)), sec(30));
    });

    test(
        'T07 randomized event logs: the playback clock IS the canonical '
        'moving time at every probed instant', () {
      for (var seed = 0; seed < 60; seed++) {
        final random = Random(seed);
        var seq = 1;
        var clock = 0.0;
        final log = <LocalRouteEvent>[ev(seq++, RouteEventType.start, s(0))];
        final n = 1 + random.nextInt(14);
        for (var i = 0; i < n; i++) {
          // Zero gaps on purpose: equal timestamps are a real case.
          clock += random.nextInt(4) == 0 ? 0 : random.nextInt(31);
          log.add(ev(
              seq++,
              random.nextBool() ? RouteEventType.pause : RouteEventType.resume,
              s(clock)));
        }
        clock += random.nextInt(31);
        log.add(ev(seq++, RouteEventType.finish, s(clock)));

        final canonicalTotal = calculateGpsJourneyStatistics(
            points: const [], events: log, now: farFuture);
        final tl = build(eventLog: log);
        expect(tl.activeDuration, canonicalTotal.moving, reason: 'seed $seed');
        expect(tl.isConsistentWithStatistics, isTrue, reason: 'seed $seed');

        var previous = Duration.zero;
        final probes = [
          for (var i = 0; i < 40; i++)
            (random.nextDouble() * clock * 1000000).round()
        ]..sort();
        for (final micros in probes) {
          final at = s(0).add(Duration(microseconds: micros));
          final expected = calculateGpsJourneyStatistics(
            points: const [],
            events: [
              for (final e in log)
                if (!e.occurredAt.isAfter(at)) e
            ],
            now: at,
          ).moving;
          final actual = tl.playbackTimeAtRecordedTime(at);
          expect((actual - expected).inMicroseconds.abs(),
              lessThanOrEqualTo(GpsReplayTimeline.toleranceMicros),
              reason: 'seed $seed at ${at.difference(t0)}');
          expect(actual >= previous, isTrue, reason: 'monotone, seed $seed');
          previous = actual;
        }
      }
    });
  });

  group('position', () {
    test('T10 a single point: leading, exact, then held', () {
      final tl = build(points: [pt(1, 50.5, 30.5, s(30))]);

      final lead = tl.positionAt(sec(10));
      expect(lead.kind, GpsReplayPositionKind.leading);
      expect(lead.latitude, 50.5);
      expect(lead.recordedAt, s(30));

      final exact = tl.positionAt(sec(30));
      expect(exact.kind, GpsReplayPositionKind.exact);
      expect(exact.longitude, 30.5);

      final held = tl.positionAt(sec(80));
      expect(held.kind, GpsReplayPositionKind.held);
      expect(held.latitude, 50.5);
      expect(held.recordedAt, s(30));
    });

    test('T11 two points interpolate linearly in time', () {
      final tl = build(points: [
        pt(1, 50.0, 30.0, s(10)),
        pt(2, 50.001, 30.002, s(30)),
      ]);

      expect(tl.positionAt(sec(10)).kind, GpsReplayPositionKind.exact);
      expect(tl.positionAt(sec(30)).kind, GpsReplayPositionKind.exact);
      final mid = tl.positionAt(sec(20));
      expect(mid.kind, GpsReplayPositionKind.interpolated);
      expect(mid.latitude, closeTo(50.0005, 1e-12));
      expect(mid.longitude, closeTo(30.001, 1e-12));
      expect(mid.recordedAt, s(20));
      final quarter = tl.positionAt(sec(15));
      expect(quarter.latitude, closeTo(50.00025, 1e-12));
      expect(quarter.longitude, closeTo(30.0005, 1e-12));
    });

    test(
        'T12 duplicate timestamps: the later sample wins at that instant and '
        'a zero-length segment is never interpolated', () {
      final tl = build(points: [
        pt(1, 50.0000, 30.0, s(10)),
        pt(2, 50.0001, 30.0, s(20)),
        pt(3, 50.0002, 30.0, s(20)), // same instant as seq 2
        pt(4, 50.0003, 30.0, s(30)),
      ]);

      final at20 = tl.positionAt(sec(20));
      expect(at20.kind, GpsReplayPositionKind.exact);
      expect(at20.latitude, 50.0002);
      expect(tl.positionAt(sec(15)).latitude, closeTo(50.00005, 1e-12));
      expect(tl.positionAt(sec(25)).latitude, closeTo(50.00025, 1e-12));
      expect(tl.diagnostics.otherGapSegments, 1);
      expect(tl.sampleCount, 4);
    });

    test(
        'T13 out-of-order input follows the canonical contract: never '
        're-sorted, the late-stamped sample is dropped and breaks continuity',
        () {
      final tl = build(points: [
        pt(1, 50.0000, 30.0, s(10)),
        pt(2, 50.0002, 30.0, s(30)),
        pt(3, 50.0001, 30.0, s(20)), // earlier than seq 2
        pt(4, 50.0003, 30.0, s(40)),
      ]);

      expect(tl.sampleCount, 3);
      expect(tl.diagnostics.outOfOrderPoints, 1);
      expect(tl.positionAt(sec(20)).latitude, closeTo(50.0001, 1e-12),
          reason: 'seq 1 -> 2 is still continuous');
      final across = tl.positionAt(sec(35));
      expect(across.kind, GpsReplayPositionKind.held);
      expect(across.latitude, 50.0002, reason: 'not bridged over the drop');
      expect(tl.positionAt(sec(40)).kind, GpsReplayPositionKind.exact);
    });

    test(
        'T14 pause: nothing is simulated through it -- the last position is '
        'held until the next sample', () {
      final tl = build(
        eventLog: events(100, between: [
          (RouteEventType.pause, 20),
          (RouteEventType.resume, 50),
        ]),
        points: [
          pt(1, 50.0000, 30.0, s(10)),
          pt(2, 50.0001, 30.0, s(15)),
          // paused 20..50
          pt(3, 50.0050, 30.0, s(60)), // the user moved while paused
          pt(4, 50.0051, 30.0, s(70)),
        ],
      );

      expect(tl.activeDuration, sec(70));
      expect(tl.diagnostics.pauseGapSegments, 1);
      expect(tl.positionAt(sec(15)).kind, GpsReplayPositionKind.exact);
      final inGap = tl.positionAt(sec(25));
      expect(inGap.kind, GpsReplayPositionKind.held);
      expect(inGap.latitude, 50.0001);
      expect(inGap.recordedAt, s(15));
      // The pause level itself: still the last sample before the pause.
      expect(tl.positionAt(sec(20)).latitude, 50.0001);
      // The first sample after the pause appears exactly at its time.
      final after = tl.positionAt(sec(30));
      expect(after.kind, GpsReplayPositionKind.exact);
      expect(after.latitude, 50.0050);
      expect(tl.positionAt(sec(35)).latitude, closeTo(50.00505, 1e-12));
      expect(tl.positionAt(sec(35)).kind, GpsReplayPositionKind.interpolated);
    });

    test('T15 an impossible GPS jump is never bridged; just below it is', () {
      final jump = build(points: [
        pt(1, 50.0, 30.0, s(10)),
        pt(2, 51.0, 30.0, s(20)), // ~111 km in 10 s
        pt(3, 51.0001, 30.0, s(30)),
      ]);
      expect(jump.diagnostics.impossibleJumpSegments, 1);
      final mid = jump.positionAt(sec(15));
      expect(mid.kind, GpsReplayPositionKind.held);
      expect(mid.latitude, 50.0, reason: 'no plausible midpoint is invented');
      expect(jump.positionAt(sec(20)).latitude, 51.0);
      expect(jump.positionAt(sec(25)).kind, GpsReplayPositionKind.interpolated);

      // ~60 m/s is allowed; ~78 m/s is above gpsImpossibleJumpThresholdMps.
      expect(gpsImpossibleJumpThresholdMps, 70.0);
      final fast = build(points: [
        pt(1, 50.0, 30.0, s(10)),
        pt(2, 50.0054, 30.0, s(20)),
      ]);
      expect(fast.diagnostics.impossibleJumpSegments, 0);
      expect(fast.positionAt(sec(15)).kind, GpsReplayPositionKind.interpolated);
      final tooFast = build(points: [
        pt(1, 50.0, 30.0, s(10)),
        pt(2, 50.0070, 30.0, s(20)),
      ]);
      expect(tooFast.diagnostics.impossibleJumpSegments, 1);
      expect(tooFast.positionAt(sec(15)).kind, GpsReplayPositionKind.held);
    });

    test(
        'T16 invalid coordinates are dropped and the gap they leave is not '
        'bridged', () {
      final tl = build(points: [
        pt(1, 50.0000, 30.0, s(10)),
        pt(2, double.nan, 30.0, s(15)),
        pt(3, 91.0, 30.0, s(20)),
        pt(4, 50.0, double.infinity, s(25)),
        pt(5, 50.0, 181.0, s(30)),
        pt(6, 50.0010, 30.0, s(40)),
        pt(7, 50.0011, 30.0, s(50)),
      ]);

      expect(tl.diagnostics.invalidCoordinatePoints, 4);
      expect(tl.sampleCount, 3);
      final across = tl.positionAt(sec(25));
      expect(across.kind, GpsReplayPositionKind.held);
      expect(across.latitude, 50.0);
      expect(tl.positionAt(sec(40)).latitude, 50.0010);
      expect(tl.positionAt(sec(45)).kind, GpsReplayPositionKind.interpolated);
      for (var t = 0; t <= 100; t += 5) {
        final p = tl.positionAt(sec(t));
        expect(p.latitude!.isFinite && p.longitude!.isFinite, isTrue);
      }
    });

    test('T17 antimeridian crossing takes the short way round', () {
      final tl = build(points: [
        pt(1, 0.0, 179.999, s(10)),
        pt(2, 0.0, -179.999, s(30)),
      ]);

      expect(tl.diagnostics.discontinuousSegments, 0);
      final quarter = tl.positionAt(sec(15));
      expect(quarter.kind, GpsReplayPositionKind.interpolated);
      expect(quarter.longitude, closeTo(179.9995, 1e-9));
      final mid = tl.positionAt(sec(20));
      expect((mid.longitude!.abs() - 180).abs(), lessThan(1e-9));
      final threeQuarters = tl.positionAt(sec(25));
      expect(threeQuarters.longitude, closeTo(-179.9995, 1e-9));
      for (var t = 10.0; t <= 30; t += 0.5) {
        final lng = tl.positionAt(sec(t)).longitude!;
        expect(lng, inInclusiveRange(-180, 180));
      }
    });

    test('T18 lookups are deterministic and side-effect free', () {
      final points = [
        for (var i = 0; i < 200; i++)
          pt(i + 1, 50 + i * 0.00001, 30 + i * 0.00002, s(1 + i * 0.4)),
      ];
      final log = events(100, between: [
        (RouteEventType.pause, 30),
        (RouteEventType.resume, 40),
      ]);
      final a = build(points: points, eventLog: log);
      final b = build(points: points, eventLog: log);

      for (var i = 0; i <= 400; i++) {
        final t = sec(i * 0.19);
        final first = a.positionAt(t);
        final again = a.positionAt(t);
        final other = b.positionAt(t);
        for (final p in [again, other]) {
          expect(p.kind, first.kind);
          expect(p.latitude, first.latitude);
          expect(p.longitude, first.longitude);
          expect(p.recordedAt, first.recordedAt);
          expect(p.playbackTime, first.playbackTime);
        }
      }
    });

    test('T19 a Journey without a start event has no playback axis', () {
      final tl = build(
        eventLog: [ev(1, RouteEventType.finish, s(60))],
        points: [pt(1, 50.0, 30.0, s(10)), pt(2, 50.001, 30.0, s(20))],
        moments: [moment('m1', s(15))],
      );

      expect(tl.hasTimeAxis, isFalse);
      expect(tl.sampleCount, 0);
      expect(tl.startedAt, isNull);
      expect(tl.recordedTimeAtPlaybackTime(sec(5)), isNull);
      expect(tl.positionAt(sec(5)).kind, GpsReplayPositionKind.unavailable);
      expect(tl.markers.single.playbackTime, Duration.zero);
    });

    test('T20 only a completed Journey can be replayed', () {
      for (final status in [
        RecordedRouteStatus.recording,
        RecordedRouteStatus.paused,
        RecordedRouteStatus.discarded,
      ]) {
        expect(
            () => build(forRoute: route(status: status)), throwsArgumentError,
            reason: status);
      }
    });
  });

  group('markers', () {
    test(
        'M01 Moments and photos align to the playback clock; a Moment is one '
        'marker however many photos it has', () {
      final tl = build(
        eventLog: events(100, between: [
          (RouteEventType.pause, 20),
          (RouteEventType.resume, 50),
        ]),
        moments: [
          moment('m3', s(60), lat: 50.3, lng: 30.3),
          moment('m1', s(10), lat: 50.1, lng: 30.1),
          moment('m2', s(30), lat: 50.2, lng: 30.2), // during the pause
          moment('m0', s(10), lat: 50.05, lng: 30.05), // same instant as m1
        ],
        media: [
          photo('a2', s(12), waypointId: 'm1'),
          photo('a1', s(11), waypointId: 'm1'),
          photo('c1', s(61), waypointId: 'm3'),
          photo('s1', s(40), lat: 50.4, lng: 30.4), // standalone, in the pause
          photo('s2', s(70)), // standalone, no position
          photo('s3', s(10)), // same instant as m0 / m1
          photo('orphan', s(80), waypointId: 'not-a-moment'),
          photo('late', s(150)), // after the finish: clamped to the axis end
        ],
      );

      expect([
        for (final m in tl.markers) m.id
      ], [
        'moment_m0',
        'moment_m1',
        'media_s3',
        'moment_m2',
        'media_s1',
        'moment_m3',
        'media_s2',
        'media_orphan',
        'media_late',
      ]);
      expect(tl.markers.where((m) => m.kind == GpsReplayMarkerKind.moment),
          hasLength(4));
      Duration at(String id) =>
          tl.markers.firstWhere((m) => m.id == id).playbackTime;
      expect(at('moment_m1'), sec(10));
      expect(at('moment_m2'), sec(20), reason: 'recorded during the pause');
      expect(at('media_s1'), sec(20));
      expect(at('moment_m3'), sec(30));
      expect(at('media_s2'), sec(40));
      expect(at('media_orphan'), sec(50));
      expect(at('media_late'), sec(70), reason: 'clamped to the axis end');

      final m1 = tl.markers.firstWhere((m) => m.id == 'moment_m1');
      expect([for (final p in m1.photos) p.id], ['a1', 'a2']);
      expect(m1.moment!.id, 'm1');
      expect(m1.latitude, 50.1);
      expect(m1.longitude, 30.1);
      expect(m1.recordedAt, s(10));
      final c = tl.markers.firstWhere((m) => m.id == 'moment_m3');
      expect([for (final p in c.photos) p.id], ['c1']);
      final s1 = tl.markers.firstWhere((m) => m.id == 'media_s1');
      expect(s1.kind, GpsReplayMarkerKind.photo);
      expect(s1.moment, isNull);
      expect(s1.latitude, 50.4);
      expect([for (final p in s1.photos) p.id], ['s1']);
      final s2 = tl.markers.firstWhere((m) => m.id == 'media_s2');
      expect(s2.hasCoordinates, isFalse);
      final orphan = tl.markers.firstWhere((m) => m.id == 'media_orphan');
      expect(orphan.hasCoordinates, isFalse);
      expect(orphan.moment, isNull);

      var last = Duration.zero;
      for (final m in tl.markers) {
        expect(m.playbackTime >= last, isTrue);
        last = m.playbackTime;
      }
      expect(tl.reachedMarkerCount(Duration.zero), 0);
      expect(tl.reachedMarkerCount(sec(10)), 3);
      expect(tl.reachedMarkerCount(sec(20)), 5);
      expect(tl.reachedMarkerCount(sec(30)), 6);
      expect(tl.reachedMarkerCount(sec(1000)), 9);
    });

    test('M02 marker order does not depend on the input order', () {
      final moments = [
        moment('b', s(10)),
        moment('a', s(10)),
        moment('c', s(5)),
      ];
      final media = [
        photo('y', s(10)),
        photo('x', s(10)),
        photo('p', s(10), waypointId: 'a'),
        photo('q', s(9), waypointId: 'a'),
      ];
      final forward = build(moments: moments, media: media);
      final backward = build(
          moments: moments.reversed.toList(), media: media.reversed.toList());

      expect([for (final m in forward.markers) m.id],
          [for (final m in backward.markers) m.id]);
      expect([
        for (final m in forward.markers) m.id
      ], [
        'moment_c',
        'moment_a',
        'moment_b',
        'media_x',
        'media_y',
      ]);
      expect([for (final p in forward.markers[1].photos) p.id], ['q', 'p']);
    });
  });

  group('isolation', () {
    test(
        'I01 another owner / another route / tombstones are excluded and '
        'counted; the timeline equals one built without them', () {
      final clean = build(
        eventLog: events(100),
        points: [pt(1, 50.0, 30.0, s(10)), pt(2, 50.001, 30.0, s(30))],
        moments: [moment('m1', s(20))],
        media: [photo('p1', s(25), waypointId: 'm1')],
      );
      final noisy = build(
        eventLog: [
          ev(1, RouteEventType.start, s(0)),
          // A foreign `start` earlier than ours must not move the axis.
          ev(2, RouteEventType.start, s(-50), ownerId: 'someone-else'),
          ev(3, RouteEventType.pause, s(40), route: 'other-route'),
          ev(4, RouteEventType.finish, s(100)),
        ],
        points: [
          pt(1, 50.0, 30.0, s(10)),
          pt(9, 10.0, 10.0, s(15), ownerId: 'someone-else'),
          pt(10, 11.0, 11.0, s(16), route: 'other-route'),
          pt(2, 50.001, 30.0, s(30)),
        ],
        moments: [
          moment('m1', s(20)),
          moment('foreign', s(21), ownerId: 'someone-else'),
          moment('elsewhere', s(22), route: 'other-route'),
          moment('gone', s(23), syncStatus: WaypointSyncStatus.pendingDelete),
        ],
        media: [
          photo('p1', s(25), waypointId: 'm1'),
          photo('pf', s(26), ownerId: 'someone-else'),
          photo('pe', s(27), route: 'other-route'),
          photo('pg', s(28), syncStatus: JourneyMediaSyncStatus.pendingDelete),
        ],
      );

      expect(noisy.diagnostics.excludedForeignItems, 8);
      expect(noisy.diagnostics.excludedTombstones, 2);
      expect(clean.diagnostics.excludedForeignItems, 0);
      expect(noisy.activeDuration, clean.activeDuration);
      expect(noisy.startedAt, clean.startedAt);
      expect(noisy.sampleCount, clean.sampleCount);
      expect([for (final m in noisy.markers) m.id],
          [for (final m in clean.markers) m.id]);
      for (var t = 0; t <= 100; t += 5) {
        final a = noisy.positionAt(sec(t));
        final b = clean.positionAt(sec(t));
        expect((a.kind, a.latitude, a.longitude),
            (b.kind, b.latitude, b.longitude));
      }
    });
  });

  // -------------------------------------------------------------------
  // P2-1 -- isConsistentWithStatistics must never claim more than it
  // guarantees.
  // -------------------------------------------------------------------

  /// The canonical `moving` time at recorded instant [at]: what the
  /// statistics reported when only the events recorded by then existed.
  Duration canonicalMovingAt(List<LocalRouteEvent> log, DateTime at) =>
      calculateGpsJourneyStatistics(
        points: const [],
        events: [
          for (final e in log)
            if (!e.occurredAt.isAfter(at)) e
        ],
        now: at,
      ).moving;

  /// Largest |replay - canonical| (microseconds) over the Journey window:
  /// every event boundary, the midpoints between boundaries, and extra
  /// random probes.
  int maxDeviationMicros(GpsReplayTimeline tl, List<LocalRouteEvent> log,
      {int randomProbes = 24, int seed = 1}) {
    final startUs = tl.startedAt!.microsecondsSinceEpoch;
    final endUs = tl.finishedAt!.microsecondsSinceEpoch;
    final marks = <int>{startUs, endUs};
    for (final e in log) {
      final us = e.occurredAt.microsecondsSinceEpoch;
      if (us >= startUs && us <= endUs) marks.add(us);
    }
    final sorted = marks.toList()..sort();
    final probes = <int>{...sorted};
    for (var i = 0; i + 1 < sorted.length; i++) {
      probes.add((sorted[i] + sorted[i + 1]) ~/ 2);
    }
    final random = Random(seed);
    for (var i = 0; i < randomProbes; i++) {
      probes.add(startUs + (random.nextDouble() * (endUs - startUs)).floor());
    }
    var worst = 0;
    for (final us in probes) {
      final at = DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);
      final deviation =
          (tl.playbackTimeAtRecordedTime(at) - canonicalMovingAt(log, at))
              .inMicroseconds
              .abs();
      if (deviation > worst) worst = deviation;
    }
    return worst;
  }

  group('P2-1 consistency flag', () {
    final tol = GpsReplayTimeline.toleranceMicros;

    test(
        'F01 the independent review\'s A1 journal (a pause stamped BEFORE the '
        'start) is NOT claimed consistent, although the totals agree', () {
      final log = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.pause, s(-10)),
        ev(3, RouteEventType.resume, s(5)),
        ev(4, RouteEventType.finish, s(100)),
      ];
      final tl = build(eventLog: log);

      // Reproduction guard: the totals match, the intermediate values do not.
      final canonical = calculateGpsJourneyStatistics(
          points: const [], events: log, now: farFuture);
      expect(tl.activeDuration, canonical.moving);
      expect(tl.elapsed, canonical.elapsed);
      expect(tl.pausedDuration, canonical.paused);
      expect(maxDeviationMicros(tl, log), greaterThan(tol));
      expect(
          tl.playbackTimeAtRecordedTime(s(10)) != canonicalMovingAt(log, s(10)),
          isTrue);
      expect(
          tl.playbackTimeAtRecordedTime(s(15)) != canonicalMovingAt(log, s(15)),
          isTrue);

      expect(tl.isConsistentWithStatistics, isFalse);
      // Still a usable, deterministic, monotone and non-negative axis.
      var previous = Duration.zero;
      for (var t = -20.0; t <= 120; t += 2.5) {
        final p = tl.playbackTimeAtRecordedTime(s(t));
        expect(p >= previous, isTrue, reason: 't=$t');
        expect(p.isNegative, isFalse);
        previous = p;
      }
    });

    test('F02 chronological journals (with equal timestamps) stay consistent',
        () {
      final log = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.pause, s(20)),
        ev(3, RouteEventType.resume, s(20)), // zero-length pause
        ev(4, RouteEventType.pause, s(30)),
        ev(5, RouteEventType.resume, s(40)),
        ev(6, RouteEventType.finish, s(40)), // finish at the same instant
      ];
      final tl = build(eventLog: log);

      expect(tl.isConsistentWithStatistics, isTrue);
      expect(maxDeviationMicros(tl, log), lessThanOrEqualTo(tol));
      expect(tl.activeDuration, sec(30));
    });

    test('F03 a clock rollback in the middle of the journal is not consistent',
        () {
      final log = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.pause, s(30)),
        ev(3, RouteEventType.resume, s(20)), // the clock went back
        ev(4, RouteEventType.finish, s(100)),
      ];
      final tl = build(eventLog: log);

      expect(tl.isConsistentWithStatistics, isFalse);
      expect(tl.playbackTimeAtRecordedTime(s(100)).isNegative, isFalse);
    });

    test('F04 out-of-order pause / resume is not consistent', () {
      final log = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.resume, s(40)),
        ev(3, RouteEventType.pause, s(20)), // logged after, stamped before
        ev(4, RouteEventType.finish, s(100)),
      ];
      expect(build(eventLog: log).isConsistentWithStatistics, isFalse);
    });

    test('F05 events after the finish are not consistent', () {
      final paired = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.finish, s(100)),
        ev(3, RouteEventType.pause, s(120)),
        ev(4, RouteEventType.resume, s(130)),
      ];
      final tlPaired = build(eventLog: paired);
      expect(tlPaired.isConsistentWithStatistics, isFalse);
      // The canonical totals disagree with the in-window axis here.
      expect(tlPaired.pausedDuration, sec(10));
      expect(tlPaired.activeDuration, sec(100));

      // Even a lone pause after the finish (which the totals happen to
      // ignore) is rejected: it lies outside the window.
      final lone = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.finish, s(100)),
        ev(3, RouteEventType.pause, s(120)),
      ];
      expect(build(eventLog: lone).isConsistentWithStatistics, isFalse);
    });

    test('F06 a tail pause (never resumed) is consistent and a clean plateau',
        () {
      final log = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.pause, s(50)),
        ev(3, RouteEventType.finish, s(100)),
      ];
      final tl = build(eventLog: log);

      expect(tl.isConsistentWithStatistics, isTrue);
      expect(tl.activeDuration, sec(50));
      expect(tl.pausedDuration, sec(50));
      expect(maxDeviationMicros(tl, log), lessThanOrEqualTo(tol));
      expect(tl.playbackTimeAtRecordedTime(s(75)), sec(50));
      expect(tl.playbackTimeAtRecordedTime(s(100)), sec(50));
      expect(tl.recordedTimeAtPlaybackTime(sec(50)), s(50),
          reason: 'the earliest instant on the plateau');
      expect(tl.recordedTimeAtPlaybackTime(sec(30)), s(30));
    });

    test('F07 a pause recorded before the start is not consistent', () {
      final log = [
        ev(1, RouteEventType.pause, s(-5)),
        ev(2, RouteEventType.start, s(0)),
        ev(3, RouteEventType.resume, s(10)),
        ev(4, RouteEventType.finish, s(100)),
      ];
      expect(build(eventLog: log).isConsistentWithStatistics, isFalse);
    });

    test('F08 a finish in the middle of the journal is not consistent', () {
      final log = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.finish, s(50)),
        ev(3, RouteEventType.pause, s(60)),
        ev(4, RouteEventType.resume, s(70)),
        ev(5, RouteEventType.finish, s(100)),
      ];
      final tl = build(eventLog: log);
      expect(tl.isConsistentWithStatistics, isFalse);
      expect(tl.playbackTimeAtRecordedTime(s(100)).isNegative, isFalse);
    });

    test(
        'F09 the inverse mapping round-trips the forward mapping on the A1 '
        'journal even though the flag is false (best effort, not a '
        'guarantee)', () {
      final log = [
        ev(1, RouteEventType.start, s(0)),
        ev(2, RouteEventType.pause, s(-10)),
        ev(3, RouteEventType.resume, s(5)),
        ev(4, RouteEventType.finish, s(100)),
      ];
      final tl = build(eventLog: log);
      expect(tl.isConsistentWithStatistics, isFalse);

      DateTime? previous;
      for (var i = 0; i <= 50; i++) {
        final t = Duration(
            microseconds: (tl.activeDuration.inMicroseconds * i / 50).round());
        final wall = tl.recordedTimeAtPlaybackTime(t)!;
        expect(wall.isBefore(tl.startedAt!), isFalse);
        expect(wall.isAfter(tl.finishedAt!), isFalse);
        expect((tl.playbackTimeAtRecordedTime(wall) - t).inMicroseconds.abs(),
            lessThanOrEqualTo(1),
            reason: 'playback $t');
        if (previous != null) expect(wall.isBefore(previous), isFalse);
        previous = wall;
      }
    });

    test(
        'F10 SOUNDNESS: whenever the flag is true the replay clock equals '
        'the canonical moving time; hostile journals are exercised', () {
      var claimedTrue = 0;
      var claimedFalse = 0;
      for (var seed = 0; seed < 400; seed++) {
        final random = Random(seed);
        final chronological = seed.isEven;
        var seq = 1;
        var clock = 0.0;
        final log = <LocalRouteEvent>[];
        final count = 2 + random.nextInt(8);
        const types = [
          RouteEventType.pause,
          RouteEventType.resume,
          RouteEventType.start,
          RouteEventType.finish,
        ];
        for (var i = 0; i < count; i++) {
          final type = i == 0 && random.nextInt(4) != 0
              ? RouteEventType.start
              : types[random.nextInt(types.length)];
          if (chronological) {
            clock += random.nextInt(3) == 0 ? 0 : random.nextInt(25);
          } else {
            clock = random.nextInt(140) - 30.0; // negative and unordered
          }
          log.add(ev(seq++, type, s(clock)));
        }
        if (!log.any((e) => e.eventType == RouteEventType.start)) {
          log.add(ev(seq++, RouteEventType.start, s(random.nextInt(20))));
        }
        if (chronological && random.nextBool()) {
          log.add(
              ev(seq++, RouteEventType.finish, s(clock + random.nextInt(20))));
        }

        final tl = build(eventLog: log);
        var previous = Duration.zero;
        for (var t = -40.0; t <= 200; t += 7.3) {
          final p = tl.playbackTimeAtRecordedTime(s(t));
          expect(p >= previous, isTrue, reason: 'seed $seed monotone');
          expect(p.isNegative, isFalse);
          previous = p;
        }
        if (tl.isConsistentWithStatistics) {
          claimedTrue++;
          expect(
              maxDeviationMicros(tl, log, seed: seed), lessThanOrEqualTo(tol),
              reason: 'seed $seed claimed consistency but deviates: '
                  '${[
                for (final e in log)
                  "${e.eventType}@${e.occurredAt.difference(t0).inSeconds}"
              ]}');
        } else {
          claimedFalse++;
        }
      }
      // The property would be vacuous if the flag were constant.
      expect(claimedTrue, greaterThan(20));
      expect(claimedFalse, greaterThan(20));
    });
  });

  // -------------------------------------------------------------------
  // P2-2 -- a future-stamped sample must not poison the rest of the route.
  // -------------------------------------------------------------------

  group('P2-2 timestamp anomalies', () {
    LocalRoutePoint at(int seq, double lat, num seconds,
            {String ownerId = owner}) =>
        pt(seq, lat, 30.0, s(seconds), ownerId: ownerId);

    List<LocalRouteEvent> window(num finish) => events(finish);

    test(
        'S01 the review\'s A2 case: a sample stamped after the finish is '
        'rejected and every later valid sample stays usable', () {
      final tl = build(points: [
        at(1, 50.0000, 10),
        at(2, 50.5000, 5000), // far after the finish at 100 s
        at(3, 50.0002, 30),
        at(4, 50.0003, 40),
        at(5, 50.0004, 50),
        at(6, 50.0005, 60),
      ]);

      expect(tl.sampleCount, 5);
      expect(tl.diagnostics.outsideFinishPoints, 1);
      expect(tl.diagnostics.outOfOrderPoints, 0);
      expect(tl.diagnostics.futureSpikePoints, 0);
      expect(tl.diagnostics.otherGapSegments, 1, reason: 'the rejected sample');

      final end = tl.positionAt(tl.activeDuration);
      expect(end.kind, GpsReplayPositionKind.held);
      expect(end.latitude, 50.0005, reason: 'the last VALID sample');
      expect(end.recordedAt, s(60));

      // No interpolation crosses the rejected spike.
      final across = tl.positionAt(sec(20));
      expect(across.kind, GpsReplayPositionKind.held);
      expect(across.latitude, 50.0000);
      expect(tl.positionAt(sec(30)).kind, GpsReplayPositionKind.exact);
      final later = tl.positionAt(sec(45));
      expect(later.kind, GpsReplayPositionKind.interpolated);
      expect(later.latitude, closeTo(50.00035, 1e-12));
      for (var t = 0; t <= 100; t += 5) {
        expect(tl.positionAt(sec(t)).latitude, isNot(50.5));
      }
    });

    test(
        'S02 a sample exactly at the finish is kept; one microsecond later is not',
        () {
      final tl = build(points: [
        at(1, 50.0000, 50),
        at(2, 50.0005, 100), // exactly the finish instant
        pt(3, 50.0006, 30.0, s(100).add(const Duration(microseconds: 1))),
      ]);

      expect(tl.sampleCount, 2);
      expect(tl.diagnostics.outsideFinishPoints, 1);
      final end = tl.positionAt(tl.activeDuration);
      expect(end.kind, GpsReplayPositionKind.exact);
      expect(end.latitude, 50.0005);
    });

    test('S03 several consecutive samples after the finish are all rejected',
        () {
      final tl = build(points: [
        at(1, 50.0000, 10),
        at(2, 51.0, 200),
        at(3, 51.1, 300),
        at(4, 51.2, 400),
        at(5, 50.0002, 30),
        at(6, 50.0003, 40),
      ]);

      expect(tl.diagnostics.outsideFinishPoints, 3);
      expect(tl.diagnostics.outOfOrderPoints, 0);
      expect(tl.sampleCount, 3);
      expect(tl.positionAt(sec(20)).kind, GpsReplayPositionKind.held);
      expect(tl.positionAt(sec(35)).kind, GpsReplayPositionKind.interpolated);
    });

    test(
        'S04 an isolated spike INSIDE the window, contradicted by more later '
        'samples than it spans, is rejected', () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.5000, 5000), // inside the window, but contradicted
        at(3, 50.0002, 30),
        at(4, 50.0003, 40),
        at(5, 50.0004, 50),
      ]);

      expect(tl.diagnostics.futureSpikePoints, 1);
      expect(tl.diagnostics.outOfOrderPoints, 0);
      expect(tl.diagnostics.outsideFinishPoints, 0);
      expect(tl.sampleCount, 4);
      expect(tl.positionAt(sec(20)).kind, GpsReplayPositionKind.held);
      expect(tl.positionAt(sec(20)).latitude, 50.0000);
      expect(tl.positionAt(sec(45)).kind, GpsReplayPositionKind.interpolated);
      final end = tl.positionAt(sec(5000));
      expect(end.latitude, 50.0004, reason: 'the last valid sample');
    });

    test('S05 a run of consecutive future samples is rejected together', () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.5, 5000),
        at(3, 50.6, 5002),
        at(4, 50.7, 5004),
        at(5, 50.0002, 30),
        at(6, 50.0003, 40),
        at(7, 50.0004, 50),
        at(8, 50.0005, 60),
      ]);

      expect(tl.diagnostics.futureSpikePoints, 3);
      expect(tl.diagnostics.outOfOrderPoints, 0);
      expect(tl.sampleCount, 5);
      expect(tl.positionAt(sec(20)).kind, GpsReplayPositionKind.held);
      expect(tl.positionAt(sec(4000)).latitude, 50.0005);
    });

    test(
        'S06 AMBIGUOUS: one confirming sample is not enough -- the contradicted '
        'sample is dropped as before and the discontinuity is reported', () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.5000, 5000),
        at(3, 50.0002, 30), // the only follower
      ]);

      expect(tl.diagnostics.futureSpikePoints, 0);
      expect(tl.diagnostics.outOfOrderPoints, 1);
      expect(tl.sampleCount, 2);
      expect(tl.positionAt(sec(5000)).latitude, 50.5000,
          reason: 'documented ambiguity: the earlier-accepted sample wins');
      expect(tl.diagnostics.discontinuousSegments, 0,
          reason: '10 -> 5000 is a plain (plausible-speed) segment');
    });

    test('S07 the confirming group must be STRICTLY larger than the run', () {
      List<LocalRoutePoint> scenario(int followers) => [
            at(1, 50.0000, 10),
            at(2, 50.5, 5000),
            at(3, 50.6, 5002),
            for (var i = 0; i < followers; i++)
              at(4 + i, 50.0001 + i * 0.0001, 30 + i * 10),
          ];

      final equal = build(eventLog: window(6000), points: scenario(2));
      expect(equal.diagnostics.futureSpikePoints, 0);
      expect(equal.diagnostics.outOfOrderPoints, 2);

      final larger = build(eventLog: window(6000), points: scenario(3));
      expect(larger.diagnostics.futureSpikePoints, 2);
      expect(larger.diagnostics.outOfOrderPoints, 0);
      expect(larger.sampleCount, 4);
    });

    test('S08 a run longer than the isolation limit is never rejected', () {
      final points = [
        at(1, 50.0000, 10),
        for (var i = 0; i < GpsReplayTimeline.maxSpikeRunLength + 1; i++)
          at(2 + i, 50.5 + i * 0.001, 5000 + i),
        for (var i = 0; i < 30; i++)
          at(20 + i, 50.0001 + i * 0.00001, 30 + i * 2),
      ];
      final tl = build(eventLog: window(6000), points: points);

      expect(tl.diagnostics.futureSpikePoints, 0);
      expect(tl.diagnostics.outOfOrderPoints, 30);
    });

    test('S09 confirming samples may share timestamps (duplicates count)', () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.5, 5000),
        at(3, 50.0002, 30),
        at(4, 50.0002, 30), // duplicate timestamp
        at(5, 50.0003, 40),
      ]);

      expect(tl.diagnostics.futureSpikePoints, 1);
      expect(tl.sampleCount, 4);
      expect(tl.positionAt(sec(30)).kind, GpsReplayPositionKind.exact);
    });

    test('S10 a spike as the very first sample is rejected too', () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.5, 5000),
        at(2, 50.0000, 10),
        at(3, 50.0001, 20),
        at(4, 50.0002, 30),
      ]);

      expect(tl.diagnostics.futureSpikePoints, 1);
      expect(tl.sampleCount, 3);
      expect(tl.positionAt(Duration.zero).kind, GpsReplayPositionKind.leading);
      expect(tl.positionAt(Duration.zero).latitude, 50.0000);
    });

    test('S11 ordinary out-of-order data is handled exactly as before', () {
      final tl = build(points: [
        at(1, 50.0000, 10),
        at(2, 50.0002, 20),
        at(3, 50.0001, 15), // late-stamped: dropped
        at(4, 50.0003, 25),
      ]);

      expect(tl.diagnostics.outOfOrderPoints, 1);
      expect(tl.diagnostics.futureSpikePoints, 0);
      expect(tl.sampleCount, 3);
      expect(tl.positionAt(sec(20)).latitude, 50.0002);
    });

    test('S12 empty, single and all-after-finish routes', () {
      final empty = build(points: const []);
      expect(empty.diagnostics.outsideFinishPoints, 0);
      expect(empty.positionAt(sec(10)).kind, GpsReplayPositionKind.unavailable);

      final single = build(points: [at(1, 50.0, 10)]);
      expect(single.sampleCount, 1);
      expect(single.diagnostics.outsideFinishPoints, 0);

      final late = build(points: [at(1, 50.0, 500)]);
      expect(late.sampleCount, 0);
      expect(late.diagnostics.outsideFinishPoints, 1);
      expect(late.positionAt(sec(50)).kind, GpsReplayPositionKind.unavailable);
    });

    test(
        'S13 other owners\' samples are excluded and never act as confirming '
        'context', () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.5, 5000),
        at(3, 50.0002, 30),
        at(4, 50.0003, 40, ownerId: 'someone-else'),
        at(5, 50.0004, 50, ownerId: 'someone-else'),
      ]);

      expect(tl.diagnostics.excludedForeignItems, 2);
      expect(tl.diagnostics.futureSpikePoints, 0,
          reason: 'only ONE of this Journey\'s own samples contradicts it');
      expect(tl.diagnostics.outOfOrderPoints, 1);
      expect(tl.sampleCount, 2);
    });

    test(
        'S14 diagnostics describe the FINAL timeline: a rejected spike\'s own '
        'jump segment is not counted', () {
      final tl = build(points: [
        at(1, 50.0, 10),
        at(2, 51.0, 60), // would be a ~2 km/s jump if it were kept
        at(3, 50.0001, 20),
        at(4, 50.0002, 30),
        at(5, 50.0003, 40),
      ]);

      expect(tl.diagnostics.futureSpikePoints, 1);
      expect(tl.diagnostics.impossibleJumpSegments, 0);
      expect(tl.diagnostics.otherGapSegments, 1);
      expect(tl.sampleCount, 4);
    });

    test(
        'S16 the confirming samples must agree with EACH OTHER and stay '
        'earlier than the spike', () {
      // Strictly falling followers contradict one another: no confirmation.
      final disagree = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.5000, 5000),
        at(3, 50.0003, 30),
        at(4, 50.0002, 20),
        at(5, 50.0001, 15),
      ]);
      expect(disagree.diagnostics.futureSpikePoints, 0);
      expect(disagree.diagnostics.outOfOrderPoints, 3);
      expect(disagree.sampleCount, 2);

      // 200 is not earlier than the 100 s "spike": it does not contradict it.
      final notContradicted = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.0005, 100),
        at(3, 50.0002, 30),
        at(4, 50.0006, 200),
      ]);
      expect(notContradicted.diagnostics.futureSpikePoints, 0);
      expect(notContradicted.diagnostics.outOfOrderPoints, 1);
      expect(notContradicted.sampleCount, 3);
    });

    test(
        'S17 the strictly larger agreeing group wins, even when part of the '
        'rejected tail looked plausible; it is reported, never bridged', () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.0001, 50), // plausible on its own, but contradicted
        at(3, 50.5000, 5000),
        at(4, 50.0002, 20),
        at(5, 50.0003, 25),
        at(6, 50.0004, 28),
      ]);

      expect(tl.diagnostics.futureSpikePoints, 2);
      expect(tl.diagnostics.outOfOrderPoints, 0);
      expect(tl.sampleCount, 4);
      expect(tl.diagnostics.otherGapSegments, 1);
      expect(tl.positionAt(sec(15)).kind, GpsReplayPositionKind.held);
      expect(tl.positionAt(sec(15)).latitude, 50.0000);
    });

    test(
        'S18 a run that opens the route needs confirmation that is not '
        'earlier than the Journey start', () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.5000, 5000),
        at(2, 50.0001, -100),
        at(3, 50.0002, -90),
        at(4, 50.0003, -80),
      ]);

      expect(tl.diagnostics.futureSpikePoints, 0);
      expect(tl.diagnostics.outOfOrderPoints, 3);
      expect(tl.sampleCount, 1);
    });

    test('S15 the jump protection still applies after a spike was rejected',
        () {
      final tl = build(eventLog: window(6000), points: [
        at(1, 50.0000, 10),
        at(2, 50.5, 5000),
        at(3, 50.0002, 30),
        at(4, 51.0000, 40), // genuine impossible jump
        at(5, 51.0001, 50),
      ]);

      expect(tl.diagnostics.futureSpikePoints, 1);
      expect(tl.diagnostics.impossibleJumpSegments, 1);
      expect(tl.positionAt(sec(35)).kind, GpsReplayPositionKind.held);
      expect(tl.positionAt(sec(35)).latitude, 50.0002);
    });
  });

  group('geometry (1I-B0 read-only view of the accepted samples)', () {
    LocalRoutePoint g(int seq, double lat, num seconds) =>
        pt(seq, lat, 30.0, s(seconds));

    // Mixed fixture: a pause gap, an impossible-jump gap, a rejected sample
    // (-> "other" gap) and a zero-length segment (-> "other" gap).
    List<LocalRoutePoint> mixedPoints() => [
          g(1, 50.0000, 10),
          g(2, 50.0001, 15),
          g(3, 50.0002, 22),
          g(4, 50.0003, 50), // after the 25..45 pause
          g(5, 51.0000, 55), // ~111 km in 5 s
          g(6, 51.0001, 60),
          g(7, double.nan, 65), // rejected: invalid coordinate
          g(8, 51.0002, 70),
          g(9, 51.0002, 70), // duplicate timestamp: zero-length segment
          g(10, 51.0003, 75),
        ];
    List<LocalRouteEvent> mixedEvents() => events(100, between: [
          (RouteEventType.pause, 25),
          (RouteEventType.resume, 45),
        ]);

    GpsReplayTimeline mixed() =>
        build(points: mixedPoints(), eventLog: mixedEvents());

    test('G01 runs and gaps describe exactly the accepted samples', () {
      final tl = mixed();

      expect(tl.sampleCount, 9);
      final shape = [
        for (final r in tl.runs) (r.startIndex, r.endIndex, r.gapBefore),
      ];
      expect(shape, [
        (0, 3, null),
        (3, 4, GpsReplayGapKind.pause),
        (4, 6, GpsReplayGapKind.impossibleJump),
        (6, 7, GpsReplayGapKind.other),
        (7, 9, GpsReplayGapKind.other),
      ]);
      // The rejected (NaN) sample never reappears.
      for (var i = 0; i < tl.sampleCount; i++) {
        expect(tl.latitudeAt(i).isFinite, isTrue);
      }
      expect([
        for (var i = 0; i < tl.sampleCount; i++) tl.latitudeAt(i)
      ], [
        50.0000,
        50.0001,
        50.0002,
        50.0003,
        51.0000,
        51.0001,
        51.0002,
        51.0002,
        51.0003,
      ]);
      expect(tl.longitudeAt(0), 30.0);
      expect(tl.playbackTimeAt(0), sec(10));
      expect(tl.playbackTimeAt(3), sec(30), reason: '50 s wall - 20 s paused');
      // Counts agree with the diagnostics the builder already reports.
      int gaps(GpsReplayGapKind k) =>
          tl.runs.where((r) => r.gapBefore == k).length;
      expect(gaps(GpsReplayGapKind.pause), tl.diagnostics.pauseGapSegments);
      expect(gaps(GpsReplayGapKind.impossibleJump),
          tl.diagnostics.impossibleJumpSegments);
      expect(gaps(GpsReplayGapKind.other), tl.diagnostics.otherGapSegments);
    });

    test('G02 a gap is never inside a run: positionAt agrees on every segment',
        () {
      final tl = mixed();
      for (var i = 0; i + 1 < tl.sampleCount; i++) {
        final a = tl.playbackTimeAt(i);
        final b = tl.playbackTimeAt(i + 1);
        final sameRun = tl.runIndexOfSample(i) == tl.runIndexOfSample(i + 1);
        if (b <= a) {
          expect(sameRun, isFalse, reason: 'zero-length segment $i');
          continue;
        }
        final mid = Duration(microseconds: (a + b).inMicroseconds ~/ 2);
        final p = tl.positionAt(mid);
        expect(
            p.kind,
            sameRun
                ? GpsReplayPositionKind.interpolated
                : GpsReplayPositionKind.held,
            reason: 'segment $i');
      }
    });

    test('G03 runs partition the samples; run lookup is consistent', () {
      final tl = mixed();
      var expectedStart = 0;
      for (var r = 0; r < tl.runs.length; r++) {
        final run = tl.runs[r];
        expect(run.startIndex, expectedStart);
        expect(run.length, greaterThan(0));
        expect(run.gapBefore == null, r == 0);
        for (var i = run.startIndex; i < run.endIndex; i++) {
          expect(tl.runIndexOfSample(i), r);
        }
        expectedStart = run.endIndex;
      }
      expect(expectedStart, tl.sampleCount);
    });

    test(
        'G04 sampleIndexAt: boundaries, clamping and agreement with positionAt',
        () {
      final tl = build(points: [
        g(1, 50.0000, 10),
        g(2, 50.0001, 20),
        g(3, 50.0002, 30),
      ]);

      expect(tl.sampleIndexAt(Duration.zero), -1);
      expect(tl.sampleIndexAt(const Duration(microseconds: -5)), -1);
      expect(tl.sampleIndexAt(sec(10) - const Duration(microseconds: 1)), -1);
      expect(tl.sampleIndexAt(sec(10)), 0);
      expect(tl.sampleIndexAt(sec(10) + const Duration(microseconds: 1)), 0);
      expect(tl.sampleIndexAt(sec(20) - const Duration(microseconds: 1)), 0);
      expect(tl.sampleIndexAt(sec(20)), 1);
      expect(tl.sampleIndexAt(sec(30)), 2);
      expect(tl.sampleIndexAt(tl.activeDuration), 2);
      expect(tl.sampleIndexAt(sec(100000)), 2, reason: 'clamped');

      for (var m = 0; m <= 100000000; m += 700001) {
        final t = Duration(microseconds: m);
        final i = tl.sampleIndexAt(t);
        final p = tl.positionAt(t);
        if (i < 0) {
          expect(p.kind, GpsReplayPositionKind.leading);
        } else {
          expect(
              p.kind == GpsReplayPositionKind.exact, tl.playbackTimeAt(i) == t);
          if (p.kind != GpsReplayPositionKind.interpolated) {
            expect(p.latitude, tl.latitudeAt(i), reason: 'm=$m');
          } else {
            expect(p.latitude,
                inInclusiveRange(tl.latitudeAt(i), tl.latitudeAt(i + 1)));
          }
        }
      }
    });

    test('G05 samples inside one pause share a playback time; the last wins',
        () {
      final tl = build(
          points: [
            g(1, 50.0000, 10),
            g(2, 50.0001, 30), // inside the 25..45 pause
            g(3, 50.0001, 40), // inside the pause too
            g(4, 50.0002, 60),
          ],
          eventLog: events(100, between: [
            (RouteEventType.pause, 25),
            (RouteEventType.resume, 45),
          ]));

      expect(tl.sampleCount, 4);
      expect(tl.playbackTimeAt(1), tl.playbackTimeAt(2));
      expect(tl.sampleIndexAt(tl.playbackTimeAt(1)), 2);
      expect(tl.positionAt(tl.playbackTimeAt(1)).latitude, tl.latitudeAt(2));
      expect(tl.runs.length, greaterThan(1),
          reason: 'zero active duration is a gap, never a drawn segment');
      expect(tl.runIndexOfSample(1), isNot(tl.runIndexOfSample(2)));
    });

    test('G06 rejected spikes and after-finish points do not appear', () {
      final tl = build(eventLog: events(6000), points: [
        g(1, 50.0000, 10),
        g(2, 50.5000, 5000), // future-stamped spike, contradicted below
        g(3, 50.0002, 30),
        g(4, 50.0003, 40),
        g(5, 50.0004, 50),
        g(6, 59.0, 7000), // after the finish
      ]);

      expect(tl.diagnostics.futureSpikePoints, 1);
      expect(tl.diagnostics.outsideFinishPoints, 1);
      expect([for (var i = 0; i < tl.sampleCount; i++) tl.latitudeAt(i)],
          [50.0000, 50.0002, 50.0003, 50.0004]);
      expect(tl.runs.length, 2, reason: 'the rejected spike is a gap');
      expect(tl.runs[1].gapBefore, GpsReplayGapKind.other);
      expect(tl.runs[1].startIndex, 1);
    });

    test('G07 empty, single-point and axis-less journeys', () {
      final empty = build(eventLog: events(60));
      expect(empty.runs, isEmpty);
      expect(empty.sampleIndexAt(sec(30)), -1);
      expect(() => empty.latitudeAt(0), throwsRangeError);
      expect(() => empty.runIndexOfSample(0), throwsRangeError);

      final single = build(points: [g(1, 50.0, 10)]);
      expect(single.runs.length, 1);
      expect(single.runs.single.startIndex, 0);
      expect(single.runs.single.endIndex, 1);
      expect(single.runs.single.length, 1);
      expect(single.runs.single.gapBefore, isNull);
      expect(single.sampleIndexAt(sec(9)), -1);
      expect(single.sampleIndexAt(sec(10)), 0);
      expect(single.sampleIndexAt(sec(99)), 0);
      expect(single.runIndexOfSample(0), 0);

      // No `start` event: there is no axis, hence no accepted sample.
      final axisless = build(
          points: [g(1, 50.0, 10)],
          eventLog: [ev(1, RouteEventType.finish, s(100))]);
      expect(axisless.sampleCount, 0);
      expect(axisless.runs, isEmpty);
      expect(axisless.sampleIndexAt(sec(10)), -1);
    });

    test('G08 the exposed view is immutable and bounds-checked', () {
      final tl = mixed();
      final runs = tl.runs;

      expect(identical(tl.runs, runs), isTrue, reason: 'built once');
      expect(() => runs.add(runs.first), throwsUnsupportedError);
      expect(() => runs.removeLast(), throwsUnsupportedError);
      expect(() => runs.clear(), throwsUnsupportedError);
      expect(() => runs[0] = runs[1], throwsUnsupportedError);
      for (final bad in [-1, tl.sampleCount, tl.sampleCount + 5]) {
        expect(() => tl.latitudeAt(bad), throwsRangeError);
        expect(() => tl.longitudeAt(bad), throwsRangeError);
        expect(() => tl.playbackTimeAt(bad), throwsRangeError);
        expect(() => tl.runIndexOfSample(bad), throwsRangeError);
      }
      // Reading the geometry never alters behavior.
      final before = [
        for (var m = 0; m <= 90000000; m += 1300007)
          tl.positionAt(Duration(microseconds: m)).latitude
      ];
      expect(tl.runs, isNotEmpty);
      expect(tl.sampleIndexAt(sec(40)), isNonNegative);
      final after = [
        for (var m = 0; m <= 90000000; m += 1300007)
          tl.positionAt(Duration(microseconds: m)).latitude
      ];
      expect(after, before);
    });

    test('G09 owner / route isolation reaches the geometry', () {
      final tl = build(points: [
        g(1, 50.0000, 10),
        pt(2, 49.0, 30.0, s(15), ownerId: 'someone-else'),
        pt(3, 48.0, 30.0, s(16), route: 'other-route'),
        g(4, 50.0001, 20),
      ]);
      expect(tl.diagnostics.excludedForeignItems, 2);
      expect([for (var i = 0; i < tl.sampleCount; i++) tl.latitudeAt(i)],
          [50.0000, 50.0001]);
      expect(tl.runs.length, 1);
    });

    test('G10 randomized: invariants hold against brute force', () {
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(seed);
        final pts = <LocalRoutePoint>[];
        var at = 0.0;
        for (var i = 0; i < 1 + random.nextInt(40); i++) {
          at += random.nextInt(4) == 0 ? 0 : random.nextDouble() * 12;
          var stamped = at;
          final roll = random.nextInt(12);
          if (roll == 0) stamped = at + 5000; // spike / after finish
          if (roll == 1) stamped = at - random.nextDouble() * 30; // late
          final lat = roll == 2
              ? double.nan
              : 50 + (random.nextInt(8) == 0 ? 1.0 : 0.0) + i * 1e-5;
          pts.add(g(i + 1, lat, stamped));
        }
        final tl = build(
            points: pts,
            eventLog: events(300, between: [
              (RouteEventType.pause, 60),
              (RouteEventType.resume, 90),
            ]));

        // Runs partition the samples in order.
        var next = 0;
        for (var r = 0; r < tl.runs.length; r++) {
          expect(tl.runs[r].startIndex, next, reason: 'seed $seed');
          expect(tl.runs[r].gapBefore == null, r == 0, reason: 'seed $seed');
          next = tl.runs[r].endIndex;
        }
        expect(next, tl.sampleCount, reason: 'seed $seed');
        int gaps(GpsReplayGapKind k) =>
            tl.runs.where((r) => r.gapBefore == k).length;
        expect(gaps(GpsReplayGapKind.pause), tl.diagnostics.pauseGapSegments,
            reason: 'seed $seed');
        expect(gaps(GpsReplayGapKind.impossibleJump),
            tl.diagnostics.impossibleJumpSegments,
            reason: 'seed $seed');
        expect(gaps(GpsReplayGapKind.other), tl.diagnostics.otherGapSegments,
            reason: 'seed $seed');

        // Playback times never decrease; lookup equals a linear scan.
        for (var i = 1; i < tl.sampleCount; i++) {
          expect(tl.playbackTimeAt(i) >= tl.playbackTimeAt(i - 1), isTrue,
              reason: 'seed $seed');
        }
        for (var k = 0; k <= 60; k++) {
          final t = Duration(
              microseconds: -1000000 +
                  k * (tl.activeDuration.inMicroseconds + 2000000) ~/ 60);
          final clamped = t.isNegative
              ? Duration.zero
              : (t > tl.activeDuration ? tl.activeDuration : t);
          var expected = -1;
          for (var i = 0; i < tl.sampleCount; i++) {
            if (tl.playbackTimeAt(i) <= clamped) expected = i;
          }
          expect(tl.sampleIndexAt(t), expected, reason: 'seed $seed k $k');
        }
      }
    });
  });

  group('loader (real Drift readers)', () {
    late GpsLocalDatabase db;
    setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> record(String id, String ownerId) async {
      await db.createLocalRecordedRoute(
          id: id, ownerId: ownerId, startedAt: s(0));
      Future<void> point(int sec, double lat) => db.appendRoutePoint(
          ownerId: ownerId,
          recordedRouteId: id,
          latitude: lat,
          longitude: 30.0,
          recordedAt: s(sec));
      await point(10, 50.0000);
      await point(20, 50.0001);
      await db.addWaypoint(
          id: 'm-$id',
          ownerId: ownerId,
          recordedRouteId: id,
          waypointType: 'custom',
          latitude: 50.0001,
          longitude: 30.0,
          recordedAt: s(20));
      await db.insertJourneyMedia(
          id: 'p-$id',
          ownerId: ownerId,
          recordedRouteId: id,
          waypointId: 'm-$id',
          capturedAt: s(21),
          localRelativePath: 'journey_media/$id/p-$id.jpg');
      await db.pauseRecording(ownerId: ownerId, routeId: id, occurredAt: s(25));
      await db.resumeRecording(
          ownerId: ownerId, routeId: id, occurredAt: s(55));
      await point(60, 50.0002);
      await point(70, 50.0003);
      await db.finishRecordingLocally(
          ownerId: ownerId, routeId: id, occurredAt: s(80));
    }

    test('L01 a completed Journey loads and matches the canonical details',
        () async {
      await record('j1', 'me');

      final tl = await loadGpsJourneyReplay(
          db: db, ownerId: 'me', routeId: 'j1', now: farFuture);

      expect(tl, isNotNull);
      expect(tl!.isConsistentWithStatistics, isTrue);
      expect(tl.elapsed, sec(80));
      expect(tl.pausedDuration, sec(30));
      expect(tl.activeDuration, sec(50));
      expect(tl.sampleCount, 4);
      expect(tl.diagnostics.pauseGapSegments, 1);
      expect(tl.diagnostics.excludedForeignItems, 0);
      expect([for (final m in tl.markers) m.id], ['moment_m-j1']);
      expect(tl.markers.single.photos.single.id, 'p-j1');
      expect(tl.markers.single.playbackTime, sec(20));
      expect(tl.positionAt(sec(25)).kind, GpsReplayPositionKind.held);
    });

    test('L02 unknown, foreign and unfinished Journeys do not load', () async {
      await record('j1', 'me');
      await db.createLocalRecordedRoute(
          id: 'active', ownerId: 'me2', startedAt: s(0));

      expect(
          await loadGpsJourneyReplay(
              db: db, ownerId: 'me', routeId: 'nope', now: farFuture),
          isNull);
      expect(
          await loadGpsJourneyReplay(
              db: db, ownerId: 'someone-else', routeId: 'j1', now: farFuture),
          isNull);
      expect(
          await loadGpsJourneyReplay(
              db: db, ownerId: 'me2', routeId: 'active', now: farFuture),
          isNull);
    });
  });

  group('purity', () {
    test('P01 the replay source has no timers, streams, I/O or live services',
        () {
      final raw = File('lib/features/gps/replay/gps_journey_replay.dart')
          .readAsStringSync();
      final code = raw
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      final imports =
          RegExp(r"^import '([^']+)'( show [A-Za-z]+)?;", multiLine: true)
              .allMatches(code)
              .map((m) => '${m.group(1)}${m.group(2) ?? ''}')
              .toList()
            ..sort();
      expect(imports, [
        '../local/gps_local_database.dart',
        '../recording/gps_journey_details.dart',
        '../recording/gps_journey_statistics.dart',
        'dart:typed_data',
        'package:geolocator/geolocator.dart show Geolocator',
      ]);
      for (final banned in [
        'Timer',
        'Stream',
        'Isolate',
        'dart:async',
        'dart:io',
        'DateTime.now',
        'HttpClient',
        'supabase',
        'riverpod',
        'getPositionStream',
        'location_source',
        'WidgetsBinding',
      ]) {
        expect(code.contains(banned), isFalse, reason: banned);
      }
      final geolocatorUses = RegExp(r'Geolocator\.\w+').allMatches(code);
      expect({for (final m in geolocatorUses) m.group(0)},
          {'Geolocator.distanceBetween'});
    });
  });
}
