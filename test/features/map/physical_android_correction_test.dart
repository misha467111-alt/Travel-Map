import 'package:flutter/material.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/presentation/location_card.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';
import 'package:flutter_application_1/features/navigation/presentation/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget atSize({
    required double width,
    required double scale,
    required Widget child,
  }) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 720),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: child),
        ),
      );

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets('filter grid fits ${width}dp at ${scale}x', (tester) async {
        await tester.pumpWidget(atSize(
          width: width,
          scale: scale,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: MapFilterCategoryGrid(
              selected: 'all',
              onSelected: (_) {},
            ),
          ),
        ));

        expect(
            find.byKey(const Key('map_filter_category_grid')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('compact discover card safely bounds long content',
      (tester) async {
    final location = LocationModel(
      id: 'long-card',
      userId: 'user',
      title: 'Надзвичайно довга назва цікавої локації для двох рядків',
      description:
          'Довгий опис локації, який має залишатися компактним і не ламати картку.',
      category: 'nature',
      latitude: 50.45,
      longitude: 30.52,
      createdAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(atSize(
      width: 320,
      scale: 1.5,
      child: ListView(children: [
        LocationCard(location: location, compact: true, onTap: () {}),
      ]),
    ));

    expect(find.text(location.title), findsOneWidget);
    expect(find.textContaining('Природа'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings remains scrollable on narrow scaled layout',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 560),
          textScaler: TextScaler.linear(1.5),
        ),
        child: SettingsPage(
          offlineMode: false,
          onOfflineChanged: (_) {},
          onLogout: () {},
        ),
      ),
    ));

    expect(find.byKey(const Key('settings_scroll')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('settings_logout')));
    expect(find.byKey(const Key('settings_logout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
