import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/presentation/create_location_screen.dart';
import 'package:flutter_application_1/features/map/presentation/location_pick_screen.dart';
import 'package:flutter_application_1/features/map/providers/map_provider.dart';
import 'package:flutter_application_1/features/map/providers/network_provider.dart';
import 'package:flutter_application_1/features/profile/presentation/my_places_screen.dart';
import 'package:flutter_application_1/features/profile/providers/my_places_provider.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class _FakeSaved extends SavedPublicLocationsNotifier {
  @override
  Future<Set<String>> build() async => <String>{};
}

/// Phase 3.4-C2 -- "Додати місце" in "Мої місця": the AppBar action and the
/// empty "Створені" list run the shared create flow; nothing about the three
/// lists changes.
void main() {
  const gps = LatLng(50.5, 30.6);
  const fallback = LatLng(50.4501, 30.5234);
  const tapped = LatLng(50.46, 30.55);

  final position = Position(
    longitude: gps.longitude,
    latitude: gps.latitude,
    timestamp: DateTime.utc(2026),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  LocationModel place(String id, String title) => LocationModel(
        id: id,
        userId: 'me',
        title: title,
        description: 'Опис',
        category: 'nature',
        latitude: 50.45,
        longitude: 30.52,
        createdAt: DateTime.utc(2026, 1, 1),
        status: 'pending',
      );

  final createdKey = (ownerId: 'me', limit: 100);

  Override emptyCreated() =>
      myCreatedLocationsProvider(createdKey).overrideWith((ref) async => []);

  Override gpsFix() =>
      currentPositionProvider.overrideWith((ref) async => position);

  Override gpsOff() => currentPositionProvider.overrideWith(
      (ref) async => throw const LocationServiceDisabledException());

  Widget screen({
    required List<Override> overrides,
    int tab = 0,
    bool online = true,
    // True: something already watches the GPS provider, as the map tab does in
    // the app, so its state is known when "Додати місце" is tapped.
    bool warm = false,
    double width = 400,
    double scale = 1,
  }) =>
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          isOnlineProvider.overrideWithValue(online),
          savedPublicLocationsProvider.overrideWith(_FakeSaved.new),
          ...overrides,
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 800), textScaler: TextScaler.linear(scale)),
            child: Consumer(builder: (context, ref, _) {
              if (warm) ref.watch(currentPositionProvider);
              return MyPlacesScreen(ownerId: 'me', initialTab: tab);
            }),
          ),
        ),
      );

  Finder addButton() => find.byKey(const Key('my_places_add_place'));
  Finder emptyAdd() => find.byKey(const Key('my_places_empty_add_place'));

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  GoogleMap pickMap(WidgetTester tester) => tester.widget<GoogleMap>(find
      .descendant(
        of: find.byKey(const Key('location_pick_map')),
        matching: find.byType(GoogleMap),
      )
      .first);

  group('the action is present', () {
    for (final tab in [0, 1, 2]) {
      testWidgets('AppBar "Додати місце" on tab $tab (accessible, tappable)',
          (tester) async {
        await tester.pumpWidget(screen(tab: tab, overrides: [emptyCreated()]));
        await tester.pumpAndSettle();

        expect(addButton(), findsOneWidget);
        expect(tester.widget<IconButton>(addButton()).tooltip, 'Додати місце');
        expect(tester.widget<IconButton>(addButton()).onPressed, isNotNull);
        final size = tester.getSize(addButton());
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      });
    }
  });

  group('empty-state button', () {
    testWidgets('empty "Створені" offers "Додати місце"', (tester) async {
      await tester.pumpWidget(screen(overrides: [emptyCreated()]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_places_empty_created')), findsOneWidget);
      expect(find.text('Ви ще не створили жодної локації'), findsOneWidget);
      expect(emptyAdd(), findsOneWidget);
      expect(
          find.descendant(of: emptyAdd(), matching: find.text('Додати місце')),
          findsOneWidget);
    });

    testWidgets('a non-empty "Створені" has no empty-state button',
        (tester) async {
      await tester.pumpWidget(screen(overrides: [
        myCreatedLocationsProvider(createdKey)
            .overrideWith((ref) async => [place('1', 'Мій парк')]),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Мій парк'), findsOneWidget);
      expect(emptyAdd(), findsNothing);
      expect(addButton(), findsOneWidget, reason: 'the AppBar one stays');
    });

    testWidgets('loading and error "Створені" have no empty-state button',
        (tester) async {
      await tester.pumpWidget(screen(overrides: [
        myCreatedLocationsProvider(createdKey)
            .overrideWith((ref) => Completer<List<LocationModel>>().future),
      ]));
      await tester.pump();
      expect(
          find.byKey(const Key('my_places_loading_created')), findsOneWidget);
      expect(emptyAdd(), findsNothing);

      await tester.pumpWidget(screen(overrides: [
        myCreatedLocationsProvider(createdKey)
            .overrideWith((ref) async => throw StateError('offline')),
      ]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my_places_error_created')), findsOneWidget);
      expect(emptyAdd(), findsNothing);
    });

    testWidgets('empty "Збережені" has no "Додати місце" button',
        (tester) async {
      await tester.pumpWidget(screen(tab: 1, overrides: [emptyCreated()]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_places_empty_saved')), findsOneWidget);
      expect(emptyAdd(), findsNothing);
      expect(find.text('Додати місце'), findsNothing,
          reason: 'only the AppBar tooltip, never a visible label here');
    });

    testWidgets('empty "Відвідані" has no "Додати місце" button',
        (tester) async {
      await tester.pumpWidget(screen(tab: 2, overrides: [
        emptyCreated(),
        myVisitedPlacesProvider('me').overrideWith(
            (ref) async => const VisitedPlaces(total: 0, places: [])),
      ]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_places_empty_visited')), findsOneWidget);
      expect(emptyAdd(), findsNothing);
      expect(find.text('Додати місце'), findsNothing);
    });
  });

  group('starts the shared create flow', () {
    for (final fromEmpty in [false, true]) {
      testWidgets(
          '${fromEmpty ? "empty-state button" : "AppBar button"}: the pick '
          'screen opens centred on the GPS fix, nothing selected',
          (tester) async {
        await tester.pumpWidget(screen(overrides: [emptyCreated(), gpsFix()]));
        await tester.pumpAndSettle();

        await tapAndSettle(tester, fromEmpty ? emptyAdd() : addButton());

        final pick =
            tester.widget<LocationPickScreen>(find.byType(LocationPickScreen));
        expect(pick.initialTarget, gps);
        expect(pick.userPosition, gps);
        expect(pick.initialPicked, isNull);
        expect(pickMap(tester).markers.map((m) => m.markerId.value),
            isNot(contains('picked_location')),
            reason: 'GPS only centres, it never selects the point');
        expect(
            tester
                .widget<FilledButton>(
                    find.byKey(const Key('location_pick_confirm_button')))
                .onPressed,
            isNull);
      });
    }

    testWidgets(
        'GPS unavailable (the map already failed to get a fix): the pick '
        'screen opens on the fallback at once', (tester) async {
      await tester.pumpWidget(
          screen(warm: true, overrides: [emptyCreated(), gpsOff()]));
      await tester.pumpAndSettle();

      await tapAndSettle(tester, addButton());

      final pick =
          tester.widget<LocationPickScreen>(find.byType(LocationPickScreen));
      expect(pick.initialTarget, fallback);
      expect(pick.userPosition, isNull);
      expect(pick.initialPicked, isNull);
    });

    testWidgets('GPS unavailable and not yet known: fallback, never an error',
        (tester) async {
      await tester.pumpWidget(screen(overrides: [emptyCreated(), gpsOff()]));
      await tester.pumpAndSettle();

      await tester.tap(addButton());
      // The provider may be retrying; the wait is bounded (3 s).
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      final pick =
          tester.widget<LocationPickScreen>(find.byType(LocationPickScreen));
      expect(pick.initialTarget, fallback);
      expect(pick.userPosition, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('GPS that never answers does not block: fallback after 3 s',
        (tester) async {
      final never = Completer<Position>();
      await tester.pumpWidget(screen(overrides: [
        emptyCreated(),
        currentPositionProvider.overrideWith((ref) => never.future),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(addButton());
      await tester.pump();
      expect(find.byType(LocationPickScreen), findsNothing,
          reason: 'still waiting for the position');
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(LocationPickScreen), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final pick =
          tester.widget<LocationPickScreen>(find.byType(LocationPickScreen));
      expect(pick.initialTarget, fallback);
      expect(pick.userPosition, isNull);
    });

    testWidgets(
        'offline: a SnackBar, no pick screen, the button is usable '
        'again', (tester) async {
      await tester.pumpWidget(
          screen(online: false, overrides: [emptyCreated(), gpsFix()]));
      await tester.pumpAndSettle();

      await tapAndSettle(tester, addButton());

      expect(find.text('Для цієї дії потрібен інтернет'), findsOneWidget);
      expect(find.byType(LocationPickScreen), findsNothing);
      expect(tester.widget<IconButton>(addButton()).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(emptyAdd()).onPressed, isNotNull);
    });

    testWidgets('cancelling the pick changes nothing and re-enables the button',
        (tester) async {
      var created = 0;
      var counts = 0;
      await tester.pumpWidget(screen(overrides: [
        gpsFix(),
        myCreatedLocationsProvider(createdKey).overrideWith((ref) async {
          created++;
          return [];
        }),
        myCreatedCountProvider('me').overrideWith((ref) async {
          counts++;
          return 0;
        }),
      ]));
      await tester.pumpAndSettle();
      expect([created, counts], [1, 1]);

      await tapAndSettle(tester, addButton());
      await tapAndSettle(
          tester, find.byKey(const Key('location_pick_back_button')));

      expect(find.byType(LocationPickScreen), findsNothing);
      expect(find.byType(CreateLocationScreen), findsNothing);
      expect([created, counts], [1, 1], reason: 'nothing was created');
      expect(tester.widget<IconButton>(addButton()).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(emptyAdd()).onPressed, isNotNull);
    });

    testWidgets('a second tap while the flow is starting is ignored',
        (tester) async {
      final fix = Completer<Position>();
      await tester.pumpWidget(screen(overrides: [
        emptyCreated(),
        currentPositionProvider.overrideWith((ref) => fix.future),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(addButton());
      await tester.pump();
      expect(tester.widget<IconButton>(addButton()).onPressed, isNull);
      expect(tester.widget<FilledButton>(emptyAdd()).onPressed, isNull,
          reason: 'the empty-state button is disabled the same way');

      fix.complete(position);
      await tester.pumpAndSettle();
      expect(find.byType(LocationPickScreen), findsOneWidget,
          reason: 'exactly one pick screen');
    });
  });

  group('after a successful create', () {
    Future<void> createPlace(WidgetTester tester) async {
      await tapAndSettle(tester, addButton());
      pickMap(tester).onTap!(tapped);
      await tester.pump();
      await tapAndSettle(
          tester, find.byKey(const Key('location_pick_confirm_button')));
      expect(
          tester
              .widget<CreateLocationScreen>(find.byType(CreateLocationScreen))
              .point,
          tapped,
          reason: 'the form gets exactly the confirmed point');
      // The form pops with `true` only after a fully successful create.
      Navigator.of(tester.element(find.byType(CreateLocationScreen))).pop(true);
      await tester.pumpAndSettle();
    }

    testWidgets(
        'the created list and the exact total are reloaded, the new '
        'place appears and the pending message is shown', (tester) async {
      var listCalls = 0;
      var countCalls = 0;
      await tester.pumpWidget(screen(overrides: [
        gpsFix(),
        myCreatedLocationsProvider(createdKey).overrideWith((ref) async {
          listCalls++;
          return listCalls == 1 ? [] : [place('new', 'Нове місце')];
        }),
        myCreatedCountProvider('me').overrideWith((ref) async {
          countCalls++;
          return countCalls == 1 ? 0 : 1;
        }),
      ]));
      await tester.pumpAndSettle();
      expect(emptyAdd(), findsOneWidget);
      expect(find.text('Нове місце'), findsNothing);

      await createPlace(tester);

      expect(listCalls, 2);
      expect(countCalls, 2);
      expect(find.text('Нове місце'), findsOneWidget);
      expect(emptyAdd(), findsNothing);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('my_places_created_total')))
              .data,
          'Усього: 1');
      expect(find.text('Локацію створено та відправлено на перевірку'),
          findsOneWidget);
    });

    testWidgets('started from another tab, "Створені" is shown afterwards',
        (tester) async {
      await tester.pumpWidget(screen(tab: 1, overrides: [
        gpsFix(),
        myCreatedLocationsProvider(createdKey)
            .overrideWith((ref) async => [place('new', 'Нове місце')]),
      ]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my_places_empty_saved')), findsOneWidget);

      await createPlace(tester);

      expect(DefaultTabController.of(tester.element(find.byType(TabBar))).index,
          0);
      expect(find.text('Нове місце'), findsOneWidget);
      expect(find.byKey(const Key('my_places_empty_saved')), findsNothing);
    });

    testWidgets('closing the form without creating reloads nothing',
        (tester) async {
      var listCalls = 0;
      await tester.pumpWidget(screen(overrides: [
        gpsFix(),
        myCreatedLocationsProvider(createdKey).overrideWith((ref) async {
          listCalls++;
          return [];
        }),
      ]));
      await tester.pumpAndSettle();

      await tapAndSettle(tester, addButton());
      pickMap(tester).onTap!(tapped);
      await tester.pump();
      await tapAndSettle(
          tester, find.byKey(const Key('location_pick_confirm_button')));
      Navigator.of(tester.element(find.byType(CreateLocationScreen))).pop();
      await tester.pumpAndSettle();

      expect(listCalls, 1);
      expect(find.text('Локацію створено та відправлено на перевірку'),
          findsNothing);
      expect(tester.widget<IconButton>(addButton()).onPressed, isNotNull);
    });
  });

  group('adaptive: the empty "Створені" with its button', () {
    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('fits ${width}dp @ ${scale}x', (tester) async {
          // A real screen width (MediaQuery alone does not narrow the layout).
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
              screen(width: width, scale: scale, overrides: [emptyCreated()]));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          for (final f in [addButton(), emptyAdd()]) {
            final r = tester.getRect(f);
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(width));
          }
          expect(find.text('Мої місця'), findsOneWidget);
        });
      }
    }
  });
}
