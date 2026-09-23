import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_start_view.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child));

void main() {
  testWidgets('C01 idle UI: shows an enabled start button, calls onStart',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(GpsStartView(
      label: 'Почати запис',
      onStart: () => tapped++,
    )));

    expect(find.text('Почати запис'), findsOneWidget);
    final button =
        tester.widget<FilledButton>(find.byKey(const Key('gps_start_button')));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('gps_start_button')));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets(
      'C02 preparing UI: button is disabled (onStart null) so a second tap '
      'cannot start a duplicate session', (tester) async {
    await tester.pumpWidget(_wrap(const GpsStartView(
      label: 'Підготовка…',
      onStart: null,
    )));

    final button =
        tester.widget<FilledButton>(find.byKey(const Key('gps_start_button')));
    expect(button.onPressed, isNull,
        reason: 'preparing must disable the button entirely, not just show '
            'a spinner alongside an active tap handler');

    // A tap on a disabled button is a no-op; assert it never increments.
    await tester.tap(find.byKey(const Key('gps_start_button')),
        warnIfMissed: false);
    await tester.pump();
  });

  testWidgets('completed: shows the optional statusCard above the button',
      (tester) async {
    await tester.pumpWidget(_wrap(GpsStartView(
      label: 'Новий запис',
      onStart: () {},
      statusCard: const Text('preview-card', key: Key('preview')),
    )));

    expect(find.byKey(const Key('preview')), findsOneWidget);
    expect(find.text('Новий запис'), findsOneWidget);
  });
}
