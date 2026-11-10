import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';

/// Journey Phase 1I-A -- a 50 000-point Journey. Correctness is proven with
/// an INDEPENDENT analytic oracle (the fixture is a straight walk whose
/// latitude is a closed-form function of active time), never with the
/// timeline's own internals. Timings and memory are printed as observations,
/// not asserted: wall-clock assertions would be flaky evidence.
void main() {
  const owner = 'owner-1';
  const routeId = 'r1';
  const pointCount = 50000;
  const pauseEvery = 5000;
  const pauseSeconds = 90;
  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime s(num seconds) =>
      t0.add(Duration(microseconds: (seconds * 1000000).round()));

  // Sample i (0-based) is recorded 2 s of ACTIVE time after sample i-1, at
  // latitude 50 + 2e-5 * (i + 1), i.e. latitude = 50 + 1e-5 * activeSeconds
  // (~1.1 m/s). Before sample i = 5000, 10000, ... the Journey is paused for
  // 90 s, so the segment (i-1 -> i) contains a pause.
  late List<LocalRoutePoint> points;
  late List<LocalRouteEvent> log;
  late List<LocalWaypoint> moments;
  late List<LocalJourneyMediaItem> media;
  late int pauseCount;
  late double wallEnd;

  double lat(int i) => 50 + 2e-5 * (i + 1);

  setUpAll(() {
    var seq = 1;
    var wall = 0.0;
    pauseCount = 0;
    points = [];
    moments = [];
    media = [];
    log = [
      LocalRouteEvent(
          recordedRouteId: routeId,
          seq: seq++,
          ownerId: owner,
          eventType: RouteEventType.start,
          occurredAt: s(0)),
    ];
    LocalRouteEvent event(String type, double at) => LocalRouteEvent(
        recordedRouteId: routeId,
        seq: seq++,
        ownerId: owner,
        eventType: type,
        occurredAt: s(at));
    for (var i = 0; i < pointCount; i++) {
      if (i > 0 && i % pauseEvery == 0) {
        log.add(event(RouteEventType.pause, wall));
        wall += pauseSeconds;
        log.add(event(RouteEventType.resume, wall));
        pauseCount++;
      }
      wall += 2;
      points.add(LocalRoutePoint(
        recordedRouteId: routeId,
        seq: i + 1,
        ownerId: owner,
        latitude: lat(i),
        longitude: 30.0,
        recordedAt: s(wall),
      ));
      if (i % 25 == 0) {
        moments.add(LocalWaypoint(
          id: 'm$i',
          recordedRouteId: routeId,
          ownerId: owner,
          waypointType: 'custom',
          latitude: lat(i),
          longitude: 30.0,
          recordedAt: s(wall),
          createdAt: s(wall),
          updatedAt: s(wall),
          syncStatus: WaypointSyncStatus.synced,
        ));
        media.add(LocalJourneyMediaItem(
          id: 'p$i',
          ownerId: owner,
          recordedRouteId: routeId,
          waypointId: i % 50 == 0 ? 'm$i' : null,
          mediaType: JourneyMediaType.image,
          capturedAt: s(wall + 0.5),
          localRelativePath: 'journey_media/$routeId/p$i.jpg',
          syncStatus: JourneyMediaSyncStatus.synced,
          createdAt: s(wall),
          updatedAt: s(wall),
        ));
      }
    }
    wall += 2;
    wallEnd = wall;
    log.add(event(RouteEventType.finish, wall));
  });

  GpsReplayTimeline buildTimeline() => GpsReplayTimeline.build(
        route: LocalRecordedRoute(
          id: routeId,
          ownerId: owner,
          transportMode: 'walking',
          status: RecordedRouteStatus.completed,
          visibility: 'private',
          startedAt: t0,
          createdAt: t0,
          updatedAt: t0,
          syncStatus: RouteSyncStatus.synced,
        ),
        points: points,
        events: log,
        moments: moments,
        media: media,
        now: s(10000000),
      );

  test('X01 a 50 000-point Journey: build once, then correct lookups', () {
    final rssBefore = ProcessInfo.currentRss;
    final build = Stopwatch()..start();
    final tl = buildTimeline();
    build.stop();
    final rssAfter = ProcessInfo.currentRss;

    final activeSeconds = 2 * pointCount + 2;
    expect(tl.sampleCount, pointCount);
    expect(tl.activeDuration, Duration(seconds: activeSeconds));
    expect(tl.pausedDuration, Duration(seconds: pauseCount * pauseSeconds));
    expect(tl.elapsed, Duration(microseconds: (wallEnd * 1000000).round()));
    expect(tl.isConsistentWithStatistics, isTrue);
    expect(pauseCount, 9);
    expect(tl.diagnostics.pauseGapSegments, pauseCount);
    expect(tl.diagnostics.discontinuousSegments, pauseCount);
    expect(tl.diagnostics.invalidCoordinatePoints, 0);

    // Oracle: random playback instants (microsecond precision).
    final random = Random(20260101);
    final totalMicros = activeSeconds * 1000000;
    // Random.nextInt is capped at 2^32; the axis is ~1e11 microseconds.
    int pick(int max) =>
        (random.nextDouble() * (max + 1)).floor().clamp(0, max);
    var interpolated = 0;
    var held = 0;
    var exact = 0;
    final lookups = Stopwatch()..start();
    for (var n = 0; n < 20000; n++) {
      final micros = pick(totalMicros);
      final p = tl.positionAt(Duration(microseconds: micros));
      expect(p.playbackTime.inMicroseconds, micros);
      final k = micros ~/ 2000000;
      if (k < 1) {
        expect(p.kind, GpsReplayPositionKind.leading);
        expect(p.latitude, lat(0));
      } else if (micros % 2000000 == 0 && k <= pointCount) {
        exact++;
        expect(p.kind, GpsReplayPositionKind.exact);
        expect(p.latitude, lat(k - 1));
      } else {
        final i = k - 1; // the sample at or before this instant
        final lastSample = i >= pointCount - 1;
        final spansPause = !lastSample && (i + 1) % pauseEvery == 0;
        if (lastSample || spansPause) {
          held++;
          expect(p.kind, GpsReplayPositionKind.held, reason: '$micros');
          expect(p.latitude, lat(i), reason: '$micros');
        } else {
          interpolated++;
          expect(p.kind, GpsReplayPositionKind.interpolated, reason: '$micros');
          expect(p.latitude, closeTo(50 + 1e-5 * micros / 1e6, 1e-9),
              reason: '$micros');
        }
      }
      expect(p.longitude, 30.0);
    }
    lookups.stop();
    expect(interpolated, greaterThan(15000));
    expect(held, greaterThan(0));
    expect(exact, greaterThanOrEqualTo(0));

    // Every sample boundary is reported exactly.
    for (var i = 0; i < pointCount; i += 7) {
      final p = tl.positionAt(Duration(seconds: 2 * (i + 1)));
      expect(p.kind, GpsReplayPositionKind.exact, reason: 'sample $i');
      expect(p.latitude, lat(i));
    }

    // Clock round trip away from the flat (paused) stretches.
    for (var n = 0; n < 2000; n++) {
      final micros = 1 + pick(totalMicros - 2);
      final wall =
          tl.recordedTimeAtPlaybackTime(Duration(microseconds: micros))!;
      final back = tl.playbackTimeAtRecordedTime(wall).inMicroseconds;
      expect((back - micros).abs(), lessThanOrEqualTo(1), reason: '$micros');
    }

    // Marker preprocessing: 2 002 Moments / photo markers, binary search
    // agrees with a brute-force count.
    expect(
        tl.markers.length, moments.length + media.length - (media.length ~/ 2));
    var last = Duration.zero;
    for (final m in tl.markers) {
      expect(m.playbackTime >= last, isTrue);
      last = m.playbackTime;
    }
    for (var n = 0; n < 300; n++) {
      final t = Duration(microseconds: pick(totalMicros));
      final brute = tl.markers.where((m) => m.playbackTime <= t).length;
      expect(tl.reachedMarkerCount(t), brute);
    }

    // Observations (not assertions).
    final perLookupNs = lookups.elapsedMicroseconds * 1000 / 20000;
    // ignore: avoid_print
    print('REPLAY_PERF points=$pointCount '
        'build_ms=${build.elapsedMilliseconds} '
        'lookups=20000 lookup_total_ms=${lookups.elapsedMilliseconds} '
        'avg_ns_per_lookup_incl_oracle=${perLookupNs.round()} '
        'rss_delta_mb=${((rssAfter - rssBefore) / 1048576).toStringAsFixed(1)} '
        'typed_array_bytes=${pointCount * (8 + 8 + 8 + 8 + 1)}');
  });

  test(
      'X03 the same 50 000-point Journey with injected timestamp anomalies: '
      'rejected, nothing bridged, every other lookup still matches the oracle',
      () {
    // Extra samples (bogus position, bogus time) slipped in after sample
    // indexes: past the finish, and as in-window future spikes.
    const afterFinish = [1000, 20000, 40000];
    const spikes = [10000, 30000];
    var extraSeq = 900000;
    final injected = <LocalRoutePoint>[];
    for (var i = 0; i < pointCount; i++) {
      injected.add(points[i]);
      if (afterFinish.contains(i)) {
        injected.add(LocalRoutePoint(
            recordedRouteId: routeId,
            seq: extraSeq++,
            ownerId: owner,
            latitude: 0.0,
            longitude: 0.0,
            recordedAt: s(wallEnd + 100)));
      }
      if (spikes.contains(i)) {
        injected.add(LocalRoutePoint(
            recordedRouteId: routeId,
            seq: extraSeq++,
            ownerId: owner,
            latitude: 10.0,
            longitude: 10.0,
            recordedAt:
                points[i].recordedAt.add(const Duration(seconds: 5000))));
      }
    }
    final brokenAfter = {...afterFinish, ...spikes};

    final build = Stopwatch()..start();
    final tl = GpsReplayTimeline.build(
      route: LocalRecordedRoute(
        id: routeId,
        ownerId: owner,
        transportMode: 'walking',
        status: RecordedRouteStatus.completed,
        visibility: 'private',
        startedAt: t0,
        createdAt: t0,
        updatedAt: t0,
        syncStatus: RouteSyncStatus.synced,
      ),
      points: injected,
      events: log,
      now: s(10000000),
    );
    build.stop();

    expect(tl.sampleCount, pointCount);
    expect(tl.isConsistentWithStatistics, isTrue);
    expect(tl.diagnostics.outsideFinishPoints, afterFinish.length);
    expect(tl.diagnostics.futureSpikePoints, spikes.length);
    expect(tl.diagnostics.outOfOrderPoints, 0);
    expect(tl.diagnostics.invalidCoordinatePoints, 0);
    expect(tl.diagnostics.pauseGapSegments, pauseCount);
    expect(tl.diagnostics.otherGapSegments, brokenAfter.length);
    expect(tl.diagnostics.impossibleJumpSegments, 0);

    final random = Random(77);
    final totalMicros = (2 * pointCount + 2) * 1000000;
    int pick(int max) =>
        (random.nextDouble() * (max + 1)).floor().clamp(0, max);
    for (var n = 0; n < 20000; n++) {
      final micros = pick(totalMicros);
      final p = tl.positionAt(Duration(microseconds: micros));
      final k = micros ~/ 2000000;
      if (k < 1) {
        expect(p.kind, GpsReplayPositionKind.leading);
        continue;
      }
      final i = k - 1;
      if (micros % 2000000 == 0 && k <= pointCount) {
        expect(p.kind, GpsReplayPositionKind.exact);
        expect(p.latitude, lat(i));
      } else {
        final lastSample = i >= pointCount - 1;
        final spansPause = !lastSample && (i + 1) % pauseEvery == 0;
        if (lastSample || spansPause || brokenAfter.contains(i)) {
          expect(p.kind, GpsReplayPositionKind.held, reason: '$micros');
          expect(p.latitude, lat(i), reason: '$micros');
        } else {
          expect(p.kind, GpsReplayPositionKind.interpolated, reason: '$micros');
          expect(p.latitude, closeTo(50 + 1e-5 * micros / 1e6, 1e-9));
        }
      }
      // A rejected sample's position can never surface.
      expect(p.latitude, greaterThan(49.9));
      expect(p.longitude, 30.0);
    }
    // The held stretch right after each injection point is exactly held.
    for (final i in brokenAfter) {
      final p =
          tl.positionAt(Duration(microseconds: (2 * (i + 1) + 1) * 1000000));
      expect(p.kind, GpsReplayPositionKind.held, reason: 'after sample $i');
      expect(p.latitude, lat(i));
    }
    // ignore: avoid_print
    print('REPLAY_PERF_ANOMALIES points=${injected.length} '
        'build_ms=${build.elapsedMilliseconds}');
  });

  test('X02 positionAt does no per-call scan or copy (structural check)', () {
    final source = File('lib/features/gps/replay/gps_journey_replay.dart')
        .readAsStringSync();
    final start = source.indexOf('GpsReplayPosition positionAt(');
    final end = source.indexOf('int reachedMarkerCount(');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    for (final banned in [
      'for (',
      'while (',
      '.toList(',
      '.sublist(',
      '.where(',
      '.map(',
      'List.from',
      'List<',
    ]) {
      expect(body.contains(banned), isFalse, reason: 'positionAt: $banned');
    }
    expect(body.contains('_upperBound('), isTrue);
  });
}
