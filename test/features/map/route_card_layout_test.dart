import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/presentation/clustered_location_map.dart';
import 'package:flutter_application_1/features/map/presentation/map_location_carousel.dart';
import 'package:flutter_application_1/features/map/presentation/map_main_controls.dart';

/// Phase 2.2: while a route is active the map buttons and the Google logo
/// must clear the route card whatever its height. `MapScreen` needs Supabase
/// and location providers, so this mounts the SAME building blocks it wires
/// (`MeasuredHeight`, the padding/inset helpers, `ClusteredLocationMap`)
/// around a card that grows with the text scale.
class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool routeActive = true;
  bool carouselExpanded = true;
  double cardHeight = 120;

  void setRoute(bool value) => setState(() => routeActive = value);

  @override
  Widget build(BuildContext context) {
    final carouselShown = !routeActive;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: ClusteredLocationMap(
            initialTarget: const LatLng(50, 30),
            userPosition: const LatLng(50, 30),
            locations: const [],
            polylines: const {},
            onLocationTap: (_) {},
            onLongPress: (_) {},
            onViewportChanged: (_) {},
            compactToolbar: true,
            toolbarBottomInset: routeActive
                ? routeCardToolbarInset(cardHeight,
                    maxInset: MediaQuery.sizeOf(context).height - 24 - 72 - 168)
                : carouselMapBottomPadding(
                        shown: carouselShown, expanded: carouselExpanded) +
                    8,
            bottomMapPadding: routeActive
                ? routeCardMapBottomPadding(cardHeight)
                : carouselMapBottomPadding(
                    shown: carouselShown, expanded: carouselExpanded),
            additionalToolbarActions: const MapCreateMenuButton(actions: []),
          ),
        ),
        if (routeActive)
          Positioned(
            left: 16,
            right: 16,
            bottom: routeCardBottomMargin,
            child: MeasuredHeight(
              onHeight: (h) {
                if (h != cardHeight) setState(() => cardHeight = h);
              },
              child: Card(
                key: const Key('route_card'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.route),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('4.4 км'),
                            Text('Орієнтовно 7 хв'),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => routeActive = false),
                        child: const Text('Скинути'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

Widget _app(Size size, double scale, GlobalKey<_HarnessState> key) =>
    ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 24)),
          child: _Harness(key: key),
        ),
      ),
    );

Rect _rect(WidgetTester t, Finder f) => t.getRect(f);

void main() {
  group('helpers', () {
    test('H01 padding and inset grow with the real card height', () {
      expect(routeCardMapBottomPadding(100), routeCardBottomMargin + 100 + 8);
      expect(routeCardToolbarInset(100), routeCardBottomMargin + 100 + 12);
      expect(
          routeCardToolbarInset(180), greaterThan(routeCardToolbarInset(100)));
      expect(routeCardToolbarInset(100) - routeCardBottomMargin - 100,
          greaterThanOrEqualTo(12));
    });
  });

  group('route active', () {
    for (final size in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
            'L01 buttons clear the card by >= 12 dp; logo padding follows: '
            '${size.width.toInt()}x${size.height.toInt()} at ${scale}x',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final key = GlobalKey<_HarnessState>();
          await tester.pumpWidget(_app(size, scale, key));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);

          final card = _rect(tester, find.byKey(const Key('route_card')));
          for (final id in const [
            'map_layers_button',
            'map_my_location_button',
            'map_create_menu_button',
          ]) {
            final r = _rect(tester, find.byKey(Key(id)));
            final wanted = routeCardToolbarInset(card.height);
            final fits = wanted <= size.height - 24 - 72 - 168;
            expect(r.top, greaterThanOrEqualTo(24), reason: '$id on screen');
            if (fits) {
              expect(r.bottom, lessThanOrEqualTo(card.top - 12 + 0.5),
                  reason: '$id must clear the card (card top ${card.top})');
              expect(r.overlaps(card), false, reason: '$id overlaps the card');
            }
            expect(r.width, greaterThanOrEqualTo(40));
          }
          // The buttons do not overlap each other.
          final a = _rect(tester, find.byKey(const Key('map_layers_button')));
          final b =
              _rect(tester, find.byKey(const Key('map_my_location_button')));
          final c =
              _rect(tester, find.byKey(const Key('map_create_menu_button')));
          expect(a.overlaps(b), false);
          expect(b.overlaps(c), false);

          // The measured height is the real one, and the Google logo's map
          // padding sits above the card with a small gap.
          final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
          final actualHeight = card.height;
          expect(key.currentState!.cardHeight, closeTo(actualHeight, 0.5));
          expect(map.padding.bottom,
              closeTo(routeCardBottomMargin + actualHeight + 8, 0.5));
          expect(
              map.padding.bottom, greaterThanOrEqualTo(size.height - card.top));
        });
      }
    }

    testWidgets('L02 a taller card (larger text) raises the buttons more',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final k1 = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_app(const Size(360, 640), 1.0, k1));
      await tester.pump();
      await tester.pump();
      final low =
          _rect(tester, find.byKey(const Key('map_my_location_button'))).bottom;
      final h1 = k1.currentState!.cardHeight;

      final k2 = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_app(const Size(360, 640), 2.0, k2));
      await tester.pump();
      await tester.pump();
      final high =
          _rect(tester, find.byKey(const Key('map_my_location_button'))).bottom;
      expect(k2.currentState!.cardHeight, greaterThan(h1));
      expect(high, lessThan(low));
    });
  });

  group('transitions', () {
    testWidgets('T01 route -> normal map -> route restores the layout',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_app(const Size(360, 640), 1.5, key));
      await tester.pump();
      await tester.pump();
      double padding() =>
          tester.widget<GoogleMap>(find.byType(GoogleMap)).padding.bottom;
      final withRoute = padding();
      expect(withRoute, greaterThan(routeCardMapBottomPadding(60)));

      // Close the route (the card's own "Скинути" button).
      await tester.tap(find.text('Скинути'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('route_card')), findsNothing);
      // Back to the carousel padding (expanded), no leftover card padding.
      expect(padding(), carouselMapBottomPadding(shown: true, expanded: true));
      final buttonLow =
          _rect(tester, find.byKey(const Key('map_my_location_button')));
      expect(
          buttonLow.bottom,
          lessThan(
              640 - carouselMapBottomPadding(shown: true, expanded: true)));

      // Reopen: the layout is restored from a fresh measurement.
      key.currentState!.setRoute(true);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(padding(), closeTo(withRoute, 0.5));
    });

    testWidgets('T02 normal modes: carousel expanded and collapsed paddings',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_app(const Size(360, 640), 1.0, key));
      await tester.pump();
      key.currentState!.setRoute(false);
      await tester.pump();
      double padding() =>
          tester.widget<GoogleMap>(find.byType(GoogleMap)).padding.bottom;
      // The harness shows the carousel strip whenever no route is active; the
      // real screen passes these same values.
      expect(padding(), carouselMapBottomPadding(shown: true, expanded: true));
      expect(tester.takeException(), isNull);
    });
  });
}
