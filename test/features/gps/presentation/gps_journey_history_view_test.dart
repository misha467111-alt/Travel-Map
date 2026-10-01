import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_history_view.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_summary_view.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_summary.dart';

final _t0 = DateTime.utc(2026, 3, 5, 10, 30);

LocalRecordedRoute _route(
  String id, {
  String sync = RouteSyncStatus.notSynced,
  String? title,
  int endMin = 60,
}) =>
    LocalRecordedRoute(
      id: id,
      ownerId: 'me',
      title: title,
      transportMode: 'walking',
      status: RecordedRouteStatus.completed,
      visibility: 'private',
      startedAt: _t0,
      endedAt: _t0.add(Duration(minutes: endMin)),
      createdAt: _t0,
      updatedAt: _t0,
      syncStatus: sync,
    );

GpsJourneySummary _summary(String id,
        {int moments = 2, double meters = 5400}) =>
    GpsJourneySummary(
      routeId: id,
      momentCount: moments,
      pointCount: 20,
      statistics: GpsJourneyStatistics(
        totalDistanceMeters: meters,
        elapsed: const Duration(hours: 1),
        moving: const Duration(minutes: 50),
        paused: const Duration(minutes: 10),
        averageSpeedMps: 1.8,
        maxSpeedMps: 3,
        elevationGainMeters: 10,
        elevationLossMeters: 5,
      ),
    );

Widget _app(
  Stream<List<LocalRecordedRoute>> routes, {
  void Function(String)? onOpen,
  double width = 390,
  double scale = 1.0,
  Future<GpsJourneySummary?> Function(String id)? summary,
}) =>
    ProviderScope(
      overrides: [
        gpsJourneyHistoryProvider('me').overrideWith((ref) => routes),
        gpsJourneySummaryProvider.overrideWith((ref, args) =>
            (summary ?? (id) async => _summary(id))(args.routeId)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: GpsJourneyHistoryBody(ownerId: 'me', onOpenJourney: onOpen),
          ),
        ),
      ),
    );

void main() {
  testWidgets('loading state is shown before the first emission',
      (tester) async {
    final controller = StreamController<List<LocalRecordedRoute>>();
    addTearDown(controller.close);
    await tester.pumpWidget(_app(controller.stream));

    expect(find.byKey(const Key('gps_history_loading')), findsOneWidget);
  });

  testWidgets('H14/H17 empty History shows the empty state and no items',
      (tester) async {
    await tester.pumpWidget(_app(Stream.value(const [])));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gps_history_empty')), findsOneWidget);
    expect(find.text('Завершених подорожей ще немає'), findsOneWidget);
    expect(find.byType(GpsJourneyHistoryCard), findsNothing);
  });

  testWidgets('error state is shown if the local query fails', (tester) async {
    await tester.pumpWidget(_app(Stream.error(StateError('db'))));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gps_history_error')), findsOneWidget);
  });

  testWidgets('H01/H06/H19 items render in the given order keyed by route id',
      (tester) async {
    await tester.pumpWidget(_app(Stream.value([
      _route('newest', title: 'Карпати'),
      _route('older'),
    ])));
    await tester.pumpAndSettle();

    final cards = tester
        .widgetList<GpsJourneyHistoryCard>(find.byType(GpsJourneyHistoryCard))
        .map((c) => c.route.id)
        .toList();
    expect(cards, ['newest', 'older']);
    expect(
        find.byKey(const ValueKey('gps_history_item_newest')), findsOneWidget);
    expect(find.text('Карпати'), findsOneWidget);
    expect(find.text('Подорож'), findsOneWidget, reason: 'untitled fallback');
  });

  testWidgets('H12/H13 metrics come from the local Summary, not the UI',
      (tester) async {
    await tester.pumpWidget(_app(
      Stream.value([_route('a')]),
      summary: (id) async => _summary(id, moments: 7, meters: 12345),
    ));
    await tester.pumpAndSettle();

    expect(find.text(formatGpsDistance(12345)), findsOneWidget);
    expect(find.text('1 год 0 хв'), findsOneWidget);
    expect(find.text('Точки: 7'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('no metric is invented while the Summary is unavailable',
      (tester) async {
    await tester.pumpWidget(_app(
      Stream.value([_route('a')]),
      summary: (id) async => null,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(GpsJourneyHistoryCard), findsOneWidget);
    expect(find.textContaining('Точки:'), findsNothing);
    expect(find.textContaining('км'), findsNothing);
  });

  testWidgets('H08/H09 existing sync states are labelled, offline included',
      (tester) async {
    await tester.pumpWidget(_app(Stream.value([
      _route('a', sync: RouteSyncStatus.notSynced),
      _route('b', sync: RouteSyncStatus.syncing),
      _route('c', sync: RouteSyncStatus.synced),
      _route('d', sync: RouteSyncStatus.failed),
    ])));
    await tester.pump();
    await tester.pump();

    expect(find.text('Збережено на пристрої'), findsOneWidget);
    expect(find.text('Синхронізація…'), findsOneWidget);
    expect(find.text('Синхронізовано'), findsOneWidget);
    expect(find.text('Помилка синхронізації'), findsOneWidget);
  });

  testWidgets('H10/H11 list reacts to a new Journey and a sync change',
      (tester) async {
    final controller = StreamController<List<LocalRecordedRoute>>();
    addTearDown(controller.close);
    await tester.pumpWidget(_app(controller.stream));

    controller.add([]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gps_history_empty')), findsOneWidget);

    controller.add([_route('a')]);
    await tester.pumpAndSettle();
    expect(find.text('Збережено на пристрої'), findsOneWidget);

    controller.add([_route('a', sync: RouteSyncStatus.synced)]);
    await tester.pumpAndSettle();
    expect(find.text('Синхронізовано'), findsOneWidget);
    expect(find.text('Збережено на пристрої'), findsNothing);
  });

  testWidgets('item tap exposes the stable route id seam', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_app(
      Stream.value([_route('abc')]),
      onOpen: opened.add,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(GpsJourneyHistoryCard));
    await tester.pump();

    expect(opened, ['abc']);
  });

  testWidgets('without a Details destination rows do nothing on tap',
      (tester) async {
    await tester.pumpWidget(_app(Stream.value([_route('abc')])));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(GpsJourneyHistoryCard));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(GpsJourneyHistoryBody), findsOneWidget);
  });

  testWidgets('H20 a long list builds lazily', (tester) async {
    final routes = [for (var i = 0; i < 300; i++) _route('r$i')];
    await tester.pumpWidget(_app(Stream.value(routes)));
    await tester.pumpAndSettle();

    expect(find.byType(GpsJourneyHistoryCard).evaluate().length, lessThan(30));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('gps_history_item_r250')), 2000,
        maxScrolls: 200);
    expect(find.byKey(const ValueKey('gps_history_item_r250')), findsOneWidget);
  });

  group('Responsive', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('fits ${width}dp @ ${scale}x without overflow',
            (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_app(
            Stream.value([
              _route('a',
                  title: 'Дуже довга назва подорожі через усі Карпати '
                      'та ще трохи далі',
                  sync: RouteSyncStatus.failed),
              _route('b'),
            ]),
            width: width,
            scale: scale,
          ));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byType(GpsJourneyHistoryCard), findsWidgets);
        });
      }
    }
  });
}
