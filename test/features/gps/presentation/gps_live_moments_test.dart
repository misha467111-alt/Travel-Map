import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_add_moment_sheet.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_live_moments.dart';

LocalWaypoint moment({
  String id = 'moment-1',
  String routeId = 'route-1',
  String ownerId = 'me',
  String type = 'custom',
  String? title,
  String? note,
  double latitude = 50.45,
  double longitude = 30.52,
  DateTime? recordedAt,
}) {
  final time = recordedAt ?? DateTime.utc(2026, 1, 1, 10, 42);
  return LocalWaypoint(
    id: id,
    recordedRouteId: routeId,
    ownerId: ownerId,
    waypointType: type,
    title: title,
    note: note,
    latitude: latitude,
    longitude: longitude,
    recordedAt: time,
    createdAt: time,
    updatedAt: time,
    syncStatus: WaypointSyncStatus.pending,
  );
}

void main() {
  group('Moment marker projection', () {
    test('C01 zero Moments produces no markers', () {
      expect(buildGpsMomentMarkers(const []), isEmpty);
    });

    test('C02-C04 marker count and positions come from persisted Moments', () {
      final markers = buildGpsMomentMarkers([
        moment(id: 'a', latitude: 49.1, longitude: 24.2),
        moment(id: 'b', latitude: 48.3, longitude: 23.4),
      ]);

      expect(markers, hasLength(2));
      expect(
          markers
              .singleWhere((m) => m.markerId.value == 'journey_moment_a')
              .position,
          const LatLng(49.1, 24.2));
      expect(
          markers
              .singleWhere((m) => m.markerId.value == 'journey_moment_b')
              .position,
          const LatLng(48.3, 23.4));
    });

    test('C05 every canonical type has semantic presentation metadata', () {
      for (final option in gpsMomentTypeOptions) {
        final presentation = gpsMomentPresentation(option.key);
        expect(presentation.label, option.label, reason: option.key);
        expect(presentation.icon, option.icon, reason: option.key);
      }
      expect(
          gpsMomentPresentation('danger').markerHue, BitmapDescriptor.hueRed);
      expect(
          gpsMomentPresentation('water').markerHue, BitmapDescriptor.hueAzure);
      expect(gpsMomentPresentation('unknown').label, 'Інше');
    });
  });

  group('persisted ordering and reactive source', () {
    late GpsLocalDatabase db;

    setUp(() {
      db = GpsLocalDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    Future<void> add({
      required String id,
      required String routeId,
      required DateTime recordedAt,
      String ownerId = 'me',
    }) =>
        db.addWaypoint(
          id: id,
          ownerId: ownerId,
          recordedRouteId: routeId,
          waypointType: 'custom',
          latitude: 50,
          longitude: 30,
          recordedAt: recordedAt,
        );

    test('C16/C17 orders by recorded time then stable id tie-breaker',
        () async {
      final later = DateTime.utc(2026, 1, 1, 11);
      final same = DateTime.utc(2026, 1, 1, 10);
      await add(id: 'z', routeId: 'route', recordedAt: same);
      await add(id: 'later', routeId: 'route', recordedAt: later);
      await add(id: 'a', routeId: 'route', recordedAt: same);

      final result =
          await db.getWaypoints(ownerId: 'me', recordedRouteId: 'route');

      expect(result.map((waypoint) => waypoint.id), ['a', 'z', 'later']);
    });

    test('C06/C07 owner and recordedRouteId isolate the current Journey',
        () async {
      final time = DateTime.utc(2026, 1, 1, 10);
      await add(id: 'current', routeId: 'current-route', recordedAt: time);
      await add(id: 'other-route', routeId: 'historical', recordedAt: time);
      await add(
          id: 'other-owner',
          routeId: 'current-route',
          ownerId: 'someone-else',
          recordedAt: time);

      final result = await db.getWaypoints(
          ownerId: 'me', recordedRouteId: 'current-route');

      expect(result.map((waypoint) => waypoint.id), ['current']);
    });

    test('C10/C26 Drift watch updates reactively with no network dependency',
        () async {
      final lengths = <int>[];
      final subscription = db
          .watchWaypoints(ownerId: 'me', recordedRouteId: 'route')
          .listen((rows) => lengths.add(rows.length));
      await Future<void>.delayed(Duration.zero);

      await add(
        id: 'new',
        routeId: 'route',
        recordedAt: DateTime.utc(2026, 1, 1, 10),
      );
      for (var i = 0; i < 20 && !lengths.contains(1); i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(lengths, containsAllInOrder([0, 1]));
      await subscription.cancel();
    });
  });

  group('Moment inspection', () {
    Future<void> openSheet(
      WidgetTester tester,
      List<LocalWaypoint> moments,
    ) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => GpsMomentInspectionButton(
              momentCount: moments.length,
              onPressed: () => showGpsMomentsSheet(context, moments: moments),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('gps_moment_inspection_button')));
      await tester.pumpAndSettle();
    }

    testWidgets('C18/C20 action shows count and opens the list',
        (tester) async {
      await openSheet(tester, [moment(), moment(id: 'moment-2')]);

      expect(find.text('Точки подорожі (2)'), findsWidgets);
      expect(find.byKey(const Key('gps_moments_sheet')), findsOneWidget);
      expect(find.byKey(const Key('gps_moments_list')), findsOneWidget);
    });

    testWidgets('C19 empty inspection state is safe', (tester) async {
      await openSheet(tester, const []);

      expect(find.text('Точки подорожі (0)'), findsWidgets);
      expect(find.byKey(const Key('gps_moments_empty')), findsOneWidget);
    });

    testWidgets('C12/C14/C15 title, note, type, and recorded time render',
        (tester) async {
      final recordedAt = DateTime.utc(2026, 1, 1, 10, 42);
      await openSheet(tester, [
        moment(
          id: 'details',
          type: 'viewpoint',
          title: 'Панорама на озеро',
          note: 'Тихе місце',
          recordedAt: recordedAt,
        ),
      ]);
      final local = recordedAt.toLocal();
      final expectedTime = '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';

      expect(find.text('Оглядове місце'), findsOneWidget);
      expect(find.text('Панорама на озеро'), findsOneWidget);
      expect(find.text('Тихе місце'), findsOneWidget);
      expect(find.text(expectedTime), findsOneWidget);
    });

    testWidgets('C13 untitled Moment keeps title absent and uses type label',
        (tester) async {
      await openSheet(tester, [moment(id: 'untitled', type: 'water')]);

      expect(find.byKey(const Key('gps_moment_title_untitled')), findsNothing);
      expect(find.text('Вода'), findsOneWidget);
    });

    testWidgets('C21-C23 close is non-mutating and no Edit/Delete exists',
        (tester) async {
      final moments = [moment(title: 'Незмінна точка')];
      await openSheet(tester, moments);

      expect(find.text('Редагувати'), findsNothing);
      expect(find.text('Видалити'), findsNothing);
      await tester.tap(find.byKey(const Key('gps_moments_close_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gps_moments_sheet')), findsNothing);
      expect(moments.single.title, 'Незмінна точка');
    });

    group('C27/C28 responsive', () {
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        for (final scale in [1.0, 1.3, 1.5]) {
          testWidgets('fits ${width}dp @ ${scale}x without overflow',
              (tester) async {
            await tester.pumpWidget(MaterialApp(
              theme: buildAppTheme(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 760),
                  textScaler: TextScaler.linear(scale),
                ),
                child: SizedBox(
                  width: width,
                  height: 760,
                  child: Scaffold(
                    body: Builder(
                      builder: (context) => GpsMomentInspectionButton(
                        momentCount: 1,
                        onPressed: () => showGpsMomentsSheet(
                          context,
                          moments: [
                            moment(
                              type: 'interesting_place',
                              title: 'Цікаве місце',
                              note: 'Коротка корисна нотатка',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ));
            await tester
                .tap(find.byKey(const Key('gps_moment_inspection_button')));
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull,
                reason: 'overflow at ${width}dp, scale $scale');
            expect(find.byKey(const Key('gps_moments_close_button')),
                findsOneWidget);
            expect(find.byKey(const Key('gps_moment_row_moment-1')),
                findsOneWidget);
          });
        }
      }
    });
  });
}
