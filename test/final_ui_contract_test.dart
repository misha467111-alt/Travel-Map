import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';

void main() {
  test('global Travel theme uses the approved palette and compact hierarchy',
      () {
    final theme = buildAppTheme();
    expect(theme.colorScheme.primary, const Color(0xFFD4A017));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF07120F));
    expect(theme.appBarTheme.backgroundColor, const Color(0xFF071A15));
    expect(theme.navigationBarTheme.height, 64);
    expect(theme.cardTheme.elevation, 0);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets('bottom navigation fits ${width}dp at ${scale}x',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 700),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: SizedBox(
                width: width,
                child: NavigationBar(
                  selectedIndex: 0,
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.map_outlined), label: 'Карта'),
                    NavigationDestination(
                        icon: Icon(Icons.dynamic_feed_outlined),
                        label: 'Відкривай'),
                    NavigationDestination(
                        icon: Icon(Icons.explore_outlined), label: 'Пригода'),
                    NavigationDestination(
                        icon: Icon(Icons.route_outlined), label: 'Маршрути'),
                    NavigationDestination(
                        icon: Icon(Icons.person_outline), label: 'Профіль'),
                  ],
                ),
              ),
            ),
          ),
        ));

        for (final label in [
          'Карта',
          'Відкривай',
          'Пригода',
          'Маршрути',
          'Профіль'
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
