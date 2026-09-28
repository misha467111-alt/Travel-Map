import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/features/map/domain/location_categories.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/domain/location_query.dart';
import 'package:flutter_application_1/features/map/providers/locations_provider.dart';
import 'package:flutter_application_1/features/map/providers/map_provider.dart';
import 'package:flutter_application_1/features/navigation/presentation/scalable_locations_screen.dart';

/// UI/UX Fix Phase 1: proves `ScalableLocationsScreen` (the actual
/// implementation behind "Сфера поруч") uses the same canonical category
/// taxonomy the rest of the app uses (no forked/stale list, no legacy
/// `general`), and that the radius now has a permanently visible label
/// that updates with the slider -- not just a transient `Slider.label`
/// drag tooltip.
///
/// `currentPositionProvider` and the exact `nearbyLocationsProvider` query
/// the widget is known to build from its own default state
/// (`_category == 'all'` -> `category: null`, `_radiusKm == 10` ->
/// `radiusMeters: 10000`) are overridden so the widget reaches its data
/// state synchronously, without touching a real GPS/Supabase call.
final _fakePosition = Position(
  latitude: 50.0,
  longitude: 30.0,
  timestamp: DateTime(2026, 1, 1),
  accuracy: 0,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

const _initialNearbyQuery = (
  latitude: 50.0,
  longitude: 30.0,
  radiusMeters: 10000.0,
  category: null,
);

ProviderScope _nearbyScope({required Widget child}) => ProviderScope(
      overrides: [
        currentPositionProvider.overrideWith((ref) async => _fakePosition),
        nearbyLocationsProvider(_initialNearbyQuery)
            .overrideWith((ref) async => const <LocationQueryItem>[]),
      ],
      child: child,
    );

/// Adventure Transport & Time Discovery Phase 2: unlike [_nearbyScope]
/// (which overrides one fixed query argument), this overrides the whole
/// `nearbyLocationsProvider` family so every query the widget builds --
/// whatever radius transport/time selection produces -- is captured in
/// [queries] and answered, without needing to predict every exact query
/// record in advance.
LocationQueryItem _fakeItem(String id) => LocationQueryItem(
      location: LocationModel(
        id: id,
        userId: 'author-$id',
        title: 'Location $id',
        description: null,
        category: 'nature',
        latitude: 50.01,
        longitude: 30.01,
        createdAt: DateTime.utc(2026),
      ),
      author: const AuthorSummary(id: 'author', name: 'Мандрівник'),
    );

({Widget scope, List<NearbyLocationQuery> queries}) _adventureScope({
  required Widget child,
  List<LocationQueryItem> Function(NearbyLocationQuery query)? responseFor,
  Object? positionError,
}) {
  final queries = <NearbyLocationQuery>[];
  final scope = ProviderScope(
    overrides: [
      if (positionError != null)
        currentPositionProvider.overrideWith((ref) async {
          throw positionError;
        })
      else
        currentPositionProvider.overrideWith((ref) async => _fakePosition),
      nearbyLocationsProvider.overrideWith((ref, query) async {
        queries.add(query);
        return responseFor?.call(query) ?? const <LocationQueryItem>[];
      }),
    ],
    child: child,
  );
  return (scope: scope, queries: queries);
}

void main() {
  testWidgets(
      'Sphere nearby renders the complete canonical category set without general',
      (tester) async {
    await tester.pumpWidget(
      _nearbyScope(
        child: const MaterialApp(
          home: ScalableLocationsScreen(mode: ScalableLocationListMode.nearby),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final category in referenceLocationCategories) {
      expect(find.byKey(Key('sphere_category_${category.key}')), findsOneWidget,
          reason: '${category.key} should be selectable in Sphere');
    }
    expect(find.byKey(const Key('sphere_category_general')), findsNothing,
        reason: 'legacy general must never appear in Sphere');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Sphere radius label is permanently visible and shows the current value',
      (tester) async {
    await tester.pumpWidget(
      _nearbyScope(
        child: const MaterialApp(
          home: ScalableLocationsScreen(mode: ScalableLocationListMode.nearby),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sphere_radius_label')), findsOneWidget);
    expect(find.text('Радіус: 10 км'), findsOneWidget);
  });

  testWidgets('Sphere radius label updates immediately as the slider moves',
      (tester) async {
    await tester.pumpWidget(
      _nearbyScope(
        child: const MaterialApp(
          home: ScalableLocationsScreen(mode: ScalableLocationListMode.nearby),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Радіус: 10 км'), findsOneWidget);

    final sliderCenter = tester.getCenter(find.byType(Slider));
    final sliderTopLeft = tester.getTopLeft(find.byType(Slider));
    final sliderSize = tester.getSize(find.byType(Slider));
    await tester.dragFrom(
      sliderCenter,
      Offset(sliderTopLeft.dx + sliderSize.width - sliderCenter.dx, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Радіус: 10 км'), findsNothing,
        reason: 'label must reflect the new slider value, not the stale one');
  });

  group('Adventure Transport & Time Discovery Phase 2', () {
    Future<void> pumpAdventure(
      WidgetTester tester,
      Widget scope,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => scope),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> selectTransport(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const Key('adventure_transport_field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> dragSliderToMax(WidgetTester tester, Key key) async {
      final finder = find.byKey(key);
      final center = tester.getCenter(finder);
      final topLeft = tester.getTopLeft(finder);
      final size = tester.getSize(finder);
      await tester.dragFrom(
        center,
        Offset(topLeft.dx + size.width - center.dx, 0),
      );
      await tester.pumpAndSettle();
    }

    /// The screen's ListView only builds nearby children -- scroll [key]
    /// into view (as a real user would) rather than relying on an
    /// unrealistically tall fixed viewport.
    Future<void> scrollToKey(WidgetTester tester, Key key) async {
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('locations_adventure_scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(find.byKey(key), 300,
          scrollable: scrollable);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'default Adventure query is bound by walking speed for 30 minutes',
        (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
      );
      await pumpAdventure(tester, built.scope);

      expect(built.queries, isNotEmpty);
      // 4.5 km/h walking * 30 min / 60 = 2.25 km -> 2250 m.
      expect(built.queries.last.radiusMeters, closeTo(2250.0, 1e-6));
    });

    testWidgets('T08 selecting transport changes the Adventure query radius',
        (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
      );
      await pumpAdventure(tester, built.scope);
      final before = built.queries.last.radiusMeters;

      await selectTransport(tester, 'Авто');

      final after = built.queries.last.radiusMeters;
      expect(after, isNot(before));
      // 45 km/h driving * 30 min / 60 = 22.5 km, capped by the 10 km user
      // radius -> 10000 m.
      expect(after, closeTo(10000.0, 1e-6));
    });

    testWidgets('T09 changing travel time changes the Adventure query radius',
        (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
      );
      await pumpAdventure(tester, built.scope);
      final before = built.queries.last.radiusMeters;

      await dragSliderToMax(tester, const Key('adventure_time_slider'));

      final after = built.queries.last.radiusMeters;
      expect(after, isNot(before));
      expect(find.text('Час у дорозі: 180 хв'), findsOneWidget);
    });

    testWidgets('T10 user radius remains an upper bound', (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
      );
      await pumpAdventure(tester, built.scope);

      await selectTransport(tester, 'Авто');

      // Driving for the default 30 minutes could reach 22.5 km, but the
      // user's own 10 km radius must still win.
      expect(built.queries.last.radiusMeters, closeTo(10000.0, 1e-6));
    });

    testWidgets('T11 the old 15 km Adventure cap is actually gone',
        (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
      );
      await pumpAdventure(tester, built.scope);

      await dragSliderToMax(tester, const Key('sphere_radius_slider'));
      await selectTransport(tester, 'Авто');

      // 45 km/h driving * 30 min / 60 = 22.5 km, and the user radius is now
      // 50 km -> effective radius is 22.5 km, well above the removed 15 km
      // cap.
      expect(built.queries.last.radiusMeters, greaterThan(15000.0));
      expect(built.queries.last.radiusMeters, closeTo(22500.0, 1e-6));
    });

    testWidgets(
        'T12 Здивуй мене keeps regenerating exactly one candidate from the '
        'constrained result set', (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
        responseFor: (query) =>
            [_fakeItem('a'), _fakeItem('b'), _fakeItem('c')],
      );
      await pumpAdventure(tester, built.scope);
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('locations_adventure_scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(find.textContaining('Location '), 300,
          scrollable: scrollable);
      expect(find.textContaining('Location '), findsOneWidget);
      expect(built.queries.last.radiusMeters, closeTo(2250.0, 1e-6),
          reason: 'the random candidate must come from the constrained query');
      final before = tester.widget<Text>(find.textContaining('Location ')).data;

      await tester.scrollUntilVisible(find.text('Здивуй мене'), -300,
          scrollable: scrollable);
      await tester.tap(find.text('Здивуй мене'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('Location '), 300,
          scrollable: scrollable);

      expect(find.textContaining('Location '), findsOneWidget,
          reason: 'regeneration must still narrow to exactly one candidate');
      final after = tester.widget<Text>(find.textContaining('Location ')).data;
      const candidates = {'Location a', 'Location b', 'Location c'};
      expect(candidates, contains(before),
          reason: 'the first generation must use the constrained result set');
      expect(candidates, contains(after),
          reason:
              'every generation must stay within the constrained result set');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'T13 zero Adventure candidates renders the canonical empty state',
        (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
        responseFor: (query) => const [],
      );
      await pumpAdventure(tester, built.scope);
      await scrollToKey(tester, const Key('adventure_empty_state'));

      expect(find.byKey(const Key('adventure_empty_state')), findsOneWidget);
      expect(
          find.text('У вибраному радіусі локацій не знайдено'), findsOneWidget);
    });

    testWidgets('T14 GPS/position error remains the canonical error text',
        (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
        positionError: StateError('no gps'),
      );
      await pumpAdventure(tester, built.scope);

      expect(find.text('Не вдалося визначити вашу позицію.'), findsOneWidget);
      expect(find.byKey(const Key('adventure_empty_state')), findsNothing);
    });

    testWidgets('T15 Nearby does not render transport/time controls',
        (tester) async {
      await tester.pumpWidget(
        _nearbyScope(
          child: const MaterialApp(
            home:
                ScalableLocationsScreen(mode: ScalableLocationListMode.nearby),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adventure_transport_field')), findsNothing);
      expect(find.byKey(const Key('adventure_time_slider')), findsNothing);
      expect(find.byKey(const Key('adventure_time_label')), findsNothing);
    });

    testWidgets('T16 Nearby radius behavior is unchanged by transport/time',
        (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.nearby),
      );
      await pumpAdventure(tester, built.scope);

      // Nearby must use the plain user radius (10 km default -> 10000 m),
      // never the transport/time-derived Adventure formula.
      expect(built.queries.last.radiusMeters, closeTo(10000.0, 1e-6));
    });

    testWidgets(
        'T17 existing Adventure category/radius/random controls remain '
        'functional alongside the new controls', (tester) async {
      final built = _adventureScope(
        child: const ScalableLocationsScreen(
            mode: ScalableLocationListMode.adventure),
        responseFor: (query) => [_fakeItem('a')],
      );
      await pumpAdventure(tester, built.scope);

      expect(find.byKey(const Key('adventure_hero')), findsOneWidget);
      expect(find.byKey(const Key('sphere_radius_label')), findsOneWidget);
      expect(find.byKey(const Key('sphere_category_nature')), findsOneWidget);
      expect(
          find.byKey(const Key('adventure_transport_field')), findsOneWidget);
      expect(find.byKey(const Key('adventure_time_slider')), findsOneWidget);
      expect(find.text('Здивуй мене'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sphere_category_nature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Здивуй мене'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets(
            'Adventure controls fit ${width}dp at ${scale}x, no overflow',
            (tester) async {
          final built = _adventureScope(
            child: const ScalableLocationsScreen(
                mode: ScalableLocationListMode.adventure),
            responseFor: (query) => [_fakeItem('a')],
          );
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(home: Builder(builder: (_) => built.scope)),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('sphere_radius_label')), findsOneWidget);
          expect(find.text('Здивуй мене'), findsOneWidget);

          await scrollToKey(tester, const Key('adventure_transport_field'));

          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('adventure_transport_field')),
              findsOneWidget);
          expect(find.byKey(const Key('adventure_time_label')), findsOneWidget);
          // Text labels (not color/icon alone) represent the selected
          // transport mode.
          expect(find.text('Пішки'), findsOneWidget);
        });
      }
    }
  });
}
