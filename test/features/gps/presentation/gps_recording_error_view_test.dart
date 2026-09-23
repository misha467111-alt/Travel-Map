import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_error_view.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_ui_state.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('C07 permission error UI: clear, distinct explanation shown',
      (tester) async {
    await tester.pumpWidget(_wrap(const GpsRecordingErrorView(
      kind: GpsRecordingErrorKind.permissionProblem,
      detail: 'дозвіл відхилено',
    )));

    expect(find.byKey(const Key('gps_error_title')), findsOneWidget);
    expect(find.textContaining('дозвіл'), findsWidgets);
  });

  testWidgets(
      'C08 service-disabled error UI: clear, distinct explanation shown',
      (tester) async {
    await tester.pumpWidget(_wrap(const GpsRecordingErrorView(
      kind: GpsRecordingErrorKind.locationServiceDisabled,
      detail: 'служби геолокації вимкнені',
    )));

    expect(find.byKey(const Key('gps_error_title')), findsOneWidget);
    expect(find.textContaining('геолокац'), findsWidgets);
  });

  testWidgets(
      'C09 generic error UI: shows only the safe short detail it was given, '
      'never dumps unrelated/raw technical content', (tester) async {
    const safeDetail = 'location stream error';
    await tester.pumpWidget(_wrap(const GpsRecordingErrorView(
      kind: GpsRecordingErrorKind.otherError,
      detail: safeDetail,
    )));

    expect(find.byKey(const Key('gps_error_title')), findsOneWidget);
    expect(find.byKey(const Key('gps_error_detail')), findsOneWidget);
    final detailText =
        tester.widget<Text>(find.byKey(const Key('gps_error_detail')));
    expect(detailText.data, safeDetail,
        reason: 'the widget must render exactly the given detail string, '
            'never append/wrap raw exception text of its own');
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('at package:'), findsNothing);
    expect(find.textContaining('#0 '), findsNothing); // stack-trace-shaped
  });

  testWidgets('otherError with no detail renders cleanly (detail omitted)',
      (tester) async {
    await tester.pumpWidget(_wrap(const GpsRecordingErrorView(
      kind: GpsRecordingErrorKind.otherError,
    )));
    expect(find.byKey(const Key('gps_error_detail')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry button calls onRetry when provided', (tester) async {
    var retryTaps = 0;
    await tester.pumpWidget(_wrap(GpsRecordingErrorView(
      kind: GpsRecordingErrorKind.otherError,
      onRetry: () => retryTaps++,
    )));
    await tester.tap(find.byKey(const Key('gps_error_retry_button')));
    await tester.pump();
    expect(retryTaps, 1);
  });
}
