import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database_provider.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_map_screen.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';
import 'package:flutter_application_1/features/gps/sync/domain/gps_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/gps_sync_coordinator.dart';
import 'package:flutter_application_1/features/map/providers/map_provider.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

/// Journey Phase 1B -- real end-to-end coverage through the actual
/// `GpsRecordingController`/`GpsLocalDatabase`, on the actual production
/// recording screen. Reuses the exact harness pattern already established
/// and proven in `gps_recording_map_screen_test.dart` (same fake-clock/
/// `runAsync` discipline; see that file's own extensive comments on why
/// each pump/runAsync call is shaped the way it is).
///
/// Covers M01/M02 (the control is reachable while recording/paused --
/// already also covered by the pre-existing `canAddWaypoint` tests, but
/// exercised here end-to-end for real), M14 (the real controller path is
/// actually invoked), and M17/M18 (creating a Moment never pauses or
/// resumes the recording itself). Everything else (M03-M13, M15/M16,
/// M19-M25) is covered in `gps_add_moment_sheet_test.dart` at the pure
/// sheet level, which needs none of this real-controller machinery.
class _NoOpGpsSyncRepository implements GpsSyncRepository {
  @override
  Future<void> ensureRouteShell({
    required String routeId,
    String? tripId,
    String? title,
    required String transportMode,
    required String visibility,
    required DateTime startedAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> syncPoints(
          {required String routeId, required List<LocalRoutePoint> points}) =>
      throw UnimplementedError();

  @override
  Future<int> syncEvents(
          {required String routeId, required List<LocalRouteEvent> events}) =>
      throw UnimplementedError();

  @override
  Future<void> upsertWaypoint(LocalWaypoint waypoint) =>
      throw UnimplementedError();

  @override
  Future<void> deleteWaypoint(String waypointId) => throw UnimplementedError();

  @override
  Future<GpsFinalizeResponse> finalizeRoute(String routeId) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GpsLocalDatabase db;
  late FakeLocationSource source;
  late FakeNotificationPermissionSource notifications;
  late GpsRecordingController controller;
  late GpsSyncCoordinator syncCoordinator;

  setUp(() {
    db = GpsLocalDatabase.forTesting(NativeDatabase.memory());
    source = FakeLocationSource()..permission = LocationPermission.whileInUse;
    notifications = FakeNotificationPermissionSource();
    controller = GpsRecordingController(
      ownerId: 'me',
      db: db,
      locationSource: source,
      notificationPermissionSource: notifications,
    );
    syncCoordinator = GpsSyncCoordinator(
      ownerId: 'me',
      db: db,
      repository: _NoOpGpsSyncRepository(),
      autoSyncOnInit: false,
    );
  });

  tearDown(() async {
    controller.dispose();
    syncCoordinator.dispose();
    await TestWidgetsFlutterBinding.instance.runAsync(() => db.close());
    await source.dispose();
  });

  Future<void> settle(WidgetTester tester) => tester.pump(Duration.zero);

  Future<T?> realAwait<T>(WidgetTester tester, Future<T> Function() action) =>
      tester.runAsync(action);

  Future<void> disposeCleanly(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  Future<void> waitUntil(
    WidgetTester tester,
    Future<bool> Function() check, {
    int maxAttempts = 50,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final done = await tester.runAsync(check);
      if (done ?? false) return;
      await tester.pump();
    }
  }

  Widget subject(GpsRecordingState state) {
    final body = GpsRecordingMapBody(
      ownerId: 'me',
      state: state,
      controller: controller,
      syncCoordinator: syncCoordinator,
    );
    return ProviderScope(
      overrides: [
        gpsLocalDatabaseProvider.overrideWithValue(db),
        currentPositionProvider.overrideWith((ref) async => testPosition()),
      ],
      // Unlike the sibling `gps_recording_map_screen_test.dart` harness
      // (which never needed a ScaffoldMessenger), this file's own
      // `_addMoment` calls `ScaffoldMessenger.of(context).showSnackBar`
      // on success -- a real `Scaffold` ancestor is required for that,
      // matching the real `GpsRecordingMapScreen` (which always wraps
      // `GpsRecordingMapBody` in exactly one `Scaffold`).
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: body),
      ),
    );
  }

  /// Mounts the screen, waits (via a real DB poll -- see this file's own
  /// class doc / the sibling file's extensive reasoning on why a plain
  /// `settle()` cannot be trusted for real, isolate-backed Drift writes)
  /// until [controller]'s last-accepted position has actually landed,
  /// then drives the real "Додати точку" -> sheet -> submit flow through
  /// the UI.
  Future<void> createMomentViaUi(
    WidgetTester tester, {
    required String routeId,
    required String type,
    String? title,
  }) async {
    await tester.pumpWidget(subject(controller.state));
    await tester.pump();
    await settle(tester);

    await waitUntil(tester, () async {
      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      return points.isNotEmpty;
    });
    await settle(tester);

    await tester
        .tap(find.byKey(const Key('gps_recording_add_waypoint_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    if (type != 'custom') {
      await tester.tap(find.byKey(Key('gps_moment_type_$type')));
      await tester.pump();
    }
    if (title != null) {
      await tester.enterText(
          find.byKey(const Key('gps_moment_title_field')), title);
    }
    await tester.tap(find.byKey(const Key('gps_moment_add_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
      'M01/M14 the real "Додати точку" control opens the sheet and a real '
      'Moment is created via the actual controller path while recording',
      (tester) async {
    await realAwait(tester, controller.start);
    await settle(tester);
    final routeId = controller.state.routeId!;
    source.emitPosition(testPosition(latitude: 50.42, longitude: 30.53));

    await createMomentViaUi(tester,
        routeId: routeId, type: 'viewpoint', title: 'Гарний вид');

    await waitUntil(tester, () async {
      final waypoints =
          await db.getWaypoints(ownerId: 'me', recordedRouteId: routeId);
      return waypoints.isNotEmpty;
    });
    await settle(tester);

    final waypoints = await tester.runAsync(() => db.getWaypoints(
          ownerId: 'me',
          recordedRouteId: routeId,
        ));
    expect(waypoints, hasLength(1));
    expect(waypoints!.single.waypointType, 'viewpoint');
    expect(waypoints.single.title, 'Гарний вид');
    expect(waypoints.single.latitude, 50.42);

    // M17: creating a Moment while recording never pauses the recording.
    expect(controller.state.status, GpsRecordingStatus.recording);
    await disposeCleanly(tester);
  });

  testWidgets(
      'M02/M18 a real Moment can be created while paused, and the '
      'recording remains paused afterwards', (tester) async {
    await realAwait(tester, controller.start);
    await settle(tester);
    final routeId = controller.state.routeId!;
    source.emitPosition(testPosition());
    // A point must land while still recording (a paused controller no
    // longer has a live position subscription) -- confirmed via the
    // controller's own real DB before pausing.
    await tester.pumpWidget(subject(controller.state));
    await tester.pump();
    await waitUntil(tester, () async {
      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      return points.isNotEmpty;
    });
    await settle(tester);
    await realAwait(tester, controller.pause);
    await settle(tester);

    await createMomentViaUi(tester, routeId: routeId, type: 'rest');

    await waitUntil(tester, () async {
      final waypoints =
          await db.getWaypoints(ownerId: 'me', recordedRouteId: routeId);
      return waypoints.isNotEmpty;
    });
    await settle(tester);

    final waypoints = await tester.runAsync(
        () => db.getWaypoints(ownerId: 'me', recordedRouteId: routeId));
    expect(waypoints, hasLength(1));
    expect(waypoints!.single.waypointType, 'rest');

    // M18: creating a Moment while paused never auto-resumes.
    expect(controller.state.status, GpsRecordingStatus.paused);
    final route = await tester
        .runAsync(() => db.getRecordedRoute(ownerId: 'me', id: routeId));
    expect(route!.status, RecordedRouteStatus.paused);
    await disposeCleanly(tester);
  });
}
