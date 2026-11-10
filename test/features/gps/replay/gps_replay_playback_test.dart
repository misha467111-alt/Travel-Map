import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/replay/gps_journey_replay.dart';
import 'package:flutter_application_1/features/gps/replay/gps_replay_playback.dart';

/// Journey Phase 1I-B1A -- the pure playback clock. No widget, no real time:
/// every test drives [GpsReplayPlayback.advance] explicitly.
void main() {
  Duration sec(num s) => Duration(microseconds: (s * 1000000).round());

  // 600 s of active time shown in 60 s: at 1x one presentation second is
  // ten active seconds.
  GpsReplayPlayback clock({
    num active = 600,
    num presentation = 60,
    GpsReplaySpeed speed = GpsReplaySpeed.one,
  }) =>
      GpsReplayPlayback(
        activeDuration: sec(active),
        presentationDuration: sec(presentation),
        speed: speed,
      );

  group('state', () {
    test('B01 starts paused at zero, not at the end', () {
      final p = clock();
      expect(p.position, Duration.zero);
      expect(p.isPlaying, isFalse);
      expect(p.isAtEnd, isFalse);
      expect(p.progress, 0);
      expect(p.speed, GpsReplaySpeed.one);
      expect(p.activeDuration, sec(600));
      expect(p.presentationDuration, sec(60));
    });

    test('B02 the default presentation length is one minute', () {
      expect(GpsReplayPlayback.defaultPresentationDuration, sec(60));
      final p = GpsReplayPlayback(activeDuration: sec(600));
      expect(p.presentationDuration, sec(60));
    });

    test('B03 invalid construction is rejected', () {
      expect(() => GpsReplayPlayback(activeDuration: sec(-1)),
          throwsArgumentError);
      expect(
          () => GpsReplayPlayback(
              activeDuration: sec(10), presentationDuration: Duration.zero),
          throwsArgumentError);
      expect(
          () => GpsReplayPlayback(
              activeDuration: sec(10), presentationDuration: sec(-5)),
          throwsArgumentError);
    });

    test('B04 the supported speeds are exactly 0.5x, 1x, 2x and 4x', () {
      expect([for (final s in GpsReplaySpeed.values) s.multiplier],
          [0.5, 1.0, 2.0, 4.0]);
    });
  });

  group('advance', () {
    test('B05 a paused clock does not move', () {
      final p = clock();
      expect(p.advance(sec(10)), Duration.zero);
      p.play();
      p.advance(sec(1));
      p.pause();
      final held = p.position;
      expect(p.advance(sec(30)), held);
      expect(p.isPlaying, isFalse);
    });

    test('B06 1x maps presentation time to active time by the ratio', () {
      final p = clock()..play();
      expect(p.advance(sec(1)), sec(10));
      expect(p.advance(sec(2.5)), sec(35));
      expect(p.progress, closeTo(35 / 600, 1e-12));
    });

    test('B07 speeds scale the rate: 0.5x, 2x and 4x', () {
      for (final (speed, expected) in [
        (GpsReplaySpeed.half, 5),
        (GpsReplaySpeed.one, 10),
        (GpsReplaySpeed.two, 20),
        (GpsReplaySpeed.four, 40),
      ]) {
        final p = clock(speed: speed)..play();
        expect(p.advance(sec(1)), sec(expected), reason: '$speed');
      }
    });

    test('B08 changing speed mid-playback applies to later advances only', () {
      final p = clock()..play();
      p.advance(sec(1)); // 10 s
      p.setSpeed(GpsReplaySpeed.four);
      expect(p.speed, GpsReplaySpeed.four);
      expect(p.advance(sec(1)), sec(50));
      p.setSpeed(GpsReplaySpeed.half);
      expect(p.advance(sec(2)), sec(60));
    });

    test('B09 other presentation lengths: real time and a long replay', () {
      final realTime = clock(active: 600, presentation: 600)..play();
      expect(realTime.advance(sec(5)), sec(5));
      final slowMo = clock(active: 30, presentation: 120)..play();
      expect(slowMo.advance(sec(8)), sec(2));
    });

    test('B10 negative elapsed time is rejected', () {
      final p = clock()..play();
      expect(() => p.advance(const Duration(microseconds: -1)),
          throwsArgumentError);
    });

    test('B11 a zero elapsed time changes nothing', () {
      final p = clock()..play();
      p.advance(sec(1));
      expect(p.advance(Duration.zero), sec(10));
      expect(p.isPlaying, isTrue);
    });

    test('B12 many small steps equal one large step (determinism)', () {
      final a = clock(speed: GpsReplaySpeed.two)..play();
      final b = clock(speed: GpsReplaySpeed.two)..play();
      for (var i = 0; i < 1000; i++) {
        a.advance(const Duration(milliseconds: 7));
      }
      b.advance(const Duration(milliseconds: 7000));
      expect((a.position - b.position).inMicroseconds.abs(), lessThan(50));

      // Same inputs, same outputs.
      final c = clock(speed: GpsReplaySpeed.two)..play();
      final d = clock(speed: GpsReplaySpeed.two)..play();
      for (var i = 0; i < 300; i++) {
        final step = Duration(microseconds: 1000 + (i * 7919) % 40000);
        expect(c.advance(step), d.advance(step));
      }
    });

    test('B13 playback is monotone and never leaves the axis', () {
      final random = Random(7);
      for (final speed in GpsReplaySpeed.values) {
        final p = clock(speed: speed)..play();
        var previous = Duration.zero;
        for (var i = 0; i < 400 && p.isPlaying; i++) {
          final now = p.advance(Duration(microseconds: random.nextInt(900000)));
          expect(now >= previous, isTrue);
          expect(now <= p.activeDuration, isTrue);
          previous = now;
        }
      }
    });
  });

  group('end of replay', () {
    test('B14 reaching the end clamps and stops playback', () {
      final p = clock()..play();
      expect(p.advance(sec(59.999999)) < sec(600), isTrue);
      expect(p.isAtEnd, isFalse);
      expect(p.isPlaying, isTrue);

      expect(p.advance(sec(1)), sec(600));
      expect(p.isAtEnd, isTrue);
      expect(p.isPlaying, isFalse);
      expect(p.progress, 1);
    });

    test('B15 an enormous elapsed time (app suspended) just ends the replay',
        () {
      final p = clock(speed: GpsReplaySpeed.four)..play();
      expect(p.advance(const Duration(days: 3650)), sec(600));
      expect(p.isAtEnd, isTrue);
      expect(p.isPlaying, isFalse);
    });

    test('B16 at the end the clock no longer moves; play() restarts', () {
      final p = clock()
        ..play()
        ..advance(sec(100));
      expect(p.advance(sec(5)), sec(600));

      p.play();
      expect(p.position, Duration.zero);
      expect(p.isPlaying, isTrue);
      expect(p.isAtEnd, isFalse);
      expect(p.advance(sec(1)), sec(10));
    });

    test('B17 a zero-length Journey is always at its end and cannot play', () {
      final p = GpsReplayPlayback(activeDuration: Duration.zero);
      expect(p.isAtEnd, isTrue);
      expect(p.progress, 1);
      p.play();
      expect(p.isPlaying, isFalse);
      expect(p.advance(sec(10)), Duration.zero);
      p.seek(sec(5));
      expect(p.position, Duration.zero);
      p.seekToFraction(0.5);
      expect(p.position, Duration.zero);
    });
  });

  group('seek', () {
    test('B18 seek clamps into the axis', () {
      final p = clock();
      p.seek(sec(100));
      expect(p.position, sec(100));
      p.seek(sec(-50));
      expect(p.position, Duration.zero);
      p.seek(sec(9999));
      expect(p.position, sec(600));
      expect(p.isAtEnd, isTrue);
    });

    test('B19 seek keeps the play / pause intent', () {
      final paused = clock()..seek(sec(100));
      expect(paused.isPlaying, isFalse);

      final playing = clock()..play();
      playing.seek(sec(300));
      expect(playing.isPlaying, isTrue);
      expect(playing.advance(sec(1)), sec(310));
    });

    test('B20 seeking to the end while playing stops playback', () {
      final p = clock()..play();
      p.seek(sec(600));
      expect(p.isAtEnd, isTrue);
      expect(p.isPlaying, isFalse);
    });

    test('B21 seeking backwards from the end allows playback again', () {
      final p = clock()
        ..play()
        ..advance(sec(100));
      p.seek(sec(500));
      expect(p.isAtEnd, isFalse);
      p.play();
      expect(p.position, sec(500), reason: 'not at the end: no restart');
      expect(p.advance(sec(1)), sec(510));
    });

    test('B22 seekToFraction maps a slider value onto the axis', () {
      final p = clock();
      p.seekToFraction(0.25);
      expect(p.position, sec(150));
      expect(p.progress, closeTo(0.25, 1e-12));
      p.seekToFraction(-3);
      expect(p.position, Duration.zero);
      p.seekToFraction(7);
      expect(p.position, sec(600));
      expect(p.isAtEnd, isTrue);
      expect(() => p.seekToFraction(double.nan), throwsArgumentError);
    });

    test('B23 pause and play keep the position', () {
      final p = clock()..play();
      p.advance(sec(2));
      p.pause();
      expect(p.position, sec(20));
      p.play();
      expect(p.position, sec(20));
      expect(p.advance(sec(1)), sec(30));
    });
  });

  group('timeline link', () {
    test('B24 forTimeline uses the timeline\'s active duration', () {
      final t0 = DateTime.utc(2026, 1, 1, 10);
      LocalRouteEvent e(int seq, String type, int s) => LocalRouteEvent(
            recordedRouteId: 'r',
            seq: seq,
            ownerId: 'o',
            eventType: type,
            occurredAt: t0.add(Duration(seconds: s)),
          );
      final timeline = GpsReplayTimeline.build(
        route: LocalRecordedRoute(
          id: 'r',
          ownerId: 'o',
          transportMode: 'walking',
          status: RecordedRouteStatus.completed,
          visibility: 'private',
          startedAt: t0,
          createdAt: t0,
          updatedAt: t0,
          syncStatus: RouteSyncStatus.synced,
        ),
        points: const [],
        events: [
          e(1, RouteEventType.start, 0),
          e(2, RouteEventType.pause, 100),
          e(3, RouteEventType.resume, 160),
          e(4, RouteEventType.finish, 700),
        ],
        now: t0.add(const Duration(days: 1)),
      );

      final p = GpsReplayPlayback.forTimeline(timeline,
          presentationDuration: sec(30), speed: GpsReplaySpeed.two);
      expect(p.activeDuration, sec(640), reason: '700 s minus the 60 s pause');
      expect(p.presentationDuration, sec(30));
      expect(p.speed, GpsReplaySpeed.two);
      p.play();
      expect(p.advance(sec(15)), sec(640));
      expect(p.isAtEnd, isTrue);
    });
  });

  group('end rounding (P3-1)', () {
    // Invariants that must hold after EVERY call.
    void expectConsistent(GpsReplayPlayback p, {String? reason}) {
      expect(p.position == p.activeDuration, p.isAtEnd,
          reason: 'position at end <=> isAtEnd; $reason');
      if (p.isAtEnd) {
        expect(p.isPlaying, isFalse, reason: 'ended => stopped; $reason');
      }
      expect(p.position <= p.activeDuration, isTrue, reason: reason);
      expect(p.position.isNegative, isFalse, reason: reason);
    }

    test('B26 the review reproduction: 1 s shown in 3 s, advance 2 999 999 us',
        () {
      final p = GpsReplayPlayback(
          activeDuration: sec(1), presentationDuration: sec(3))
        ..play();
      p.advance(const Duration(microseconds: 2999999));

      expect(p.isAtEnd, isFalse, reason: 'one microsecond of show remains');
      expect(p.isPlaying, isTrue);
      expect(p.position < sec(1), isTrue);
      expectConsistent(p);

      // The last microsecond really ends it.
      p.advance(const Duration(microseconds: 1));
      expect(p.isAtEnd, isTrue);
      expect(p.position, sec(1));
      expect(p.isPlaying, isFalse);
      expectConsistent(p);
    });

    test('B27 exactly the full presentation time ends the replay', () {
      for (final speed in GpsReplaySpeed.values) {
        final p = GpsReplayPlayback(
            activeDuration: sec(1), presentationDuration: sec(3), speed: speed)
          ..play();
        final full =
            Duration(microseconds: (3000000 / speed.multiplier).round());
        p.advance(full);
        expect(p.isAtEnd, isTrue, reason: '$speed');
        expect(p.position, sec(1), reason: '$speed');
        expect(p.isPlaying, isFalse, reason: '$speed');
      }
    });

    test('B28 just before the end stays playing at every speed', () {
      for (final speed in GpsReplaySpeed.values) {
        final p = GpsReplayPlayback(
            activeDuration: sec(1), presentationDuration: sec(3), speed: speed)
          ..play();
        final full = (3000000 / speed.multiplier).round();
        p.advance(Duration(microseconds: full - 3));
        expect(p.isAtEnd, isFalse, reason: '$speed');
        expect(p.isPlaying, isTrue, reason: '$speed');
        expectConsistent(p, reason: '$speed');
      }
    });

    test('B29 position never shows the end before the clock is at the end', () {
      // seekToFraction just below 1 rounds to the last microsecond.
      final p = GpsReplayPlayback(activeDuration: sec(1))..play();
      p.seekToFraction(0.9999999999);
      expect(p.isAtEnd, isFalse);
      expect(p.isPlaying, isTrue);
      expect(p.position < sec(1), isTrue);
      expectConsistent(p);
      p.advance(const Duration(milliseconds: 20));
      expect(p.isAtEnd, isTrue);
      expectConsistent(p);
    });

    test('B30 very short Journeys with fractional microsecond rates', () {
      for (final activeMicros in [1, 2, 3, 7, 100, 999]) {
        for (final presentationMicros in [1, 3, 7, 1000, 2999999]) {
          for (final speed in GpsReplaySpeed.values) {
            final p = GpsReplayPlayback(
                activeDuration: Duration(microseconds: activeMicros),
                presentationDuration:
                    Duration(microseconds: presentationMicros),
                speed: speed)
              ..play();
            // Jump close to the end, then walk the last microseconds.
            final total = (presentationMicros / speed.multiplier).round();
            var steps = 0;
            var previous = p.advance(Duration(microseconds: max(0, total - 3)));
            expectConsistent(p, reason: '$activeMicros/$presentationMicros');
            while (p.isPlaying && steps++ < 100) {
              final now = p.advance(const Duration(microseconds: 1));
              expectConsistent(p, reason: '$activeMicros/$presentationMicros');
              expect(now >= previous, isTrue);
              previous = now;
            }
            expect(p.isAtEnd, isTrue,
                reason: '$activeMicros/$presentationMicros $speed ended');
          }
        }
      }
    });

    test('B31 randomized: the invariants hold after every call', () {
      final random = Random(31);
      for (var seed = 0; seed < 300; seed++) {
        final p = GpsReplayPlayback(
          activeDuration: Duration(microseconds: 1 + random.nextInt(5000000)),
          presentationDuration:
              Duration(microseconds: 1 + random.nextInt(9000000)),
          speed: GpsReplaySpeed.values[random.nextInt(4)],
        );
        for (var i = 0; i < 60; i++) {
          switch (random.nextInt(6)) {
            case 0:
              p.play();
            case 1:
              p.pause();
            case 2:
              p.seek(Duration(microseconds: random.nextInt(6000000)));
            case 3:
              p.seekToFraction(random.nextDouble());
            case 4:
              p.setSpeed(GpsReplaySpeed.values[random.nextInt(4)]);
            default:
              p.advance(Duration(microseconds: random.nextInt(3000000)));
          }
          expectConsistent(p, reason: 'seed $seed step $i');
        }
      }
    });
  });

  group('purity', () {
    test('B25 the engine has no timers, streams, wall clock or Flutter', () {
      final code = File('lib/features/gps/replay/gps_replay_playback.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final banned in [
        'package:flutter',
        'dart:async',
        'dart:io',
        'dart:ui',
        'Timer',
        'Stream',
        'Future',
        'Ticker',
        'Isolate',
        'DateTime',
        'Stopwatch',
        'SchedulerBinding',
        'ChangeNotifier',
      ]) {
        expect(code.contains(banned), isFalse, reason: banned);
      }
    });
  });
}
