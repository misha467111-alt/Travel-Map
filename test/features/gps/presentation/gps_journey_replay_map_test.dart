import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_replay_map.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_playback.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_polyline_plan.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_session.dart';

const _owner = 'o';
const _routeId = 'r';
final _t0 = DateTime.utc(2026, 1, 1, 10);
DateTime _s(num sec) => _t0.add(Duration(microseconds: (sec * 1e6).round()));

LocalRecordedRoute _route() => LocalRecordedRoute(
      id: _routeId,
      ownerId: _owner,
      transportMode: 'walking',
      status: RecordedRouteStatus.completed,
      visibility: 'private',
      startedAt: _t0,
      createdAt: _t0,
      updatedAt: _t0,
      syncStatus: RouteSyncStatus.synced,
    );

LocalRoutePoint _pt(int seq, double lat, num sec, [double lng = 30]) =>
    LocalRoutePoint(
      recordedRouteId: _routeId,
      seq: seq,
      ownerId: _owner,
      latitude: lat,
      longitude: lng,
      recordedAt: _s(sec),
    );

LocalRouteEvent _ev(int seq, String type, num sec) => LocalRouteEvent(
      recordedRouteId: _routeId,
      seq: seq,
      ownerId: _owner,
      eventType: type,
      occurredAt: _s(sec),
    );

GpsReplayTimeline _build(List<LocalRoutePoint> p, List<LocalRouteEvent> e) =>
    GpsReplayTimeline.build(
        route: _route(), points: p, events: e, now: _s(1e6));

/// One run of [n] samples, 2 s apart.
GpsReplayTimeline _walk(int n) => _build([
      for (var i = 0; i < n; i++) _pt(i + 1, 50 + 2e-5 * i, 2.0 * (i + 1)),
    ], [
      _ev(1, RouteEventType.start, 0),
      _ev(2, RouteEventType.finish, 2.0 * n + 2),
    ]);

/// [runs] runs of three samples each, separated by pauses.
GpsReplayTimeline _manyRuns(int runs) {
  final points = <LocalRoutePoint>[];
  final events = <LocalRouteEvent>[_ev(1, RouteEventType.start, 0)];
  var seq = 1;
  var t = 1.0;
  for (var r = 0; r < runs; r++) {
    for (var k = 0; k < 3; k++) {
      points.add(_pt(seq++, 40 + r * 1e-3 + k * 1e-5, t));
      t += 2;
    }
    events.add(_ev(events.length + 1, RouteEventType.pause, t));
    t += 30;
    events.add(_ev(events.length + 1, RouteEventType.resume, t));
    t += 1;
  }
  events.add(_ev(events.length + 1, RouteEventType.finish, t));
  return _build(points, events);
}

GpsReplayRenderModel _model(GpsReplayTimeline tl,
        {GpsReplayPolylinePlanner? planner,
        int maxGhost = 150,
        int maxProgress = 600}) =>
    GpsReplayRenderModel(
      ghostLines: (planner ?? GpsReplayPolylinePlanner(tl)).ghostLines,
      progressColor: Colors.blue,
      ghostColor: Colors.blue.withValues(alpha: .3),
      maxGhostLines: maxGhost,
      maxProgressLines: maxProgress,
    );

void _step(
    GpsReplaySession s, GpsReplayPolylinePlanner p, GpsReplayRenderModel m) {
  final u = s.takeUpdate();
  m.apply(p.apply(u), u.cursor);
}

void main() {
  test('M01 ghost polylines are built once, per run, with stable ids', () {
    final tl = _build([
      _pt(1, 50.0, 10),
      _pt(2, 50.0001, 12),
      _pt(3, 50.0002, 14),
      _pt(4, 50.5, 80), // after a pause: another run
      _pt(5, 50.5001, 82),
    ], [
      _ev(1, RouteEventType.start, 0),
      _ev(2, RouteEventType.pause, 20),
      _ev(3, RouteEventType.resume, 70),
      _ev(4, RouteEventType.finish, 100),
    ]);
    final m = _model(tl);
    expect(tl.runs.length, 2);
    expect(m.ghostLineCount, 2);
    expect(m.ghostTruncated, false);
    expect(m.polylines.map((p) => p.polylineId.value), {'g0', 'g1'});
    for (final p in m.polylines) {
      final lats = p.points.map((e) => e.latitude);
      expect(
          lats.reduce((a, b) => a > b ? a : b) -
              lats.reduce((a, b) => a < b ? a : b),
          lessThan(0.1)); // never joins the two runs
    }
    expect(m.markers, isEmpty);
  });

  test(
      'M02 progress chunks are cached objects; a frame replaces only the '
      'changed ones', () {
    final tl = _walk(1200);
    final planner = GpsReplayPolylinePlanner(tl);
    final m = _model(tl, planner: planner);
    final s = GpsReplaySession(tl);
    s.seekToFraction(0.5);
    _step(s, planner, m);
    final stable = {
      for (final id in ['p0_0', 'p0_1']) id: m.progressLine(id)!,
    };
    expect(m.progressLineCount, greaterThan(2));

    s.seekToFraction(0.51);
    _step(s, planner, m);
    for (final e in stable.entries) {
      expect(identical(m.progressLine(e.key), e.value), isTrue,
          reason: '${e.key} must not be rebuilt');
    }
  });

  test('M03 backward seek removes chunks; forward restores them', () {
    final tl = _walk(1000);
    final planner = GpsReplayPolylinePlanner(tl);
    final m = _model(tl, planner: planner);
    final s = GpsReplaySession(tl);
    s.seekToFraction(0.9);
    _step(s, planner, m);
    final full = m.progressLineCount;
    s.seekToFraction(0.1);
    _step(s, planner, m);
    expect(m.progressLineCount, lessThan(full));
    s.seekToFraction(0.0);
    _step(s, planner, m);
    expect(m.progressLineCount, 0);
    s.seekToFraction(0.9);
    _step(s, planner, m);
    expect(m.progressLineCount, full);
  });

  test('M04 head follows interpolation without a new completed sample', () {
    final tl = _walk(50);
    final planner = GpsReplayPolylinePlanner(tl);
    final m = _model(tl, planner: planner);
    final s = GpsReplaySession(tl);
    s.seek(const Duration(seconds: 11));
    _step(s, planner, m);
    final first = m.polylines.firstWhere((p) => p.polylineId.value == 'head');
    final firstMarker = m.markers.single.position;
    s.seek(const Duration(seconds: 11, milliseconds: 500));
    _step(s, planner, m);
    final second = m.polylines.firstWhere((p) => p.polylineId.value == 'head');
    expect(second.points.last, isNot(first.points.last));
    expect(m.markers.single.position, isNot(firstMarker));
    expect(m.markers.single.markerId, GpsReplayRenderModel.positionMarkerId);
  });

  test('M05 reset clears progress, head and marker but keeps the ghost', () {
    final tl = _walk(100);
    final planner = GpsReplayPolylinePlanner(tl);
    final m = _model(tl, planner: planner);
    final s = GpsReplaySession(tl);
    s.seekToFraction(0.5);
    _step(s, planner, m);
    expect(m.progressLineCount, greaterThan(0));
    m.reset();
    planner.reset();
    expect(m.progressLineCount, 0);
    expect(m.hasHead, false);
    expect(m.markers, isEmpty);
    expect(m.ghostLineCount, 1);
    final u = s.resync();
    m.apply(planner.apply(u), u.cursor);
    expect(m.progressLineCount, greaterThan(0));
  });

  group('M06 completed route is preserved or degrades gracefully', () {
    // Runs (by index) that have any line on the map: ghost, exact chunk or
    // merged progress.
    Set<int> drawnRuns(GpsReplayRenderModel m) => {
          for (final p in m.polylines)
            if (p.polylineId.value != 'head')
              int.parse(RegExp(r'\d+').firstMatch(p.polylineId.value)![0]!),
        };

    GpsReplayRenderModel endOf(GpsReplayTimeline tl,
        {int maxProgress = 600, int mergedBudget = 1500}) {
      final p = GpsReplayPolylinePlanner(tl);
      final m = GpsReplayRenderModel(
        ghostLines: p.ghostLines,
        progressColor: Colors.blue,
        ghostColor: Colors.blue.withValues(alpha: .3),
        maxProgressLines: maxProgress,
        mergedVertexBudget: mergedBudget,
      );
      final s = GpsReplaySession(tl)..seekToFraction(1.0);
      _step(s, p, m);
      return m;
    }

    void expectNoBridging(GpsReplayRenderModel m, double maxSpreadDegrees) {
      for (final p in m.polylines) {
        final lats = p.points.map((e) => e.latitude).toList()..sort();
        expect(lats.last - lats.first, lessThan(maxSpreadDegrees),
            reason: '${p.polylineId.value} joins runs');
      }
    }

    test('within the budget completed geometry is exact (no loss)', () {
      final tl = _walk(1000);
      final m = endOf(tl);
      expect(m.isCompacted, false);
      expect(m.droppedRunCount, 0);
      final points = <LatLng>[];
      final chunks = m.polylines
          .where((p) => p.polylineId.value.startsWith('p0_'))
          .toList()
        ..sort((a, b) => int.parse(a.polylineId.value.substring(3))
            .compareTo(int.parse(b.polylineId.value.substring(3))));
      for (var i = 0; i < chunks.length; i++) {
        points.addAll(i == 0 ? chunks[i].points : chunks[i].points.skip(1));
      }
      expect(points.length, 1000);
      for (var i = 0; i < 1000; i++) {
        expect(points[i], LatLng(tl.latitudeAt(i), tl.longitudeAt(i)));
      }
    });

    test('a long single run is merged into two lines and nothing vanishes', () {
      final tl = _walk(3000);
      final m = endOf(tl, maxProgress: 8, mergedBudget: 500);
      expect(m.isCompacted, true);
      expect(m.chunkCount, greaterThan(8));
      expect(m.droppedRunCount, 0);
      expect(m.progressLineCount, 2); // merged body + newest chunk
      final body = m.polylines.firstWhere((p) => p.polylineId.value == 'm0');
      expect(body.points.length, lessThanOrEqualTo(500));
      expect(body.points.first, LatLng(tl.latitudeAt(0), tl.longitudeAt(0)));
      final newest =
          m.polylines.firstWhere((p) => p.polylineId.value.startsWith('p0_'));
      expect(body.points.last, newest.points.first); // continuous, no gap
      expect(newest.points.last,
          LatLng(tl.latitudeAt(2999), tl.longitudeAt(2999)));
    });

    test('merging a run is lossless below the vertex budget (no duplicates)',
        () {
      final tl = _walk(3000);
      final m = endOf(tl, maxProgress: 4, mergedBudget: 5000);
      final newest =
          m.polylines.firstWhere((p) => p.polylineId.value.startsWith('p0_'));
      final newestChunk = int.parse(newest.polylineId.value.substring(3));
      final body = m.polylines.firstWhere((p) => p.polylineId.value == 'm0');
      // The body is samples 0..newestChunk*255 (chunks share one vertex).
      expect(body.points.length, newestChunk * 255 + 1);
      for (var i = 0; i < body.points.length; i++) {
        expect(body.points[i], LatLng(tl.latitudeAt(i), tl.longitudeAt(i)));
      }
    });

    test('compact body is reused while only the newest chunk changes', () {
      final tl = _walk(3000);
      final planner = GpsReplayPolylinePlanner(tl);
      final m = GpsReplayRenderModel(
          ghostLines: planner.ghostLines,
          progressColor: Colors.blue,
          ghostColor: Colors.blue,
          maxProgressLines: 4);
      final s = GpsReplaySession(tl);
      s.seekToFraction(0.6);
      _step(s, planner, m);
      expect(m.isCompacted, true);
      Polyline body() =>
          m.polylines.firstWhere((p) => p.polylineId.value == 'm0');
      final before = body();
      s.seek(s.position + const Duration(milliseconds: 300));
      _step(s, planner, m);
      expect(identical(body(), before), isTrue);
      s.seekToFraction(0.9); // newer chunks complete: the body must grow
      _step(s, planner, m);
      expect(body().points.length, greaterThanOrEqualTo(before.points.length));
      expect(identical(body(), before), isFalse);
    });

    test('hundreds of short runs within budget are all drawn', () {
      final tl = _manyRuns(300);
      final m = endOf(tl);
      expect(m.isCompacted, false);
      expect(m.droppedRunCount, 0);
      for (var r = 0; r < tl.runs.length; r++) {
        expect(m.polylines.any((p) => p.polylineId.value == 'p${r}_0'), true,
            reason: 'run $r');
      }
      expectNoBridging(m, 5e-4);
    });

    test('above the line budget runs degrade; ghost covers what progress drops',
        () {
      final tl = _manyRuns(700);
      final m = endOf(tl);
      expect(m.isCompacted, true);
      expect(m.droppedRunCount, 700 - 1 - 598);
      expect(m.polylines.length, lessThanOrEqualTo(150 + 600 + 1));
      // 598 newest runs + the live one as progress, the earliest 150 as
      // ghost: together they cover every run.
      expect(drawnRuns(m).length, 700);
      expectNoBridging(m, 5e-4);
    });

    test('far above the budget some runs are NOT visible (documented)', () {
      final tl = _manyRuns(2500);
      final m = endOf(tl);
      expect(m.isCompacted, true);
      expect(m.droppedRunCount, 2500 - 1 - 598);
      expect(m.polylines.length, lessThanOrEqualTo(150 + 600 + 1));
      expect(drawnRuns(m).length, lessThan(2500)); // impossible to show all
      expect(m.ghostTruncated, true);
      expectNoBridging(m, 5e-4);
    });

    test('meaningful (long) runs win the budget over tiny fragments', () {
      // 800 runs: every 8th is a real 20-sample stretch, the rest 3 samples.
      final points = <LocalRoutePoint>[];
      final events = <LocalRouteEvent>[_ev(1, RouteEventType.start, 0)];
      var seq = 1;
      var t = 1.0;
      final longRuns = <int>[];
      for (var r = 0; r < 800; r++) {
        final n = r % 8 == 0 ? 20 : 3;
        if (n == 20) longRuns.add(r);
        for (var k = 0; k < n; k++) {
          points.add(_pt(seq++, 40 + r * 1e-3 + k * 1e-4, t));
          t += 2;
        }
        events.add(_ev(events.length + 1, RouteEventType.pause, t));
        t += 30;
        events.add(_ev(events.length + 1, RouteEventType.resume, t));
        t += 1;
      }
      events.add(_ev(events.length + 1, RouteEventType.finish, t));
      final tl = _build(points, events);
      final m = endOf(tl, maxProgress: 120);
      expect(m.isCompacted, true);
      final ids = m.polylines.map((p) => p.polylineId.value).toSet();
      for (final r in longRuns.take(longRuns.length - 1)) {
        expect(ids.contains('m$r'), true, reason: 'long run $r lost');
      }
      expect(m.droppedRunCount, greaterThan(0));
    });

    test(
        'seek back and forward after compaction, and resync, restore the '
        'same drawing', () {
      final tl = _manyRuns(800);
      final planner = GpsReplayPolylinePlanner(tl);
      final m = _model(tl, planner: planner);
      final s = GpsReplaySession(tl);
      Set<String> ids() => m.polylines.map((p) => p.polylineId.value).toSet();

      s.seekToFraction(1.0);
      _step(s, planner, m);
      final atEnd = ids();
      expect(m.isCompacted, true);

      s.seekToFraction(0.3);
      _step(s, planner, m);
      expect(m.chunkCount, lessThan(800));
      s.seekToFraction(0.0);
      _step(s, planner, m);
      expect(m.chunkCount, 0);
      expect(m.progressLineCount, 0);
      expect(m.isCompacted, false);

      s.seekToFraction(1.0);
      _step(s, planner, m);
      expect(ids(), atEnd);

      m.reset();
      planner.reset();
      final u = s.resync();
      m.apply(planner.apply(u), u.cursor);
      expect(ids(), atEnd);
      expect(m.chunkCount, 800);
    });
  });

  test('M07 limits are validated', () {
    final tl = _walk(10);
    expect(
        () => GpsReplayRenderModel(
            ghostLines: const [],
            progressColor: Colors.red,
            ghostColor: Colors.red,
            maxGhostLines: 0),
        throwsArgumentError);
    expect(
        () => GpsReplayRenderModel(
            ghostLines: GpsReplayPolylinePlanner(tl).ghostLines,
            progressColor: Colors.red,
            ghostColor: Colors.red,
            maxProgressLines: 3),
        throwsArgumentError);
  });

  test('M08 route bounds: empty, single point, many points', () {
    final empty = _build(const [], [
      _ev(1, RouteEventType.start, 0),
      _ev(2, RouteEventType.finish, 10),
    ]);
    expect(gpsReplayRouteBounds(empty), isNull);

    final one = _build([
      _pt(1, 10, 5, 20)
    ], [
      _ev(1, RouteEventType.start, 0),
      _ev(2, RouteEventType.finish, 10),
    ]);
    final b1 = gpsReplayRouteBounds(one)!;
    expect(b1.southwest, const LatLng(10, 20));
    expect(b1.northeast, const LatLng(10, 20));

    final b = gpsReplayRouteBounds(_walk(100))!;
    expect(b.southwest.latitude, 50);
    expect(b.northeast.latitude, closeTo(50 + 2e-5 * 99, 1e-12));
  });

  testWidgets('M09 the map widget shows the model and rebuilds only on change',
      (tester) async {
    final tl = _walk(100);
    final planner = GpsReplayPolylinePlanner(tl);
    final m = _model(tl, planner: planner);
    addTearDown(m.dispose);
    await tester.pumpWidget(MaterialApp(
      home: GpsJourneyReplayMap(
        key: const Key('map'),
        model: m,
        bounds: gpsReplayRouteBounds(tl)!,
      ),
    ));
    GoogleMap map() => tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map().polylines.length, 1); // ghost only
    expect(map().markers, isEmpty);

    final s = GpsReplaySession(tl, speed: GpsReplaySpeed.one);
    s.seekToFraction(0.5);
    _step(s, planner, m);
    await tester.pump();
    expect(map().polylines.length, greaterThan(1));
    expect(map().markers.length, 1);
    expect(map().zoomControlsEnabled, false);
    expect(map().scrollGesturesEnabled, true); // manual gestures stay on
  });
}
