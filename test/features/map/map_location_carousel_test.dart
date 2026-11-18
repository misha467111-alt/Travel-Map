import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/presentation/map_location_carousel.dart';
import 'package:flutter_application_1/features/map/presentation/map_main_controls.dart';
import 'package:flutter_application_1/features/map/presentation/clustered_location_map.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart'
    show MapLocationPreview;
import 'package:google_maps_flutter/google_maps_flutter.dart';

LocationModel _loc(String id,
        {double lat = 50.0,
        double lng = 30.0,
        double? rating,
        String? image,
        String category = 'nature'}) =>
    LocationModel(
      id: id,
      userId: 'u',
      title: 'Місце $id',
      description: null,
      category: category,
      latitude: lat,
      longitude: lng,
      createdAt: DateTime.utc(2026),
      rating: rating,
      imageUrl: image,
    );

Widget _host(Widget child, {double width = 360}) => ProviderScope(
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 640)),
          child: Scaffold(
              body: Align(alignment: Alignment.bottomCenter, child: child)),
        ),
      ),
    );

/// Main-screen redesign: the floating header, the real-data location
/// carousel and the independently configurable map style.
void main() {
  group('nearestCarouselEntries', () {
    test('C01 nearest first, with distances', () {
      final entries = nearestCarouselEntries(
        [
          _loc('far', lat: 50.2),
          _loc('near', lat: 50.001),
          _loc('mid', lat: 50.05),
        ],
        userLatitude: 50.0,
        userLongitude: 30.0,
      );
      expect(entries.map((e) => e.location.id), ['near', 'mid', 'far']);
      expect(
          entries.first.distanceMeters, lessThan(entries.last.distanceMeters!));
    });

    test('C02 the strip is bounded; the input list is not touched', () {
      final all = [
        for (var i = 0; i < 100; i++) _loc('p$i', lat: 50 + i * 1e-3)
      ];
      final entries = nearestCarouselEntries(all,
          userLatitude: 50, userLongitude: 30, limit: 10);
      expect(entries.length, 10);
      expect(all.length, 100);
      expect(entries.first.location.id, 'p0');
    });

    test('C03 without a position the order is kept and no distance is shown',
        () {
      final entries = nearestCarouselEntries([_loc('b'), _loc('a')]);
      expect(entries.map((e) => e.location.id), ['b', 'a']);
      expect(entries.every((e) => e.distanceMeters == null), true);
    });

    test('C04 empty in, empty out', () {
      expect(nearestCarouselEntries(const []), isEmpty);
    });
  });

  group('carousel widget', () {
    Widget carousel(
      List<MapCarouselEntry> entries, {
      bool expanded = true,
      VoidCallback? onToggle,
      ValueChanged<LocationModel>? onSelected,
      double width = 360,
    }) =>
        _host(
          MapLocationCarousel(
            entries: entries,
            expanded: expanded,
            onToggle: onToggle ?? () {},
            onSelected: onSelected ?? (_) {},
          ),
          width: width,
        );

    testWidgets('W01 cards show only real data', (tester) async {
      await tester.pumpWidget(carousel([
        MapCarouselEntry(_loc('1', rating: 4.5), 850),
        MapCarouselEntry(_loc('2'), 2400),
      ]));
      expect(find.text('Місце 1'), findsOneWidget);
      expect(find.textContaining('850 м'), findsOneWidget);
      expect(find.textContaining('2.4 км'), findsOneWidget);
      expect(find.text('4.5/5'), findsOneWidget);
      // The second location has no rating: nothing is shown for it.
      expect(find.byKey(const Key('map_carousel_rating_2')), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.text('Поруч · 2'), findsOneWidget);
    });

    testWidgets('W02 a missing photo falls back to the category placeholder',
        (tester) async {
      await tester.pumpWidget(carousel([MapCarouselEntry(_loc('1'), 100)]));
      expect(
          find.byKey(const Key('location_image_placeholder')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('W03 tapping a card selects that location', (tester) async {
      LocationModel? selected;
      await tester.pumpWidget(carousel(
        [MapCarouselEntry(_loc('1'), 100), MapCarouselEntry(_loc('2'), 200)],
        onSelected: (l) => selected = l,
      ));
      await tester.tap(find.byKey(const Key('map_carousel_card_2')));
      expect(selected?.id, '2');
    });

    testWidgets('W04 the handle collapses the strip to a slim pill',
        (tester) async {
      var toggles = 0;
      await tester.pumpWidget(carousel(
        [MapCarouselEntry(_loc('1'), 100)],
        onToggle: () => toggles++,
      ));
      await tester.tap(find.byKey(const Key('map_carousel_handle')));
      expect(toggles, 1);
      await tester.pumpWidget(
          carousel([MapCarouselEntry(_loc('1'), 100)], expanded: false));
      expect(find.byKey(const Key('map_carousel')), findsNothing);
      expect(find.byKey(const Key('map_carousel_handle')), findsOneWidget);
      final height =
          tester.getSize(find.byKey(const Key('map_carousel_handle'))).height;
      expect(height, MapLocationCarousel.collapsedHeight);
    });

    testWidgets('W05 nothing is drawn without locations', (tester) async {
      await tester.pumpWidget(carousel(const []));
      expect(find.byKey(const Key('map_carousel_handle')), findsNothing);
      expect(find.byKey(const Key('map_carousel')), findsNothing);
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('W06 fits $width dp and stays slim', (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(carousel([
          MapCarouselEntry(_loc('1', rating: 4.8, category: 'historic'), 12345),
          MapCarouselEntry(_loc('2'), 40),
        ], width: width));
        expect(tester.takeException(), isNull);
        final box = tester.getRect(find.byKey(const Key('map_carousel')));
        expect(box.height, MapLocationCarousel.cardHeight);
        // The whole strip stays under a fifth of a 640 dp screen.
        expect(MapLocationCarousel.expandedHeight, lessThan(640 / 5));
      });
    }
  });

  group('floating header', () {
    Widget bar({
      VoidCallback? onSearch,
      VoidCallback? onAdvanced,
      int unread = 0,
      VoidCallback? onNotifications,
      double width = 360,
    }) =>
        _host(
          MapTopBar(
            onSearch: onSearch ?? () {},
            onOpenAdvancedFilters: onAdvanced ?? () {},
            unreadCount: unread,
            onOpenNotifications: onNotifications ?? () {},
          ),
          width: width,
        );

    testWidgets('H01 search pill, filter and overflow are reachable',
        (tester) async {
      var searches = 0, advanced = 0, notifications = 0;
      await tester.pumpWidget(bar(
        onSearch: () => searches++,
        onAdvanced: () => advanced++,
        unread: 2,
        onNotifications: () => notifications++,
      ));
      await tester.tap(find.byKey(const Key('map_search_bar')));
      expect(searches, 1);

      await tester.tap(find.byKey(const Key('map_filter_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('map_filter_advanced')));
      await tester.pumpAndSettle();
      expect(advanced, 1);

      await tester.tap(find.byKey(const Key('map_overflow_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('map_overflow_notifications')));
      await tester.pumpAndSettle();
      expect(notifications, 1);
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('H02 fits $width dp with a long unread count',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(bar(unread: 150, width: width));
        expect(tester.takeException(), isNull);
        // One row, touch targets of at least 44 dp.
        for (final key in [
          'map_search_bar',
          'map_filter_button',
          'map_overflow_menu'
        ]) {
          final size = tester.getSize(find.byKey(Key(key)));
          expect(size.height, greaterThanOrEqualTo(40), reason: key);
        }
      });
    }
  });

  group('map style configuration', () {
    test('M01 the map style is chosen independently of the UI palette', () {
      expect(AppMapStyle.kind, AppMapStyleKind.dark);
      expect(AppMapStyle.assetPath, AppMapStyleKind.dark.asset);
      for (final kind in AppMapStyleKind.values) {
        expect(File(kind.asset).existsSync(), true, reason: kind.asset);
      }
      // A different UI palette does not touch the map style.
      final before = AppMapStyle.assetPath;
      buildAppTheme(const AppPalette(
        background: Color(0xFF101010),
        surface: Color(0xFF181818),
        elevated: Color(0xFF202020),
        accent: Color(0xFF4FC3F7),
        onAccent: Color(0xFF001018),
        textPrimary: Color(0xFFFFFFFF),
        textSecondary: Color(0xFF9E9E9E),
        border: Color(0xFF303030),
      ));
      expect(AppMapStyle.assetPath, before);
    });
  });

  group('Phase 2 composition', () {
    test('R01 a missing or zero rating is never shown as 0.0', () {
      expect(carouselRatingLabel(null), isNull);
      expect(carouselRatingLabel(0), isNull);
      expect(carouselRatingLabel(0.0), isNull);
      expect(carouselRatingLabel(-1), isNull);
      expect(carouselRatingLabel(double.nan), isNull);
      expect(carouselRatingLabel(4.94), '4.9/5');
      expect(carouselRatingLabel(5), '5.0/5');
    });

    testWidgets('R02 a zero rating renders nothing on the card',
        (tester) async {
      await tester.pumpWidget(_host(MapLocationCarousel(
        entries: [MapCarouselEntry(_loc('z', rating: 0), null)],
        expanded: true,
        onToggle: () {},
        onSelected: (_) {},
      )));
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.byKey(const Key('map_carousel_rating_z')), findsNothing);
    });

    testWidgets('R03 only the active card has the thin gold outline',
        (tester) async {
      await tester.pumpWidget(_host(MapLocationCarousel(
        entries: [
          MapCarouselEntry(_loc('a'), 10),
          MapCarouselEntry(_loc('b'), 20),
        ],
        expanded: true,
        selectedId: 'b',
        onToggle: () {},
        onSelected: (_) {},
      )));
      BorderSide side(String id) => (tester
              .widget<Material>(find.byKey(Key('map_carousel_card_$id')))
              .shape as RoundedRectangleBorder)
          .side;
      expect(side('b').color, AppColors.accent);
      expect(side('b').width, 1);
      expect(side('a').style, BorderStyle.none);
    });

    testWidgets('R04 without a distance only the category is shown',
        (tester) async {
      await tester.pumpWidget(_host(MapLocationCarousel(
        entries: [MapCarouselEntry(_loc('a', category: 'cafe'), null)],
        expanded: true,
        onToggle: () {},
        onSelected: (_) {},
      )));
      expect(
          find.descendant(
              of: find.byKey(const Key('map_carousel_card_a')),
              matching: find.textContaining(' · ')),
          findsNothing);
    });

    for (final width in [320.0, 360.0]) {
      testWidgets(
          'R05 header: two-line title, light search, round controls at $width dp',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(
          MapTopBar(
            subtitle: 'На карті: 12',
            onSearch: () {},
            onOpenAdvancedFilters: () {},
            unreadCount: 99,
            onOpenNotifications: () {},
          ),
          width: width,
        ));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('map_title')), findsOneWidget);
        expect(find.text('На карті: 12'), findsOneWidget);
        expect(
            tester.getTopLeft(find.byKey(const Key('map_title'))).dy,
            lessThan(
                tester.getTopLeft(find.byKey(const Key('map_subtitle'))).dy));
        final search = tester.getSize(find.byKey(const Key('map_search_bar')));
        // Visual 40 dp, interactive area 48x48.
        expect(search, const Size(MapTopBar.hitSize, MapTopBar.hitSize));
        for (final key in ['map_filter_button', 'map_overflow_menu']) {
          final size = tester.getSize(find.byKey(Key(key)));
          expect(size.width, greaterThanOrEqualTo(48), reason: key);
          expect(size.height, greaterThanOrEqualTo(48), reason: key);
        }
        // Never a full-width bar: the header leaves the map visible.
        expect(tester.getSize(find.byType(MapTopBar)).height, lessThan(80));
      });
    }

    testWidgets('R06 neutral tagline without a real count', (tester) async {
      await tester.pumpWidget(_host(MapTopBar(
        onSearch: () {},
        onOpenAdvancedFilters: () {},
        unreadCount: 0,
        onOpenNotifications: () {},
      )));
      expect(find.text('Відкривай нові місця'), findsOneWidget);
    });

    testWidgets('R07 floating map buttons share one size', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: SizedBox(
            width: 360,
            height: 600,
            child: ClusteredLocationMap(
              initialTarget: const LatLng(50, 30),
              userPosition: const LatLng(50, 30),
              locations: const [],
              polylines: const {},
              onLocationTap: (_) {},
              onLongPress: (_) {},
              onViewportChanged: (_) {},
              compactToolbar: true,
              additionalToolbarActions: const MapCreateMenuButton(actions: []),
            ),
          ),
        ),
      ));
      Size circle(String key) => tester.getSize(find
          .descendant(
              of: find.byKey(Key(key)), matching: find.byType(Container))
          .first);
      expect(circle('map_layers_button'), const Size(40, 40)); // visual
      for (final key in ['map_layers_button', 'map_my_location_button']) {
        final hit = tester.getSize(find.byKey(Key(key)));
        expect(hit.width, greaterThanOrEqualTo(48), reason: key);
        expect(hit.height, greaterThanOrEqualTo(48), reason: key);
      }
      expect(circle('map_my_location_button'), const Size(40, 40));
      final fab = tester.getSize(find.byType(FloatingActionButton));
      expect(fab.width, greaterThanOrEqualTo(48));
      expect(fab.height, greaterThanOrEqualTo(48));
    });

    testWidgets('R08 the location sheet: no photo, no rating, no 0.0',
        (tester) async {
      await tester.pumpWidget(_host(MapLocationPreview(
        location: _loc('a', rating: 0),
        onBuildRoute: () {},
        onOpenDetails: () {},
      )));
      expect(find.byType(AspectRatio), findsNothing);
      expect(find.byKey(const Key('preview_rating')), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.byKey(const Key('preview_route')), findsOneWidget);
      expect(find.byKey(const Key('preview_open_details')), findsOneWidget);
    });

    testWidgets('R09 the location sheet shows a real rating and a photo slot',
        (tester) async {
      await tester.pumpWidget(_host(MapLocationPreview(
        location:
            _loc('a', rating: 4.2, image: 'https://example.invalid/x.jpg'),
        onBuildRoute: () {},
        onOpenDetails: () {},
      )));
      expect(find.text('4.2/5'), findsOneWidget);
      expect(find.byType(AspectRatio), findsOneWidget);
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('R10 the location sheet fits $width dp', (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_host(
          MapLocationPreview(
            location: LocationModel(
              id: 'x',
              userId: 'u',
              title: 'Дуже довга назва локації, яка не повинна ламати розмітку',
              description: 'Опис ' * 60,
              category: 'historic',
              latitude: 50,
              longitude: 30,
              createdAt: DateTime.utc(2026),
              rating: 4.8,
            ),
            onBuildRoute: () {},
            onOpenDetails: () {},
          ),
          width: width,
        ));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Phase 2.1 final polish', () {
    Widget sheet(double width, double scale) => ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 800), textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: MapLocationPreview(
                  location: _loc('a', rating: 4.5),
                  onBuildRoute: () {},
                  onOpenDetails: () {},
                ),
              ),
            ),
          ),
        );

    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        testWidgets(
            'P01 location sheet buttons: no word wrap, big targets, '
            '$width dp at ${scale}x', (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(sheet(width, scale));
          expect(tester.takeException(), isNull);

          // One line each: a single-line label has the same height as the
          // shorter one (a wrapped "Детальніш/е" would be taller).
          final details = tester.getSize(find.text('Детальніше'));
          final route = tester.getSize(find.text('Маршрут'));
          expect(details.height, route.height);

          for (final key in ['preview_route', 'preview_open_details']) {
            final size = tester.getSize(find.byKey(Key(key)));
            expect(size.height, greaterThanOrEqualTo(48), reason: key);
            expect(size.width, greaterThanOrEqualTo(48), reason: key);
          }
          final routeRect =
              tester.getRect(find.byKey(const Key('preview_route')));
          final detailsRect =
              tester.getRect(find.byKey(const Key('preview_open_details')));
          final sideBySide = routeRect.top == detailsRect.top;
          // Side by side only where it truly fits; otherwise stacked.
          if (scale > 1.15 || width < 340) {
            expect(sideBySide, false, reason: 'stacked');
            expect(routeRect.left, detailsRect.left);
          } else {
            expect(sideBySide, true);
          }
        });
      }
    }

    testWidgets('C01 carousel cards and the handle are opaque', (tester) async {
      await tester.pumpWidget(_host(MapLocationCarousel(
        entries: [MapCarouselEntry(_loc('a'), 100)],
        expanded: true,
        onToggle: () {},
        onSelected: (_) {},
      )));
      final card =
          tester.widget<Material>(find.byKey(const Key('map_carousel_card_a')));
      expect(card.color!.a, 1.0);
      expect(card.color, AppColors.surface);
      final handle = tester.widget<Container>(find.descendant(
          of: find.byKey(const Key('map_carousel_handle')),
          matching: find.byType(Container)));
      expect(((handle.decoration as BoxDecoration).color)!.a, 1.0);
    });

    test('A01 map bottom padding keeps the Google logo above the carousel', () {
      expect(carouselMapBottomPadding(shown: false, expanded: true), 0);
      final collapsed = carouselMapBottomPadding(shown: true, expanded: false);
      final expanded = carouselMapBottomPadding(shown: true, expanded: true);
      expect(
          collapsed, greaterThanOrEqualTo(MapLocationCarousel.collapsedHeight));
      expect(
          expanded, greaterThanOrEqualTo(MapLocationCarousel.expandedHeight));
      expect(expanded, greaterThan(collapsed));
    });

    testWidgets('A02 the official GoogleMap padding follows the carousel',
        (tester) async {
      Widget map(double padding) => ProviderScope(
            child: MaterialApp(
              home: SizedBox(
                width: 360,
                height: 640,
                child: ClusteredLocationMap(
                  initialTarget: const LatLng(50, 30),
                  userPosition: null,
                  locations: const [],
                  polylines: const {},
                  onLocationTap: (_) {},
                  onLongPress: (_) {},
                  onViewportChanged: (_) {},
                  bottomMapPadding: padding,
                ),
              ),
            ),
          );
      await tester.pumpWidget(map(0));
      expect(
          tester.widget<GoogleMap>(find.byType(GoogleMap)).padding.bottom, 0);
      final expanded = carouselMapBottomPadding(shown: true, expanded: true);
      await tester.pumpWidget(map(expanded));
      expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).padding.bottom,
          expanded);
      final collapsed = carouselMapBottomPadding(shown: true, expanded: false);
      await tester.pumpWidget(map(collapsed));
      expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).padding.bottom,
          collapsed);
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('H01 header scrim, no overflow at 320 dp, ${scale}x',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  size: const Size(320, 640),
                  textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Stack(children: [
                  MapTopBar(
                    subtitle: 'На карті: 27',
                    onSearch: () {},
                    onOpenAdvancedFilters: () {},
                    unreadCount: 3,
                    onOpenNotifications: () {},
                  ),
                ]),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('map_header_scrim')), findsOneWidget);
      });
    }

    testWidgets('H02 the scrim never blocks map gestures', (tester) async {
      var mapTaps = 0;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Stack(children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => mapTaps++,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MapTopBar(
                  onSearch: () {},
                  onOpenAdvancedFilters: () {},
                  unreadCount: 0,
                  onOpenNotifications: () {},
                ),
              ),
            ]),
          ),
        ),
      ));
      // On the title text area, under the scrim, but not on a control, and
      // just below the header where the scrim fades out.
      await tester.tapAt(tester.getTopLeft(find.byKey(const Key('map_title'))) +
          const Offset(4, 4));
      await tester.tapAt(const Offset(40, 90));
      expect(mapTaps, 2);
      // A control still receives its own tap.
      await tester.tap(find.byKey(const Key('map_search_bar')));
      expect(mapTaps, 2);
    });
  });
}
