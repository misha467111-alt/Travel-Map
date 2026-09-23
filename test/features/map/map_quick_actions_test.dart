import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';

/// Phase 4D — D01/D02: the Map's "Записати маршрут" entry point.
///
/// [MapQuickActions] is the exact private-turned-`@visibleForTesting`
/// widget `MapScreen` wires into `ClusteredLocationMap`'s
/// `additionalToolbarActions` slot (see `map_screen.dart`) — tested here
/// in isolation for the same reason `clustered_location_map_test.dart`
/// and `location_pick_screen_test.dart` already avoid mounting the full,
/// heavily provider-dependent `MapScreen`: no other Map quick action
/// (`Поруч`/`Додати місце`) has ever needed a full `MapScreen` widget
/// test either. `MapScreen`'s own wiring
/// (`onRecordRoute: () => Navigator.push(..., GpsRecordingMapScreen())`)
/// is verified by direct code inspection; what an automated test can and
/// does prove is exactly what matters here: the button exists with the
/// right label/key, and tapping it invokes the callback it was given
/// exactly once.
void main() {
  Widget subject({
    VoidCallback? onAdd,
    VoidCallback? onRecordRoute,
  }) =>
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MapQuickActions(
            onAdd: onAdd ?? () {},
            onRecordRoute: onRecordRoute ?? () {},
          ),
        ),
      );

  testWidgets('D01 exposes a "Записати маршрут" action', (tester) async {
    await tester.pumpWidget(subject());

    expect(find.byKey(const Key('gps_record_route_action')), findsOneWidget);
    expect(find.byTooltip('Записати маршрут'), findsOneWidget);
  });

  testWidgets('D02 tapping it invokes the record-route callback exactly once',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(subject(onRecordRoute: () => taps++));

    await tester.tap(find.byKey(const Key('gps_record_route_action')));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('the existing "Поруч"/"Додати місце" actions are unaffected',
      (tester) async {
    var addTaps = 0;
    await tester.pumpWidget(subject(onAdd: () => addTaps++));

    expect(find.byTooltip('Поруч'), findsOneWidget);
    expect(find.byTooltip('Додати місце'), findsOneWidget);

    await tester.tap(find.byTooltip('Додати місце'));
    await tester.pump();
    expect(addTaps, 1);
  });
}
