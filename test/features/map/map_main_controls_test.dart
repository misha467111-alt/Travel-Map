import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/domain/location_categories.dart';
import 'package:flutter_application_1/features/map/presentation/clustered_location_map.dart';
import 'package:flutter_application_1/features/map/presentation/map_main_controls.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart'
    show MapSearchAction;
import 'package:flutter_application_1/features/map/providers/map_filter_provider.dart';
import 'package:flutter_application_1/features/navigation/presentation/main_navigation_screen.dart'
    show MapBottomNavigation;

/// Main-map UI redesign: the compact header, the filter sheet, the single
/// creation menu, the compact map toolbar and the bottom navigation. Each
/// control is mounted in isolation (the full `MapScreen` needs Supabase and
/// location providers); `MapScreen` only wires the callbacks, which are the
/// same ones the old buttons used.
void main() {
  Widget host(Widget child, {ProviderContainer? container}) {
    final app = MaterialApp(theme: buildAppTheme(), home: child);
    return container == null
        ? ProviderScope(child: app)
        : UncontrolledProviderScope(container: container, child: app);
  }

  group('header (search, filters, overflow)', () {
    Widget header({
      VoidCallback? onSearch,
      VoidCallback? onAdvanced,
      int unread = 0,
      VoidCallback? onNotifications,
    }) =>
        host(Scaffold(
          appBar: AppBar(
            toolbarHeight: 48,
            title: const Text('Travel Map'),
            actions: [
              MapSearchAction(onPressed: onSearch ?? () {}),
              MapFilterButton(onOpenAdvanced: onAdvanced ?? () {}),
              MapOverflowMenu(
                unreadCount: unread,
                onOpenNotifications: onNotifications ?? () {},
              ),
            ],
          ),
          body: const SizedBox(),
        ));

    testWidgets('H01 shows exactly title, search, filters and overflow',
        (tester) async {
      await tester.pumpWidget(header());
      expect(find.text('Travel Map'), findsOneWidget);
      expect(find.byKey(const Key('map_search_action')), findsOneWidget);
      expect(find.byKey(const Key('map_filter_button')), findsOneWidget);
      expect(find.byKey(const Key('map_overflow_menu')), findsOneWidget);
      // No category strip and no standalone notifications button.
      expect(find.byTooltip('Сповіщення'), findsNothing);
    });

    testWidgets('H02 search invokes its callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(header(onSearch: () => taps++));
      await tester.tap(find.byKey(const Key('map_search_action')));
      expect(taps, 1);
    });

    testWidgets('H03 notifications are reachable from the overflow menu',
        (tester) async {
      var opened = 0;
      await tester
          .pumpWidget(header(unread: 3, onNotifications: () => opened++));
      await tester.tap(find.byKey(const Key('map_overflow_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Сповіщення (3)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('map_overflow_notifications')));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('H04 unread dot on the overflow icon only when unread',
        (tester) async {
      Badge badge() => tester.widget<Badge>(
          find.byKey(const Key('map_overflow_unread_indicator')));
      await tester.pumpWidget(header(unread: 0));
      expect(badge().isLabelVisible, false);
      await tester.pumpWidget(header(unread: 2));
      expect(badge().isLabelVisible, true);
    });

    testWidgets('H05 fits a 320 dp phone at 1.12x text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 640), textScaler: TextScaler.linear(1.12)),
        child: header(unread: 120),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('filter sheet', () {
    testWidgets('F01 lists every existing category', (tester) async {
      await tester.pumpWidget(
          host(Scaffold(body: MapFilterQuickSheet(onOpenAdvanced: () {}))));
      for (final c in referenceLocationCategories) {
        expect(find.byKey(Key('map_filter_category_${c.key}')), findsOneWidget,
            reason: c.key);
      }
    });

    testWidgets('F02 selecting a category uses the shared filter state',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(host(
          Scaffold(body: MapFilterQuickSheet(onOpenAdvanced: () {})),
          container: container));
      await tester.tap(find.byKey(const Key('map_filter_category_historic')));
      await tester.pump();
      expect(container.read(mapFilterProvider).applied.category, 'historic');

      await tester.tap(find.byKey(const Key('map_filter_reset')));
      await tester.pump();
      expect(container.read(mapFilterProvider).applied.category, 'all');
    });

    testWidgets(
        'F03 the filter button opens the sheet and shows the active '
        'indicator after a selection', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var advanced = 0;
      await tester.pumpWidget(host(
          Scaffold(
            appBar: AppBar(actions: [
              MapFilterButton(onOpenAdvanced: () => advanced++),
            ]),
          ),
          container: container));
      Badge indicator() => tester
          .widget<Badge>(find.byKey(const Key('map_filter_active_indicator')));
      expect(indicator().isLabelVisible, false);

      await tester.tap(find.byKey(const Key('map_filter_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('map_filter_sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('map_filter_category_nature')));
      await tester.pumpAndSettle();
      expect(indicator().isLabelVisible, true);

      await tester.tap(find.byKey(const Key('map_filter_advanced')));
      await tester.pumpAndSettle();
      expect(advanced, 1);
      expect(find.byKey(const Key('map_filter_sheet')), findsNothing);
    });

    test('F04 active-filter rule covers every filter dimension', () {
      expect(mapFiltersAreActive(const MapFilterState()), false);
      expect(mapFiltersAreActive(const MapFilterState(category: 'cafe')), true);
      expect(mapFiltersAreActive(const MapFilterState(distanceIndex: 1)), true);
      expect(mapFiltersAreActive(const MapFilterState(minimumRating: 4)), true);
      expect(mapFiltersAreActive(const MapFilterState(openNow: true)), true);
      expect(mapFiltersAreActive(const MapFilterState(familyOnly: true)), true);
      expect(
          mapFiltersAreActive(const MapFilterState(sort: LocationSort.nearest)),
          true);
    });
  });

  group('creation menu', () {
    final keys = <String>[
      'map_menu_add_place',
      'gps_record_route_action',
      'gps_journey_history_action',
      'map_menu_nearby',
      'map_menu_random',
    ];

    testWidgets('C01 one button opens a menu with every former action',
        (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(host(Scaffold(
        floatingActionButton: MapCreateMenuButton(actions: [
          for (final k in keys)
            MapMenuAction(
              key: Key(k),
              label: k,
              icon: Icons.circle,
              onSelected: () => taps.add(k),
            ),
        ]),
      )));
      for (final k in keys) {
        await tester.tap(find.byKey(const Key('map_create_menu_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('map_actions_sheet')), findsOneWidget);
        await tester.tap(find.byKey(Key(k)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('map_actions_sheet')), findsNothing,
            reason: 'the sheet closes after a choice');
      }
      expect(taps, keys);
    });
  });

  group('compact map toolbar', () {
    Widget map({
      bool compact = true,
      LatLng? user = const LatLng(50.47, 30.53),
      VoidCallback? onCreate,
    }) =>
        host(Scaffold(
          body: SizedBox(
            width: 320,
            height: 560,
            child: ClusteredLocationMap(
              initialTarget: const LatLng(50.45, 30.52),
              userPosition: user,
              locations: const [],
              polylines: const {},
              onLocationTap: (_) {},
              onLongPress: (_) {},
              onViewportChanged: (_) {},
              compactToolbar: compact,
              beforeLocationToolbarAction: const SizedBox(
                key: Key('legacy_before_action'),
              ),
              additionalToolbarActions: MapCreateMenuButton(actions: [
                MapMenuAction(
                  key: const Key('gps_record_route_action'),
                  label: 'Записати маршрут',
                  icon: Icons.fiber_manual_record,
                  onSelected: onCreate ?? () {},
                ),
              ]),
            ),
          ),
        ));

    testWidgets('T01 only layers, current location and the create button',
        (tester) async {
      await tester.pumpWidget(map());
      expect(find.byKey(const Key('map_layers_button')), findsOneWidget);
      expect(find.byKey(const Key('map_my_location_button')), findsOneWidget);
      expect(find.byKey(const Key('map_create_menu_button')), findsOneWidget);
      expect(find.byKey(const Key('legacy_before_action')), findsNothing);
      expect(find.byType(MapToolbarButton), findsNWidgets(2));
    });

    testWidgets('T02 layers toggle still switches the map type',
        (tester) async {
      await tester.pumpWidget(map());
      expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).mapType,
          MapType.normal);
      await tester.tap(find.byKey(const Key('map_layers_button')));
      await tester.pump();
      expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).mapType,
          MapType.hybrid);
    });

    testWidgets('T03 current location is enabled only with a position',
        (tester) async {
      await tester.pumpWidget(map());
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(const Key('map_my_location_button')))
              .onPressed,
          isNotNull);
      await tester.pumpWidget(map(user: null));
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(const Key('map_my_location_button')))
              .onPressed,
          isNull);
    });

    testWidgets('T04 GPS recording is reachable through the create menu',
        (tester) async {
      var recordTaps = 0;
      await tester.pumpWidget(map(onCreate: () => recordTaps++));
      await tester.tap(find.byKey(const Key('map_create_menu_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gps_record_route_action')));
      await tester.pumpAndSettle();
      expect(recordTaps, 1);
    });

    testWidgets('T05 the default (classic) toolbar is unchanged',
        (tester) async {
      await tester.pumpWidget(map(compact: false));
      expect(find.byKey(const Key('map_layers_button')), findsNothing);
      expect(find.byKey(const Key('legacy_before_action')), findsOneWidget);
      expect(find.byKey(const Key('map_my_location_button')), findsOneWidget);
    });
  });

  group('bottom navigation', () {
    testWidgets('N01 all five tabs stay functional', (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(host(Scaffold(
        bottomNavigationBar: MapBottomNavigation(onSelected: selected.add),
      )));
      for (final label in [
        'Карта',
        'Відкривай',
        'Пригода',
        'Маршрути',
        'Профіль'
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(Key('map_nav_$i')));
      }
      expect(selected, [0, 1, 2, 3, 4]);
    });

    testWidgets('N02 fits a 320 dp phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(Scaffold(
        bottomNavigationBar: MapBottomNavigation(onSelected: (_) {}),
      )));
      expect(tester.takeException(), isNull);
      // Touch target: each tab is at least 48 dp wide.
      expect(tester.getSize(find.byKey(const Key('map_nav_0'))).width,
          greaterThanOrEqualTo(48));
    });
  });

  group('Phase 2 polish', () {
    final five = [
      'map_menu_add_place',
      'gps_record_route_action',
      'gps_journey_history_action',
      'map_menu_nearby',
      'map_menu_random',
    ];

    Widget menuHost(List<String> taps) => host(Scaffold(
          floatingActionButton: MapCreateMenuButton(actions: [
            for (final k in five)
              MapMenuAction(
                key: Key(k),
                label: k,
                icon: Icons.circle,
                onSelected: () => taps.add(k),
              ),
          ]),
        ));

    for (final width in [320.0, 360.0]) {
      testWidgets(
          'P01 quick-actions sheet at $width dp: heading, all five '
          'actions, no scrolling, no overflow', (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final taps = <String>[];
        await tester.pumpWidget(menuHost(taps));
        await tester.tap(find.byKey(const Key('map_create_menu_button')));
        await tester.pumpAndSettle();

        expect(find.text('Швидкі дії'), findsOneWidget);
        for (final k in five) {
          expect(find.byKey(Key(k)), findsOneWidget);
          expect(tester.getSize(find.byKey(Key(k))).height,
              greaterThanOrEqualTo(48));
        }
        // Everything is on screen without scrolling.
        final scrollable = tester.state<ScrollableState>(find.descendant(
            of: find.byKey(const Key('map_actions_sheet')),
            matching: find.byType(Scrollable)));
        expect(scrollable.position.maxScrollExtent, 0);
        final sheet =
            tester.getRect(find.byKey(const Key('map_actions_sheet')));
        expect(sheet.height, lessThan(340));
        expect(tester.takeException(), isNull);

        for (final (i, k) in five.indexed) {
          if (i > 0) {
            await tester.tap(find.byKey(const Key('map_create_menu_button')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(Key(k)));
          await tester.pumpAndSettle();
        }
        expect(taps, five);
      });
    }

    testWidgets('P02 the create button uses the theme primary gold',
        (tester) async {
      await tester.pumpWidget(menuHost([]));
      final fab = tester.widget<FloatingActionButton>(
          find.byKey(const Key('map_create_menu_button')));
      final scheme = buildAppTheme().colorScheme;
      expect(fab.backgroundColor, scheme.primary);
      expect(fab.foregroundColor, scheme.onPrimary);
    });

    testWidgets(
        'P03 the active tab uses the same primary colour, with a '
        'outlined icons of one weight; only the active tab is gold',
        (tester) async {
      await tester.pumpWidget(host(Scaffold(
        bottomNavigationBar: MapBottomNavigation(onSelected: (_) {}),
      )));
      final primary = buildAppTheme().colorScheme.primary;
      Icon iconOf(int i) => tester.widget<Icon>(find.descendant(
          of: find.byKey(Key('map_nav_$i')), matching: find.byType(Icon)));
      expect(iconOf(0).icon, Icons.map_outlined);
      expect(iconOf(0).color, primary);
      expect(iconOf(1).icon, Icons.explore_outlined);
      expect(iconOf(1).color, isNot(primary));
      for (var i = 0; i < 5; i++) {
        expect(iconOf(i).size, 22, reason: 'one icon size for every tab');
      }
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('P04 bottom navigation fits $width dp at 1.12x text',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
              size: Size(width, 640),
              textScaler: const TextScaler.linear(1.12)),
          child: host(Scaffold(
            bottomNavigationBar: MapBottomNavigation(onSelected: (_) {}),
          )),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
