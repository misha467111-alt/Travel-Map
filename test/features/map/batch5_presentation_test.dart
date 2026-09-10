import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/domain/location_query.dart';
import 'package:flutter_application_1/features/map/presentation/location_card.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';
import 'package:flutter_application_1/features/map/presentation/search_screen.dart';

void main() {
  final location = LocationModel(
    id: 'location-1',
    userId: 'user-1',
    title: 'Ботанічний сад',
    description: 'Тихе зелене місце для прогулянок.',
    category: 'nature',
    latitude: 50.45,
    longitude: 30.52,
    createdAt: DateTime.utc(2026),
  );

  testWidgets('details hero uses placeholder when real image is absent',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(width: 320, child: LocationImage(location: location)),
    ));

    expect(find.byKey(const Key('location_image_placeholder')), findsOneWidget);
    expect(find.byKey(const Key('location_real_image')), findsNothing);
  });

  testWidgets('details hero uses only the canonical image URL when present',
      (tester) async {
    final withImage = LocationModel(
      id: location.id,
      userId: location.userId,
      title: location.title,
      description: location.description,
      category: location.category,
      latitude: location.latitude,
      longitude: location.longitude,
      createdAt: location.createdAt,
      imageUrl: 'https://example.com/real.jpg',
    );
    await tester
        .pumpWidget(MaterialApp(home: LocationImage(location: withImage)));

    final image =
        tester.widget<Image>(find.byKey(const Key('location_real_image')));
    expect((image.image as NetworkImage).url, withImage.imageUrl);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets('map preview is responsive at ${width}dp and ${scale}x',
          (tester) async {
        var routed = false;
        var opened = false;
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 700),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: MapLocationPreview(
                  location: location,
                  onBuildRoute: () => routed = true,
                  onOpenDetails: () => opened = true,
                ),
              ),
            ),
          ),
        ));

        expect(find.text(location.title), findsOneWidget);
        expect(find.text(location.description!), findsOneWidget);
        await tester.tap(find.byKey(const Key('preview_route')));
        await tester.tap(find.byKey(const Key('preview_open_details')));
        expect(routed, isTrue);
        expect(opened, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('canonical categories are localized and never expose raw values', () {
    expect(locationCategoryLabel('all'), 'Усі');
    expect(locationCategoryLabel('general'), 'Загальне');
    expect(locationCategoryLabel('nature'), 'Природа');
    expect(locationCategoryLabel('culture'), 'Культура');
    expect(locationCategoryLabel('entertainment'), 'Розваги');
  });

  testWidgets('search starts with localized discovery categories',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LocationSearchScreen()),
    ));

    expect(find.text('Популярні категорії'), findsOneWidget);
    expect(find.text('Природа'), findsOneWidget);
    expect(find.text('nature'), findsNothing);
    expect(find.byKey(const ValueKey('search_initial')), findsOneWidget);
  });

  testWidgets('search debounces and sends a bounded server query',
      (tester) async {
    var calls = 0;
    String? receivedSearch;
    int? receivedLimit;
    Future<LocationPage> loader({
      LocationCursor? cursor,
      String? category,
      String? search,
      required int limit,
    }) async {
      calls++;
      receivedSearch = search;
      receivedLimit = limit;
      return const LocationPage(items: [], hasMore: false);
    }

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: LocationSearchScreen(pageLoader: loader)),
    ));
    await tester.enterText(find.byKey(const Key('travel_search_field')), 'сад');
    await tester.pump(const Duration(milliseconds: 349));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(calls, 1);
    expect(receivedSearch, 'сад');
    expect(receivedLimit, 20);
    expect(find.text('Нічого не знайдено'), findsOneWidget);
  });

  testWidgets('search exposes a compact loading state', (tester) async {
    final completer = Completer<LocationPage>();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: LocationSearchScreen(
            pageLoader: ({cursor, category, search, required limit}) =>
                completer.future),
      ),
    ));
    await tester.enterText(find.byKey(const Key('travel_search_field')), 'сад');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byKey(const Key('search_loading')), findsOneWidget);
    completer.complete(const LocationPage(items: [], hasMore: false));
    await tester.pump();
  });

  testWidgets(
      'result opens details flow and cursor pagination avoids duplicates',
      (tester) async {
    var calls = 0;
    LocationModel? opened;
    final item = LocationQueryItem(
      location: location,
      author: const AuthorSummary(id: 'user-1', name: 'Автор'),
    );
    Future<LocationPage> loader({
      LocationCursor? cursor,
      String? category,
      String? search,
      required int limit,
    }) async {
      calls++;
      expect(limit, 20);
      if (calls == 1) {
        expect(cursor, isNull);
        return LocationPage(items: [item], hasMore: true);
      }
      expect(cursor?.id, location.id);
      return LocationPage(items: [item], hasMore: false);
    }

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: LocationSearchScreen(
          pageLoader: loader,
          savedLocationIds: const {},
          onLocationTap: (value) => opened = value,
        ),
      ),
    ));
    await tester.enterText(find.byKey(const Key('travel_search_field')), 'сад');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    await tester.tap(find.text(location.title));
    expect(opened?.id, location.id);
    await tester.tap(find.byKey(const Key('search_load_more')));
    await tester.pump();

    expect(calls, 2);
    expect(find.text(location.title), findsOneWidget);
  });
}
