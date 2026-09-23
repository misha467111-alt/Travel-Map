import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/navigation/presentation/main_navigation_screen.dart';
import 'package:flutter_application_1/features/navigation/presentation/settings_screen.dart';

void main() {
  testWidgets(
      'production settings navigation exposes GPS recording debug and returns back',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open_production_settings'),
                onPressed: () => openSecondarySection(context, 'settings'),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_production_settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(const Key('settings_gps_debug')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_production_settings')), findsOneWidget);
  });

  testWidgets(
      'C4: SettingsPage with onOpenGpsDebug null renders no debug tile and '
      'no empty РОЗРОБКА section (release gating)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          offlineMode: false,
          onOfflineChanged: (_) {},
          onLogout: () {},
          onOpenGpsDebug: null,
        ),
      ),
    );

    expect(find.byKey(const Key('settings_gps_debug')), findsNothing);
    expect(find.text('РОЗРОБКА'), findsNothing);
  });
}
