import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/domain/location_photo_normalizer.dart';
import 'package:flutter_application_1/features/map/presentation/location_card.dart';
import 'package:flutter_application_1/features/map/presentation/route_details_screen.dart';

/// Phase 2.2A1-F: pure unit tests for the decode-size calculation shared
/// by every live location-photo display surface (compact/full cards via
/// `LocationImage`, and the Location Details hero) -- no widget pumping
/// needed since the function only takes a `BoxConstraints` and a
/// `devicePixelRatio`.
void main() {
  test('scales a bounded box by devicePixelRatio', () {
    final result = locationImageDecodeSize(
      constraints: const BoxConstraints.tightFor(width: 78, height: 92),
      devicePixelRatio: 2.0,
    );
    expect(result.width, 156);
    expect(result.height, 184);
  });

  test('rounds fractional device-pixel results', () {
    final result = locationImageDecodeSize(
      constraints: const BoxConstraints.tightFor(width: 78, height: 92),
      devicePixelRatio: 2.75,
    );
    expect(result.width, (78 * 2.75).round());
    expect(result.height, (92 * 2.75).round());
  });

  test(
      'a larger box (hero) yields a larger decode target than a small '
      'card, from the exact same function', () {
    const cardConstraints = BoxConstraints.tightFor(width: 78, height: 92);
    final cardSize = locationImageDecodeSize(
      constraints: cardConstraints,
      devicePixelRatio: 2.0,
    );
    const heroConstraints = BoxConstraints.tightFor(width: 400, height: 120);
    final heroSize = locationImageDecodeSize(
      constraints: heroConstraints,
      devicePixelRatio: 2.0,
    );

    expect(heroSize.width! > cardSize.width!, isTrue);
    expect(heroSize.height! > cardSize.height!, isTrue);
  });

  test('never requests more than the stored image\'s own max long edge', () {
    final result = locationImageDecodeSize(
      constraints: const BoxConstraints.tightFor(width: 5000, height: 4000),
      devicePixelRatio: 3.0,
    );
    expect(result.width, lessThanOrEqualTo(locationPhotoMaxLongEdgePx));
    expect(result.height, lessThanOrEqualTo(locationPhotoMaxLongEdgePx));
  });

  test('returns null for unbounded constraints rather than a bogus value', () {
    final result = locationImageDecodeSize(
      constraints: const BoxConstraints(),
      devicePixelRatio: 2.0,
    );
    expect(result.width, isNull);
    expect(result.height, isNull);
  });

  test('never returns a non-positive dimension', () {
    final result = locationImageDecodeSize(
      constraints: const BoxConstraints.tightFor(width: 0, height: 0),
      devicePixelRatio: 1.0,
    );
    expect(result.width, greaterThanOrEqualTo(1));
    expect(result.height, greaterThanOrEqualTo(1));
  });

  group('LocationImage widget wiring', () {
    final location = LocationModel(
      id: 'location-1',
      userId: 'user-1',
      title: 'Ботанічний сад',
      description: 'Тихе зелене місце для прогулянок.',
      category: 'nature',
      latitude: 50.45,
      longitude: 30.52,
      createdAt: DateTime.utc(2026),
      imageUrl: 'https://example.com/real.jpg',
    );

    testWidgets(
        'a small compact-card box gets bounded decode dimensions matching '
        'the shared calculation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 2.0),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 78,
                  height: 92,
                  child: LocationImage(location: location),
                ),
              ),
            ),
          ),
        ),
      );

      final image =
          tester.widget<Image>(find.byKey(const Key('location_real_image')));
      final resize = image.image as ResizeImage;
      final expected = locationImageDecodeSize(
        constraints: const BoxConstraints.tightFor(width: 78, height: 92),
        devicePixelRatio: 2.0,
      );
      expect(resize.width, expected.width);
      expect(resize.height, expected.height);
      // Not visibly blurry: at 2x DPR a 78x92 box asks for a genuinely
      // higher-resolution decode than the logical box size, not a 1:1
      // (or smaller) one.
      expect(resize.width! > 78, isTrue);
      expect(resize.height! > 92, isTrue);
    });

    testWidgets(
        'a large hero-sized box gets a larger decode target than '
        'the compact card, through the same widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 2.0),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  height: 120,
                  child: LocationImage(location: location),
                ),
              ),
            ),
          ),
        ),
      );

      final image =
          tester.widget<Image>(find.byKey(const Key('location_real_image')));
      final resize = image.image as ResizeImage;
      expect(resize.width! > 78 * 2, isTrue,
          reason: 'hero decode target must exceed the compact-card one');
    });

    testWidgets('BoxFit, error builder, and layout are all preserved',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 78,
            height: 92,
            child: LocationImage(location: location),
          ),
        ),
      );

      final image =
          tester.widget<Image>(find.byKey(const Key('location_real_image')));
      expect(image.fit, BoxFit.cover);
      expect(image.width, double.infinity);
      expect(image.height, double.infinity);
      expect(image.errorBuilder, isNotNull);
    });

    testWidgets('route destination hero uses a bounded, DPR-aware decode',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 2.0),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 400,
                  child: RouteHero(destination: location, height: 120),
                ),
              ),
            ),
          ),
        ),
      );

      final image =
          tester.widget<Image>(find.byKey(const Key('route_real_image')));
      final resize = image.image as ResizeImage;
      expect(resize.width, 800);
      expect(resize.height, 240);
      expect(image.fit, BoxFit.cover);
      expect(image.errorBuilder, isNotNull);
    });
  });
}
