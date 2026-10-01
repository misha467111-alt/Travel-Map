import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_details_view.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_history_view.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_details.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';

final _t0 = DateTime.utc(2026, 3, 5, 10, 30);
DateTime _at(int min) => _t0.add(Duration(minutes: min));

LocalRecordedRoute _route(
  String id, {
  String sync = RouteSyncStatus.notSynced,
  String? title,
}) =>
    LocalRecordedRoute(
      id: id,
      ownerId: 'me',
      title: title,
      transportMode: 'walking',
      status: RecordedRouteStatus.completed,
      visibility: 'private',
      startedAt: _t0,
      endedAt: _at(60),
      createdAt: _t0,
      updatedAt: _t0,
      syncStatus: sync,
    );

LocalRoutePoint _point(int seq, double lat, {double? alt}) => LocalRoutePoint(
      recordedRouteId: 'r1',
      seq: seq,
      ownerId: 'me',
      latitude: lat,
      longitude: 30.0,
      altitude: alt,
      recordedAt: _at(seq),
    );

LocalWaypoint _moment(String id, int min,
        {String? title, String? note, String type = 'viewpoint'}) =>
    LocalWaypoint(
      id: id,
      recordedRouteId: 'r1',
      ownerId: 'me',
      waypointType: type,
      title: title,
      note: note,
      latitude: 50.0015,
      longitude: 30.0,
      recordedAt: _at(min),
      createdAt: _at(min),
      updatedAt: _at(min),
      syncStatus: WaypointSyncStatus.pending,
    );

LocalRouteEvent _event(int seq, String type, int min) => LocalRouteEvent(
      recordedRouteId: 'r1',
      seq: seq,
      ownerId: 'me',
      eventType: type,
      occurredAt: _at(min),
    );

GpsJourneyDetails _details({
  String id = 'r1',
  String sync = RouteSyncStatus.notSynced,
  String? title,
  List<LocalRoutePoint>? points,
  List<LocalWaypoint>? moments,
  List<LocalRouteEvent>? events,
  GpsJourneyStatistics? stats,
}) {
  final m = moments ?? [_moment('m1', 20, title: 'Перевал')];
  return GpsJourneyDetails(
    route: _route(id, sync: sync, title: title),
    points: points ?? [_point(1, 50.0), _point(2, 50.001), _point(3, 50.002)],
    moments: m,
    statistics: stats ??
        const GpsJourneyStatistics(
          totalDistanceMeters: 5400,
          elapsed: Duration(hours: 1),
          moving: Duration(minutes: 50),
          paused: Duration(minutes: 10),
          averageSpeedMps: 1.8,
          maxSpeedMps: 3,
          elevationGainMeters: 25,
          elevationLossMeters: 10,
        ),
    timeline: buildGpsJourneyTimeline(
      events: events ??
          [
            _event(1, RouteEventType.start, 0),
            _event(2, RouteEventType.pause, 30),
            _event(3, RouteEventType.resume, 40),
            _event(4, RouteEventType.finish, 60),
          ],
      moments: m,
    ),
  );
}

Widget _body([String id = 'r1']) =>
    GpsJourneyDetailsBody(ownerId: 'me', routeId: id);

Widget _detailsApp(
  GpsJourneyDetails? details, {
  Stream<LocalRecordedRoute?> Function(String id)? liveRoute,
  double width = 390,
  double scale = 1.0,
}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        gpsJourneyDetailsProvider.overrideWith((ref, args) async => details),
        gpsJourneyDetailsRouteProvider.overrideWith((ref, args) =>
            liveRoute == null ? const Stream.empty() : liveRoute(args.routeId)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: _body()),
        ),
      ),
    );

GoogleMap _map(WidgetTester tester) => tester.widget<GoogleMap>(find.descendant(
    of: find.byKey(const Key('gps_details_map')),
    matching: find.byType(GoogleMap)));

/// Tall surface so the whole Details scroll content is built without scrolling.
void _tw(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await body(tester);
    });

void main() {
  _tw('shows title, dates, statistics and Timeline', (tester) async {
    await tester.pumpWidget(_detailsApp(_details(title: 'Карпати')));
    await tester.pumpAndSettle();

    expect(find.text('Карпати'), findsOneWidget);
    expect(find.byKey(const Key('gps_details_stats')), findsOneWidget);
    expect(find.text('5.40 км'), findsOneWidget);
    expect(find.text('Хронологія'), findsOneWidget);
    expect(find.text('Подорож розпочато'), findsOneWidget);
    expect(find.text('Пауза'), findsOneWidget);
    expect(find.text('Продовження'), findsOneWidget);
    expect(find.text('Перевал'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Подорож завершено'), 300);
    expect(find.text('Подорож завершено'), findsOneWidget);
  });

  _tw('D14/D16 Timeline rows follow the read model order', (tester) async {
    await tester.pumpWidget(_detailsApp(_details()));
    await tester.pumpAndSettle();

    final ys = [
      for (final t in ['Подорож розпочато', 'Перевал', 'Пауза', 'Продовження'])
        tester.getTopLeft(find.text(t)).dy,
    ];
    expect(ys, [...ys]..sort());
  });

  _tw('D22 a missing or non-completed route is safely unavailable',
      (tester) async {
    await tester.pumpWidget(_detailsApp(null));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gps_details_unavailable')), findsOneWidget);
    expect(find.byKey(const Key('gps_details_stats')), findsNothing);
  });

  _tw('D23/D24/D25 every existing sync state is shown, offline too',
      (tester) async {
    for (final entry in {
      RouteSyncStatus.notSynced: 'Збережено на пристрої',
      RouteSyncStatus.synced: 'Синхронізовано',
      RouteSyncStatus.failed: 'Помилка синхронізації',
    }.entries) {
      await tester.pumpWidget(_detailsApp(_details(sync: entry.key)));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      expect(find.byKey(const Key('gps_details_stats')), findsOneWidget);
    }
  });

  _tw('sync status stays reactive after completion', (tester) async {
    final stream = Stream.fromIterable([
      _route('r1', sync: RouteSyncStatus.synced),
    ]);
    await tester.pumpWidget(_detailsApp(
      _details(sync: RouteSyncStatus.notSynced),
      liveRoute: (_) => stream,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Синхронізовано'), findsOneWidget);
    expect(find.text('Збережено на пристрої'), findsNothing);
  });

  _tw('D26/D27/D28/D29 zero Moments, pauses, altitude and pace',
      (tester) async {
    await tester.pumpWidget(_detailsApp(_details(
      moments: const [],
      events: [
        _event(1, RouteEventType.start, 0),
        _event(2, RouteEventType.finish, 60),
      ],
      points: [_point(1, 50.0), _point(2, 50.0)],
      stats: GpsJourneyStatistics.empty,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Пауза'), findsNothing);
    expect(find.text('Продовження'), findsNothing);
    expect(find.text('—'), findsNWidgets(3),
        reason: 'average speed, max speed and pace are unavailable');
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  _tw('no geometry at all shows a note instead of a map', (tester) async {
    await tester
        .pumpWidget(_detailsApp(_details(points: const [], moments: const [])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gps_details_no_geometry')), findsOneWidget);
    expect(find.byKey(const Key('gps_details_map')), findsNothing);
  });

  group('map', () {
    _tw('D30/D31 draws the persisted polyline and Moment markers',
        (tester) async {
      await tester.pumpWidget(_detailsApp(_details()));
      await tester.pumpAndSettle();

      final map = _map(tester);
      final line = map.polylines.single;
      expect(line.points.map((p) => p.latitude), [50.0, 50.001, 50.002],
          reason: 'canonical seq order, unmodified');
      final markers = map.markers
          .where((m) => m.markerId.value.startsWith('journey_moment_'));
      expect(markers.map((m) => m.markerId.value), ['journey_moment_m1']);
      expect(markers.single.position, const LatLng(50.0015, 30.0));
    });

    _tw('D32/D33 the map is read-only and starts no recording', (tester) async {
      await tester.pumpWidget(_detailsApp(_details()));
      await tester.pumpAndSettle();

      final map = _map(tester);
      expect(map.myLocationEnabled, isFalse);
      expect(map.onTap, isNull);
      expect(find.byKey(const Key('gps_recording_pause_button')), findsNothing);
      expect(
          find.byKey(const Key('gps_recording_finish_button')), findsNothing);
      expect(find.byKey(const Key('gps_start_button')), findsNothing);
    });

    _tw('a single point draws no polyline but still shows the map',
        (tester) async {
      await tester.pumpWidget(
          _detailsApp(_details(points: [_point(1, 50.0)], moments: const [])));
      await tester.pumpAndSettle();

      expect(_map(tester).polylines, isEmpty);
    });
  });

  _tw('D20 completed Moments are read-only (no edit/delete)', (tester) async {
    await tester.pumpWidget(_detailsApp(_details(
        moments: [_moment('m1', 20, title: 'Перевал', note: 'Вітряно')])));
    await tester.pumpAndSettle();

    expect(find.text('Вітряно'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byIcon(Icons.delete), findsNothing);
    final row = find.byKey(const ValueKey('gps_timeline_moment_m1'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byType(IconButton)),
        findsNothing);
    expect(
        find.descendant(of: row, matching: find.byType(InkWell)), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  _tw('D21 History item opens Details for exactly that route', (tester) async {
    final routes = [_route('first', title: 'Перша'), _route('second')];
    Widget history(BuildContext context) => GpsJourneyHistoryBody(
          ownerId: 'me',
          onOpenJourney: (id) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(body: _body(id)),
            ),
          ),
        );

    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        gpsJourneyHistoryProvider('me')
            .overrideWith((ref) => Stream.value(routes)),
        gpsJourneyDetailsProvider.overrideWith((ref, args) async =>
            _details(id: args.routeId, title: 'Деталі ${args.routeId}')),
        gpsJourneyDetailsRouteProvider
            .overrideWith((ref, args) => const Stream.empty()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: Builder(builder: history)),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('gps_history_item_second')));
    await tester.pumpAndSettle();

    expect(find.text('Деталі second'), findsOneWidget);
    expect(find.text('Деталі first'), findsNothing);
  });

  group('Responsive', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        _tw('fits ${width}dp @ ${scale}x, all sections reachable',
            (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_detailsApp(
            _details(
              title: 'Дуже довга назва подорожі через усі Карпати і ще далі',
              sync: RouteSyncStatus.failed,
              moments: [
                _moment('m1', 20,
                    title: 'Надзвичайно довга назва точки подорожі, '
                        'яка не повинна переповнювати екран',
                    note: 'Дуже довга нотатка ' * 12),
              ],
            ),
            width: width,
            scale: scale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.scrollUntilVisible(
              find.byKey(const Key('gps_details_stats')), 300,
              scrollable: find.byType(Scrollable).first);
          await tester.scrollUntilVisible(find.text('Подорож завершено'), 300,
              scrollable: find.byType(Scrollable).first);
          expect(find.text('Подорож завершено'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
