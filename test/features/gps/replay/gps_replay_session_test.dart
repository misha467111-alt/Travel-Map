import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_playback.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_session.dart';

/// Journey Phase 1I-B1B-1 -- the deterministic replay session. Every test
/// drives it with explicit cumulative ticker values; there is no real time.
void main() {
  const owner = 'owner-1';
  const routeId = 'r1';
  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime s(num seconds) =>
      t0.add(Duration(microseconds: (seconds * 1000000).round()));
  Duration sec(num seconds) =>
      Duration(microseconds: (seconds * 1000000).round());
  Duration ms(int v) => Duration(milliseconds: v);

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

  LocalRoutePoint pt(int seq, double lat, num seconds) => LocalRoutePoint(
        recordedRouteId: routeId,
        seq: seq,
        ownerId: owner,
        latitude: lat,
        longitude: 30.0,
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

  GpsReplayTimeline timeline(
          {num active = 600, List<LocalRoutePoint> points = const []}) =>
      GpsReplayTimeline.build(
        route: route(),
        points: points,
        events: events(active),
        now: s(100000),
      );

  // 600 s of active time watched in 60 s: at 1x one watch second is ten
  // recorded seconds. Unless a test names a frame cap, the cap is out of the
  // way so that large tick values test the BASELINE logic, not the stall policy.
  const standardCap = GpsReplaySession.defaultMaxFrameDelta;
  GpsReplaySession session({
    num active = 600,
    Duration? presentation = const Duration(seconds: 60),
    GpsReplaySpeed speed = GpsReplaySpeed.one,
    Duration maxFrameDelta = const Duration(days: 1),
    List<LocalRoutePoint> points = const [],
  }) =>
      GpsReplaySession(
        timeline(active: active, points: points),
        presentationDuration: presentation,
        speed: speed,
        maxFrameDelta: maxFrameDelta,
      );

  group('defaults', () {
    test('E01 the default presentation length is min(60 s, activeDuration)',
        () {
      expect(
          GpsReplaySession.defaultPresentationDurationFor(sec(600)), sec(60));
      expect(GpsReplaySession.defaultPresentationDurationFor(sec(60)), sec(60));
      expect(GpsReplaySession.defaultPresentationDurationFor(sec(30)), sec(30));
      expect(
          GpsReplaySession.defaultPresentationDurationFor(
              const Duration(microseconds: 5)),
          const Duration(microseconds: 5));
      // A zero-length Journey gets a positive placeholder (it cannot play).
      expect(GpsReplaySession.defaultPresentationDurationFor(Duration.zero),
          sec(1));

      expect(GpsReplaySession(timeline(active: 600)).presentationDuration,
          sec(60));
      expect(
          GpsReplaySession(timeline(active: 12)).presentationDuration, sec(12));
    });

    test('E02 a fresh session is paused at zero and dirty', () {
      final x = session();
      expect(x.position, Duration.zero);
      expect(x.isPlaying, isFalse);
      expect(x.isAtEnd, isFalse);
      expect(x.isScrubbing, isFalse);
      expect(x.isDirty, isTrue, reason: 'the renderer needs a first update');
      expect(x.speed, GpsReplaySpeed.one);
      expect(x.canPlay, isTrue);
      expect(x.stallTimeDiscarded, Duration.zero);
      expect(x.fraction, 0);
    });

    test('E03 a non-positive frame cap is rejected', () {
      expect(() => session(maxFrameDelta: Duration.zero), throwsArgumentError);
      expect(() => session(maxFrameDelta: ms(-1)), throwsArgumentError);
    });
  });

  group('ticker baseline', () {
    test('E04 the first tick only establishes the baseline', () {
      final x = session()..play();
      expect(x.onTick(Duration.zero), isFalse);
      expect(x.position, Duration.zero);
      expect(x.onTick(ms(1000)), isTrue);
      expect(x.position, sec(10), reason: '1 s watched = 10 s recorded');
    });

    test('E05 cumulative elapsed is converted to per-frame deltas', () {
      final x = session()..play();
      x.onTick(Duration.zero);
      // 60 fps style: cumulative values, NOT deltas.
      var elapsed = Duration.zero;
      for (var i = 0; i < 60; i++) {
        elapsed += const Duration(microseconds: 16667);
        x.onTick(elapsed);
      }
      // 60 * 16 667 us ~= 1.00002 s watched -> ~10.0002 s recorded
      expect(x.position.inMicroseconds, closeTo(10000200, 5));
      // Equal to a clock fed the exact deltas.
      final reference = GpsReplayPlayback(
          activeDuration: sec(600), presentationDuration: sec(60))
        ..play();
      for (var i = 0; i < 60; i++) {
        reference.advance(const Duration(microseconds: 16667));
      }
      expect(
          (x.position - reference.position).inMicroseconds.abs(), lessThan(3));
    });

    test('E06 a restarted ticker (elapsed back to zero) never goes negative',
        () {
      final x = session()..play();
      x.onTick(Duration.zero);
      x.onTick(ms(2000));
      expect(x.position, sec(20));

      // The ticker restarted without the session noticing.
      expect(x.onTick(ms(16)), isFalse, reason: 'a new baseline only');
      expect(x.position, sec(20));
      x.onTick(ms(1016));
      expect(x.position, sec(30));
    });

    test('E07 pause then play starts a fresh baseline (fresh ticker)', () {
      final x = session()..play();
      x.onTick(Duration.zero);
      x.onTick(ms(1000));
      x.pause();
      expect(x.onTick(ms(5000)), isFalse, reason: 'ticks while paused');
      expect(x.position, sec(10));

      x.play(); // the UI starts a NEW ticker: it reports zero first
      x.onTick(Duration.zero);
      x.onTick(ms(500));
      expect(x.position, sec(15));
    });

    test('E08 pause then play with a ticker that kept running: no jump', () {
      final x = session()..play();
      x.onTick(ms(100000)); // the ticker is far into its life
      x.onTick(ms(101000));
      expect(x.position, sec(10));
      x.pause();
      x.onTick(ms(150000)); // ignored
      x.play();
      x.onTick(ms(200000)); // establishes the baseline, no jump
      expect(x.position, sec(10));
      x.onTick(ms(200500));
      expect(x.position, sec(15));
    });

    test('E09 restartTicker resets the baseline explicitly', () {
      final x = session()..play();
      x.onTick(Duration.zero);
      x.onTick(ms(1000));
      x.restartTicker();
      x.onTick(ms(90000)); // new baseline
      expect(x.position, sec(10));
      x.onTick(ms(90500));
      expect(x.position, sec(15));
    });

    test('E43 play at the end with a ticker that kept running: no jump', () {
      final x = session(maxFrameDelta: GpsReplaySession.defaultMaxFrameDelta)
        ..play();
      var elapsed = Duration.zero;
      x.onTick(elapsed);
      while (x.isPlaying) {
        elapsed += ms(250);
        x.onTick(elapsed);
      }
      expect(x.isAtEnd, isTrue);

      // The ticker was never restarted; much time passes before play().
      elapsed += const Duration(seconds: 30);
      x.play();
      expect(x.position, Duration.zero);
      x.onTick(elapsed); // must only establish the baseline
      expect(x.position, Duration.zero, reason: 'no catch-up of the 30 s');
      expect(x.stallTimeDiscarded, Duration.zero);
      x.onTick(elapsed + ms(100));
      expect(x.position, sec(1));
    });

    test('E10 identical tick sequences give identical results', () {
      final a = session(speed: GpsReplaySpeed.two)..play();
      final b = session(speed: GpsReplaySpeed.two)..play();
      var elapsed = Duration.zero;
      for (var i = 0; i < 200; i++) {
        elapsed += Duration(microseconds: 1000 + (i * 7919) % 30000);
        expect(a.onTick(elapsed), b.onTick(elapsed));
        expect(a.position, b.position);
      }
    });
  });

  group('stall policy', () {
    test('E11 a delta up to the cap is applied in full, the cap itself too',
        () {
      final x = session(maxFrameDelta: standardCap)..play();
      x.onTick(Duration.zero);
      x.onTick(ms(250)); // exactly the cap
      expect(x.position, sec(2.5));
      x.onTick(ms(250 + 249));
      expect(x.position, sec(2.5) + sec(2.49));
      expect(x.stallTimeDiscarded, Duration.zero);
    });

    test('E12 a longer gap applies the cap only and records the excess', () {
      final x = session(maxFrameDelta: standardCap)..play();
      x.onTick(Duration.zero);
      x.onTick(ms(1000)); // a 1 s stall
      expect(x.position, sec(2.5), reason: '250 ms watched = 2.5 s recorded');
      expect(x.stallTimeDiscarded, ms(750));

      x.onTick(ms(1000 + 600)); // another stall, 350 ms over
      expect(x.position, sec(5));
      expect(x.stallTimeDiscarded, ms(750 + 350));
    });

    test('E13 a custom cap changes the threshold, speed applies after it', () {
      final x = session(maxFrameDelta: ms(100), speed: GpsReplaySpeed.four)
        ..play();
      x.onTick(Duration.zero);
      x.onTick(ms(1000));
      // cap 100 ms watched * 4x * 10 = 4 s recorded
      expect(x.position, sec(4));
      expect(x.stallTimeDiscarded, ms(900));
    });

    test('E14 an hour-long gap (suspended app) cannot jump to the end', () {
      final x = session(maxFrameDelta: standardCap)..play();
      x.onTick(Duration.zero);
      for (var i = 1; i <= 10; i++) {
        x.onTick(ms(100 * i)); // ten ordinary frames: 1 s watched
      }
      expect(x.position, sec(10));
      x.onTick(const Duration(hours: 1));
      expect(x.isAtEnd, isFalse);
      expect(x.isPlaying, isTrue);
      expect(x.position, sec(10) + sec(2.5), reason: 'only 250 ms applied');
      expect(
          x.stallTimeDiscarded, const Duration(hours: 1) - ms(1000) - ms(250));
    });

    test('E15 the policy never changes ordinary 60 fps playback', () {
      final capped = session(maxFrameDelta: standardCap)..play();
      final uncapped = session(maxFrameDelta: const Duration(days: 1))..play();
      var elapsed = Duration.zero;
      capped.onTick(elapsed);
      uncapped.onTick(elapsed);
      for (var i = 0; i < 600; i++) {
        elapsed += ms(16);
        capped.onTick(elapsed);
        uncapped.onTick(elapsed);
      }
      expect(capped.position, uncapped.position);
      expect(capped.stallTimeDiscarded, Duration.zero);
    });
  });

  group('transport', () {
    test('E16 all four speeds scale the rate', () {
      for (final (speed, expected) in [
        (GpsReplaySpeed.half, 5),
        (GpsReplaySpeed.one, 10),
        (GpsReplaySpeed.two, 20),
        (GpsReplaySpeed.four, 40),
      ]) {
        final x = session(speed: speed)..play();
        x.onTick(Duration.zero);
        x.onTick(ms(1000 ~/ 4));
        x.onTick(ms(1000 ~/ 2));
        x.onTick(ms(3 * 1000 ~/ 4));
        x.onTick(ms(1000));
        expect(x.position, sec(expected), reason: '$speed');
      }
    });

    test('E17 a speed change applies to later ticks only', () {
      final x = session()..play();
      x.onTick(Duration.zero);
      x.onTick(ms(200));
      expect(x.position, sec(2));
      x.setSpeed(GpsReplaySpeed.four);
      expect(x.speed, GpsReplaySpeed.four);
      expect(x.position, sec(2), reason: 'changing speed moves nothing');
      x.onTick(ms(400));
      expect(x.position, sec(2) + sec(8));
    });

    test('E18 seek and seekToFraction work paused and while playing', () {
      final x = session();
      x.seek(sec(100));
      expect(x.position, sec(100));
      expect(x.isPlaying, isFalse);
      x.seekToFraction(0.5);
      expect(x.position, sec(300));
      expect(() => x.seekToFraction(double.nan), throwsArgumentError);

      x.play();
      x.onTick(Duration.zero);
      x.seek(sec(10));
      expect(x.isPlaying, isTrue);
      x.onTick(ms(100));
      expect(x.position, sec(11));
    });

    test('E19 reaching the end stops playback and ignores later ticks', () {
      final x = session()..play();
      x.onTick(Duration.zero);
      var elapsed = Duration.zero;
      while (x.isPlaying) {
        elapsed += ms(250);
        x.onTick(elapsed);
      }
      expect(x.isAtEnd, isTrue);
      expect(x.position, sec(600));
      expect(x.isPlaying, isFalse);
      expect(x.fraction, 1);
      expect(x.onTick(elapsed + ms(250)), isFalse);
      expect(x.position, sec(600));
    });

    test('E20 play at the end restarts from the beginning', () {
      final x = session()..seek(sec(600));
      expect(x.isAtEnd, isTrue);
      x.play();
      expect(x.position, Duration.zero);
      expect(x.isPlaying, isTrue);
      x.onTick(ms(5000));
      x.onTick(ms(5100));
      expect(x.position, sec(1));
    });

    test('E21 togglePlayPause alternates', () {
      final x = session();
      x.togglePlayPause();
      expect(x.isPlaying, isTrue);
      x.togglePlayPause();
      expect(x.isPlaying, isFalse);
    });

    test('E22 end-state invariants hold under random use', () {
      // position == active <=> isAtEnd; isAtEnd => not playing.
      final x = session(active: 3, presentation: sec(7));
      var elapsed = Duration.zero;
      for (var i = 0; i < 4000; i++) {
        switch (i % 11) {
          case 0:
            x.play();
          case 3:
            x.pause();
          case 5:
            x.seekToFraction((i % 97) / 96);
          case 7:
            x.setSpeed(GpsReplaySpeed.values[i % 4]);
          case 9:
            x.beginScrub();
            x.scrubToFraction((i % 89) / 88);
            x.endScrub();
          default:
            elapsed += Duration(microseconds: 1 + (i * 104729) % 400000);
            x.onTick(elapsed);
        }
        expect(x.position == x.activeDuration, x.isAtEnd, reason: 'step $i');
        if (x.isAtEnd) expect(x.isPlaying, isFalse, reason: 'step $i');
      }
    });
  });

  group('scrubbing', () {
    test('E23 nothing advances while scrubbing; the scrub position holds', () {
      final x = session()..play();
      x.onTick(Duration.zero);
      x.onTick(ms(100));
      expect(x.position, sec(1));

      x.beginScrub();
      expect(x.isScrubbing, isTrue);
      expect(x.isPlaying, isFalse);
      expect(x.onTick(ms(5000)), isFalse);
      x.scrubToFraction(0.5);
      expect(x.position, sec(300));
      expect(x.onTick(ms(9000)), isFalse);
      expect(x.position, sec(300));
      x.scrubToFraction(0.25);
      expect(x.position, sec(150));
    });

    test('E24 ending a scrub resumes only if it was playing, fresh baseline',
        () {
      final x = session()..play();
      x.onTick(Duration.zero);
      x.onTick(ms(100));
      x.beginScrub();
      x.scrubToFraction(0.5);
      x.endScrub();
      expect(x.isScrubbing, isFalse);
      expect(x.isPlaying, isTrue);
      // The ticker kept running during the scrub: no catch-up jump.
      x.onTick(ms(20000));
      expect(x.position, sec(300));
      x.onTick(ms(20100));
      expect(x.position, sec(301));
    });

    test('E25 a scrub that began while paused stays paused', () {
      final x = session();
      x.beginScrub();
      x.scrubToFraction(0.4);
      x.endScrub();
      expect(x.isPlaying, isFalse);
      expect(x.position, sec(240));
    });

    test('E26 scrubbing to the end does not resume', () {
      final x = session()..play();
      x.beginScrub();
      x.scrubToFraction(1);
      x.endScrub();
      expect(x.isAtEnd, isTrue);
      expect(x.isPlaying, isFalse);
      expect(x.position, sec(600));
    });

    test('E27 play, pause and a second beginScrub are ignored while scrubbing',
        () {
      final x = session()..play();
      x.beginScrub();
      x.play();
      expect(x.isPlaying, isFalse);
      x.pause();
      x.beginScrub(); // does not overwrite the remembered intent
      x.endScrub();
      expect(x.isPlaying, isTrue, reason: 'it was playing before the scrub');
    });

    test('E28 scrubToFraction outside a scrub is a programming error', () {
      expect(() => session().scrubToFraction(0.5), throwsStateError);
      expect(() => session().endScrub(), returnsNormally);
    });
  });

  group('lifecycle', () {
    test('E29 backgrounding pauses and the session never resumes by itself',
        () {
      final x = session()..play();
      x.onTick(Duration.zero);
      x.onTick(ms(1000));
      x.pauseForLifecycle();
      expect(x.isPlaying, isFalse);
      expect(x.position, sec(10));

      // Back in the foreground: ticks may arrive, nothing moves.
      expect(x.onTick(const Duration(hours: 2)), isFalse);
      expect(x.onTick(const Duration(hours: 2, seconds: 1)), isFalse);
      expect(x.position, sec(10));
      expect(x.isPlaying, isFalse);
    });

    test('E30 an explicit play after the background starts a fresh baseline',
        () {
      final x = session()..play();
      x.onTick(Duration.zero);
      x.onTick(ms(1000));
      x.pauseForLifecycle();
      x.onTick(const Duration(hours: 3));

      x.play();
      x.onTick(const Duration(hours: 3, seconds: 5)); // baseline only
      expect(x.position, sec(10), reason: 'no large jump on return');
      x.onTick(const Duration(hours: 3, seconds: 5, milliseconds: 500));
      expect(x.position, sec(15));
      expect(x.stallTimeDiscarded, Duration.zero);
    });

    test('E31 backgrounding without a pause is still safe (stall policy)', () {
      // A UI that forgot to call pauseForLifecycle: the ticker resumes with
      // an hour of elapsed time.
      final x = session(maxFrameDelta: standardCap)..play();
      x.onTick(Duration.zero);
      for (var i = 1; i <= 10; i++) {
        x.onTick(ms(100 * i));
      }
      x.onTick(const Duration(hours: 1));
      expect(x.position, sec(12.5));
      expect(x.isAtEnd, isFalse);
    });

    test('E32 a lifecycle pause during a scrub cancels the scrub\'s resume',
        () {
      final x = session()..play();
      x.beginScrub();
      x.scrubToFraction(0.5);
      x.pauseForLifecycle();
      x.endScrub();
      expect(x.isPlaying, isFalse);
      expect(x.position, sec(300));
    });
  });

  group('degenerate journeys', () {
    test('E33 a zero-length Journey cannot play and nothing moves', () {
      final x = session(active: 0);
      expect(x.canPlay, isFalse);
      expect(x.isAtEnd, isTrue);
      x.play();
      expect(x.isPlaying, isFalse);
      expect(x.onTick(Duration.zero), isFalse);
      expect(x.onTick(ms(1000)), isFalse);
      x.seek(sec(5));
      x.seekToFraction(0.5);
      expect(x.position, Duration.zero);
      x.beginScrub();
      x.scrubToFraction(1);
      x.endScrub();
      expect(x.position, Duration.zero);
      expect(x.takeUpdate().cursor.sampleIndex, -1);
    });

    test('E34 a Journey without samples still has a running clock', () {
      final x = session(active: 600);
      expect(x.hasRoute, isFalse);
      x.play();
      x.onTick(Duration.zero);
      x.onTick(ms(200));
      expect(x.position, sec(2));
      final u = x.takeUpdate();
      expect(u.addedSpans, isEmpty);
      expect(u.cursor.position.kind, GpsReplayPositionKind.unavailable);
    });

    test('E35 a short Journey plays in real time by default', () {
      final x = GpsReplaySession(timeline(active: 12))..play();
      x.onTick(Duration.zero);
      x.onTick(ms(200));
      x.onTick(ms(400));
      expect(x.position, ms(400), reason: '12 s shown in 12 s: real time');
    });
  });

  group('renderer updates', () {
    // 0..22 s one run, a pause, then more samples.
    List<LocalRoutePoint> points() => [
          pt(1, 50.0000, 10),
          pt(2, 50.0001, 15),
          pt(3, 50.0002, 22),
          pt(4, 50.0003, 50),
          pt(5, 50.0004, 55),
        ];

    GpsReplaySession withPoints() => GpsReplaySession(
          GpsReplayTimeline.build(
            route: route(),
            points: points(),
            events: events(100, between: [
              (RouteEventType.pause, 25),
              (RouteEventType.resume, 45),
            ]),
            now: s(100000),
          ),
          presentationDuration: sec(80),
        );

    test('E36 the first takeUpdate initializes an empty renderer', () {
      final x = withPoints();
      expect(x.isDirty, isTrue);
      final u = x.takeUpdate();
      expect(x.isDirty, isFalse);
      expect(u.fromCompletedSampleCount, 0);
      expect(u.addedSpans, isEmpty, reason: 'nothing completed at t = 0');
    });

    test('E37 isDirty tracks position changes only', () {
      final x = withPoints()..play();
      x.takeUpdate();
      expect(x.isDirty, isFalse);
      x.onTick(Duration.zero); // baseline only
      expect(x.isDirty, isFalse);
      x.onTick(ms(1000));
      expect(x.isDirty, isTrue);
      x.takeUpdate();
      x.setSpeed(GpsReplaySpeed.two);
      expect(x.isDirty, isFalse, reason: 'speed alone moves nothing');
      x.seek(x.position);
      expect(x.isDirty, isFalse, reason: 'seek to the same place');
      x.seek(sec(60));
      expect(x.isDirty, isTrue);
    });

    test('E38 a renderer that skips ticks loses nothing: deltas accumulate',
        () {
      final every = withPoints()..play();
      final sparse = withPoints()..play();
      final completedEvery = <int>[];
      var addedEvery = 0;
      var addedSparse = 0;
      var elapsed = Duration.zero;
      every.onTick(elapsed);
      sparse.onTick(elapsed);
      for (var i = 1; i <= 160; i++) {
        elapsed += ms(16);
        every.onTick(elapsed);
        sparse.onTick(elapsed);
        final u = every.takeUpdate();
        addedEvery += u.addedSampleCount;
        completedEvery.add(u.cursor.completedSampleCount);
        if (i % 7 == 0) {
          final v = sparse.takeUpdate();
          addedSparse += v.addedSampleCount;
          expect(v.cursor.completedSampleCount, completedEvery[i - 1]);
        }
      }
      addedSparse += sparse.takeUpdate().addedSampleCount;
      expect(addedSparse, addedEvery);
      expect(addedSparse, sparse.cursor.completedSampleCount);
    });

    test('E39 backward seek is reported as a rewind', () {
      final x = withPoints();
      x.seek(sec(60));
      final first = x.takeUpdate();
      expect(first.addedSampleCount, 5);
      x.seek(sec(15));
      final back = x.takeUpdate();
      expect(back.rewound, isTrue);
      expect(back.removedSampleCount, 3);
    });

    test('E40 resync reports the whole current drawing from empty', () {
      final x = withPoints();
      x.seek(sec(60));
      x.takeUpdate();
      x.seek(sec(30)); // moved but not yet taken
      final u = x.resync();
      expect(u.fromCompletedSampleCount, 0);
      expect(u.addedSampleCount, u.cursor.completedSampleCount);
      expect(u.cursor.playbackTime, sec(30));
      expect(x.isDirty, isFalse);
      // The next delta continues from the resync.
      x.seek(sec(60));
      expect(x.takeUpdate().fromCompletedSampleCount,
          u.cursor.completedSampleCount);
    });

    test('E41 cursor and reachedMarkerCount are pure reads', () {
      final x = withPoints();
      x.seek(sec(30));
      final c = x.cursor;
      expect(c.playbackTime, sec(30));
      expect(x.reachedMarkerCount, 0);
      expect(x.isDirty, isTrue, reason: 'reading the cursor is not taking');
    });
  });

  group('purity', () {
    test('E42 the session is pure Dart: no Flutter, timers or wall clock', () {
      final code = File('lib/features/gps/replay/gps_replay_session.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // 'Ticker' as a whole word (restartTicker is the session's own method).
      expect(RegExp(r'(?<![A-Za-z])Ticker').hasMatch(code), isFalse,
          reason: 'Ticker');
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
        'DateTime',
        'Stopwatch',
        'SchedulerBinding',
        'WidgetsBinding',
      ]) {
        expect(code.contains(banned), isFalse, reason: banned);
      }
    });
  });
}
