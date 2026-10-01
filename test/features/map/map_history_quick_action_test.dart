import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';

/// Journey Phase 1F: the Map's "Історія подорожей" entry point. Kept in its
/// own file so `map_quick_actions_test.dart` (Phase 4D) stays unchanged.
void main() {
  Widget subject({VoidCallback? onOpenHistory}) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MapQuickActions(
            onAdd: () {},
            onRecordRoute: () {},
            onOpenHistory: onOpenHistory,
          ),
        ),
      );

  testWidgets('shows the history action and invokes it exactly once',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(subject(onOpenHistory: () => taps++));

    expect(find.byTooltip('Історія подорожей'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gps_journey_history_action')));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('without a callback the action is absent and others remain',
      (tester) async {
    await tester.pumpWidget(subject());

    expect(find.byKey(const Key('gps_journey_history_action')), findsNothing);
    expect(find.byKey(const Key('gps_record_route_action')), findsOneWidget);
  });
}
