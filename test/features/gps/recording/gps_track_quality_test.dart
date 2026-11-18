import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';
import 'package:flutter_application_1/features/gps/recording/gps_track_quality.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';

/// Journey Phase 2.5 -- GPS signal-quality protection. Pure fixtures built
/// from the persisted data classes (as the statistics tests do).
void main() {
  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime s(num seconds) => t0.add(Duration(seconds: seconds.round()));

  // 0.00001 deg of latitude ~ 1.11 m.
  const metersPerDegLat = 111195.0;

  LocalRoutePoint pt(
    int seq,
    double lat,
    double lng,
    num sec, {
    double? acc = 5,
    double? speed,
  }) =>
      LocalRoutePoint(
        recordedRouteId: 'r1',
        seq: seq,
        ownerId: 'owner-1',
        latitude: lat,
        longitude: lng,
        horizontalAccuracy: acc,
        speed: speed,
        recordedAt: s(sec),
      );

  /// [n] samples heading north from [lat0] at [mps], one every [cadence] s,
  /// starting at [startSec]; sequence numbers start at [seq0].
  List<LocalRoutePoint> track(
    int n, {
    int seq0 = 0,
    double lat0 = 50.0,
    double lng = 30.0,
    double mps = 1.5,
    double cadence = 3,
    num startSec = 0,
    double? acc = 5,
    bool reportSpeed = true,
  }) =>
      [
        for (var i = 0; i < n; i++)
          pt(seq0 + i, lat0 + mps * cadence * i / metersPerDegLat, lng,
              startSec + cadence * i,
              acc: acc, speed: reportSpeed ? mps : null),
      ];

  double along(List<LocalRoutePoint> pts) => Geolocator.distanceBetween(
      pts.first.latitude,
      pts.first.longitude,
      pts.last.latitude,
      pts.last.longitude);

  group('Q01 unusable accuracy', () {
    test('accuracy 40 300 m is excluded, the chain is not cut', () {
      final pts = track(21);
      pts[10] = pt(10, pts[10].latitude + 0.0001, 30.0, 30, acc: 40300);

      final a = analyzeGpsTrack(pts);

      expect(a.verdicts[10], GpsPointVerdict.lowAccuracy);
      expect(a.trustedCount, 20);
      expect(a.lowAccuracyCount, 1);
      expect(a.trustedRuns().single, hasLength(20));
      // 19 links over the same straight line, minus nothing: the neighbours
      // of the bad fix connect to each other.
      expect(a.confirmedDistanceMeters, closeTo(along(pts), 0.5));
    });

    test('a missing accuracy is NOT a reason to exclude', () {
      final pts = track(10, acc: null);
      final a = analyzeGpsTrack(pts);
      expect(a.trustedCount, 10);
      expect(a.confirmedDistanceMeters, closeTo(along(pts), 0.5));
    });

    test('accuracy exactly at the limit is kept, just above is not', () {
      final ok = analyzeGpsTrack(track(3, acc: gpsMaxReliableAccuracyMeters));
      expect(ok.trustedCount, 3);
      final bad =
          analyzeGpsTrack(track(3, acc: gpsMaxReliableAccuracyMeters + 1));
      expect(bad.trustedCount, 0);
      expect(bad.confirmedDistanceMeters, 0);
    });
  });

  group('Q02 jumps of thousands of kilometres', () {
    // The recorded incident: 26 walking samples, then a 12 275 km jump in
    // one second, then a self-consistent 56 m/s chain with accuracy 2-5 m.
    List<LocalRoutePoint> incident({required int farPoints}) {
      final walk = track(26, acc: 100, mps: 0.8, cadence: 10);
      return [
        ...walk,
        for (var i = 0; i < farPoints; i++)
          pt(26 + i, -12.0 + 56 * 2 * i / metersPerDegLat, -77.0,
              250 + 1 + 2 * i,
              acc: 3, speed: 56),
      ];
    }

    test('the jump and the chain behind it are not confirmed distance', () {
      final pts = incident(farPoints: 100);
      final a = analyzeGpsTrack(pts);

      expect(a.trustedCount, 26);
      expect(a.unconfirmedCount, 100);
      expect(a.confirmedDistanceMeters,
          closeTo(along(pts.sublist(0, 26)), 1)); // ~ 200 m, not 5.6 km
      expect(a.trustedRuns(), hasLength(1));
      expect(a.trustedRuns().single, hasLength(26));
    });

    test('the old rule would have counted the fake chain', () {
      final pts = incident(farPoints: 100);
      var old = 0.0;
      for (var i = 1; i < pts.length; i++) {
        final dt =
            pts[i].recordedAt.difference(pts[i - 1].recordedAt).inSeconds;
        final d = Geolocator.distanceBetween(pts[i - 1].latitude,
            pts[i - 1].longitude, pts[i].latitude, pts[i].longitude);
        if (d / dt <= gpsImpossibleJumpThresholdMps) old += d;
      }
      expect(old, greaterThan(10000));
      expect(analyzeGpsTrack(pts).confirmedDistanceMeters, lessThan(300));
    });

    test(
        'AMBIGUOUS: an alternative chain that holds for 10 min is adopted '
        'behind a discontinuity, never bridged', () {
      final pts = incident(farPoints: 330); // 660 s
      final a = analyzeGpsTrack(pts);

      expect(a.trustedCount, 26 + 330);
      expect(a.links[26], GpsLinkKind.discontinuity);
      final runs = a.trustedRuns();
      expect(runs, hasLength(2));
      expect(runs.first, hasLength(26));
      // The jump itself is never counted: far below 12 275 km.
      expect(a.confirmedDistanceMeters, lessThan(60000));
    });

    test('a jump that never persists leaves the old track intact', () {
      final pts = [
        ...track(10, cadence: 3),
        // two far samples, then the user is back where they were
        pt(10, -12.0, -77.0, 31, acc: 5, speed: 1.5),
        pt(11, -12.00004, -77.0, 34, acc: 5, speed: 1.5),
        ...track(10,
            seq0: 12, lat0: 50.0 + 1.5 * 3 * 9 / metersPerDegLat, startSec: 37),
      ];
      final a = analyzeGpsTrack(pts);
      expect(a.unconfirmedCount, 2);
      expect(a.trustedCount, 20);
      expect(a.trustedRuns(), hasLength(1));
    });
  });

  group('Q03 plausible vehicle movement', () {
    test('a car accelerating to 30 m/s is fully confirmed', () {
      final pts = <LocalRoutePoint>[];
      var lat = 50.0;
      var t = 0.0;
      for (var i = 0; i < 200; i++) {
        final v = min(30.0, i * 3.0); // ramp up over ten samples
        pts.add(pt(i, lat, 30.0, t, acc: 6, speed: v));
        lat += v * 3 / metersPerDegLat;
        t += 3;
      }
      final a = analyzeGpsTrack(pts);
      expect(a.trustedCount, 200);
      expect(a.brokenLinkCount, 0);
      expect(a.confirmedDistanceMeters, closeTo(along(pts), 5));
      expect(a.confirmedDistanceMeters, greaterThan(15000));
    });

    test('a car without any reported speed is still confirmed', () {
      final pts = track(100, mps: 30, reportSpeed: false, acc: 8);
      final a = analyzeGpsTrack(pts);
      expect(a.trustedCount, 100);
      expect(a.confirmedDistanceMeters, closeTo(along(pts), 5));
    });

    test('a motorway pace of 45 m/s (162 km/h) is allowed', () {
      final pts = track(60, mps: 45, acc: 5);
      final a = analyzeGpsTrack(pts);
      expect(a.trustedCount, 60);
      expect(a.brokenLinkCount, 0);
    });

    test('the same displacement is NOT accepted for a walker', () {
      // A walker reporting 1.5 m/s cannot move 150 m in 3 s (50 m/s):
      // under 70 m/s, so only the context-aware rule can reject it.
      final pts = track(21);
      pts[10] = pt(10, pts[10].latitude + 150 / metersPerDegLat, 30.0, 30,
          acc: 5, speed: 1.5);
      final a = analyzeGpsTrack(pts);
      expect(a.verdicts[10], GpsPointVerdict.unconfirmed);
      expect(a.trustedCount, 20);
      expect(a.trustedRuns().single, hasLength(20));
      expect(a.confirmedDistanceMeters, closeTo(along(pts), 1));
    });
  });

  group('Q04 city GPS (noisy but honest)', () {
    test('jitter within the stated accuracy never excludes a point', () {
      final rnd = Random(7);
      final pts = <LocalRoutePoint>[];
      for (var i = 0; i < 300; i++) {
        final jitterLat = (rnd.nextDouble() - 0.5) * 2 * 25 / metersPerDegLat;
        final jitterLng = (rnd.nextDouble() - 0.5) * 2 * 25 / 71000;
        pts.add(pt(i, 50.0 + 1.4 * 3 * i / metersPerDegLat + jitterLat,
            30.0 + jitterLng, 3.0 * i,
            acc: 40, speed: 1.4));
      }
      final a = analyzeGpsTrack(pts);
      expect(a.trustedCount, 300);
      expect(a.brokenLinkCount, 0);
    });
  });

  group('Q05 temporary signal loss', () {
    test(
        'a long silence over real ground is a gap: not counted, not drawn, '
        'and the Journey continues', () {
      final before = track(10);
      final after = track(10,
          seq0: 10, lat0: 50.0 + 500 / metersPerDegLat, startSec: 27 + 120);
      final pts = [...before, ...after];

      final a = analyzeGpsTrack(pts);

      expect(a.trustedCount, 20);
      expect(a.links[10], GpsLinkKind.gap);
      expect(a.brokenLinkCount, 1);
      final runs = a.trustedRuns();
      expect(runs, hasLength(2));
      expect(
          a.confirmedDistanceMeters, closeTo(along(before) + along(after), 1));
    });

    test('a long stationary pause (tiny displacement) is not a gap', () {
      final pts = [
        ...track(5),
        pt(5, 50.0 + 1.5 * 3 * 4 / metersPerDegLat + 3 / metersPerDegLat, 30.0,
            300,
            acc: 5, speed: 0.2),
      ];
      final a = analyzeGpsTrack(pts);
      expect(a.brokenLinkCount, 0);
      expect(a.links[5], GpsLinkKind.connected);
    });

    test('signal returning near the last good point continues the track', () {
      final pts = [
        ...track(10),
        // 15 unusable samples
        for (var i = 0; i < 15; i++)
          pt(10 + i, 50.0, 30.0, 30 + 3.0 * i, acc: 38946),
        ...track(10,
            seq0: 25,
            lat0: 50.0 + 1.5 * 3 * 9 / metersPerDegLat + 8 / metersPerDegLat,
            startSec: 80),
      ];
      final a = analyzeGpsTrack(pts);
      expect(a.lowAccuracyCount, 15);
      expect(a.trustedCount, 20);
      expect(a.trustedRuns(), hasLength(1));
      expect(a.brokenLinkCount, 0);
    });
  });

  group('Q06 raw points and time handling', () {
    test('the analysis never changes or reorders its input', () {
      final pts = track(30);
      pts[7] = pt(7, 12.0, 12.0, 21, acc: 40300);
      final snapshot = List<LocalRoutePoint>.of(pts);

      final a = analyzeGpsTrack(pts);

      expect(pts, snapshot);
      expect(a.verdicts, hasLength(pts.length));
      expect(a.links, hasLength(pts.length));
      expect(a.excludedCount, 1);
    });

    test('a non-increasing timestamp is a discontinuity, never distance', () {
      final pts = [
        pt(0, 50.0, 30.0, 0, speed: 1),
        pt(1, 50.0001, 30.0, 3, speed: 1),
        pt(2, 50.0002, 30.0, 3, speed: 1), // same instant
        pt(3, 50.0003, 30.0, 6, speed: 1),
      ];
      final a = analyzeGpsTrack(pts);
      expect(a.links[2], GpsLinkKind.discontinuity);
      expect(a.trustedCount, 4);
      expect(a.confirmedDistanceMeters, closeTo(11.1 + 11.1, 1));
    });

    test('a clean track equals the plain sum of segment distances', () {
      final pts = track(200, mps: 1.4);
      var plain = 0.0;
      for (var i = 1; i < pts.length; i++) {
        plain += Geolocator.distanceBetween(pts[i - 1].latitude,
            pts[i - 1].longitude, pts[i].latitude, pts[i].longitude);
      }
      expect(
          analyzeGpsTrack(pts).confirmedDistanceMeters, closeTo(plain, 1e-6));
    });

    test('empty and single-point inputs are safe', () {
      expect(analyzeGpsTrack(const []).confirmedDistanceMeters, 0);
      final one = analyzeGpsTrack(track(1));
      expect(one.trustedCount, 1);
      expect(one.trustedRuns().single, hasLength(1));
    });
  });

  group('Q07 Journey statistics use the confirmed track', () {
    List<LocalRouteEvent> events(num finish) => [
          LocalRouteEvent(
              recordedRouteId: 'r1',
              seq: 1,
              ownerId: 'owner-1',
              eventType: RouteEventType.start,
              occurredAt: s(0)),
          LocalRouteEvent(
              recordedRouteId: 'r1',
              seq: 2,
              ownerId: 'owner-1',
              eventType: RouteEventType.finish,
              occurredAt: s(finish)),
        ];

    test('the incident: 15 km fake distance and 56 m/s max speed are gone', () {
      final walk = track(26, acc: 100, mps: 0.8, cadence: 10);
      final fake = [
        for (var i = 0; i < 100; i++)
          pt(26 + i, -12.0 + 56 * 2 * i / metersPerDegLat, -77.0, 251 + 2 * i,
              acc: 3, speed: 56),
      ];
      final stats = calculateGpsJourneyStatistics(
        points: [...walk, ...fake],
        events: events(500),
        now: s(500),
      );

      expect(stats.totalDistanceMeters, closeTo(along(walk), 1));
      expect(stats.maxSpeedMps, 0.8);
      expect(stats.excludedPointCount, 100);
      expect(stats.trackGapCount, 0);
    });

    test('a clean 247-point walk is unchanged', () {
      final pts = track(247, mps: 1.4);
      final stats = calculateGpsJourneyStatistics(
        points: pts,
        events: events(800),
        now: s(800),
      );
      expect(stats.totalDistanceMeters, closeTo(along(pts), 1));
      expect(stats.excludedPointCount, 0);
      expect(stats.maxSpeedMps, 1.4);
    });
  });

  group('Q08 Replay follows the same rules', () {
    LocalRecordedRoute route() => LocalRecordedRoute(
          id: 'r1',
          ownerId: 'owner-1',
          transportMode: 'walking',
          status: RecordedRouteStatus.completed,
          visibility: 'private',
          startedAt: t0,
          createdAt: t0,
          updatedAt: t0,
          syncStatus: RouteSyncStatus.synced,
        );

    List<LocalRouteEvent> events(num finish) => [
          LocalRouteEvent(
              recordedRouteId: 'r1',
              seq: 1,
              ownerId: 'owner-1',
              eventType: RouteEventType.start,
              occurredAt: s(0)),
          LocalRouteEvent(
              recordedRouteId: 'r1',
              seq: 2,
              ownerId: 'owner-1',
              eventType: RouteEventType.finish,
              occurredAt: s(finish)),
        ];

    GpsReplayTimeline build(List<LocalRoutePoint> pts, num finish) =>
        GpsReplayTimeline.build(
            route: route(),
            points: pts,
            events: events(finish),
            now: s(100000),
            confirmTrack: true);

    test('unconfirmed far samples are not replayed; the marker is held', () {
      final walk = track(26, acc: 100, mps: 0.8, cadence: 10);
      final fake = [
        for (var i = 0; i < 100; i++)
          pt(26 + i, -12.0 + 56 * 2 * i / metersPerDegLat, -77.0, 251 + 2 * i,
              acc: 3, speed: 56),
      ];
      final tl = build([...walk, ...fake], 500);

      expect(tl.sampleCount, 26);
      expect(tl.diagnostics.unreliablePoints, 100);
      expect(tl.runs, hasLength(1));
      final late = tl.positionAt(const Duration(seconds: 400));
      expect(late.kind, GpsReplayPositionKind.held);
      expect(late.latitude, closeTo(walk.last.latitude, 1e-9));
      expect(late.longitude, closeTo(30.0, 1e-9));
    });

    test('a long signal gap splits the runs; no line bridges it', () {
      final before = track(10);
      final after = track(10,
          seq0: 10, lat0: 50.0 + 500 / metersPerDegLat, startSec: 27 + 120);
      final tl = build([...before, ...after], 200);

      expect(tl.sampleCount, 20);
      expect(tl.runs, hasLength(2));
      expect(tl.runs[1].gapBefore, GpsReplayGapKind.impossibleJump);
      expect(tl.diagnostics.unreliablePoints, 0);
      // Inside the silence the marker stays where it last was.
      final inside = tl.positionAt(const Duration(seconds: 60));
      expect(inside.kind, GpsReplayPositionKind.held);
      expect(inside.latitude, closeTo(before.last.latitude, 1e-9));
    });

    test('a clean route replays exactly as before (one run, no exclusions)',
        () {
      final tl = build(track(100, mps: 1.4), 400);
      expect(tl.sampleCount, 100);
      expect(tl.runs, hasLength(1));
      expect(tl.diagnostics.unreliablePoints, 0);
      expect(tl.diagnostics.discontinuousSegments, 0);
    });
  });
}
