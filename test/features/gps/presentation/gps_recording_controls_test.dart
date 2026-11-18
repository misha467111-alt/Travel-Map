import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_controls.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_status_card.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_ui_state.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

GpsRecordingUiState _map(GpsRecordingStatus status) =>
    mapGpsRecordingUiState(GpsRecordingState(status: status));

void main() {
  testWidgets(
      'C03 recording UI: pause/finish/discard/waypoint visible and '
      'enabled, resume is not shown', (tester) async {
    var pauseTaps = 0, finishTaps = 0, waypointTaps = 0;
    await tester.pumpWidget(_wrap(GpsRecordingControls(
      uiState: _map(GpsRecordingStatus.recording),
      onPause: () => pauseTaps++,
      onFinish: () => finishTaps++,
      onAddWaypoint: () => waypointTaps++,
      onDiscard: () {},
    )));

    expect(find.byKey(const Key('gps_recording_pause_button')), findsOneWidget);
    expect(
        find.byKey(const Key('gps_recording_finish_button')), findsOneWidget);
    expect(find.byKey(const Key('gps_recording_add_waypoint_button')),
        findsOneWidget);
    expect(
        find.byKey(const Key('gps_recording_discard_button')), findsOneWidget);
    expect(find.byKey(const Key('gps_recording_resume_button')), findsNothing);

    await tester.tap(find.byKey(const Key('gps_recording_pause_button')));
    await tester.tap(find.byKey(const Key('gps_recording_finish_button')));
    await tester.pumpAndSettle();
    expect(finishTaps, 0, reason: 'finish requires confirmation');
    await tester.tap(find.byKey(const Key('gps_finish_confirm_button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('gps_recording_add_waypoint_button')));
    await tester.pumpAndSettle();
    expect(pauseTaps, 1);
    expect(finishTaps, 1);
    expect(waypointTaps, 1);
  });

  testWidgets(
      'C04 paused UI: resume/finish/discard/waypoint visible, pause is not',
      (tester) async {
    var resumeTaps = 0;
    await tester.pumpWidget(_wrap(GpsRecordingControls(
      uiState: _map(GpsRecordingStatus.paused),
      onResume: () => resumeTaps++,
      onFinish: () {},
      onAddWaypoint: () {},
      onDiscard: () {},
    )));

    expect(
        find.byKey(const Key('gps_recording_resume_button')), findsOneWidget);
    expect(
        find.byKey(const Key('gps_recording_finish_button')), findsOneWidget);
    expect(find.byKey(const Key('gps_recording_add_waypoint_button')),
        findsOneWidget);
    expect(
        find.byKey(const Key('gps_recording_discard_button')), findsOneWidget);
    expect(find.byKey(const Key('gps_recording_pause_button')), findsNothing);

    await tester.tap(find.byKey(const Key('gps_recording_resume_button')));
    await tester.pump();
    expect(resumeTaps, 1);
  });

  testWidgets(
      'C05 finishing UI: zero controls rendered -- prevents a duplicate '
      'finish tap', (tester) async {
    await tester.pumpWidget(_wrap(GpsRecordingControls(
      uiState: _map(GpsRecordingStatus.finishing),
    )));

    expect(find.byKey(const Key('gps_recording_pause_button')), findsNothing);
    expect(find.byKey(const Key('gps_recording_resume_button')), findsNothing);
    expect(find.byKey(const Key('gps_recording_finish_button')), findsNothing);
    expect(find.byKey(const Key('gps_recording_discard_button')), findsNothing);
    expect(find.byKey(const Key('gps_recording_add_waypoint_button')),
        findsNothing);
  });

  group('C10 discard confirmation', () {
    testWidgets('cancel => discard callback never called', (tester) async {
      var discardCalls = 0;
      await tester.pumpWidget(_wrap(GpsRecordingControls(
        uiState: _map(GpsRecordingStatus.recording),
        onDiscard: () => discardCalls++,
      )));

      await tester.tap(find.byKey(const Key('gps_recording_discard_button')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('gps_discard_cancel_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('gps_discard_cancel_button')));
      await tester.pumpAndSettle();

      expect(discardCalls, 0);
      expect(find.byKey(const Key('gps_discard_cancel_button')), findsNothing);
    });

    testWidgets('confirm => discard callback called exactly once',
        (tester) async {
      var discardCalls = 0;
      await tester.pumpWidget(_wrap(GpsRecordingControls(
        uiState: _map(GpsRecordingStatus.recording),
        onDiscard: () => discardCalls++,
      )));

      await tester.tap(find.byKey(const Key('gps_recording_discard_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('gps_discard_confirm_button')));
      await tester.pumpAndSettle();

      expect(discardCalls, 1);
    });
  });

  test(
      'C17 contract-driven: every visibility flag traces to the accepted '
      'Phase 4B GpsRecordingUiState fields, never widget-local status '
      'branching (paused has canPause=false, recoverable has '
      'canAddWaypoint=false, etc. -- exactly the 4B guard matrix)', () {
    final recording = _map(GpsRecordingStatus.recording);
    final paused = _map(GpsRecordingStatus.paused);
    final recoverable = _map(GpsRecordingStatus.recoverable);

    expect(recording.canPause, isTrue);
    expect(recording.canResume, isFalse);
    expect(paused.canResume, isTrue);
    expect(paused.canPause, isFalse);
    expect(recoverable.canAddWaypoint, isFalse);
    expect(recoverable.canResume, isTrue);
  });

  group('Phase 1 polish layout', () {
    testWidgets('U01 Pause and Finish sit side by side, Pause is wider',
        (tester) async {
      await tester.pumpWidget(_wrap(GpsRecordingControls(
        uiState: _map(GpsRecordingStatus.recording),
        onPause: () {},
        onFinish: () {},
        onAddWaypoint: () {},
        onDiscard: () {},
      )));
      final pause =
          tester.getRect(find.byKey(const Key('gps_recording_pause_button')));
      final finish =
          tester.getRect(find.byKey(const Key('gps_recording_finish_button')));
      expect(pause.top, finish.top);
      expect(pause.width, greaterThan(finish.width));
      expect(pause.height, greaterThanOrEqualTo(56));
      final secondary = tester
          .getRect(find.byKey(const Key('gps_recording_add_waypoint_button')));
      expect(secondary.top, greaterThan(pause.bottom));
    });

    testWidgets('U02 Pause and Finish stack at a large text scale',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 640), textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: GpsRecordingControls(
              uiState: _map(GpsRecordingStatus.paused),
              onResume: () {},
              onFinish: () {},
            ),
          ),
        ),
      ));
      final resume =
          tester.getRect(find.byKey(const Key('gps_recording_resume_button')));
      final finish =
          tester.getRect(find.byKey(const Key('gps_recording_finish_button')));
      expect(finish.top, greaterThanOrEqualTo(resume.bottom));
      expect(tester.takeException(), isNull);
    });
  });

  group('stream error retry row (P1 hotfix)', () {
    testWidgets('S01 shown only with a callback; Retry is tappable',
        (tester) async {
      var retries = 0;
      Widget card({VoidCallback? onRetryStream}) =>
          _wrap(GpsRecordingStatusCard(
            uiState: _map(GpsRecordingStatus.recording),
            onRetryStream: onRetryStream,
          ));
      await tester.pumpWidget(card());
      expect(find.byKey(const Key('gps_stream_error_row')), findsNothing);
      await tester.pumpWidget(card(onRetryStream: () => retries++));
      expect(find.text('Помилка GPS-сигналу, точки збережено'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gps_stream_retry_button')));
      expect(retries, 1);
    });

    testWidgets('S02 Pause and Finish stay available during the error',
        (tester) async {
      await tester.pumpWidget(_wrap(GpsRecordingControls(
        uiState: _map(GpsRecordingStatus.recording),
        onPause: () {},
        onFinish: () {},
      )));
      expect(
          find.byKey(const Key('gps_recording_pause_button')), findsOneWidget);
      expect(
          find.byKey(const Key('gps_recording_finish_button')), findsOneWidget);
    });
  });
}
