import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_replay_screen.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';

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

LocalRoutePoint _pt(int seq, double lat, num sec) => LocalRoutePoint(
      recordedRouteId: _routeId,
      seq: seq,
      ownerId: _owner,
      latitude: lat,
      longitude: 30,
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

/// One run, 100 samples 2 s apart: 202 s active, so 60 s of presentation.
GpsReplayTimeline _walk() => _build([
      for (var i = 0; i < 100; i++) _pt(i + 1, 50 + 2e-5 * i, 2.0 * (i + 1)),
    ], [
      _ev(1, RouteEventType.start, 0),
      _ev(2, RouteEventType.finish, 202),
    ]);

/// Two runs 0.5 degrees apart (a pause and a jump between them).
GpsReplayTimeline _twoRuns() => _build([
      for (var i = 0; i < 10; i++) _pt(i + 1, 50 + 1e-4 * i, 2.0 * (i + 1)),
      for (var i = 0; i < 10; i++) _pt(11 + i, 50.5 + 1e-4 * i, 100 + 2.0 * i),
    ], [
      _ev(1, RouteEventType.start, 0),
      _ev(2, RouteEventType.pause, 30),
      _ev(3, RouteEventType.resume, 90),
      _ev(4, RouteEventType.finish, 130),
    ]);

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

Widget _view(GpsReplayTimeline tl) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: GpsJourneyReplayView(timeline: tl)),
    );

Widget _screen(Future<GpsReplayTimeline?> Function() load) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        gpsJourneyReplayTimelineProvider.overrideWith((ref, args) => load()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const GpsJourneyReplayScreen(ownerId: _owner, routeId: _routeId),
      ),
    );

GoogleMap _map(WidgetTester t) => t.widget<GoogleMap>(find.byType(GoogleMap));
Finder _play() => find.byKey(const Key('gps_replay_play_pause'));
Finder _slider() => find.byKey(const Key('gps_replay_slider'));
String _current(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('gps_replay_time_current'))).data!;
double _sliderValue(WidgetTester t) => t.widget<Slider>(_slider()).value;
bool _isPlaying(WidgetTester t) =>
    find.byIcon(Icons.pause).evaluate().isNotEmpty;
Set<String> _ids(WidgetTester t) =>
    _map(t).polylines.map((p) => p.polylineId.value).toSet();

Future<void> _run(WidgetTester t, int ms, {int step = 100}) async {
  for (var i = 0; i < ms ~/ step; i++) {
    await t.pump(Duration(milliseconds: step));
  }
}

void _tw(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await body(tester);
    });

void main() {
  group('screen states', () {
    _tw('S01 loading, then the replay', (tester) async {
      await tester.pumpWidget(_screen(() async => _walk()));
      expect(find.byKey(const Key('gps_replay_loading')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gps_replay_map')), findsOneWidget);
      expect(find.byKey(const Key('gps_replay_play_pause')), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);
    });

    _tw('S02 error, unavailable and empty states', (tester) async {
      await tester.pumpWidget(_screen(() async => throw StateError('x')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gps_replay_error')), findsOneWidget);

      await tester.pumpWidget(_screen(() async => null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gps_replay_unavailable')), findsOneWidget);

      await tester.pumpWidget(_screen(() async => _build(const [], [
            _ev(1, RouteEventType.start, 0),
            _ev(2, RouteEventType.finish, 10),
          ])));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gps_replay_empty')), findsOneWidget);
      expect(find.byType(GoogleMap), findsNothing);
    });

    _tw('S03 a single-point Journey shows a marker and plays safely',
        (tester) async {
      await tester.pumpWidget(_view(_build([
        _pt(1, 50, 5)
      ], [
        _ev(1, RouteEventType.start, 0),
        _ev(2, RouteEventType.finish, 20),
      ])));
      expect(_map(tester).polylines, isEmpty);
      expect(_map(tester).markers.length, 1);
      await tester.tap(_play());
      await tester.pump();
      await _run(tester, 3000, step: 200);
      expect(tester.takeException(), isNull);
      expect(_map(tester).polylines, isEmpty);
      expect(_map(tester).markers.length, 1);
    });

    _tw('S04 a zero-length Journey cannot play', (tester) async {
      await tester.pumpWidget(_view(_build([
        _pt(1, 50, 0)
      ], [
        _ev(1, RouteEventType.start, 0),
        _ev(2, RouteEventType.finish, 0),
      ])));
      expect(tester.widget<IconButton>(_play()).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('playback', () {
    _tw('P01 play advances time, draws the route; pause freezes it',
        (tester) async {
      await tester.pumpWidget(_view(_walk()));
      expect(_ids(tester), {'g0'});
      await tester.tap(_play());
      await tester.pump();
      expect(_isPlaying(tester), isTrue);
      await _run(tester, 2100, step: 100);
      expect(_current(tester), '0:02');
      expect(_ids(tester), contains('p0_0'));
      expect(_map(tester).markers.length, 1);

      await tester.tap(_play());
      await tester.pump();
      expect(_isPlaying(tester), isFalse);
      final frozen = _current(tester);
      final frozenSlider = _sliderValue(tester);
      await _run(tester, 2000, step: 100);
      expect(_current(tester), frozen);
      expect(_sliderValue(tester), frozenSlider);
    });

    _tw('P02 speed changes the rate', (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.tap(find.byKey(const Key('gps_replay_speed_4x')));
      await tester.pump();
      await tester.tap(_play());
      await tester.pump();
      await _run(tester, 2100, step: 100);
      expect(_current(tester), '0:08');

      await tester.tap(find.byKey(const Key('gps_replay_speed_0.5x')));
      await tester.pump();
      await _run(tester, 2000, step: 100);
      expect(_current(tester), '0:09'); // +1 s at half speed
    });

    _tw('P03 the head moves between GPS samples', (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.tap(_play());
      await tester.pump();
      await _run(tester, 1000, step: 50);
      final a = _map(tester)
          .polylines
          .firstWhere((p) => p.polylineId.value == 'head')
          .points
          .last;
      await _run(tester, 100, step: 50);
      final b = _map(tester)
          .polylines
          .firstWhere((p) => p.polylineId.value == 'head')
          .points
          .last;
      expect(b, isNot(a));
    });

    _tw('P04 reaching the end stops, then play restarts from the start',
        (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.tap(find.byKey(const Key('gps_replay_speed_4x')));
      await tester.pump();
      await tester.tap(_play());
      await tester.pump();
      await _run(tester, 16000, step: 200);
      expect(_current(tester), '1:00');
      expect(_isPlaying(tester), isFalse);
      expect(_sliderValue(tester), 1.0);
      expect(_ids(tester), contains('p0_0'));

      await tester.tap(_play());
      await tester.pump();
      expect(_isPlaying(tester), isTrue);
      expect(_sliderValue(tester), lessThan(0.1));
      expect(_ids(tester).where((i) => i.startsWith('p')), isEmpty);
    });

    _tw('P05 a stalled frame does not leap forward', (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.tap(_play());
      await tester.pump();
      await tester.pump(const Duration(seconds: 30)); // suspended app
      expect(_current(tester), '0:00');
      expect(_isPlaying(tester), isTrue);
    });
  });

  group('seeking and scrubbing', () {
    _tw('K01 seek forward and backward redraws the route', (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.drag(_slider(), const Offset(300, 0));
      await tester.pump();
      expect(_sliderValue(tester), greaterThan(0.5));
      final forward = _ids(tester);
      expect(forward, contains('p0_0'));
      expect(_current(tester), isNot('0:00'));

      await tester.drag(_slider(), const Offset(-600, 0));
      await tester.pump();
      expect(_sliderValue(tester), lessThan(0.05));
      expect(_ids(tester).length, lessThan(forward.length));
      expect(_isPlaying(tester), isFalse);
    });

    _tw('K02 scrubbing while playing pauses the clock and resumes after',
        (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.tap(_play());
      await tester.pump();
      await _run(tester, 500, step: 100);
      final gesture = await tester.startGesture(tester.getCenter(_slider()));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final during = _current(tester);
      await _run(tester, 1000, step: 100);
      expect(_current(tester), during); // nothing advances while scrubbing
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(_isPlaying(tester), isTrue);
      await _run(tester, 1000, step: 100);
      expect(_current(tester), isNot(during));
    });

    _tw('K03 a cancelled slider gesture does not leave the scrub stuck',
        (tester) async {
      await tester.pumpWidget(_view(_walk()));
      final gesture = await tester.startGesture(tester.getCenter(_slider()));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      // play is ignored while scrubbing, so this proves the scrub is closed.
      await tester.tap(_play());
      await tester.pump();
      expect(_isPlaying(tester), isTrue);
      final at = _current(tester);
      await _run(tester, 1500, step: 100);
      expect(_current(tester), isNot(at));
    });
  });

  group('lifecycle', () {
    _tw('L01 backgrounding pauses and the app never resumes by itself',
        (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.tap(_play());
      await tester.pump();
      await _run(tester, 500, step: 100);
      expect(_isPlaying(tester), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_isPlaying(tester), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final frozen = _current(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await _run(tester, 2000, step: 100);
      expect(_isPlaying(tester), isFalse);
      expect(_current(tester), frozen);

      await tester.tap(_play()); // explicit resume works, without a jump
      await tester.pump();
      await _run(tester, 500, step: 100);
      expect(_isPlaying(tester), isTrue);
    });

    _tw('L02 resume redraws the route (resync) without duplicating lines',
        (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.drag(_slider(), const Offset(200, 0));
      await tester.pump();
      final before = _ids(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_ids(tester), before);
      // and the drawing keeps following later updates after the resync
      await tester.drag(_slider(), const Offset(100, 0));
      await tester.pump();
      expect(_ids(tester).length, greaterThanOrEqualTo(before.length));
      expect(tester.takeException(), isNull);
    });

    _tw('L03 backgrounding during a scrub closes it', (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.tap(_play());
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(_slider()));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      // The finger is still down: only the lifecycle cleanup can have closed
      // the scrub, so an explicit play must already work.
      await tester.tap(_play());
      await tester.pump();
      expect(_isPlaying(tester), isTrue);
      await tester.tap(_play());
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(_isPlaying(tester), isFalse); // not resumed by the scrub end
      await tester.tap(_play());
      await tester.pump();
      expect(_isPlaying(tester), isTrue);
    });

    _tw('L04 leaving the screen while playing or scrubbing disposes cleanly',
        (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.tap(_play());
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(_slider()));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    _tw('L05 popping the route while playing disposes the ticker',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                          body: GpsJourneyReplayView(timeline: _walk())))),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(_play());
      await tester.pump();
      await _run(tester, 300, step: 100);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(GoogleMap), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('map content', () {
    _tw('G01 runs are never joined by a polyline', (tester) async {
      await tester.pumpWidget(_view(_twoRuns()));
      await tester.drag(_slider(), const Offset(380, 0));
      await tester.pump();
      expect(_sliderValue(tester), 1.0);
      final lines = _map(tester).polylines;
      expect(lines.where((p) => p.polylineId.value.startsWith('p')).length, 2);
      for (final p in lines) {
        final lats = p.points.map((e) => e.latitude);
        final spread = lats.reduce((a, b) => a > b ? a : b) -
            lats.reduce((a, b) => a < b ? a : b);
        expect(spread, lessThan(0.1), reason: p.polylineId.value);
      }
    });

    _tw('G02 an extreme number of runs keeps the line count bounded',
        (tester) async {
      await tester.pumpWidget(_view(_manyRuns(2500)));
      await tester.drag(_slider(), const Offset(380, 0));
      await tester.pump();
      expect(_sliderValue(tester), 1.0);
      expect(_map(tester).polylines.length, lessThanOrEqualTo(150 + 600 + 1));
      expect(tester.takeException(), isNull);
    });

    // Counts real map renders: every render replaces the model's polyline
    // set, so a changed `GoogleMap.polylines` identity is one render.
    Future<int> renders(WidgetTester tester, Duration interval,
        {int steps = 20}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: GpsJourneyReplayView(
            key: UniqueKey(),
            timeline: _walk(),
            renderInterval: interval,
          ),
        ),
      ));
      await tester.tap(_play());
      await tester.pump();
      var last = _map(tester).polylines;
      var count = 0;
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final now = _map(tester).polylines;
        if (!identical(now, last)) count++;
        last = now;
      }
      return count;
    }

    _tw('G03 the render throttle suppresses intermediate renders',
        (tester) async {
      // 20 ticks of 100 ms: an unthrottled view renders on every one.
      final fast = await renders(tester, const Duration(milliseconds: 33));
      expect(fast, 20);

      final throttled =
          await renders(tester, const Duration(milliseconds: 500));
      // 2 s of ticks, one render per 500 ms.
      expect(throttled, inInclusiveRange(3, 5));
      expect(throttled, lessThan(fast ~/ 3));

      // The clock itself is not throttled: time still advanced.
      expect(_current(tester), isNot('0:00'));
    });

    _tw('G04 the Google logo area is padded above the control panel',
        (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.pump();
      await tester.pump();
      final panel = tester.getRect(find.byType(Card).last);
      final padding = _map(tester).padding.bottom;
      // The map's bottom padding covers the whole panel (with its margin).
      expect(padding, greaterThanOrEqualTo(panel.height));
      expect(padding, lessThan(panel.height + 40));
      expect(tester.takeException(), isNull);
    });

    _tw('G05 playing at every speed redraws only what changed', (tester) async {
      await tester.pumpWidget(_view(_walk()));
      await tester.pump();
      await tester.pump();
      final play =
          tester.widget(find.byKey(const Key('gps_replay_play_pause')));
      final speed = tester.widget(find.byKey(const Key('gps_replay_speed')));
      await tester.tap(_play());
      await tester.pump();
      for (final x in ['0.5x', '1x', '2x', '4x']) {
        await tester.tap(find.byKey(Key('gps_replay_speed_$x')));
        await tester.pump();
        await _run(tester, 500, step: 100);
        expect(_isPlaying(tester), isTrue, reason: x);
      }
      // The speed selector was rebuilt for the speed changes only; while
      // playing at one speed the same widget instance is reused.
      final sel = tester.widget(find.byKey(const Key('gps_replay_speed')));
      await _run(tester, 400, step: 100);
      expect(
          identical(
              sel, tester.widget(find.byKey(const Key('gps_replay_speed')))),
          isTrue);
      expect(
          identical(play,
              tester.widget(find.byKey(const Key('gps_replay_play_pause')))),
          isFalse,
          reason: 'the play button changed to pause');
      expect(speed, isNotNull);
    });
  });
}
