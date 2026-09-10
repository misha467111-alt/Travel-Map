import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/presentation/clustered_location_map.dart';

void main() {
  const fallback = LatLng(50.4501, 30.5234);
  final location = LocationModel(
    id: 'poi-1',
    userId: 'user-1',
    title: 'POI',
    description: null,
    category: 'nature',
    latitude: 50.46,
    longitude: 30.52,
    createdAt: DateTime.utc(2026),
  );

  Widget subject({LatLng? userPosition}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 480,
            child: ClusteredLocationMap(
              initialTarget: fallback,
              userPosition: userPosition,
              locations: [location],
              polylines: const {},
              onLocationTap: (_) {},
              onLongPress: (_) {},
              onViewportChanged: (_) {},
            ),
          ),
        ),
      );

  testWidgets('permission unavailable keeps fallback and no fake GPS marker',
      (tester) async {
    await tester.pumpWidget(subject());

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.initialCameraPosition.target, fallback);
    expect(
        map.markers.map((marker) => marker.markerId.value), contains('poi-1'));
    expect(map.markers.map((marker) => marker.markerId.value),
        isNot(contains('current_user_location')));
    expect(map.circles, isEmpty);
    expect(map.markers.single.clusterManagerId,
        map.clusterManagers.single.clusterManagerId);
    expect(
      tester
          .widget<IconButton>(find.byKey(
            const Key('map_my_location_button'),
          ))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('layer toggle preserves camera and POI markers', (tester) async {
    await tester.pumpWidget(subject(userPosition: const LatLng(50.47, 30.53)));

    final before = tester.widget<GoogleMap>(find.byType(GoogleMap));
    final target = before.initialCameraPosition.target;
    final markerIds = before.markers.map((marker) => marker.markerId).toSet();
    expect(before.mapType, MapType.normal);
    expect(find.byTooltip('Звичайна карта'), findsOneWidget);

    await tester.tap(find.byTooltip('Звичайна карта'));
    await tester.pump();

    final after = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(after.mapType, MapType.hybrid);
    expect(after.initialCameraPosition.target, target);
    expect(after.markers.map((marker) => marker.markerId).toSet(), markerIds);
    expect(tester.takeException(), isNull);
  });
}
