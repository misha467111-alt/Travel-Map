import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_stats.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_ui_state.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('C11 pointCount rendered directly from stats (no Drift query)',
      (tester) async {
    await tester.pumpWidget(_wrap(const GpsRecordingStats(
      stats: GpsRecordingStatsUiState(pointCount: 137),
      isTicking: false,
    )));

    expect(find.byKey(const Key('gps_recording_point_count')), findsOneWidget);
    final text =
        tester.widget<Text>(find.byKey(const Key('gps_recording_point_count')));
    expect(text.data, '137');
  });

  testWidgets('C12 no fake live distance rendered anywhere in the stats widget',
      (tester) async {
    await tester.pumpWidget(_wrap(const GpsRecordingStats(
      stats: GpsRecordingStatsUiState(
        pointCount: 10,
        lastLatitude: 50.45,
        lastLongitude: 30.52,
        lastHorizontalAccuracyMeters: 12,
      ),
      isTicking: true,
    )));

    // Only the three documented stat tiles exist: duration, points,
    // accuracy. No "distance"/"км"/"м" (as a distance unit) label exists
    // anywhere -- the accuracy tile's "м" (meters) is the one legitimate
    // use of that unit and is asserted separately by its exact key/text.
    expect(find.textContaining('Дистанція'), findsNothing);
    expect(find.textContaining('Відстань'), findsNothing);
    expect(find.byKey(const Key('gps_recording_accuracy')), findsOneWidget);
    final accuracyText =
        tester.widget<Text>(find.byKey(const Key('gps_recording_accuracy')));
    expect(accuracyText.data, '±12 м');
  });

  testWidgets('accuracy tile shows a dash when no sample is available yet',
      (tester) async {
    await tester.pumpWidget(_wrap(const GpsRecordingStats(
      stats: GpsRecordingStatsUiState(pointCount: 0),
      isTicking: false,
    )));
    final accuracyText =
        tester.widget<Text>(find.byKey(const Key('gps_recording_accuracy')));
    expect(accuracyText.data, '—');
  });

  group('elapsed-time ticker lifecycle', () {
    testWidgets('ticks once a second only while isTicking is true',
        (tester) async {
      final start = DateTime.utc(2026, 1, 1, 10, 0, 0);
      var fakeNow = start;
      await tester.pumpWidget(_wrap(GpsElapsedTimeText(
        startedAt: start,
        isTicking: true,
        now: () => fakeNow,
      )));
      expect(find.text('00:00'), findsOneWidget);

      fakeNow = start.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:03'), findsOneWidget);
    });

    testWidgets('freezes (stops ticking) once isTicking becomes false',
        (tester) async {
      final start = DateTime.utc(2026, 1, 1, 10, 0, 0);
      var fakeNow = start;
      bool ticking = true;

      await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
        return _wrap(GpsElapsedTimeText(
          startedAt: start,
          isTicking: ticking,
          now: () => fakeNow,
        ));
      }));

      fakeNow = start.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:02'), findsOneWidget);

      // Flip to paused: rebuild with isTicking=false. Even though real
      // time (fakeNow) keeps moving forward, the displayed value must
      // not advance because the internal Timer has been cancelled.
      ticking = false;
      fakeNow = start.add(const Duration(seconds: 10));
      await tester.pumpWidget(_wrap(GpsElapsedTimeText(
        startedAt: start,
        isTicking: false,
        now: () => fakeNow,
      )));
      // One rebuild happens from the pumpWidget call itself, showing the
      // fresh now() at that instant -- that's expected (it's not a
      // *timer* tick, just a normal widget rebuild). What matters is that
      // no further Timer-driven ticks occur after this.
      await tester.pump(const Duration(seconds: 5));
      final afterFreeze = tester.widget<Text>(find.byType(Text).first).data;
      fakeNow = start.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 5));
      final stillFrozen = tester.widget<Text>(find.byType(Text).first).data;
      expect(stillFrozen, afterFreeze,
          reason: 'no Timer should be firing once isTicking is false');
    });

    testWidgets('disposes its timer cleanly on widget removal', (tester) async {
      await tester.pumpWidget(_wrap(GpsElapsedTimeText(
        startedAt: DateTime.utc(2026, 1, 1),
        isTicking: true,
      )));
      await tester.pump(const Duration(seconds: 1));

      // Replace the whole tree -- if the timer weren't cancelled in
      // dispose(), pumping further would either throw or leak.
      await tester.pumpWidget(_wrap(const SizedBox()));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a placeholder when startedAt is not yet known',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const GpsElapsedTimeText(startedAt: null, isTicking: false),
      ));
      expect(find.text('--:--'), findsOneWidget);
    });
  });
}
