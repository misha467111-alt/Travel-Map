import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';

/// Journey Phase 0 -- server-parity coverage for the pure, offline-first
/// Journey statistics calculator. Every fixture here is deliberately
/// built to mirror the exact semantics `finalize_recorded_route(uuid)`
/// uses (`supabase/migrations/202609140002_trips_gps_core.sql`) -- see
/// `gps_journey_statistics.dart`'s own doc comments for the one-to-one
/// mapping and the two documented, unavoidable local/server differences
/// (distance formula, no PostGIS geometry output).
void main() {
  final t0 = DateTime.utc(2026, 1, 1, 10);

  LocalRoutePoint point({
    required int seq,
    required double lat,
    required double lng,
    double? altitude,
    double? speed,
    required DateTime at,
  }) =>
      LocalRoutePoint(
        recordedRouteId: 'r1',
        seq: seq,
        ownerId: 'owner-1',
        latitude: lat,
        longitude: lng,
        altitude: altitude,
        speed: speed,
        recordedAt: at,
      );

  LocalRouteEvent event(String type, DateTime at, {int seq = 1}) =>
      LocalRouteEvent(
        recordedRouteId: 'r1',
        seq: seq,
        ownerId: 'owner-1',
        eventType: type,
        occurredAt: at,
      );

  group('S01-S04 distance over points', () {
    test('S01 zero points: distance 0, moving = elapsed, avg speed 0', () {
      final stats = calculateGpsJourneyStatistics(
        points: const [],
        events: [event(RouteEventType.start, t0)],
        now: t0.add(const Duration(minutes: 10)),
      );

      expect(stats.totalDistanceMeters, 0);
      expect(stats.elapsed, const Duration(minutes: 10));
      expect(stats.paused, Duration.zero);
      expect(stats.moving, const Duration(minutes: 10));
      expect(stats.averageSpeedMps, 0.0);
      expect(stats.maxSpeedMps, isNull);
      expect(stats.elevationGainMeters, 0);
      expect(stats.elevationLossMeters, 0);
      expect(stats.paceSecondsPerKilometer, isNull);
    });

    test('S02 one point: no segment, distance 0, single altitude no delta', () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(
              seq: 1,
              lat: 50.45,
              lng: 30.52,
              altitude: 100,
              speed: 2.5,
              at: t0.add(const Duration(minutes: 1))),
        ],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.finish, t0.add(const Duration(minutes: 5)),
              seq: 2),
        ],
        now: t0,
      );

      expect(stats.totalDistanceMeters, 0);
      expect(stats.maxSpeedMps, 2.5);
      expect(stats.elevationGainMeters, 0);
      expect(stats.elevationLossMeters, 0);
      expect(stats.elapsed, const Duration(minutes: 5));
    });

    test('S03 two valid points: distance matches Geolocator.distanceBetween',
        () {
      final p1 = (lat: 50.4501, lng: 30.5234);
      final p2 = (lat: 50.4510, lng: 30.5240);
      final expectedDistance =
          Geolocator.distanceBetween(p1.lat, p1.lng, p2.lat, p2.lng);

      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: p1.lat, lng: p1.lng, at: t0),
          point(
              seq: 2,
              lat: p2.lat,
              lng: p2.lng,
              at: t0.add(const Duration(seconds: 60))),
        ],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.finish, t0.add(const Duration(seconds: 60)),
              seq: 2),
        ],
        now: t0,
      );

      expect(stats.totalDistanceMeters, closeTo(expectedDistance, 0.01));
    });

    test('S04 multiple valid points: distance is the sum of each segment', () {
      final coords = [
        (lat: 50.4501, lng: 30.5234),
        (lat: 50.4505, lng: 30.5238),
        (lat: 50.4512, lng: 30.5231),
        (lat: 50.4520, lng: 30.5245),
      ];
      var expected = 0.0;
      for (var i = 1; i < coords.length; i++) {
        expected += Geolocator.distanceBetween(
            coords[i - 1].lat, coords[i - 1].lng, coords[i].lat, coords[i].lng);
      }

      final stats = calculateGpsJourneyStatistics(
        points: [
          for (final (i, c) in coords.indexed)
            point(
                seq: i + 1,
                lat: c.lat,
                lng: c.lng,
                at: t0.add(Duration(seconds: 30 * i))),
        ],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.finish,
              t0.add(Duration(seconds: 30 * (coords.length - 1))),
              seq: 2),
        ],
        now: t0,
      );

      expect(stats.totalDistanceMeters, closeTo(expected, 0.01));
    });
  });

  group('S05-S09 distance filtering (mirrors finalize_recorded_route)', () {
    test('S05 duplicate coordinate contributes ~0 distance', () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, at: t0),
          point(
              seq: 2,
              lat: 50.45,
              lng: 30.52,
              at: t0.add(const Duration(seconds: 10))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      expect(stats.totalDistanceMeters, closeTo(0, 0.001));
    });

    test('S06 zero/duplicate timestamp segment is excluded entirely', () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, at: t0),
          // Same recordedAt as the previous point but a real coordinate
          // change -- segmentSeconds == 0, must be skipped, not divide
          // by zero / produce Infinity.
          point(seq: 2, lat: 50.4501, lng: 30.5201, at: t0),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      expect(stats.totalDistanceMeters, 0);
      expect(stats.totalDistanceMeters.isFinite, isTrue);
    });

    test('S07 impossible jump above threshold is excluded', () {
      // ~200 km apart in 1 second => far above 70 m/s.
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, at: t0),
          point(
              seq: 2,
              lat: 52.0,
              lng: 31.5,
              at: t0.add(const Duration(seconds: 1))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      expect(stats.totalDistanceMeters, 0);
    });

    test(
        'S08 threshold boundary: just under 70 m/s is kept, just over is dropped',
        () {
      final a = (lat: 50.4501, lng: 30.5234);
      final b = (lat: 50.4520, lng: 30.5260);
      final segmentDistance =
          Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng);

      final underThresholdSeconds = segmentDistance / 69.9;
      final overThresholdSeconds = segmentDistance / 70.1;

      final kept = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: a.lat, lng: a.lng, at: t0),
          point(
              seq: 2,
              lat: b.lat,
              lng: b.lng,
              at: t0.add(Duration(
                  microseconds:
                      (underThresholdSeconds * Duration.microsecondsPerSecond)
                          .round()))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );
      expect(kept.totalDistanceMeters, closeTo(segmentDistance, 0.01));

      final dropped = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: a.lat, lng: a.lng, at: t0),
          point(
              seq: 2,
              lat: b.lat,
              lng: b.lng,
              at: t0.add(Duration(
                  microseconds:
                      (overThresholdSeconds * Duration.microsecondsPerSecond)
                          .round()))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );
      expect(dropped.totalDistanceMeters, 0);
    });

    test('S09 out-of-order timestamp segment is excluded, never negative-time',
        () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(
              seq: 1,
              lat: 50.4520,
              lng: 30.5260,
              at: t0.add(const Duration(seconds: 10))),
          // seq 2's recordedAt is BEFORE seq 1's -- out of order.
          point(seq: 2, lat: 50.4501, lng: 30.5234, at: t0),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      expect(stats.totalDistanceMeters, 0);
    });
  });

  group('S10-S13 pause/resume accounting', () {
    test('S10 a single pause/resume interval is subtracted from moving time',
        () {
      final stats = calculateGpsJourneyStatistics(
        points: const [],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.pause, t0.add(const Duration(minutes: 2)),
              seq: 2),
          event(RouteEventType.resume, t0.add(const Duration(minutes: 5)),
              seq: 3),
          event(RouteEventType.finish, t0.add(const Duration(minutes: 10)),
              seq: 4),
        ],
        now: t0,
      );

      expect(stats.elapsed, const Duration(minutes: 10));
      expect(stats.paused, const Duration(minutes: 3));
      expect(stats.moving, const Duration(minutes: 7));
    });

    test('S11 multiple pause intervals are all summed', () {
      final stats = calculateGpsJourneyStatistics(
        points: const [],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.pause, t0.add(const Duration(minutes: 1)),
              seq: 2),
          event(RouteEventType.resume, t0.add(const Duration(minutes: 2)),
              seq: 3),
          event(RouteEventType.pause, t0.add(const Duration(minutes: 4)),
              seq: 4),
          event(RouteEventType.resume, t0.add(const Duration(minutes: 6)),
              seq: 5),
          event(RouteEventType.finish, t0.add(const Duration(minutes: 10)),
              seq: 6),
        ],
        now: t0,
      );

      expect(stats.elapsed, const Duration(minutes: 10));
      // (2-1) + (6-4) = 1 + 2 = 3 minutes paused.
      expect(stats.paused, const Duration(minutes: 3));
      expect(stats.moving, const Duration(minutes: 7));
    });

    test(
        'S12 finish while still paused counts the trailing pause through to finish',
        () {
      final stats = calculateGpsJourneyStatistics(
        points: const [],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.pause, t0.add(const Duration(minutes: 3)),
              seq: 2),
          event(RouteEventType.finish, t0.add(const Duration(minutes: 8)),
              seq: 3),
        ],
        now: t0,
      );

      expect(stats.elapsed, const Duration(minutes: 8));
      expect(stats.paused, const Duration(minutes: 5));
      expect(stats.moving, const Duration(minutes: 3));
    });

    test('S13 no pauses: moving equals elapsed', () {
      final stats = calculateGpsJourneyStatistics(
        points: const [],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.finish, t0.add(const Duration(minutes: 20)),
              seq: 2),
        ],
        now: t0,
      );

      expect(stats.paused, Duration.zero);
      expect(stats.moving, stats.elapsed);
    });
  });

  test('S14 unfinished/active recording uses the explicit now as the boundary',
      () {
    final stats = calculateGpsJourneyStatistics(
      points: const [],
      events: [event(RouteEventType.start, t0)],
      now: t0.add(const Duration(minutes: 7)),
    );

    expect(stats.elapsed, const Duration(minutes: 7));
    expect(stats.moving, const Duration(minutes: 7));
  });

  group('S15-S17 speed', () {
    test('S15 average speed is distance over moving time', () {
      final a = (lat: 50.4501, lng: 30.5234);
      final b = (lat: 50.4520, lng: 30.5260);
      final expectedDistance =
          Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng);

      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: a.lat, lng: a.lng, at: t0),
          point(
              seq: 2,
              lat: b.lat,
              lng: b.lng,
              at: t0.add(const Duration(seconds: 100))),
        ],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.finish, t0.add(const Duration(seconds: 100)),
              seq: 2),
        ],
        now: t0,
      );

      expect(stats.averageSpeedMps, closeTo(expectedDistance / 100, 0.001));
    });

    test('S16 max speed is the maximum reported per-point speed', () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, speed: 1.2, at: t0),
          point(
              seq: 2,
              lat: 50.4501,
              lng: 30.5201,
              speed: 4.8,
              at: t0.add(const Duration(seconds: 5))),
          point(
              seq: 3,
              lat: 50.4502,
              lng: 30.5202,
              speed: 2.0,
              at: t0.add(const Duration(seconds: 10))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      expect(stats.maxSpeedMps, 4.8);
    });

    test('S17 invalid/negative speed values never corrupt max speed', () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, speed: -5, at: t0),
          point(
              seq: 2,
              lat: 50.4501,
              lng: 30.5201,
              speed: double.nan,
              at: t0.add(const Duration(seconds: 5))),
          point(
              seq: 3,
              lat: 50.4502,
              lng: 30.5202,
              speed: double.infinity,
              at: t0.add(const Duration(seconds: 10))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      expect(stats.maxSpeedMps, isNull);
      expect(stats.totalDistanceMeters.isFinite, isTrue);

      final withOneValid = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, speed: -5, at: t0),
          point(
              seq: 2,
              lat: 50.4501,
              lng: 30.5201,
              speed: 3.3,
              at: t0.add(const Duration(seconds: 5))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );
      expect(withOneValid.maxSpeedMps, 3.3);
    });
  });

  group('S18-S19 pace', () {
    test('S18 zero-distance pace is null, never NaN/Infinity', () {
      final stats = calculateGpsJourneyStatistics(
        points: const [],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.finish, t0.add(const Duration(minutes: 5)),
              seq: 2),
        ],
        now: t0,
      );

      expect(stats.paceSecondsPerKilometer, isNull);
    });

    test('S19 pace is moving seconds per kilometer', () {
      final a = (lat: 50.4501, lng: 30.5234);
      final b = (lat: 50.4520, lng: 30.5260);
      final expectedDistance =
          Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng);

      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: a.lat, lng: a.lng, at: t0),
          point(
              seq: 2,
              lat: b.lat,
              lng: b.lng,
              at: t0.add(const Duration(seconds: 100))),
        ],
        events: [
          event(RouteEventType.start, t0),
          event(RouteEventType.finish, t0.add(const Duration(seconds: 100)),
              seq: 2),
        ],
        now: t0,
      );

      final expectedPace = 100 / (expectedDistance / 1000);
      expect(stats.paceSecondsPerKilometer, closeTo(expectedPace, 0.01));
    });
  });

  group('S20-S23 elevation', () {
    test('S20 elevation gain only, ascending sequence', () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, altitude: 100, at: t0),
          point(
              seq: 2,
              lat: 50.4501,
              lng: 30.5201,
              altitude: 110,
              at: t0.add(const Duration(seconds: 10))),
          point(
              seq: 3,
              lat: 50.4502,
              lng: 30.5202,
              altitude: 125,
              at: t0.add(const Duration(seconds: 20))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      expect(stats.elevationGainMeters, closeTo(25, 0.001));
      expect(stats.elevationLossMeters, 0);
    });

    test('S21 elevation loss only, descending sequence', () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, altitude: 125, at: t0),
          point(
              seq: 2,
              lat: 50.4501,
              lng: 30.5201,
              altitude: 110,
              at: t0.add(const Duration(seconds: 10))),
          point(
              seq: 3,
              lat: 50.4502,
              lng: 30.5202,
              altitude: 100,
              at: t0.add(const Duration(seconds: 20))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      expect(stats.elevationLossMeters, closeTo(25, 0.001));
      expect(stats.elevationGainMeters, 0);
    });

    test('S22 mixed elevation: gain and loss both accumulate independently',
        () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, altitude: 100, at: t0),
          point(
              seq: 2,
              lat: 50.4501,
              lng: 30.5201,
              altitude: 120,
              at: t0.add(const Duration(seconds: 10))),
          point(
              seq: 3,
              lat: 50.4502,
              lng: 30.5202,
              altitude: 105,
              at: t0.add(const Duration(seconds: 20))),
          point(
              seq: 4,
              lat: 50.4503,
              lng: 30.5203,
              altitude: 115,
              at: t0.add(const Duration(seconds: 30))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      // +20, -15, +10
      expect(stats.elevationGainMeters, closeTo(30, 0.001));
      expect(stats.elevationLossMeters, closeTo(15, 0.001));
    });

    test('S23 missing altitude is skipped, not treated as a break in the chain',
        () {
      final stats = calculateGpsJourneyStatistics(
        points: [
          point(seq: 1, lat: 50.45, lng: 30.52, altitude: 100, at: t0),
          // No altitude -- must be skipped, not counted as a 0 or a reset.
          point(
              seq: 2,
              lat: 50.4501,
              lng: 30.5201,
              at: t0.add(const Duration(seconds: 10))),
          point(
              seq: 3,
              lat: 50.4502,
              lng: 30.5202,
              altitude: 115,
              at: t0.add(const Duration(seconds: 20))),
        ],
        events: [event(RouteEventType.start, t0)],
        now: t0,
      );

      // Delta measured from the last real altitude (100) to the next
      // real one (115) = +15, skipping straight over the null sample.
      expect(stats.elevationGainMeters, closeTo(15, 0.001));
      expect(stats.elevationLossMeters, 0);
    });
  });

  test('S24 deterministic: identical inputs always produce identical output',
      () {
    List<LocalRoutePoint> points() => [
          point(
              seq: 1,
              lat: 50.45,
              lng: 30.52,
              altitude: 100,
              speed: 1.5,
              at: t0),
          point(
              seq: 2,
              lat: 50.4501,
              lng: 30.5201,
              altitude: 105,
              speed: 2.1,
              at: t0.add(const Duration(seconds: 10))),
        ];
    List<LocalRouteEvent> events() => [
          event(RouteEventType.start, t0),
          event(RouteEventType.pause, t0.add(const Duration(seconds: 20)),
              seq: 2),
          event(RouteEventType.resume, t0.add(const Duration(seconds: 30)),
              seq: 3),
          event(RouteEventType.finish, t0.add(const Duration(seconds: 40)),
              seq: 4),
        ];

    final first = calculateGpsJourneyStatistics(
        points: points(), events: events(), now: t0);
    final second = calculateGpsJourneyStatistics(
        points: points(), events: events(), now: t0);

    expect(first.totalDistanceMeters, second.totalDistanceMeters);
    expect(first.elapsed, second.elapsed);
    expect(first.moving, second.moving);
    expect(first.paused, second.paused);
    expect(first.averageSpeedMps, second.averageSpeedMps);
    expect(first.maxSpeedMps, second.maxSpeedMps);
    expect(first.elevationGainMeters, second.elevationGainMeters);
    expect(first.elevationLossMeters, second.elevationLossMeters);
  });

  group('performance', () {
    test(
        'a many-thousand-point recording completes and yields finite, sane values',
        () {
      const n = 28800; // 8h at 1 point/sec -- the largest volume this
      // project's own architecture audit estimated as realistic.
      final points = <LocalRoutePoint>[];
      for (var i = 0; i < n; i++) {
        points.add(point(
          seq: i + 1,
          lat: 50.45 + i * 0.00001,
          lng: 30.52 + i * 0.00001,
          altitude: 100 + (i % 50).toDouble(),
          speed: 1.0 + (i % 5),
          at: t0.add(Duration(seconds: i)),
        ));
      }
      final events = [
        event(RouteEventType.start, t0),
        event(RouteEventType.finish, t0.add(Duration(seconds: n - 1)), seq: 2),
      ];

      final stopwatch = Stopwatch()..start();
      final stats = calculateGpsJourneyStatistics(
          points: points, events: events, now: t0);
      stopwatch.stop();

      expect(stats.totalDistanceMeters.isFinite, isTrue);
      expect(stats.totalDistanceMeters, greaterThan(0));
      expect(stats.elevationGainMeters.isFinite, isTrue);
      expect(stats.maxSpeedMps, isNotNull);
      // A loose, non-flaky ceiling -- this is a linear-pass calculation
      // over 28,800 points; a few seconds is an extremely generous bound
      // for CI hardware, not a tight performance assertion.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });
  });
}
