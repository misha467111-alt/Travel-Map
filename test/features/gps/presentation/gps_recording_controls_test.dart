import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_controls.dart';
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
    await tester
        .tap(find.byKey(const Key('gps_recording_add_waypoint_button')));
    await tester.pump();
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
}
