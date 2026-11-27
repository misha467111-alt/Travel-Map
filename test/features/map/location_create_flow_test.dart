import 'package:flutter/material.dart';
import 'package:flutter_application_1/features/map/presentation/create_location_screen.dart';
import 'package:flutter_application_1/features/map/presentation/location_create_flow.dart';
import 'package:flutter_application_1/features/map/presentation/location_pick_screen.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart'
    as map;
import 'package:flutter_application_1/features/map/providers/network_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Phase 3.4-C1: the "pick a point, then create the place" flow was moved out
/// of `_MapScreenState` so the map and "Мої місця" share it. These tests pin
/// the behaviour that must not change.
void main() {
  const target = LatLng(50.4501, 30.5234);
  const userGps = LatLng(50.40, 30.40);
  const tapped = LatLng(50.46, 30.55);
  const longPressed = LatLng(50.47, 30.56);

  Future<void> pumpHost(
    WidgetTester tester, {
    required bool online,
    required List<bool> results,
    LatLng? userPosition,
    LatLng? initialPicked,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [isOnlineProvider.overrideWithValue(online)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('start_flow'),
                onPressed: () async => results.add(await pickLocationThenCreate(
                  context,
                  ref,
                  initialTarget: target,
                  initialPicked: initialPicked,
                  userPosition: userPosition,
                )),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  GoogleMap pickMap(WidgetTester tester) => tester.widget<GoogleMap>(
        find.descendant(
          of: find.byKey(const Key('location_pick_map')),
          matching: find.byType(GoogleMap),
        ),
      );

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('start_flow')));
    await tester.pumpAndSettle();
  }

  testWidgets('offline: a SnackBar, no screen is opened, result false',
      (tester) async {
    final results = <bool>[];
    await pumpHost(tester, online: false, results: results);
    await start(tester);

    expect(find.text('Для цієї дії потрібен інтернет'), findsOneWidget);
    expect(find.byType(LocationPickScreen), findsNothing);
    expect(find.byType(CreateLocationScreen), findsNothing);
    expect(results, [false]);
  });

  testWidgets(
      'GPS unavailable: the pick screen still opens, centred on the '
      'given target, with nothing selected', (tester) async {
    final results = <bool>[];
    await pumpHost(tester, online: true, results: results);
    await start(tester);

    final pick =
        tester.widget<LocationPickScreen>(find.byType(LocationPickScreen));
    expect(pick.userPosition, isNull);
    expect(pick.initialTarget, target);
    expect(pick.initialPicked, isNull);
    expect(pickMap(tester).markers.map((m) => m.markerId.value),
        isNot(contains('picked_location')));
    final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('location_pick_confirm_button')));
    expect(confirm.onPressed, isNull, reason: 'GPS never confirms a point');
    expect(results, isEmpty, reason: 'the flow is still waiting');
  });

  testWidgets('GPS available: only passed on to centre/locate, never selected',
      (tester) async {
    await pumpHost(tester, online: true, results: [], userPosition: userGps);
    await start(tester);

    final pick =
        tester.widget<LocationPickScreen>(find.byType(LocationPickScreen));
    expect(pick.userPosition, userGps);
    expect(pick.initialPicked, isNull);
    expect(pickMap(tester).markers.map((m) => m.markerId.value),
        isNot(contains('picked_location')));
  });

  testWidgets('a long-pressed point pre-seeds the selection', (tester) async {
    await pumpHost(tester,
        online: true, results: [], initialPicked: longPressed);
    await start(tester);

    final marker = pickMap(tester)
        .markers
        .singleWhere((m) => m.markerId.value == 'picked_location');
    expect(marker.position, longPressed);
  });

  testWidgets('cancelling the pick (back) ends the flow: no form, false',
      (tester) async {
    final results = <bool>[];
    await pumpHost(tester, online: true, results: results);
    await start(tester);

    await tester.tap(find.byKey(const Key('location_pick_back_button')));
    await tester.pumpAndSettle();

    expect(find.byType(CreateLocationScreen), findsNothing);
    expect(find.byType(LocationPickScreen), findsNothing);
    expect(results, [false]);
  });

  testWidgets('confirming a point opens the form with exactly that point',
      (tester) async {
    final results = <bool>[];
    await pumpHost(tester, online: true, results: results);
    await start(tester);

    pickMap(tester).onTap!(tapped);
    await tester.pump();
    await tester.tap(find.byKey(const Key('location_pick_confirm_button')));
    await tester.pumpAndSettle();

    final form =
        tester.widget<CreateLocationScreen>(find.byType(CreateLocationScreen));
    expect(form.point, tapped);
    expect(find.text('Нова локація'), findsOneWidget);
    expect(results, isEmpty, reason: 'still waiting for the form');
  });

  testWidgets('closing the form without creating: false, no message',
      (tester) async {
    final results = <bool>[];
    await pumpHost(tester, online: true, results: results);
    await start(tester);
    pickMap(tester).onTap!(tapped);
    await tester.pump();
    await tester.tap(find.byKey(const Key('location_pick_confirm_button')));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(CreateLocationScreen))).pop();
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(find.text(locationPendingReviewMessage), findsNothing);
  });

  testWidgets('a created place: true and the pending-moderation message',
      (tester) async {
    final results = <bool>[];
    await pumpHost(tester, online: true, results: results);
    await start(tester);
    pickMap(tester).onTap!(tapped);
    await tester.pump();
    await tester.tap(find.byKey(const Key('location_pick_confirm_button')));
    await tester.pumpAndSettle();

    // The form pops with `true` only after a fully successful create.
    Navigator.of(tester.element(find.byType(CreateLocationScreen))).pop(true);
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.text('Локацію створено та відправлено на перевірку'),
        findsOneWidget);
  });

  testWidgets('addLocationAtPoint offline: SnackBar, nothing opened',
      (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [isOnlineProvider.overrideWithValue(false)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ElevatedButton(
              key: const Key('add_here'),
              onPressed: () async =>
                  results.add(await addLocationAtPoint(context, ref, tapped)),
              child: const Text('add'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('add_here')));
    await tester.pumpAndSettle();

    expect(find.text('Для цієї дії потрібен інтернет'), findsOneWidget);
    expect(find.byType(CreateLocationScreen), findsNothing);
    expect(results, [false]);
  });

  test('the pending message is still exported by map_screen.dart', () {
    expect(map.locationPendingReviewMessage, locationPendingReviewMessage);
  });

  group('addLocationAtPoint, online (direct call)', () {
    Future<List<bool>> pumpAdd(WidgetTester tester) async {
      final results = <bool>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [isOnlineProvider.overrideWithValue(true)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                key: const Key('add_here'),
                onPressed: () async =>
                    results.add(await addLocationAtPoint(context, ref, tapped)),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('add_here')));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets(
        'opens the form with exactly that point; success: true and '
        'the pending message', (tester) async {
      final results = await pumpAdd(tester);

      expect(
          tester
              .widget<CreateLocationScreen>(find.byType(CreateLocationScreen))
              .point,
          tapped);
      expect(results, isEmpty, reason: 'still waiting for the form');

      Navigator.of(tester.element(find.byType(CreateLocationScreen))).pop(true);
      await tester.pumpAndSettle();

      expect(results, [true]);
      expect(find.text(locationPendingReviewMessage), findsOneWidget);
    });

    testWidgets('the form closed without creating: false, no message',
        (tester) async {
      final results = await pumpAdd(tester);

      Navigator.of(tester.element(find.byType(CreateLocationScreen))).pop();
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(find.text(locationPendingReviewMessage), findsNothing);
    });
  });

  group('the caller is gone (context unmounted)', () {
    // The caller's page is removed from under the open screen, as if the user
    // had left it; the open screen then returns its result.
    final host = GlobalKey<NavigatorState>();
    const startKey = Key('start_here');

    Future<(MaterialPageRoute<void>, List<bool>)> pumpHost(
      WidgetTester tester, {
      required Future<bool> Function(BuildContext, WidgetRef) action,
    }) async {
      final results = <bool>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [isOnlineProvider.overrideWithValue(true)],
        child: MaterialApp(
          navigatorKey: host,
          home: const Scaffold(body: Text('home')),
        ),
      ));
      final route = MaterialPageRoute<void>(
        builder: (_) => Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ElevatedButton(
              key: startKey,
              onPressed: () async => results.add(await action(context, ref)),
              child: const Text('go'),
            ),
          ),
        ),
      );
      host.currentState!.push(route);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(startKey));
      await tester.pumpAndSettle();
      return (route, results);
    }

    testWidgets('after a successful create: still true, no SnackBar, no crash',
        (tester) async {
      final (route, results) = await pumpHost(tester,
          action: (context, ref) => addLocationAtPoint(context, ref, tapped));
      expect(find.byType(CreateLocationScreen), findsOneWidget);

      host.currentState!.removeRoute(route);
      await tester.pumpAndSettle();
      expect(find.byKey(startKey), findsNothing, reason: 'the caller is gone');
      expect(find.byType(CreateLocationScreen), findsOneWidget);

      host.currentState!.pop(true);
      await tester.pumpAndSettle();

      expect(results, [true],
          reason: 'the create did happen, whatever became of the caller');
      expect(find.text(locationPendingReviewMessage), findsNothing,
          reason: 'no SnackBar is shown through an unmounted context');
      expect(tester.takeException(), isNull);
    });

    testWidgets('while the point is being picked: no form is opened, false',
        (tester) async {
      var finished = false;
      bool? outcome;
      final (route, _) = await pumpHost(tester, action: (context, ref) async {
        final r =
            await pickLocationThenCreate(context, ref, initialTarget: target);
        outcome = r;
        finished = true;
        return r;
      });
      expect(find.byType(LocationPickScreen), findsOneWidget);

      host.currentState!.removeRoute(route);
      await tester.pumpAndSettle();
      pickMap(tester).onTap!(tapped);
      await tester.pump();
      await tester.tap(find.byKey(const Key('location_pick_confirm_button')));
      await tester.pumpAndSettle();

      expect(finished, isTrue);
      expect(outcome, isFalse);
      expect(find.byType(CreateLocationScreen), findsNothing,
          reason: 'no form is pushed from an unmounted caller');
      expect(tester.takeException(), isNull);
    });
  });
}
