import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/features/map/domain/location_categories.dart';
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
}
