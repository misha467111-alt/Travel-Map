import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';

/// Search Phase 2A — the Map's Search entry point.
///
/// [MapSearchAction] is the exact private-turned-`@visibleForTesting`
/// widget `MapScreen` wires into its AppBar `actions` (see
/// `map_screen.dart`) — tested here in isolation for the same reason
/// `MapQuickActions` already is (see `map_quick_actions_test.dart`): no
/// Map AppBar action has ever needed a full `MapScreen` widget test.
/// `MapScreen`'s own wiring (`onPressed: () => Navigator.push(...,
/// LocationSearchScreen())`) is verified by direct code inspection; what
/// an automated test can and does prove is exactly what matters here:
/// the button exists with the right label/key, and tapping it invokes
/// the callback it was given exactly once.
void main() {
  Widget subject({VoidCallback? onPressed}) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          appBar: AppBar(
            actions: [MapSearchAction(onPressed: onPressed ?? () {})],
          ),
        ),
      );

  testWidgets('exposes a "Пошук" action', (tester) async {
    await tester.pumpWidget(subject());

    expect(find.byKey(const Key('map_search_action')), findsOneWidget);
    expect(find.byTooltip('Пошук'), findsOneWidget);
  });

  testWidgets('tapping it invokes the given callback exactly once',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(subject(onPressed: () => taps++));

    await tester.tap(find.byKey(const Key('map_search_action')));
    await tester.pump();

    expect(taps, 1);
  });
}
