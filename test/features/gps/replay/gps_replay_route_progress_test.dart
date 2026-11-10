import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_route_progress.dart';

/// Journey Phase 1I-B1A -- route progress over the Phase 1I-B0 geometry.
void main() {
  const owner = 'owner-1';
  const routeId = 'r1';
  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime s(num seconds) =>
      t0.add(Duration(microseconds: (seconds * 1000000).round()));
  Duration sec(num seconds) =>
      Duration(microseconds: (seconds * 1000000).round());

  LocalRecordedRoute route() => LocalRecordedRoute(
        id: routeId,
        ownerId: owner,
        transportMode: 'walking',
        status: RecordedRouteStatus.completed,
        visibility: 'private',
        startedAt: t0,
        createdAt: t0,
        updatedAt: t0,
        syncStatus: RouteSyncStatus.synced,
      );

  LocalRoutePoint pt(int seq, double lat, num seconds, [double lng = 30.0]) =>
      LocalRoutePoint(
        recordedRouteId: routeId,
        seq: seq,
        ownerId: owner,
        latitude: lat,
        longitude: lng,
        recordedAt: s(seconds),
      );

  List<LocalRouteEvent> events(num finishAt,
      {List<(String, num)> between = const []}) {
    var seq = 1;
    LocalRouteEvent e(String type, num at) => LocalRouteEvent(
          recordedRouteId: routeId,
          seq: seq++,
          ownerId: owner,
          eventType: type,
          occurredAt: s(at),
        );
    return [
      e(RouteEventType.start, 0),
      for (final (type, at) in between) e(type, at),
      e(RouteEventType.finish, finishAt),
    ];
  }

  GpsReplayTimeline build(List<LocalRoutePoint> points,
          {List<LocalRouteEvent>? eventLog}) =>
      GpsReplayTimeline.build(
        route: route(),
        points: points,
        events: eventLog ?? events(100),
        now: s(100000),
      );

  // Samples (active time): s0 10, s1 15, s2 22 | pause | s3 30 | jump | s4 35,
  // s5 40 | rejected NaN | s6 50, s7 50 (duplicate) , s8 55. Axis end: 80 s.
  // Runs: [0,3) [3,4) [4,6) [6,7) [7,9).
  GpsReplayTimeline mixed() => build([
        pt(1, 50.0000, 10),
        pt(2, 50.0001, 15),
        pt(3, 50.0002, 22),
        pt(4, 50.0003, 50),
        pt(5, 51.0000, 55),
        pt(6, 51.0001, 60),
        pt(7, double.nan, 65),
        pt(8, 51.0002, 70),
        pt(9, 51.0002, 70),
        pt(10, 51.0003, 75),
      ],
          eventLog: events(100, between: [
            (RouteEventType.pause, 25),
            (RouteEventType.resume, 45),
          ]));

  void expectCursor(
    GpsReplayCursor c, {
    required int sample,
    required int runs,
    required int partial,
    required int vertices,
    required bool extends_,
    GpsReplayPositionKind? kind,
    String? reason,
  }) {
    expect(c.sampleIndex, sample, reason: 'sampleIndex $reason');
    expect(c.completedSampleCount, sample + 1, reason: reason);
    expect(c.completedRunCount, runs, reason: 'completedRunCount $reason');
    expect(c.partialRunIndex, partial, reason: 'partialRunIndex $reason');
    expect(c.partialVertexCount, vertices, reason: 'partialVertices $reason');
    expect(c.headExtendsLine, extends_, reason: 'headExtendsLine $reason');
    if (kind != null) expect(c.position.kind, kind, reason: 'kind $reason');
  }

  group('cursor', () {
    test('R01 before the first sample nothing is completed', () {
      final p = GpsReplayRouteProgress(mixed());
      for (final t in [0, 5, 9.999999]) {
        expectCursor(p.cursorAt(sec(t)),
            sample: -1,
            runs: 0,
            partial: -1,
            vertices: 0,
            extends_: false,
            kind: GpsReplayPositionKind.leading,
            reason: 't=$t');
      }
      expect(p.cursorAt(sec(5)).position.latitude, 50.0000,
          reason: 'the head waits on the first sample');
    });

    test('R02 an exact sample inside a run is a vertex; the head is on it', () {
      final p = GpsReplayRouteProgress(mixed());
      expectCursor(p.cursorAt(sec(10)),
          sample: 0,
          runs: 0,
          partial: 0,
          vertices: 1,
          extends_: false,
          kind: GpsReplayPositionKind.exact);
      expectCursor(p.cursorAt(sec(15)),
          sample: 1,
          runs: 0,
          partial: 0,
          vertices: 2,
          extends_: false,
          kind: GpsReplayPositionKind.exact);
    });

    test('R03 between two samples of one run the head extends the line', () {
      final c = GpsReplayRouteProgress(mixed()).cursorAt(sec(12.5));
      expectCursor(c,
          sample: 0,
          runs: 0,
          partial: 0,
          vertices: 1,
          extends_: true,
          kind: GpsReplayPositionKind.interpolated);
      expect(c.position.latitude, closeTo(50.00005, 1e-12));
    });

    test('R04 the last sample of a run completes it; no run is bridged', () {
      final p = GpsReplayRouteProgress(mixed());
      expectCursor(p.cursorAt(sec(22)),
          sample: 2,
          runs: 1,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.exact);
      // Inside the pause gap: held, the line does not extend to sample 3.
      expectCursor(p.cursorAt(sec(26)),
          sample: 2,
          runs: 1,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.held);
      // A single-sample run is complete the moment it is reached.
      expectCursor(p.cursorAt(sec(30)),
          sample: 3, runs: 2, partial: -1, vertices: 0, extends_: false);
      // Impossible-jump gap 3 -> 4 is never drawn.
      expectCursor(p.cursorAt(sec(32)),
          sample: 3,
          runs: 2,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.held);
    });

    test('R05 a run entered after a gap starts a new partial run', () {
      final p = GpsReplayRouteProgress(mixed());
      expectCursor(p.cursorAt(sec(35)),
          sample: 4, runs: 2, partial: 2, vertices: 1, extends_: false);
      expectCursor(p.cursorAt(sec(37)),
          sample: 4, runs: 2, partial: 2, vertices: 1, extends_: true);
      expectCursor(p.cursorAt(sec(40)),
          sample: 5, runs: 3, partial: -1, vertices: 0, extends_: false);
      // The rejected sample made 5 -> 6 a gap.
      expectCursor(p.cursorAt(sec(45)),
          sample: 5,
          runs: 3,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.held);
    });

    test('R06 duplicate playback times: the last of them is the vertex', () {
      final p = GpsReplayRouteProgress(mixed());
      final c = p.cursorAt(sec(50)); // samples 6 and 7 share 50 s
      expectCursor(c,
          sample: 7,
          runs: 4,
          partial: 4,
          vertices: 1,
          extends_: false,
          kind: GpsReplayPositionKind.exact);
      expect(c.position.latitude, 51.0002);
      expectCursor(p.cursorAt(sec(52)),
          sample: 7, runs: 4, partial: 4, vertices: 1, extends_: true);
    });

    test('R07 the end of the axis completes every run', () {
      final timeline = mixed();
      final p = GpsReplayRouteProgress(timeline);
      expectCursor(p.cursorAt(sec(55)),
          sample: 8, runs: 5, partial: -1, vertices: 0, extends_: false);
      final end = p.cursorAt(timeline.activeDuration);
      expectCursor(end,
          sample: 8,
          runs: timeline.runs.length,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.held);
      expect(end.playbackTime, timeline.activeDuration);
      // Past either end is clamped.
      expect(p.cursorAt(sec(9999)).sampleIndex, 8);
      expect(p.cursorAt(sec(9999)).playbackTime, timeline.activeDuration);
      expect(p.cursorAt(sec(-5)).sampleIndex, -1);
      expect(p.cursorAt(sec(-5)).playbackTime, Duration.zero);
    });

    test('R08 the head position is exactly timeline.positionAt', () {
      final timeline = mixed();
      final p = GpsReplayRouteProgress(timeline);
      for (var m = -1000000; m <= 85000000; m += 333333) {
        final t = Duration(microseconds: m);
        final c = p.cursorAt(t);
        final expected = timeline.positionAt(t);
        expect(c.position.kind, expected.kind, reason: 'm=$m');
        expect(c.position.latitude, expected.latitude, reason: 'm=$m');
        expect(c.position.longitude, expected.longitude, reason: 'm=$m');
        expect(c.position.recordedAt, expected.recordedAt, reason: 'm=$m');
        expect(c.sampleIndex, timeline.sampleIndexAt(t), reason: 'm=$m');
      }
    });

    test('R09 the line is never extended across a gap (sweep)', () {
      final timeline = mixed();
      final p = GpsReplayRouteProgress(timeline);
      for (var m = 0; m <= 80000000; m += 97001) {
        final c = p.cursorAt(Duration(microseconds: m));
        if (!c.headExtendsLine) continue;
        expect(c.sampleIndex, greaterThanOrEqualTo(0));
        expect(c.sampleIndex + 1, lessThan(timeline.sampleCount));
        expect(timeline.runIndexOfSample(c.sampleIndex),
            timeline.runIndexOfSample(c.sampleIndex + 1),
            reason: 'm=$m would join two runs');
        expect(c.partialRunIndex, timeline.runIndexOfSample(c.sampleIndex));
      }
    });
  });

  group('update', () {
    test('R10 forward playback reports added vertices', () {
      final p = GpsReplayRouteProgress(mixed());
      expect(p.cursor.sampleIndex, -1, reason: 'starts at playback time zero');

      var u = p.update(sec(12));
      expect(u.rewound, isFalse);
      expect(u.addedSampleCount, 1);
      expect(u.removedSampleCount, 0);
      expect(u.fromCompletedSampleCount, 0);
      expect(identical(p.cursor, u.cursor), isTrue);

      u = p.update(sec(13));
      expect(u.addedSampleCount, 0, reason: 'only the head moved');
      expect(u.rewound, isFalse);

      // The head moving BACK inside the same sample interval is not a
      // rewind: no vertex is removed.
      u = p.update(sec(12));
      expect(u.rewound, isFalse);
      expect(u.addedSampleCount, 0);
      expect(u.removedSampleCount, 0);
      u = p.update(sec(13));

      u = p.update(sec(30));
      expect(u.addedSampleCount, 3, reason: 'samples 1, 2 and 3');
      expect(u.cursor.completedSampleCount, 4);
    });

    test('R11 seeking backwards is a rewind with an exact removal count', () {
      final p = GpsReplayRouteProgress(mixed());
      p.update(sec(60));
      expect(p.cursor.completedSampleCount, 9);

      final u = p.update(sec(20));
      expect(u.rewound, isTrue);
      expect(u.addedSampleCount, 0);
      expect(u.removedSampleCount, 9 - 2);
      expectCursor(u.cursor,
          sample: 1, runs: 0, partial: 0, vertices: 2, extends_: true);

      // A rewound cursor equals a fresh one.
      final fresh = GpsReplayRouteProgress(mixed()).cursorAt(sec(20));
      expect(u.cursor.sampleIndex, fresh.sampleIndex);
      expect(u.cursor.completedRunCount, fresh.completedRunCount);
      expect(u.cursor.partialVertexCount, fresh.partialVertexCount);
    });

    test('R12 cursorAt is pure; update is the only stateful call', () {
      final p = GpsReplayRouteProgress(mixed());
      p.update(sec(40));
      final before = p.cursor;
      p.cursorAt(sec(70));
      expect(identical(p.cursor, before), isTrue);
    });

    test('R13 added + removed + unchanged always reconcile (random seeks)', () {
      final random = Random(5);
      final p = GpsReplayRouteProgress(mixed());
      var completed = 0; // a renderer starts with nothing drawn
      for (var i = 0; i < 500; i++) {
        final u = p.update(Duration(microseconds: random.nextInt(85000000)));
        completed += u.addedSampleCount - u.removedSampleCount;
        expect(completed, u.cursor.completedSampleCount);
        expect(u.addedSampleCount == 0 || u.removedSampleCount == 0, isTrue);
      }
    });
  });

  group('initial snapshot (P3-2)', () {
    // Samples AT the start instant, one of them duplicated: active time 0.
    GpsReplayTimeline atStart() => build([
          pt(1, 50.0000, 0),
          pt(2, 50.0001, 0), // duplicate timestamp
          pt(3, 50.0002, 5),
          pt(4, 50.0003, 10),
        ]);

    test('R22 the first update reports every vertex completed at t = 0', () {
      final timeline = atStart();
      final p = GpsReplayRouteProgress(timeline);
      expect(p.reportedSampleCount, 0, reason: 'nothing has been reported');
      expect(p.cursor.completedSampleCount, 2, reason: 'state at t = 0');

      final u = p.update(Duration.zero);
      expect(u.fromCompletedSampleCount, 0);
      expect(u.addedSampleCount, 2);
      expect(u.removedSampleCount, 0);
      expect([
        for (final sp in u.addedSpans)
          (sp.runIndex, sp.startIndex, sp.endIndex, sp.startsInsideRun)
      ], [
        (0, 0, 1, false),
        (1, 1, 2, false),
      ], reason: 'the duplicate starts its own run; both are reported');
      expect(p.reportedSampleCount, 2);
    });

    test('R23 later updates are relative to the first: nothing is repeated',
        () {
      final p = GpsReplayRouteProgress(atStart());
      final first = p.update(Duration.zero);
      final second = p.update(sec(5));
      final third = p.update(sec(10));

      expect(second.fromCompletedSampleCount, 2);
      expect([
        for (final sp in second.addedSpans)
          (sp.runIndex, sp.startIndex, sp.endIndex, sp.startsInsideRun)
      ], [
        (1, 2, 3, true),
      ], reason: 'appended to the existing polyline of run 1');
      expect([
        for (final sp in third.addedSpans) (sp.runIndex, sp.startIndex)
      ], [
        (1, 3),
      ]);
      final seen = <int>[
        for (final u in [first, second, third])
          for (final sp in u.addedSpans)
            for (var i = sp.startIndex; i < sp.endIndex; i++) i
      ];
      expect(seen, [0, 1, 2, 3], reason: 'every vertex once, in order');
    });

    test('R24 updating the same time twice adds nothing the second time', () {
      final p = GpsReplayRouteProgress(atStart());
      p.update(sec(5));
      final again = p.update(sec(5));
      expect(again.addedSpans, isEmpty);
      expect(again.removedSpans, isEmpty);
      expect(again.rewound, isFalse);
    });

    test('R25 resync reports the whole drawn set again from empty', () {
      final timeline = mixed();
      final p = GpsReplayRouteProgress(timeline);
      p.update(sec(60));
      expect(p.reportedSampleCount, 9);

      final u = p.resync();
      expect(u.fromCompletedSampleCount, 0);
      expect(u.addedSampleCount, 9);
      expect([
        for (final sp in u.addedSpans)
          (sp.runIndex, sp.startIndex, sp.endIndex, sp.startsInsideRun)
      ], [
        (0, 0, 3, false),
        (1, 3, 4, false),
        (2, 4, 6, false),
        (3, 6, 7, false),
        (4, 7, 9, false),
      ]);
      expect(u.cursor.playbackTime, sec(60));
      // Afterwards updates continue normally.
      final next = p.update(sec(70));
      expect(next.fromCompletedSampleCount, 9);
      expect(next.addedSpans, isEmpty);
    });

    test('R26 resync before any update equals the first update', () {
      final p = GpsReplayRouteProgress(atStart());
      final u = p.resync();
      expect(u.addedSampleCount, 2);
      expect(u.fromCompletedSampleCount, 0);
    });
  });

  group('run-aware deltas (P3-3)', () {
    List<(int, int, int, bool)> spans(List<GpsReplayRunSpan> l) => [
          for (final sp in l)
            (sp.runIndex, sp.startIndex, sp.endIndex, sp.startsInsideRun)
        ];

    test('R27 a forward jump is split at every run boundary', () {
      final p = GpsReplayRouteProgress(mixed());
      p.update(sec(12)); // sample 0 reported
      final u = p.update(sec(60));

      expect(u.rewound, isFalse);
      expect(u.removedSpans, isEmpty);
      expect(spans(u.addedSpans), [
        (0, 1, 3, true), // continues run 0
        (1, 3, 4, false), // new run after the pause gap
        (2, 4, 6, false), // new run after the impossible-jump gap
        (3, 6, 7, false), // new run after the rejected sample
        (4, 7, 9, false), // new run after the zero-length segment
      ]);
      expect(u.addedSampleCount, 8);
    });

    test('R28 a backward seek removes spans latest run first', () {
      final p = GpsReplayRouteProgress(mixed());
      p.update(sec(60));
      final u = p.update(sec(20));

      expect(u.rewound, isTrue);
      expect(u.addedSpans, isEmpty);
      expect(spans(u.removedSpans), [
        (4, 7, 9, false), // remove the whole polyline
        (3, 6, 7, false),
        (2, 4, 6, false),
        (1, 3, 4, false),
        (0, 2, 3, true), // truncate run 0 to two vertices
      ]);
      expect(u.removedSampleCount, 7);
    });

    test('R29 a rewind that stays inside one run truncates that run only', () {
      final p = GpsReplayRouteProgress(mixed());
      p.update(sec(22)); // samples 0..2
      final u = p.update(sec(11)); // sample 0 only
      expect(spans(u.removedSpans), [(0, 1, 3, true)]);
    });

    test('R30 a span never covers samples of two runs', () {
      final timeline = mixed();
      final p = GpsReplayRouteProgress(timeline);
      final random = Random(30);
      for (var i = 0; i < 400; i++) {
        final u = p.update(Duration(microseconds: random.nextInt(85000000)));
        for (final sp in [...u.addedSpans, ...u.removedSpans]) {
          expect(sp.length, greaterThan(0));
          expect(timeline.runIndexOfSample(sp.startIndex), sp.runIndex);
          expect(timeline.runIndexOfSample(sp.endIndex - 1), sp.runIndex);
        }
        expect(u.addedSpans.isEmpty || u.removedSpans.isEmpty, isTrue);
      }
    });

    test('R31 lists are unmodifiable', () {
      final p = GpsReplayRouteProgress(mixed());
      final u = p.update(sec(60));
      expect(() => u.addedSpans.clear(), throwsUnsupportedError);
      final back = p.update(sec(20));
      expect(() => back.removedSpans.clear(), throwsUnsupportedError);
    });

    test('R32 a renderer model fed only by deltas always equals the cursor',
        () {
      final timeline = mixed();
      final p = GpsReplayRouteProgress(timeline);
      final renderer = _Renderer(timeline);
      final random = Random(32);
      for (var i = 0; i < 600; i++) {
        final t = Duration(microseconds: random.nextInt(85000000));
        final u = p.update(t);
        renderer.apply(u);
        renderer.expectMatches(u.cursor, 'step $i t=$t');
      }
      // Lost drawing: resync rebuilds it from nothing.
      final lost = _Renderer(timeline);
      lost.apply(p.resync());
      lost.expectMatches(p.cursor, 'after resync');
    });

    test('R33 randomized journeys: forward, backward and jumping seeks', () {
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(seed);
        final pts = <LocalRoutePoint>[];
        var at = 0.0;
        for (var i = 0; i < 1 + random.nextInt(40); i++) {
          at += random.nextInt(4) == 0 ? 0 : random.nextDouble() * 12;
          var stamped = at;
          final roll = random.nextInt(12);
          if (roll == 0) stamped = at + 5000;
          if (roll == 1) stamped = at - random.nextDouble() * 30;
          final lat = roll == 2
              ? double.nan
              : 50 + (random.nextInt(8) == 0 ? 1.0 : 0.0) + i * 1e-5;
          pts.add(pt(i + 1, lat, stamped));
        }
        final timeline = build(pts,
            eventLog: events(300, between: [
              (RouteEventType.pause, 60),
              (RouteEventType.resume, 90),
              (RouteEventType.pause, 150),
              (RouteEventType.resume, 170),
            ]));
        final p = GpsReplayRouteProgress(timeline);
        final renderer = _Renderer(timeline);
        final end = timeline.activeDuration.inMicroseconds;
        for (var i = 0; i < 80; i++) {
          final u = p.update(Duration(
              microseconds: switch (random.nextInt(3)) {
            0 => random.nextInt(end + 1), // jump anywhere
            1 => (i * end ~/ 80), // forward sweep
            _ => end - (i * end ~/ 80), // backward sweep
          }));
          renderer.apply(u);
          renderer.expectMatches(u.cursor, 'seed $seed step $i');
        }
        if (random.nextBool()) {
          final lost = _Renderer(timeline)..apply(p.resync());
          lost.expectMatches(p.cursor, 'seed $seed resync');
        }
      }
    });
  });

  group('edge routes', () {
    test('R14 a route without samples has a head-less, empty cursor', () {
      final p = GpsReplayRouteProgress(build(const []));
      for (final t in [0, 30, 100]) {
        final c = p.cursorAt(sec(t));
        expectCursor(c,
            sample: -1,
            runs: 0,
            partial: -1,
            vertices: 0,
            extends_: false,
            kind: GpsReplayPositionKind.unavailable);
        expect(c.position.hasCoordinates, isFalse);
      }
    });

    test('R15 a single-sample route', () {
      final p = GpsReplayRouteProgress(build([pt(1, 50.0, 10)]));
      expectCursor(p.cursorAt(sec(5)),
          sample: -1,
          runs: 0,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.leading);
      expectCursor(p.cursorAt(sec(10)),
          sample: 0,
          runs: 1,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.exact);
      expectCursor(p.cursorAt(sec(90)),
          sample: 0,
          runs: 1,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.held);
    });

    test('R16 a Journey without a start event has no axis and no cursor data',
        () {
      final p = GpsReplayRouteProgress(build([
        pt(1, 50.0, 10)
      ], eventLog: [
        LocalRouteEvent(
            recordedRouteId: routeId,
            seq: 1,
            ownerId: owner,
            eventType: RouteEventType.finish,
            occurredAt: s(100)),
      ]));
      final c = p.cursorAt(sec(10));
      expect(c.sampleIndex, -1);
      expect(c.completedRunCount, 0);
      expect(c.headExtendsLine, isFalse);
    });

    test('R17 rejected spikes and after-finish points are not vertices', () {
      final timeline = build([
        pt(1, 50.0000, 10),
        pt(2, 50.5000, 5000), // after the finish at 100 s
        pt(3, 50.0002, 30),
        pt(4, 50.0003, 40),
      ]);
      final p = GpsReplayRouteProgress(timeline);
      expect(timeline.sampleCount, 3);
      final c = p.cursorAt(sec(35));
      expect(c.sampleIndex, 1);
      for (var m = 0; m <= 100000000; m += 250000) {
        expect(p.cursorAt(Duration(microseconds: m)).position.latitude,
            isNot(50.5));
      }
      // The rejected sample is a gap: 10 s -> 30 s is not bridged.
      expectCursor(p.cursorAt(sec(20)),
          sample: 0,
          runs: 1,
          partial: -1,
          vertices: 0,
          extends_: false,
          kind: GpsReplayPositionKind.held);
    });
  });

  group('randomized', () {
    test('R18 cursors equal a brute-force reading of the geometry', () {
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(seed);
        final pts = <LocalRoutePoint>[];
        var at = 0.0;
        for (var i = 0; i < 1 + random.nextInt(40); i++) {
          at += random.nextInt(4) == 0 ? 0 : random.nextDouble() * 12;
          var stamped = at;
          final roll = random.nextInt(12);
          if (roll == 0) stamped = at + 5000;
          if (roll == 1) stamped = at - random.nextDouble() * 30;
          final lat = roll == 2
              ? double.nan
              : 50 + (random.nextInt(8) == 0 ? 1.0 : 0.0) + i * 1e-5;
          pts.add(pt(i + 1, lat, stamped));
        }
        final timeline = build(pts,
            eventLog: events(300, between: [
              (RouteEventType.pause, 60),
              (RouteEventType.resume, 90),
              (RouteEventType.pause, 150),
              (RouteEventType.resume, 170),
            ]));
        final progress = GpsReplayRouteProgress(timeline);
        final end = timeline.activeDuration.inMicroseconds;
        for (var k = 0; k <= 80; k++) {
          final t = Duration(microseconds: -500000 + k * (end + 1000000) ~/ 80);
          final clamped = t.isNegative
              ? Duration.zero
              : (t > timeline.activeDuration ? timeline.activeDuration : t);
          var completed = 0;
          for (var i = 0; i < timeline.sampleCount; i++) {
            if (timeline.playbackTimeAt(i) <= clamped) completed = i + 1;
          }
          var fullRuns = 0;
          var partial = -1;
          var vertices = 0;
          for (var r = 0; r < timeline.runs.length; r++) {
            final run = timeline.runs[r];
            if (run.endIndex <= completed) {
              fullRuns++;
            } else if (run.startIndex < completed) {
              partial = r;
              vertices = completed - run.startIndex;
            }
          }
          final c = progress.cursorAt(t);
          final why = 'seed $seed k $k';
          expect(c.completedSampleCount, completed, reason: why);
          expect(c.completedRunCount, fullRuns, reason: why);
          expect(c.partialRunIndex, partial, reason: why);
          expect(c.partialVertexCount, vertices, reason: why);
          expect(c.playbackTime, clamped, reason: why);
          if (c.headExtendsLine) {
            expect(c.partialRunIndex, isNot(-1), reason: why);
            expect(c.sampleIndex + 1, lessThan(timeline.sampleCount));
            expect(timeline.runIndexOfSample(c.sampleIndex),
                timeline.runIndexOfSample(c.sampleIndex + 1),
                reason: why);
          }
        }
      }
    });
  });

  group('structure', () {
    test('R19 a lookup does no scan or copy of the route (structural)', () {
      final source =
          File('lib/features/gps/replay/gps_replay_route_progress.dart')
              .readAsStringSync();
      final start = source.indexOf('GpsReplayCursor cursorAt(');
      final end = source.indexOf('GpsReplayProgressUpdate update(');
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
        '.latitudeAt(',
      ]) {
        expect(body.contains(banned), isFalse, reason: 'cursorAt: $banned');
      }
      expect(body.contains('sampleIndexAt('), isTrue);
      expect(body.contains('positionAt('), isTrue);
    });

    test('R20 the component is pure Dart: no Flutter, timers or maps', () {
      final code =
          File('lib/features/gps/replay/gps_replay_route_progress.dart')
              .readAsLinesSync()
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n');
      for (final banned in [
        'package:flutter',
        'google_maps',
        'dart:async',
        'dart:io',
        'dart:ui',
        'Timer',
        'Stream',
        'Future',
        'Isolate',
        'DateTime.now',
        'Polyline',
        'LatLng',
      ]) {
        expect(code.contains(banned), isFalse, reason: banned);
      }
    });
  });

  test('R21 a 50 000-point Journey: closed-form cursors, sweeps both ways', () {
    const count = 50000;
    const pauseEvery = 5000;
    final between = <(String, num)>[];
    final points = <LocalRoutePoint>[];
    var wall = 0.0;
    for (var i = 0; i < count; i++) {
      if (i > 0 && i % pauseEvery == 0) {
        between.add((RouteEventType.pause, wall));
        wall += 90;
        between.add((RouteEventType.resume, wall));
      }
      wall += 2;
      points.add(pt(i + 1, 50 + 2e-5 * (i + 1), wall));
    }
    final timeline =
        build(points, eventLog: events(wall + 2, between: between));
    expect(timeline.sampleCount, count);

    final progress = GpsReplayRouteProgress(timeline);
    // Sample i is at active time 2 * (i + 1) s.
    void check(int micros) {
      final c = progress.cursorAt(Duration(microseconds: micros));
      final completed = (micros ~/ 2000000).clamp(0, count);
      expect(c.completedSampleCount, completed, reason: '$micros');
      expect(c.completedRunCount, completed ~/ pauseEvery, reason: '$micros');
      final inside = completed % pauseEvery;
      expect(c.partialRunIndex, inside == 0 ? -1 : completed ~/ pauseEvery,
          reason: '$micros');
      expect(c.partialVertexCount, inside, reason: '$micros');
    }

    final random = Random(99);
    final total = (2 * count + 2) * 1000000;
    final sw = Stopwatch()..start();
    for (var n = 0; n < 20000; n++) {
      check((random.nextDouble() * (total + 1)).floor());
    }
    final oracleMs = sw.elapsedMilliseconds;

    // Forward sweep then backward sweep: vertices added == removed.
    final bare = GpsReplayRouteProgress(timeline);
    var added = 0;
    var removed = 0;
    const steps = 20000;
    final sweep = Stopwatch()..start();
    for (var k = 0; k <= steps; k++) {
      final u = bare.update(Duration(microseconds: k * total ~/ steps));
      added += u.addedSampleCount;
      removed += u.removedSampleCount;
    }
    final forwardMs = sweep.elapsedMilliseconds;
    expect(added, count);
    expect(removed, 0);
    for (var k = steps; k >= 0; k--) {
      final u = bare.update(Duration(microseconds: k * total ~/ steps));
      added += u.addedSampleCount;
      removed += u.removedSampleCount;
    }
    expect(added, count);
    expect(removed, count);
    expect(bare.cursor.sampleIndex, -1);

    // ignore: avoid_print
    print('REPLAY_PROGRESS_PERF points=$count random_lookups=20000 '
        'oracle_ms=$oracleMs sweep_updates=${2 * steps + 2} '
        'forward_ms=$forwardMs total_ms=${sweep.elapsedMilliseconds}');
  });
}

/// A stand-in for the future map renderer: one polyline (list of sample
/// indices) per run, changed ONLY through the span deltas. It asserts the
/// contract while applying: appended spans extend an existing polyline of
/// exactly the right length, new polylines start at the run's first sample,
/// removals truncate the tail.
class _Renderer {
  _Renderer(this.timeline);

  final GpsReplayTimeline timeline;
  final Map<int, List<int>> lines = {};

  void apply(GpsReplayProgressUpdate u) {
    for (final span in u.removedSpans) {
      final run = timeline.runs[span.runIndex];
      final line = lines[span.runIndex];
      expect(line, isNotNull, reason: 'removing a polyline that is not there');
      expect(line!.length, span.endIndex - run.startIndex,
          reason: 'a removal starts at the current tail of the polyline');
      final keep = span.startIndex - run.startIndex;
      expect(span.startsInsideRun, keep > 0);
      if (keep == 0) {
        lines.remove(span.runIndex);
      } else {
        line.removeRange(keep, line.length);
      }
    }
    for (final span in u.addedSpans) {
      final run = timeline.runs[span.runIndex];
      final line = lines[span.runIndex];
      if (span.startsInsideRun) {
        expect(line, isNotNull, reason: 'appending to a missing polyline');
        expect(line!.length, span.startIndex - run.startIndex,
            reason: 'an append continues the polyline exactly');
      } else {
        expect(line, isNull, reason: 'starting a polyline that already exists');
        expect(span.startIndex, run.startIndex);
      }
      final target = line ?? (lines[span.runIndex] = <int>[]);
      for (var i = span.startIndex; i < span.endIndex; i++) {
        target.add(i);
      }
    }
  }

  void expectMatches(GpsReplayCursor c, String reason) {
    final expected = <int, List<int>>{};
    for (var r = 0; r < timeline.runs.length; r++) {
      final run = timeline.runs[r];
      final end = run.endIndex < c.completedSampleCount
          ? run.endIndex
          : c.completedSampleCount;
      if (end > run.startIndex) {
        expected[r] = [for (var i = run.startIndex; i < end; i++) i];
      }
    }
    expect(lines, expected, reason: reason);
    // Consistent with the cursor's own compact description.
    final fullRuns = lines.entries
        .where((e) => e.value.length == timeline.runs[e.key].length)
        .length;
    expect(fullRuns, c.completedRunCount, reason: reason);
    if (c.partialRunIndex >= 0) {
      expect(lines[c.partialRunIndex]!.length, c.partialVertexCount,
          reason: reason);
    }
  }
}
