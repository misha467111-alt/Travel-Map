import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database_provider.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_journey_replay_screen.dart';

/// Phase 2.5.1 -- the PRODUCT path of the Replay screen
/// (`gpsJourneyReplayTimelineProvider` -> `GpsJourneyReplayScreen`) must use
/// the confirmed GPS track. Real in-memory Drift data; the timeline provider
/// itself is NOT overridden.
void main() {
  const owner = 'me';
  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime at(num s) => t0.add(Duration(seconds: s.round()));
  const mPerDeg = 111195.0;

  late GpsLocalDatabase db;
  setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> point(String id, double lat, double lng, num sec,
      {double acc = 5, double speed = 1.5}) async {
    await db.appendRoutePoint(
      ownerId: owner,
      recordedRouteId: id,
      latitude: lat,
      longitude: lng,
      horizontalAccuracy: acc,
      speed: speed,
      recordedAt: at(sec),
    );
  }

  /// [confirmed] walking samples near Kyiv, then (optionally) a jump to Peru
  /// followed by [fake] self-consistent samples at 56 m/s.
  Future<void> journey(String id,
      {required int confirmed, int fake = 0, double finish = 1000}) async {
    await db.createLocalRecordedRoute(id: id, ownerId: owner, startedAt: t0);
    for (var i = 0; i < confirmed; i++) {
      await point(id, 50.33 + 0.8 * 10 * i / mPerDeg, 30.49, 10.0 * i,
          acc: 100, speed: 0.8);
    }
    final base = 10.0 * confirmed;
    for (var i = 0; i < fake; i++) {
      await point(id, -12.0 + 56 * 2 * i / mPerDeg, -77.0, base + 1 + 2 * i,
          acc: 3, speed: 56);
    }
    await db.finishRecordingLocally(
        ownerId: owner, routeId: id, occurredAt: at(finish));
  }

  ProviderContainer container() {
    final c = ProviderContainer(
        overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpScreen(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: GpsJourneyReplayScreen(ownerId: owner, routeId: id),
      ),
    ));
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(GoogleMap).evaluate().isNotEmpty) break;
    }
  }

  test('P01 the provider builds the CONFIRMED timeline (no Peru samples)',
      () async {
    await journey('r1', confirmed: 26, fake: 100);
    final tl = await container().read(
        gpsJourneyReplayTimelineProvider((ownerId: owner, routeId: 'r1'))
            .future);

    expect(tl, isNotNull);
    expect(tl!.sampleCount, 26);
    expect(tl.diagnostics.unreliablePoints, 100);
    for (var i = 0; i < tl.sampleCount; i++) {
      expect(tl.latitudeAt(i), closeTo(50.33, 0.01));
    }
    expect(tl.runs, hasLength(1));
    expect(tl.positionAt(tl.activeDuration).latitude, closeTo(50.33, 0.01),
        reason: 'never in Peru');
  });

  test(
      'P02 an adopted far chain stays behind a discontinuity: the marker is '
      'held, never moved across the world', () async {
    await db.createLocalRecordedRoute(id: 'r2', ownerId: owner, startedAt: t0);
    for (var i = 0; i < 10; i++) {
      await point('r2', 50.33 + 0.8 * 10 * i / mPerDeg, 30.49, 10.0 * i,
          acc: 50, speed: 0.8);
    }
    for (var i = 0; i < 350; i++) {
      await point('r2', -12.0 + 30 * 2 * i / mPerDeg, -77.0, 101 + 2 * i,
          acc: 3, speed: 30);
    }
    await db.finishRecordingLocally(
        ownerId: owner, routeId: 'r2', occurredAt: at(900));
    final tl = await container().read(
        gpsJourneyReplayTimelineProvider((ownerId: owner, routeId: 'r2'))
            .future);

    expect(tl!.runs, hasLength(2));
    final lastNear = tl.playbackTimeAt(9);
    final firstFar = tl.playbackTimeAt(10);
    final mid = lastNear + (firstFar - lastNear) ~/ 2;
    final held = tl.positionAt(mid);
    expect(held.latitude, closeTo(50.33, 0.01));
  });

  test('P03 zero and one confirmed point are handled', () async {
    await db.createLocalRecordedRoute(id: 'r3', ownerId: owner, startedAt: t0);
    await point('r3', 50.0, 30.0, 5, acc: 40300);
    await db.finishRecordingLocally(
        ownerId: owner, routeId: 'r3', occurredAt: at(60));
    final none = await container().read(
        gpsJourneyReplayTimelineProvider((ownerId: owner, routeId: 'r3'))
            .future);
    expect(none!.sampleCount, 0);

    await db.createLocalRecordedRoute(id: 'r4', ownerId: owner, startedAt: t0);
    await point('r4', 50.0, 30.0, 5);
    await db.finishRecordingLocally(
        ownerId: owner, routeId: 'r4', occurredAt: at(60));
    final one = await container().read(
        gpsJourneyReplayTimelineProvider((ownerId: owner, routeId: 'r4'))
            .future);
    expect(one!.sampleCount, 1);
  });

  testWidgets(
      'P04 the screen frames Kyiv, not the Atlantic; marker at the '
      'confirmed position', (tester) async {
    await tester.runAsync(() => journey('r5', confirmed: 26, fake: 100));
    await pumpScreen(tester, 'r5');

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.initialCameraPosition.target.latitude, closeTo(50.33, 0.01));
    expect(map.initialCameraPosition.target.longitude, closeTo(30.49, 0.01));
    for (final m in map.markers) {
      expect(m.position.latitude, closeTo(50.33, 0.01));
    }
    expect(find.byKey(const Key('gps_replay_play_pause')), findsOneWidget);
  });

  testWidgets('P05 a clean Journey replays as before (Play/Pause, speeds)',
      (tester) async {
    await tester.runAsync(() => journey('r6', confirmed: 60));
    await pumpScreen(tester, 'r6');

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.initialCameraPosition.target.latitude, closeTo(50.33, 0.01));
    await tester.tap(find.byKey(const Key('gps_replay_play_pause')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.pause), findsOneWidget);
    for (final label in ['0.5x', '2x', '4x', '1x']) {
      await tester.tap(find.byKey(Key('gps_replay_speed_$label')));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('gps_replay_play_pause')));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
