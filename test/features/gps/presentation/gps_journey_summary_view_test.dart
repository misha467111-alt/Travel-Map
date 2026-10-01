import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_summary_view.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_controls.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_ui_state.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_summary.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

GpsJourneySummary _summary({
  GpsJourneyStatistics? stats,
  int moments = 3,
}) =>
    GpsJourneySummary(
      routeId: 'r1',
      momentCount: moments,
      pointCount: 10,
      statistics: stats ??
          const GpsJourneyStatistics(
            totalDistanceMeters: 12345,
            elapsed: Duration(hours: 2, minutes: 30),
            moving: Duration(hours: 2),
            paused: Duration(minutes: 30),
            averageSpeedMps: 1.7,
            maxSpeedMps: 3.4,
            elevationGainMeters: 250,
            elevationLossMeters: 180,
          ),
    );

Widget _wrap(Widget child, {double width = 390, double scale = 1.0}) =>
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('Finish confirmation (E01/E02)', () {
    Future<(List<int>, Finder)> pumpControls(WidgetTester tester) async {
      final taps = <int>[];
      await tester.pumpWidget(_wrap(GpsRecordingControls(
        uiState: mapGpsRecordingUiState(
            const GpsRecordingState(status: GpsRecordingStatus.recording)),
        onFinish: () => taps.add(1),
      )));
      return (taps, find.byKey(const Key('gps_recording_finish_button')));
    }

    testWidgets('E01 asks before finishing, with the agreed copy',
        (tester) async {
      final (taps, finish) = await pumpControls(tester);

      await tester.tap(finish);
      await tester.pumpAndSettle();

      expect(find.text('Завершити подорож?'), findsOneWidget);
      expect(find.text('Після завершення запис цієї подорожі буде зупинено.'),
          findsOneWidget);
      expect(taps, isEmpty, reason: 'nothing finishes before confirmation');
    });

    testWidgets('E02 Скасувати keeps the Journey active', (tester) async {
      final (taps, finish) = await pumpControls(tester);

      await tester.tap(finish);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gps_finish_cancel_button')));
      await tester.pumpAndSettle();

      expect(taps, isEmpty);
      expect(find.text('Завершити подорож?'), findsNothing);
      expect(finish, findsOneWidget, reason: 'controls remain available');
    });

    testWidgets('confirming finishes exactly once', (tester) async {
      final (taps, finish) = await pumpControls(tester);

      await tester.tap(finish);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gps_finish_confirm_button')));
      await tester.pumpAndSettle();

      expect(taps, hasLength(1));
    });
  });

  group('Summary content', () {
    testWidgets('shows completion title and every Phase 0 metric',
        (tester) async {
      await tester.pumpWidget(_wrap(GpsJourneySummaryView(
        summary: _summary(),
        onDone: () {},
      )));

      expect(find.text('Подорож завершено'), findsOneWidget);
      expect(find.text('12.35 км'), findsOneWidget);
      expect(find.text('2 год 30 хв'), findsOneWidget);
      expect(find.text('2 год 0 хв'), findsOneWidget);
      expect(find.text('30 хв 0 с'), findsOneWidget);
      expect(find.text('6.1 км/год'), findsOneWidget);
      expect(find.text('12.2 км/год'), findsOneWidget);
      expect(find.text('250 м'), findsOneWidget);
      expect(find.text('180 м'), findsOneWidget);
      expect(find.text('Темп'), findsOneWidget);
      expect(find.text('Точки подорожі'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('E24/E25 unavailable metrics render a dash, never NaN',
        (tester) async {
      await tester.pumpWidget(_wrap(GpsJourneySummaryView(
        summary: _summary(stats: GpsJourneyStatistics.empty, moments: 0),
        onDone: () {},
      )));

      expect(find.text('—'), findsNWidgets(3),
          reason: 'average speed, max speed and pace are unavailable');
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
      expect(find.text('0'), findsOneWidget, reason: 'zero Moments');
    });

    testWidgets('no invented metrics are offered', (tester) async {
      await tester.pumpWidget(_wrap(GpsJourneySummaryView(
        summary: _summary(),
        onDone: () {},
      )));

      for (final invented in ['Калор', 'Пульс', 'Досягнення']) {
        expect(find.textContaining(invented), findsNothing);
      }
    });

    testWidgets('Готово calls onDone once', (tester) async {
      var done = 0;
      await tester.pumpWidget(_wrap(GpsJourneySummaryView(
        summary: _summary(),
        onDone: () => done++,
      )));

      await tester.tap(find.byKey(const Key('gps_summary_done_button')));
      await tester.pump();

      expect(done, 1);
    });
  });

  group('Panel (E08/E26)', () {
    testWidgets('renders the loaded summary from the provider', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          gpsJourneySummaryProvider
              .overrideWith((ref, args) async => _summary(moments: 7)),
        ],
        child: _wrap(GpsJourneySummaryPanel(
          ownerId: 'me',
          routeId: 'r1',
          onDone: () {},
        )),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Подорож завершено'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a missing/non-completed route shows no success Summary',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          gpsJourneySummaryProvider.overrideWith((ref, args) async => null),
        ],
        child: _wrap(GpsJourneySummaryPanel(
          ownerId: 'me',
          routeId: 'r1',
          onDone: () {},
        )),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Подорож завершено'), findsNothing);
      expect(find.text('Підсумок подорожі недоступний.'), findsOneWidget);
      expect(find.byKey(const Key('gps_summary_done_button')), findsOneWidget);
    });
  });

  group('Responsive', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('fits ${width}dp @ ${scale}x, exit action reachable',
            (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_wrap(
            GpsJourneySummaryView(summary: _summary(), onDone: () {}),
            width: width,
            scale: scale,
          ));

          expect(tester.takeException(), isNull);
          expect(
              find.byKey(const Key('gps_summary_done_button')), findsOneWidget);
          final button =
              tester.getRect(find.byKey(const Key('gps_summary_done_button')));
          expect(button.bottom, lessThanOrEqualTo(700));
          // Last metric is reachable by scrolling.
          await tester.scrollUntilVisible(
            find.text('Точки подорожі'),
            200,
            scrollable: find.descendant(
              of: find.byKey(const Key('gps_summary_scroll')),
              matching: find.byType(Scrollable),
            ),
          );
          expect(find.text('Точки подорожі'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
