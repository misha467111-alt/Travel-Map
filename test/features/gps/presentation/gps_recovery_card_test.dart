import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recovery_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

void main() {
  testWidgets(
      'C06 recoverable UI: resume/finish/discard all offered, resume/finish '
      'call their callback directly', (tester) async {
    var resumeTaps = 0, finishTaps = 0, discardTaps = 0;
    await tester.pumpWidget(_wrap(GpsRecoveryCard(
      pointCount: 42,
      onResume: () => resumeTaps++,
      onFinish: () => finishTaps++,
      onDiscard: () => discardTaps++,
    )));

    expect(find.byKey(const Key('gps_recovery_resume_button')), findsOneWidget);
    expect(find.byKey(const Key('gps_recovery_finish_button')), findsOneWidget);
    expect(
        find.byKey(const Key('gps_recovery_discard_button')), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gps_recovery_resume_button')));
    await tester.pump();
    expect(resumeTaps, 1);

    await tester.tap(find.byKey(const Key('gps_recovery_finish_button')));
    await tester.pump();
    expect(finishTaps, 1);

    // Discard reuses the same shared confirmation dialog as active-session
    // discard -- must not fire before confirmation.
    await tester.tap(find.byKey(const Key('gps_recovery_discard_button')));
    await tester.pumpAndSettle();
    expect(discardTaps, 0);
    expect(find.byKey(const Key('gps_discard_confirm_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gps_discard_confirm_button')));
    await tester.pumpAndSettle();
    expect(discardTaps, 1);
  });

  testWidgets('renders without a point count when unknown', (tester) async {
    await tester.pumpWidget(_wrap(GpsRecoveryCard(
      onResume: () {},
      onFinish: () {},
      onDiscard: () {},
    )));
    expect(tester.takeException(), isNull);
  });
}
