import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_polyline_plan.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_route_progress.dart';

/// Journey Phase 1I-B1B-1 -- the run-aware polyline planner. A stand-in
/// renderer ([_Canvas]) is changed ONLY through the planner's output and is
/// compared with a from-scratch description of what should be drawn.
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
  // s5 40 | rejected NaN | s6 50, s7 50 (duplicate), s8 55.
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

  // n samples, 2 s apart, one continuous run; sample i is at active 2(i+1) s.
  GpsReplayTimeline walk(int n) => build([
        for (var i = 0; i < n; i++)
          pt(i + 1, 50 + 2e-5 * (i + 1), 2.0 * (i + 1)),
      ], eventLog: events(2.0 * n + 2));

  group('construction', () {
    test('P01 ids, defaults and argument checks', () {
      expect(GpsReplayPolylinePlanner.progressLineId(3, 7), 'p3_7');
      expect(GpsReplayPolylinePlanner.ghostLineId(2), 'g2');
      expect(GpsReplayPolylinePlanner.headId, 'head');
      expect(GpsReplayPolylinePlanner.defaultChunkVertexCount, 256);
      final timeline = mixed();
      expect(() => GpsReplayPolylinePlanner(timeline, chunkVertexCount: 1),
          throwsArgumentError);
      expect(() => GpsReplayPolylinePlanner(timeline, ghostToleranceMeters: 0),
          throwsArgumentError);
      expect(() => GpsReplayPolylinePlanner(timeline, ghostToleranceMeters: -3),
          throwsArgumentError);
      expect(() => GpsReplayPolylinePlanner(timeline, ghostVertexBudget: 1),
          throwsArgumentError);
      GpsReplayPolylinePlanner(timeline, chunkVertexCount: 2);
    });
  });

  group('progress chunks', () {
    test('P02 forward playback step by step: one or two chunks per update', () {
      final timeline = walk(60);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline, chunkVertexCount: 8);
      final canvas = _Canvas(timeline, 8);
      for (var i = 1; i <= 60; i++) {
        final u = progress.update(sec(2.0 * i)); // exactly sample i - 1
        final changes = planner.apply(u);
        expect(changes.removedIds, isEmpty);
        expect(changes.upserted.length, lessThanOrEqualTo(2), reason: 'i=$i');
        for (final line in changes.upserted) {
          expect(line.length, lessThanOrEqualTo(8));
          expect(line.kind, GpsReplayLineKind.progress);
        }
        canvas.apply(changes);
        canvas.expectMatches(u.cursor, 'step $i');
      }
      // 60 vertices in chunks of 8 sharing one vertex: ceil((60-1)/7) = 9.
      expect(canvas.progressIds.length, 9);
      expect(canvas.lines['p0_0']!.length, 8);
      expect(canvas.lines['p0_8']!.length, 4, reason: 'the partial last chunk');
    });

    test('P03 chunks share exactly one vertex: the line has no gap', () {
      final timeline = walk(30);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline, chunkVertexCount: 6);
      final canvas = _Canvas(timeline, 6)
        ..apply(planner.apply(progress.update(sec(100))));
      final ids = canvas.progressIds.toList()..sort(_byChunk);
      for (var k = 1; k < ids.length; k++) {
        final previous = canvas.lines[ids[k - 1]]!;
        final next = canvas.lines[ids[k]]!;
        expect(next.first, previous.last, reason: '${ids[k]} overlaps');
      }
      // Concatenated (overlap dropped) == the run's vertices.
      final all = <(double, double)>[];
      for (final id in ids) {
        all.addAll(canvas.lines[id]!.skip(all.isEmpty ? 0 : 1));
      }
      final drawn = progress.cursor.completedSampleCount;
      expect(all, [
        for (var i = 0; i < drawn; i++)
          (timeline.latitudeAt(i), timeline.longitudeAt(i))
      ]);
    });

    test('P04 a full chunk is never replaced again during forward play', () {
      final timeline = walk(100);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline, chunkVertexCount: 8);
      final upserts = <String, int>{};
      for (var i = 1; i <= 100; i++) {
        final changes = planner.apply(progress.update(sec(2.0 * i)));
        for (final line in changes.upserted) {
          upserts[line.id] = (upserts[line.id] ?? 0) + 1;
        }
      }
      // A chunk is replaced once per vertex it gains (2..8 vertices).
      for (final entry in upserts.entries) {
        expect(entry.value, lessThanOrEqualTo(7), reason: entry.key);
      }
      expect(upserts['p0_0'], 7);
    });

    test('P05 several runs: lines never mix runs; lone points draw nothing',
        () {
      final timeline = mixed();
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline, chunkVertexCount: 4);
      final changes = planner.apply(progress.update(sec(60)));
      final canvas = _Canvas(timeline, 4)..apply(changes);
      canvas.expectMatches(progress.cursor, 'all runs');

      // Runs [0,3) [4,6) [7,9) have two or more vertices; runs of ONE vertex
      // ([3,4) and [6,7)) produce no line.
      expect(canvas.progressIds.toSet(), {'p0_0', 'p2_0', 'p4_0'});
      for (final line in changes.upserted) {
        final run = timeline.runs[line.runIndex];
        expect(line.length, run.length);
      }
    });

    test('P06 a backward seek truncates and removes chunks', () {
      final timeline = walk(40);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline, chunkVertexCount: 8);
      final canvas = _Canvas(timeline, 8);
      canvas.apply(planner.apply(progress.update(sec(80)))); // 40 vertices
      expect(canvas.progressIds.length, 6);

      final back = planner.apply(progress.update(sec(20))); // 10 vertices
      expect(back.removedIds.toSet(), {'p0_2', 'p0_3', 'p0_4', 'p0_5'});
      expect(back.upserted.map((l) => l.id), ['p0_1'],
          reason: 'chunk 1 keeps vertices 7, 8 and 9');
      expect(back.upserted.single.length, 3);
      canvas.apply(back);
      canvas.expectMatches(progress.cursor, 'after rewind');

      // Back to the very start removes everything.
      final zero = planner.apply(progress.update(Duration.zero));
      canvas.apply(zero);
      expect(canvas.progressIds, isEmpty);
      canvas.expectMatches(progress.cursor, 'at zero');
    });

    test('P07 a large seek touches only the chunks it crosses', () {
      final timeline = walk(500);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline, chunkVertexCount: 16);
      final canvas = _Canvas(timeline, 16);
      canvas.apply(planner.apply(progress.update(sec(400)))); // 200 vertices
      canvas.expectMatches(progress.cursor, 'first');

      // Move 8 vertices further: at most two chunks change.
      final small = planner.apply(progress.update(sec(416)));
      expect(small.upserted.length, lessThanOrEqualTo(2));
      expect(small.removedIds, isEmpty);
      canvas.apply(small);
      canvas.expectMatches(progress.cursor, 'small step');

      // Far jump: proportionally many, and still exact.
      final far = planner.apply(progress.update(sec(980)));
      // 208 -> 490 vertices with chunks of 16 (stride 15): chunks 13..32.
      expect(far.upserted.length, 20);
      canvas.apply(far);
      canvas.expectMatches(progress.cursor, 'far jump');
    });

    test('P08 the vertices sent per update do not depend on route length', () {
      for (final n in [200, 2000, 20000]) {
        final timeline = walk(n);
        final progress = GpsReplayRouteProgress(timeline);
        final planner = GpsReplayPolylinePlanner(timeline);
        planner.apply(progress.update(sec(2.0 * (n ~/ 2))));
        var maxVertices = 0;
        for (var i = n ~/ 2 + 1; i < n ~/ 2 + 400; i++) {
          final changes = planner.apply(progress.update(sec(2.0 * i)));
          final v = changes.upserted.fold<int>(0, (a, l) => a + l.length);
          if (v > maxVertices) maxVertices = v;
        }
        expect(maxVertices, lessThanOrEqualTo(2 * 256), reason: 'n=$n');
      }
    });
  });

  group('head', () {
    test('P09 the head exists only inside a continuous run', () {
      final timeline = mixed();
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline);

      GpsReplayPolylineChanges at(num t) =>
          planner.apply(progress.update(sec(t)));

      expect(at(5).head, isNull, reason: 'before the first sample');
      expect(at(10).head, isNull, reason: 'exactly on a sample');

      final inside = at(12.5);
      expect(inside.head, isNotNull);
      expect(inside.headChanged, isTrue);
      final head = inside.head!;
      expect(head.id, 'head');
      expect(head.kind, GpsReplayLineKind.head);
      expect(head.runIndex, 0);
      expect(head.length, 2);
      expect(head.latitudeAt(0), timeline.latitudeAt(0));
      expect(head.latitudeAt(1), closeTo(50.00005, 1e-12));

      expect(at(26).head, isNull, reason: 'inside the pause gap');
      expect(at(32).head, isNull, reason: 'inside the impossible-jump gap');
      expect(at(45).head, isNull, reason: 'after the rejected sample');
      expect(at(52).head, isNotNull, reason: 'inside the last run');
      expect(at(80).head, isNull, reason: 'at the end');
    });

    test('P10 headChanged follows the head, not the chunks', () {
      final timeline = walk(20);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline);
      planner.apply(progress.update(sec(10)));

      final a = planner.apply(progress.update(sec(11))); // head appears
      expect(a.headChanged, isTrue);
      final b = planner.apply(progress.update(sec(11))); // same time again
      expect(b.headChanged, isFalse);
      expect(b.isEmpty, isTrue);
      final c = planner.apply(progress.update(sec(11.5))); // head moves
      expect(c.headChanged, isTrue);
      expect(c.upserted, isEmpty, reason: 'no new vertex completed');
      final d = planner.apply(progress.update(sec(12))); // exactly a sample
      expect(d.head, isNull);
      expect(d.headChanged, isTrue, reason: 'the head disappeared');
      expect(d.upserted.length, 1);
    });

    test('P11 the head joins the last completed vertex of the SAME run', () {
      final timeline = mixed();
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline);
      final changes = planner.apply(progress.update(sec(37)));
      final head = changes.head!;
      expect(head.runIndex, 2, reason: 'inside [4,6), after the jump gap');
      expect(head.latitudeAt(0), timeline.latitudeAt(4));
      expect(head.latitudeAt(0), isNot(timeline.latitudeAt(3)));
    });
  });

  group('contract', () {
    test('P12 an out-of-order update is rejected', () {
      final timeline = walk(20);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline);
      progress.update(sec(10)); // skipped by the planner
      final second = progress.update(sec(20));
      expect(() => planner.apply(second), throwsStateError);
    });

    test('P12b a skipped update is detected even when the next one is empty',
        () {
      final timeline = walk(20);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline);
      progress.update(sec(10)); // 5 vertices; never reaches the planner
      final headOnly = progress.update(sec(10.5)); // no new vertices
      expect(headOnly.addedSpans, isEmpty);
      expect(headOnly.removedSpans, isEmpty);
      expect(() => planner.apply(headOnly), throwsStateError,
          reason: 'the renderer would silently miss five vertices');
    });

    test('P13 reset before a resync rebuilds everything', () {
      final timeline = walk(20);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline, chunkVertexCount: 4);
      planner.apply(progress.update(sec(30)));

      final resync = progress.resync();
      expect(() => planner.apply(resync), throwsStateError,
          reason: 'the planner still remembers the old drawing');
      planner.reset();
      final canvas = _Canvas(timeline, 4); // the renderer started afresh
      canvas.apply(planner.apply(resync));
      canvas.expectMatches(progress.cursor, 'after resync');

      // And updates continue normally.
      canvas.apply(planner.apply(progress.update(sec(36))));
      canvas.expectMatches(progress.cursor, 'after resync + step');
    });

    test('P14 the first update of a fresh planner initializes from empty', () {
      final timeline = mixed();
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline);
      final changes = planner.apply(progress.update(Duration.zero));
      expect(changes.isEmpty, isTrue, reason: 'nothing is complete at 0');
    });

    test('P15 outputs are immutable lists', () {
      final timeline = walk(20);
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline);
      final changes = planner.apply(progress.update(sec(30)));
      expect(() => changes.upserted.clear(), throwsUnsupportedError);
      expect(() => changes.removedIds.add('x'), throwsUnsupportedError);
      expect(() => planner.ghostLines.clear(), throwsUnsupportedError);
    });

    test('P16 apply never scans the route (structural)', () {
      final source =
          File('lib/features/gps/replay/gps_replay_polyline_plan.dart')
              .readAsStringSync();
      final start = source.indexOf('GpsReplayPolylineChanges apply(');
      final end = source.indexOf('int _visible(');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);
      for (final banned in [
        'for (var r',
        'while (',
        '_runs.length',
        '.toList(',
        '.where(',
        '.map(',
        'timeline.runs',
        'sampleCount',
      ]) {
        expect(body.contains(banned), isFalse, reason: 'apply: $banned');
      }
    });
  });

  group('randomized', () {
    test('P17 model-based: forward, backward, jumps and resync (300 journeys)',
        () {
      for (var seed = 0; seed < 300; seed++) {
        final random = Random(seed);
        final pts = <LocalRoutePoint>[];
        var at = 0.0;
        for (var i = 0; i < 1 + random.nextInt(50); i++) {
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
        final chunk = [2, 3, 4, 8][random.nextInt(4)];
        final progress = GpsReplayRouteProgress(timeline);
        final planner =
            GpsReplayPolylinePlanner(timeline, chunkVertexCount: chunk);
        var canvas = _Canvas(timeline, chunk);
        final end = timeline.activeDuration.inMicroseconds;
        for (var i = 0; i < 70; i++) {
          final t = switch (random.nextInt(4)) {
            0 => random.nextInt(end + 1),
            1 => i * end ~/ 70,
            2 => end - i * end ~/ 70,
            _ => end ~/ 2,
          };
          final u = progress.update(Duration(microseconds: t));
          final changes = planner.apply(u);
          canvas.apply(changes);
          canvas.expectMatches(u.cursor, 'seed $seed step $i chunk $chunk');

          if (i == 35 && random.nextBool()) {
            // The renderer lost its drawing.
            planner.reset();
            canvas = _Canvas(timeline, chunk);
            final re = progress.resync();
            canvas.apply(planner.apply(re));
            canvas.expectMatches(re.cursor, 'seed $seed resync');
          }
        }
      }
    });
  });

  group('ghost route', () {
    test('P18 one line per run with two or more vertices; never joined', () {
      final timeline = mixed();
      final planner = GpsReplayPolylinePlanner(timeline);
      final ghost = planner.ghostLines;
      expect(identical(planner.ghostLines, ghost), isTrue);
      expect(ghost.map((l) => l.id), ['g0', 'g2', 'g4']);
      for (final line in ghost) {
        expect(line.kind, GpsReplayLineKind.ghost);
        final run = timeline.runs[line.runIndex];
        // Endpoints of the run are kept; every vertex is an accepted sample
        // of THAT run, in order.
        expect(line.latitudeAt(0), timeline.latitudeAt(run.startIndex));
        expect(line.latitudeAt(line.length - 1),
            timeline.latitudeAt(run.endIndex - 1));
        var cursor = run.startIndex;
        for (var k = 0; k < line.length; k++) {
          while (cursor < run.endIndex &&
              timeline.latitudeAt(cursor) != line.latitudeAt(k)) {
            cursor++;
          }
          expect(cursor < run.endIndex, isTrue, reason: '${line.id} vertex $k');
          cursor++;
        }
      }
    });

    test('P19 empty and single-sample routes have no ghost', () {
      expect(GpsReplayPolylinePlanner(build(const [])).ghostLines, isEmpty);
      expect(GpsReplayPolylinePlanner(build([pt(1, 50.0, 10)])).ghostLines,
          isEmpty);
    });

    test('P20 simplification stays within the tolerance of the original', () {
      // A wiggly track, ~1 m between samples.
      final random = Random(20);
      final pts = <LocalRoutePoint>[];
      var lat = 50.0, lng = 30.0;
      for (var i = 0; i < 3000; i++) {
        lat += (random.nextDouble() - 0.3) * 1e-5;
        lng += (random.nextDouble() - 0.5) * 1e-5;
        pts.add(pt(i + 1, lat, 2.0 * (i + 1), lng));
      }
      final timeline = build(pts, eventLog: events(7000));
      expect(timeline.runs.length, 1);
      const tolerance = 10.0;
      final planner = GpsReplayPolylinePlanner(timeline,
          ghostToleranceMeters: tolerance, ghostVertexBudget: 100000);
      final line = planner.ghostLines.single;
      expect(line.length, lessThan(3000));
      expect(line.length, greaterThan(10));
      // Every original vertex is within the tolerance of some kept vertex.
      for (var i = 0; i < timeline.sampleCount; i++) {
        var best = double.infinity;
        for (var k = 0; k < line.length; k++) {
          final d = _meters(timeline.latitudeAt(i), timeline.longitudeAt(i),
              line.latitudeAt(k), line.longitudeAt(k));
          if (d < best) best = d;
        }
        expect(best, lessThanOrEqualTo(tolerance * 1.01), reason: 'vertex $i');
      }
    });

    test('P21 the vertex budget coarsens the ghost until it fits', () {
      final timeline = walk(5000); // a straight ~11 km walk, 2.2 m spacing
      final loose = GpsReplayPolylinePlanner(timeline,
          ghostToleranceMeters: 1, ghostVertexBudget: 100000);
      final tight = GpsReplayPolylinePlanner(timeline,
          ghostToleranceMeters: 1, ghostVertexBudget: 100);
      expect(loose.ghostLines.single.length, greaterThan(1000));
      expect(tight.ghostLines.single.length, lessThanOrEqualTo(100));
      expect(tight.ghostLines.single.length, greaterThanOrEqualTo(2));
      expect(tight.ghostLines.single.latitudeAt(0), timeline.latitudeAt(0));
      expect(
          tight.ghostLines.single
              .latitudeAt(tight.ghostLines.single.length - 1),
          timeline.latitudeAt(4999));
    });

    test('P22 the budget is soft: every run keeps its two endpoints', () {
      final timeline = mixed();
      final planner = GpsReplayPolylinePlanner(timeline, ghostVertexBudget: 2);
      expect(planner.ghostLines.length, 3);
      for (final line in planner.ghostLines) {
        expect(line.length, greaterThanOrEqualTo(2));
      }
    });

    test('P23 a run crossing the antimeridian is measured the short way', () {
      // ~1 m apart across 180 degrees: a naive longitude difference would
      // see 360 degrees and keep every vertex.
      final pts = <LocalRoutePoint>[
        for (var i = 0; i < 200; i++)
          pt(i + 1, 10.0, 2.0 * (i + 1), _wrap(179.99990 + i * 1e-6 * 9)),
      ];
      final timeline = build(pts, eventLog: events(500));
      expect(timeline.runs.length, 1);
      final planner = GpsReplayPolylinePlanner(timeline,
          ghostToleranceMeters: 50, ghostVertexBudget: 10000);
      final kept = planner.ghostLines.single.length;
      expect(kept, lessThan(60), reason: 'distance measured across 180');
      expect(kept, greaterThan(2));

      // The same track far from the antimeridian keeps exactly as many.
      final shifted = build([
        for (var i = 0; i < 200; i++)
          pt(i + 1, 10.0, 2.0 * (i + 1), 100.0 + 1e-6 * 9 * i - 1e-4),
      ], eventLog: events(500));
      final reference = GpsReplayPolylinePlanner(shifted,
          ghostToleranceMeters: 50, ghostVertexBudget: 10000);
      expect(kept, reference.ghostLines.single.length,
          reason: 'crossing 180 must not change the simplification');
    });
  });

  group('purity and size', () {
    test('P24 the planner is pure Dart: no Flutter, maps, timers or clock', () {
      final code = File('lib/features/gps/replay/gps_replay_polyline_plan.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final banned in [
        'package:flutter',
        'google_maps',
        'LatLng',
        'dart:async',
        'dart:io',
        'dart:ui',
        'Timer',
        'Stream',
        'Future',
        'Isolate',
        'DateTime',
        'Stopwatch',
      ]) {
        expect(code.contains(banned), isFalse, reason: banned);
      }
    });

    test('P25 a 50 000-point Journey: playback sweep and ghost', () {
      const count = 50000;
      final pts = [
        for (var i = 0; i < count; i++)
          pt(i + 1, 50 + 2e-5 * (i + 1), 2.0 * (i + 1), 30 + 1e-5 * (i % 700)),
      ];
      final timeline = build(pts, eventLog: events(2.0 * count + 2));
      final progress = GpsReplayRouteProgress(timeline);
      final planner = GpsReplayPolylinePlanner(timeline);

      final ghostWatch = Stopwatch()..start();
      final ghost = planner.ghostLines;
      ghostWatch.stop();
      final ghostVertices = ghost.fold<int>(0, (a, l) => a + l.length);
      expect(ghostVertices, lessThanOrEqualTo(4000));

      // 60 fps for a one-minute replay.
      const frames = 3600;
      final total = timeline.activeDuration.inMicroseconds;
      var maxFrameVertices = 0;
      var sentVertices = 0;
      var maxLines = 0;
      final sweep = Stopwatch()..start();
      for (var f = 0; f <= frames; f++) {
        final u = progress.update(Duration(microseconds: f * total ~/ frames));
        final changes = planner.apply(u);
        final v = changes.upserted.fold<int>(0, (a, l) => a + l.length);
        sentVertices += v;
        if (v > maxFrameVertices) maxFrameVertices = v;
        if (changes.upserted.length > maxLines) {
          maxLines = changes.upserted.length;
        }
      }
      sweep.stop();
      // ~14 samples per frame: a frame touches the tail chunk and maybe one
      // more, never the route behind it.
      expect(maxFrameVertices, lessThanOrEqualTo(2 * 256));
      expect(maxLines, lessThanOrEqualTo(3));

      // ignore: avoid_print
      print('REPLAY_PLAN_PERF points=$count ghost_vertices=$ghostVertices '
          'ghost_ms=${ghostWatch.elapsedMilliseconds} frames=$frames '
          'sweep_ms=${sweep.elapsedMilliseconds} '
          'max_frame_vertices=$maxFrameVertices '
          'sent_vertices_total=$sentVertices');
    });
  });
}

double _wrap(double lng) => lng > 180 ? lng - 360 : lng;

double _meters(double latA, double lngA, double latB, double lngB) {
  var dLng = lngB - lngA;
  if (dLng > 180) dLng -= 360;
  if (dLng < -180) dLng += 360;
  final dy = (latB - latA) * 111320.0;
  final dx = dLng * 111320.0 * cos((latA + latB) / 2 * pi / 180);
  return sqrt(dx * dx + dy * dy);
}

int _byChunk(String a, String b) {
  int chunk(String id) => int.parse(id.split('_').last);
  return chunk(a).compareTo(chunk(b));
}

/// A stand-in for the map renderer: polylines by id (lists of coordinates)
/// changed ONLY through [GpsReplayPolylineChanges]. It also enforces that a
/// progress line never mixes runs.
class _Canvas {
  _Canvas(this.timeline, this.chunk);

  final GpsReplayTimeline timeline;
  final int chunk;
  final Map<String, List<(double, double)>> lines = {};
  GpsReplayPlannedLine? head;

  Iterable<String> get progressIds => lines.keys;

  void apply(GpsReplayPolylineChanges changes) {
    for (final id in changes.removedIds) {
      expect(lines.remove(id), isNotNull, reason: 'removed unknown $id');
    }
    for (final line in changes.upserted) {
      expect(line.length, greaterThanOrEqualTo(2));
      lines[line.id] = [
        for (var i = 0; i < line.length; i++)
          (line.latitudeAt(i), line.longitudeAt(i))
      ];
    }
    if (changes.headChanged) head = changes.head;
  }

  // What should be drawn at [cursor], computed from scratch.
  void expectMatches(GpsReplayCursor cursor, String reason) {
    final stride = chunk - 1;
    final expected = <String, List<(double, double)>>{};
    for (var r = 0; r < timeline.runs.length; r++) {
      final run = timeline.runs[r];
      final drawn = r < cursor.completedRunCount
          ? run.length
          : (r == cursor.partialRunIndex ? cursor.partialVertexCount : 0);
      for (var c = 0; drawn - c * stride >= 2; c++) {
        final visible = min(chunk, drawn - c * stride);
        expected['p${r}_$c'] = [
          for (var i = 0; i < visible; i++)
            (
              timeline.latitudeAt(run.startIndex + c * stride + i),
              timeline.longitudeAt(run.startIndex + c * stride + i)
            )
        ];
      }
    }
    expect(lines, expected, reason: reason);

    // The head matches the cursor.
    if (cursor.headExtendsLine) {
      expect(head, isNotNull, reason: 'head $reason');
      expect(head!.length, 2);
      expect(head!.latitudeAt(0), timeline.latitudeAt(cursor.sampleIndex),
          reason: 'head start $reason');
      expect(head!.latitudeAt(1), cursor.position.latitude,
          reason: 'head end $reason');
      expect(head!.runIndex, timeline.runIndexOfSample(cursor.sampleIndex));
    } else {
      expect(head, isNull, reason: 'head $reason');
    }
  }
}
