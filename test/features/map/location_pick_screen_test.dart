import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/features/map/presentation/location_pick_screen.dart';

/// Phase 2.2B: `LocationPickScreen` is the only place a new public
/// location's coordinates are ever chosen -- the product rule under test
/// throughout this file is that the user's GPS position may only center
/// the map, never silently become the submitted coordinate. Real map
/// taps can't be simulated in a widget test (no native Google Maps
/// surface renders here), so tests drive the exact same callback the
/// real `GoogleMap` widget invokes on a tap: `GoogleMap.onTap`, read
/// straight off the pumped widget, exactly as `clustered_location_map_test
/// .dart` already does for other `GoogleMap` callbacks.
void main() {
  const target = LatLng(50.4501, 30.5234);
  const userGps = LatLng(50.40, 30.40);
  const tapped = LatLng(50.46, 30.55);
  const tappedAgain = LatLng(50.47, 30.56);

  // Bare screen (no MaterialApp wrapper) -- callers either pump it
  // directly wrapped once in their own MaterialApp, or push it via
  // MaterialPageRoute onto an existing Navigator. Wrapping it in a
  // second, nested MaterialApp here would give it its own independent
  // Navigator, so `Navigator.of(context).pop(...)` inside it would pop
  // that inner stack instead of the outer push a test is awaiting.
  Widget subject({LatLng? initialPicked, LatLng? userPosition}) =>
      LocationPickScreen(
        initialTarget: target,
        initialPicked: initialPicked,
        userPosition: userPosition,
      );

  GoogleMap map(WidgetTester tester) => tester.widget<GoogleMap>(
        find.descendant(
          of: find.byKey(const Key('location_pick_map')),
          matching: find.byType(GoogleMap),
        ),
      );

  testWidgets(
      'GPS is available only to center the map -- it never pre-selects a '
      'point, and confirm starts disabled', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subject(userPosition: userGps)));

    expect(map(tester).markers.map((m) => m.markerId.value),
        isNot(contains('picked_location')));
    final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('location_pick_confirm_button')));
    expect(confirm.onPressed, isNull);
    expect(find.text('Оберіть місце на карті'), findsOneWidget);
  });

  testWidgets('tapping the map selects that exact coordinate', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subject()));
    map(tester).onTap!(tapped);
    await tester.pump();

    final marker = map(tester)
        .markers
        .singleWhere((m) => m.markerId.value == 'picked_location');
    expect(marker.position, tapped);
    final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('location_pick_confirm_button')));
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('a second tap replaces the previous selection, not adds to it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: subject()));
    map(tester).onTap!(tapped);
    await tester.pump();
    map(tester).onTap!(tappedAgain);
    await tester.pump();

    final pickedMarkers =
        map(tester).markers.where((m) => m.markerId.value == 'picked_location');
    expect(pickedMarkers, hasLength(1));
    expect(pickedMarkers.single.position, tappedAgain);
  });

  testWidgets('confirm pops with the exact selected LatLng', (tester) async {
    LatLng? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<LatLng>(
              MaterialPageRoute<LatLng>(builder: (_) => subject()),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    map(tester).onTap!(tapped);
    await tester.pump();
    await tester.tap(find.byKey(const Key('location_pick_confirm_button')));
    await tester.pumpAndSettle();

    expect(result, tapped);
  });

  testWidgets('cancel pops with null and never confirms a point',
      (tester) async {
    Object? result = 'not called';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<LatLng>(
              MaterialPageRoute<LatLng>(builder: (_) => subject()),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    map(tester).onTap!(tapped);
    await tester.pump();
    await tester.tap(find.byKey(const Key('location_pick_cancel_button')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('back button pops with null the same way cancel does',
      (tester) async {
    Object? result = 'not called';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<LatLng>(
              MaterialPageRoute<LatLng>(builder: (_) => subject()),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('location_pick_back_button')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets(
      'a pre-seeded point (e.g. from an explicit long-press) starts '
      'selected, but a fresh tap still replaces it', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subject(initialPicked: tapped)));

    var marker = map(tester)
        .markers
        .singleWhere((m) => m.markerId.value == 'picked_location');
    expect(marker.position, tapped);
    final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('location_pick_confirm_button')));
    expect(confirm.onPressed, isNotNull,
        reason: 'a pre-seeded explicit point is already a valid selection');

    map(tester).onTap!(tappedAgain);
    await tester.pump();
    marker = map(tester)
        .markers
        .singleWhere((m) => m.markerId.value == 'picked_location');
    expect(marker.position, tappedAgain);
  });
}
