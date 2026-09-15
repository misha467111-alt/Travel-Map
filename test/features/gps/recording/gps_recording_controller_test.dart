import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

void main() {
  // GpsRecordingController registers itself as a WidgetsBindingObserver
  // (for app-lifecycle-aware stream suspension), which needs
  // WidgetsBinding.instance to exist -- automatic in testWidgets(), not
  // in plain test(), so it's initialized explicitly here.
  TestWidgetsFlutterBinding.ensureInitialized();

  late GpsLocalDatabase db;
  late FakeLocationSource source;
  late FakeNotificationPermissionSource notifications;
  late GpsRecordingController controller;

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
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
    await source.dispose();
  });

  /// Drains the microtask queue enough for the controller's
  /// fire-and-forget async work (construction-time recovery detection,
  /// stream listener callbacks) to complete before assertions run.
  Future<void> settle() => pumpEventQueue();

  group('state stream', () {
    test('immediately emits idle when no recording is recoverable', () async {
      final initial = await controller.stateStream.first;

      expect(initial, GpsRecordingState.idle);
    });
  });

  group('start', () {
    test(
        'with permission granted transitions to recording and creates the '
        'local route', () async {
      await controller.start();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.recording);
      expect(controller.state.routeId, isNotNull);
      final route = await db.getRecordedRoute(
          ownerId: 'me', id: controller.state.routeId!);
      expect(route, isNotNull);
      expect(route!.status, RecordedRouteStatus.recording);
    });

    test(
        'permission denied does not create a local route and reports '
        'permissionError', () async {
      source.permission = LocationPermission.denied;
      await controller.start();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.permissionError);
      expect(controller.state.routeId, isNull);
      expect((await db.getRecoverableRecording('me')), isNull);
    });

    test(
        'services disabled does not create a local route and reports '
        'serviceError', () async {
      source.serviceEnabled = false;
      await controller.start();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.serviceError);
      expect(controller.state.routeId, isNull);
      expect((await db.getRecoverableRecording('me')), isNull);
    });

    test('subscribes to the position stream exactly once', () async {
      await controller.start();
      await settle();
      expect(source.subscribeCallCount, 1);
      expect(source.activeSubscriptionCount, 1);
    });
  });

  group('accepted samples', () {
    test('the first accepted GPS sample is persisted locally', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      source.emitPosition(testPosition(latitude: 50.4, longitude: 30.5));
      await settle();

      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, hasLength(1));
      expect(points.single.latitude, 50.4);
      expect(controller.state.pointCount, 1);
      expect(controller.state.lastAccepted?.latitude, 50.4);
    });

    test('multiple positions produce monotonic, gap-free seq', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      for (var i = 0; i < 5; i++) {
        source.emitPosition(testPosition(
          latitude: 50.4 + i * 0.001,
          timestamp: DateTime.utc(2026, 1, 1, 10, i),
        ));
        await settle();
      }

      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points.map((p) => p.seq), [1, 2, 3, 4, 5]);
    });

    test('a malformed coordinate is rejected and never reaches local storage',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      source.emitPosition(testPosition(latitude: double.nan));
      await settle();

      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, isEmpty);
      expect(controller.state.pointCount, 0);
    });

    test(
        'a stream error is handled without corrupting already-persisted '
        'local state', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      source.emitPosition(testPosition());
      await settle();
      source.emitStreamError(Exception('simulated GPS chip failure'));
      await settle();

      // The controller reflects the error...
      expect(controller.state.status, GpsRecordingStatus.otherError);
      // ...but the point already accepted before the error is untouched,
      // and the local route itself is still there and still recoverable.
      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, hasLength(1));
      final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route, isNotNull);
    });
  });

  group('pause / resume', () {
    test('pause stops further point writes', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      await controller.pause();
      await settle();
      expect(controller.state.status, GpsRecordingStatus.paused);

      source.emitPosition(testPosition());
      await settle();

      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, isEmpty,
          reason: 'no subscription should be active while paused');
    });

    test(
        'pause atomically flips the local route to paused and appends a '
        'pause event', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      await controller.pause();
      await settle();

      final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
      final events =
          await db.getRouteEvents(ownerId: 'me', recordedRouteId: routeId);
      expect(route!.status, RecordedRouteStatus.paused);
      expect(events.map((e) => e.eventType),
          [RouteEventType.start, RouteEventType.pause]);
    });

    test('resume restarts point writes', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      await controller.pause();
      await settle();

      await controller.resume();
      await settle();
      expect(controller.state.status, GpsRecordingStatus.recording);

      source.emitPosition(testPosition());
      await settle();

      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, hasLength(1));
    });

    test(
        'never accumulates more than one active stream subscription across '
        'pause/resume cycles', () async {
      await controller.start();
      await settle();
      await controller.pause();
      await settle();
      await controller.resume();
      await settle();
      await controller.pause();
      await settle();
      await controller.resume();
      await settle();

      expect(source.activeSubscriptionCount, 1);
    });

    test(
        'resume re-checks permission and refuses to resume if it was revoked '
        'while paused', () async {
      await controller.start();
      await settle();
      await controller.pause();
      await settle();

      source.permission = LocationPermission.denied;
      await controller.resume();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.permissionError);
      final route = await db.getRecordedRoute(
          ownerId: 'me', id: controller.state.routeId!);
      expect(route!.status, RecordedRouteStatus.paused,
          reason: 'must remain paused locally, not silently resumed');
    });
  });

  group('waypoints', () {
    test('can be added while recording, using the last known position',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      source.emitPosition(testPosition(latitude: 50.41, longitude: 30.51));
      await settle();

      await controller.addWaypoint(
          waypointType: 'viewpoint', title: 'Nice view');
      await settle();

      final waypoints =
          await db.getWaypoints(ownerId: 'me', recordedRouteId: routeId);
      expect(waypoints, hasLength(1));
      expect(waypoints.single.latitude, 50.41);
      expect(waypoints.single.title, 'Nice view');
      expect(waypoints.single.photoRef, isNull);
    });

    test('can be added while paused', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      source.emitPosition(testPosition());
      await settle();
      await controller.pause();
      await settle();

      await controller.addWaypoint(waypointType: 'campsite');
      await settle();

      final waypoints =
          await db.getWaypoints(ownerId: 'me', recordedRouteId: routeId);
      expect(waypoints, hasLength(1));
    });

    test('is rejected when idle (no active recording)', () async {
      await controller.addWaypoint(waypointType: 'danger');
      await settle();
      expect(controller.state.status, GpsRecordingStatus.idle);
    });

    test('accepts explicit coordinates instead of the last known position',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      await controller.addWaypoint(
        waypointType: 'parking',
        latitude: 51.0,
        longitude: 31.0,
      );
      await settle();

      final waypoints =
          await db.getWaypoints(ownerId: 'me', recordedRouteId: routeId);
      expect(waypoints.single.latitude, 51.0);
    });
  });

  group('finish', () {
    test(
        'stops the stream and completes the route locally, preserving all '
        'points/events', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      source.emitPosition(testPosition());
      await settle();

      await controller.finish();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.completed);
      expect(source.activeSubscriptionCount, 0);
      final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route!.status, RecordedRouteStatus.completed);
      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, hasLength(1),
          reason: 'raw points must be preserved, not erased');
    });

    test('a point emitted after finish is not written', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      await controller.finish();
      await settle();

      source.emitPosition(testPosition());
      await settle();

      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, isEmpty);
    });
  });

  group('discard', () {
    test(
        'stops the stream and marks the route discarded without erasing '
        'raw data', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      source.emitPosition(testPosition());
      await settle();

      await controller.discard();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.idle);
      expect(source.activeSubscriptionCount, 0);
      final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route!.status, RecordedRouteStatus.discarded);
      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, hasLength(1),
          reason: 'discard must not erase raw GPS data');
    });
  });

  group('restart/crash recovery', () {
    test(
        'a fresh controller detects an unfinished (recording) route on '
        'construction', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      // Simulate an app restart: dispose this controller (as the OS
      // killing the process would end its lifetime) and construct a new
      // one against the same local database.
      controller.dispose();

      final recovered = GpsRecordingController(
          ownerId: 'me',
          db: db,
          locationSource: source,
          notificationPermissionSource: notifications);
      await settle();
      expect(recovered.state.status, GpsRecordingStatus.recoverable);
      expect(recovered.state.routeId, routeId);
      recovered.dispose();
    });

    test(
        'a fresh controller detects an unfinished (paused) route on '
        'construction', () async {
      await controller.start();
      await settle();
      await controller.pause();
      await settle();
      final routeId = controller.state.routeId!;
      controller.dispose();

      final recovered = GpsRecordingController(
          ownerId: 'me',
          db: db,
          locationSource: source,
          notificationPermissionSource: notifications);
      await settle();
      expect(recovered.state.status, GpsRecordingStatus.recoverable);
      expect(recovered.state.routeId, routeId);
      recovered.dispose();
    });

    test('a second recording is blocked while a recoverable route exists',
        () async {
      await controller.start();
      await settle();
      controller.dispose();

      final recovered = GpsRecordingController(
          ownerId: 'me',
          db: db,
          locationSource: source,
          notificationPermissionSource: notifications);
      await settle();
      expect(recovered.state.status, GpsRecordingStatus.recoverable);

      await recovered.start();
      await settle();
      expect(recovered.state.status, GpsRecordingStatus.recoverable,
          reason: 'start() must refuse to run while a route is recoverable');
      recovered.dispose();
    });

    test('resumeRecoverableRecording restarts sampling on the recovered route',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      controller.dispose();

      final recovered = GpsRecordingController(
          ownerId: 'me',
          db: db,
          locationSource: source,
          notificationPermissionSource: notifications);
      await settle();
      await recovered.resumeRecoverableRecording();
      await settle();

      expect(recovered.state.status, GpsRecordingStatus.recording);
      expect(recovered.state.routeId, routeId);
      recovered.dispose();
    });

    test('finishRecoverableRecording completes the recovered route', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      controller.dispose();

      final recovered = GpsRecordingController(
          ownerId: 'me',
          db: db,
          locationSource: source,
          notificationPermissionSource: notifications);
      await settle();
      await recovered.finishRecoverableRecording();
      await settle();

      final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route!.status, RecordedRouteStatus.completed);
      recovered.dispose();
    });

    test('discardRecoverableRecording discards the recovered route', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      controller.dispose();

      final recovered = GpsRecordingController(
          ownerId: 'me',
          db: db,
          locationSource: source,
          notificationPermissionSource: notifications);
      await settle();
      await recovered.discardRecoverableRecording();
      await settle();

      final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route!.status, RecordedRouteStatus.discarded);
      recovered.dispose();
    });

    test('user B cannot recover or observe user A\'s unfinished route',
        () async {
      await controller.start();
      await settle();
      controller.dispose();

      final controllerB = GpsRecordingController(
          ownerId: 'accountB',
          db: db,
          locationSource: source,
          notificationPermissionSource: notifications);
      await settle();

      expect(controllerB.state.status, GpsRecordingStatus.idle);
      expect(await db.getRecoverableRecording('accountB'), isNull);
      controllerB.dispose();
    });
  });

  group('app lifecycle (GPS-4B2 background continuity)', () {
    test(
        'TEST A -- an active recording is not suspended when the app is '
        'backgrounded (paused or detached), because the Android foreground '
        'service is what keeps the same stream alive, not this class',
        () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await settle();
      expect(source.activeSubscriptionCount, 1);

      controller.didChangeAppLifecycleState(AppLifecycleState.detached);
      await settle();
      expect(source.activeSubscriptionCount, 1);

      final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route!.status, RecordedRouteStatus.recording,
          reason: 'backgrounding must not touch local status either');
    });

    test(
        'TEST B -- returning to foreground while still recording does not '
        'create a duplicate subscription', () async {
      await controller.start();
      await settle();
      final routeId = controller.state.routeId!;
      expect(source.subscribeCallCount, 1);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await settle();
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(source.activeSubscriptionCount, 1);
      expect(source.subscribeCallCount, 1,
          reason: 'the same subscription must survive the round trip, not '
              'be torn down and recreated');

      // the one subscription that survived is still the live one -- a
      // point emitted now is still accepted on the same route.
      source.emitPosition(testPosition());
      await settle();
      final points =
          await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
      expect(points, hasLength(1));
    });

    test(
        'a paused recording has no subscription regardless of app '
        'lifecycle, and no lifecycle transition ever creates one', () async {
      await controller.start();
      await settle();
      await controller.pause();
      await settle();
      expect(source.activeSubscriptionCount, 0);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await settle();
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      expect(controller.state.status, GpsRecordingStatus.paused,
          reason: 'only an explicit resume() call may restart sampling');
      expect(source.activeSubscriptionCount, 0);
    });

    test('inactive/hidden while recording do not affect the subscription',
        () async {
      await controller.start();
      await settle();

      controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await settle();
      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await settle();

      expect(source.activeSubscriptionCount, 1);
    });

    test(
        'TEST G -- with no active recording, no lifecycle transition ever '
        'creates a subscription', () async {
      for (final lifecycleState in AppLifecycleState.values) {
        controller.didChangeAppLifecycleState(lifecycleState);
        await settle();
      }

      expect(controller.state.status, GpsRecordingStatus.idle);
      expect(source.subscribeCallCount, 0,
          reason: 'no background GPS subscription may exist without an '
              'explicitly started recording');
      expect(source.activeSubscriptionCount, 0);
    });
  });

  group('notification permission (GPS-4B2.1)', () {
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;

    tearDown(() {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    });

    test('start() requests it lazily, exactly once, on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await controller.start();
      await settle();

      expect(notifications.requestCallCount, 1);
      expect(controller.state.status, GpsRecordingStatus.recording);
    });

    test('is never requested on iOS -- GPS-4B2/GPS-4B2.1 stay Android-only',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await controller.start();
      await settle();

      expect(notifications.requestCallCount, 0);
      expect(controller.state.status, GpsRecordingStatus.recording,
          reason: 'recording itself must be unaffected by this platform '
              'branch either way');
    });

    test(
        'a denial does not block recording, corrupt state, or create a '
        'duplicate stream', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      notifications.granted = false;

      await controller.start();
      await settle();

      expect(controller.state.status, GpsRecordingStatus.recording,
          reason: 'the location foreground service remains fully '
              'functional regardless of this permission\'s outcome');
      expect(source.activeSubscriptionCount, 1);
      expect(source.subscribeCallCount, 1);

      final routeId = controller.state.routeId!;
      final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
      expect(route!.status, RecordedRouteStatus.recording);
    });

    test('is requested again on an explicit resume(), not only on start()',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await controller.start();
      await settle();
      expect(notifications.requestCallCount, 1);

      await controller.pause();
      await settle();
      await controller.resume();
      await settle();

      expect(notifications.requestCallCount, 2);
      expect(controller.state.status, GpsRecordingStatus.recording);
    });
  });
}
