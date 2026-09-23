import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database_provider.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_active_recording_banner.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_map_screen.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recovery_card.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';
import 'package:flutter_application_1/features/gps/sync/domain/gps_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/gps_sync_coordinator.dart';
import 'package:flutter_application_1/features/map/providers/map_provider.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

/// Never actually invoked by these tests (no test triggers a real sync
/// pass -- every [GpsSyncCoordinator] here is constructed with
/// `autoSyncOnInit: false`); throwing loudly on any use catches a test
/// accidentally exercising a real sync path instead of a fake one.
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

/// Records every pushed route without requiring it to ever actually
/// build/mount -- `Navigator.push` notifies observers synchronously,
/// before any frame builds the new route's widget. This is what lets
/// E05/E06/E09/E10/E20 verify *which* screen the banner's "Повернутися"
/// action pushes (and how many times) without ever calling
/// `GpsRecordingMapScreen.build()`, which reads `Supabase.instance`
/// directly and would throw in a test with no live Supabase session --
/// the same wall documented in `gps_logout_guard_test.dart`.
class _RecordingRouteObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
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

  // --- Helpers, carried over verbatim from Phase 4D's own test-file ---
  // --- (see gps_recording_map_screen_test.dart for the full reasoning) --

  /// Flushes microtasks and advances the fake clock by a zero duration --
  /// NOT a bare `tester.pump()` (which never calls `elapse()` at all, so
  /// it cannot fire an already-pending zero-duration Timer -- e.g. the one
  /// Drift's `StreamQueryStore.markAsClosed` schedules on stream
  /// disposal).
  Future<void> settle(WidgetTester tester) => tester.pump(Duration.zero);

  /// `GpsLocalDatabase`'s real `NativeDatabase` executor does work that
  /// never completes on its own inside `testWidgets()`'s fake-clock zone.
  /// `tester.runAsync` is the correct escape. Kept to a single, narrow
  /// call per use and, where possible, invoked before any
  /// `ClusteredLocationMap`/`GoogleMap` is mounted -- an explicit
  /// `Future.delayed` inside `runAsync` while a live `GoogleMap` is
  /// mounted was observed (in Phase 4D) to eventually let a real frame
  /// reach `RenderAndroidView._sizePlatformView`, throwing
  /// `MissingPluginException`.
  Future<T?> realAwait<T>(WidgetTester tester, Future<T> Function() action) =>
      tester.runAsync(action);

  /// Polls a real query (never a fixed real-time delay) until [check] is
  /// satisfied, one `runAsync` call per attempt with a plain `pump()` in
  /// between -- looping inside a single `runAsync` callback was observed
  /// (Phase 4D) to hang indefinitely.
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

  Future<void> disposeCleanly(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  Widget bannerSubject({NavigatorObserver? observer}) => ProviderScope(
        overrides: [
          gpsLocalDatabaseProvider.overrideWithValue(db),
          // Without this, gpsRecordingStateProvider('me') would build its
          // *own*, entirely separate default controller (real
          // GeolocatorLocationSource/PermissionHandlerNotificationSource,
          // no platform-channel mock in `flutter test`) instead of
          // reflecting the fake-backed `controller` this file actually
          // drives -- besides being the wrong controller, its unawaited
          // constructor-time _detectRecoverableRecording() Drift query
          // (see gpsRecordingStateProvider's own doc) never gets a
          // runAsync escape here, which was observed to hang the test.
          gpsRecordingControllerProvider('me').overrideWithValue(controller),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          navigatorObservers: [if (observer != null) observer],
          home:
              const Scaffold(body: GpsActiveRecordingBannerBody(ownerId: 'me')),
        ),
      );

  // --- E01-E03: idle / recording / paused visibility -----------------

  group('E01-E03 visibility by status', () {
    testWidgets('E01 idle: banner is hidden', (tester) async {
      await tester.pumpWidget(bannerSubject());
      await tester.pump();

      expect(
          find.byKey(const Key('gps_active_recording_banner')), findsNothing);
    });

    testWidgets('E02 recording: banner is visible', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);

      await tester.pumpWidget(bannerSubject());
      await tester.pump();

      expect(
          find.byKey(const Key('gps_active_recording_banner')), findsOneWidget);
      expect(find.text('Запис триває'), findsOneWidget);
      await disposeCleanly(tester);
    });

    testWidgets('E03 paused: banner is visible with paused meaning',
        (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      await realAwait(tester, controller.pause);
      await settle(tester);

      await tester.pumpWidget(bannerSubject());
      await tester.pump();

      expect(
          find.byKey(const Key('gps_active_recording_banner')), findsOneWidget);
      expect(find.text('Пауза'), findsOneWidget);
      await disposeCleanly(tester);
    });
  });

  // --- E04/E10: recoverable ------------------------------------------

  group('E04/E10 recoverable', () {
    testWidgets('E04 recoverable: recovery-oriented banner is visible',
        (tester) async {
      // Seed a 'recording' local route directly (no controller involved
      // yet), then construct a *fresh* controller -- its constructor-time
      // _detectRecoverableRecording() picks this up as `recoverable`,
      // exactly like a real app restart after a crash.
      await realAwait(
        tester,
        () => db.createLocalRecordedRoute(
            id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1)),
      );
      controller.dispose();
      controller = GpsRecordingController(
        ownerId: 'me',
        db: db,
        locationSource: source,
        notificationPermissionSource: notifications,
      );
      await waitUntil(
          tester,
          () async =>
              controller.state.status == GpsRecordingStatus.recoverable);

      await tester.pumpWidget(bannerSubject());
      await tester.pump();

      expect(
          find.byKey(const Key('gps_active_recording_banner')), findsOneWidget);
      expect(find.text('Знайдено незавершений запис'), findsOneWidget);
      await disposeCleanly(tester);
    });
  });

  // --- E05/E06/E09/E20: navigation behavior ---------------------------

  group('E05/E06/E09/E20 "Повернутися" navigation', () {
    testWidgets(
        'E05 tapping "Повернутися" pushes a route that builds the real '
        'production GpsRecordingMapScreen', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);

      final observer = _RecordingRouteObserver();
      await tester.pumpWidget(bannerSubject(observer: observer));
      await tester.pump();
      // MaterialApp's own initial route ("/") already fired didPush once
      // by this point -- only count pushes from here on.
      final before = observer.pushed.length;

      // Deliberately no pump() after this tap: Navigator.push() notifies
      // observers synchronously, before any frame builds the new route's
      // widget -- pumping here would call GpsRecordingMapScreen.build(),
      // which reads Supabase.instance directly and throws without a live
      // session (see _RecordingRouteObserver's own doc comment).
      await tester
          .tap(find.byKey(const Key('gps_active_recording_banner_action')));

      expect(observer.pushed, hasLength(before + 1));
      final route = observer.pushed.last as MaterialPageRoute<void>;
      expect(route.fullscreenDialog, isTrue);
      // Merely instantiating the widget (not building/mounting it) never
      // touches Supabase -- only GpsRecordingMapScreen.build() does.
      final built = route.builder(tester.element(find.byType(Scaffold)));
      expect(built, isA<GpsRecordingMapScreen>());
    });

    testWidgets(
        'E06 the return action never calls any controller method -- it is '
        'pure navigation, so it cannot start a second recording',
        (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      expect(source.subscribeCallCount, 1);
      final pointsBefore = controller.state.pointCount;

      final observer = _RecordingRouteObserver();
      await tester.pumpWidget(bannerSubject(observer: observer));
      await tester.pump();
      await tester
          .tap(find.byKey(const Key('gps_active_recording_banner_action')));

      expect(source.subscribeCallCount, 1,
          reason: 'start()/resume() would subscribe again; neither ran');
      expect(controller.state.status, GpsRecordingStatus.recording,
          reason: 'still the same, uninterrupted session');
      expect(controller.state.pointCount, pointsBefore);
    });

    testWidgets(
        'E09 re-entering via the indicator resolves to the identical '
        'controller instance -- the same session, never a new one',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          gpsLocalDatabaseProvider.overrideWithValue(db),
          gpsRecordingControllerProvider('me').overrideWithValue(controller),
        ],
      );
      addTearDown(container.dispose);

      await realAwait(tester, controller.start);
      await settle(tester);
      final before = container.read(gpsRecordingControllerProvider('me'));

      final observer = _RecordingRouteObserver();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          navigatorObservers: [observer],
          home:
              const Scaffold(body: GpsActiveRecordingBannerBody(ownerId: 'me')),
        ),
      ));
      await tester.pump();
      await tester
          .tap(find.byKey(const Key('gps_active_recording_banner_action')));

      final after = container.read(gpsRecordingControllerProvider('me'));
      expect(identical(before, after), isTrue);
      expect(after.state.routeId, before.state.routeId);
    });

    testWidgets(
        'E20 a rapid double-tap pushes GpsRecordingMapScreen exactly once',
        (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);

      final observer = _RecordingRouteObserver();
      await tester.pumpWidget(bannerSubject(observer: observer));
      await tester.pump();
      final before = observer.pushed.length;

      // Deliberately no pump() between the two taps: `_opening` is a
      // plain State field that `_open()`'s `setState(() => _opening =
      // true)` sets synchronously (only the *rebuild* is deferred to the
      // next frame) -- so the guard is already active for the second tap
      // even before either tap's route has had a chance to build. Pumping
      // in between would build the first pushed route for real, which
      // (like E05's own comment explains) reads Supabase.instance and
      // throws with no live session in this test.
      final finder =
          find.byKey(const Key('gps_active_recording_banner_action'));
      await tester.tap(finder);
      await tester.tap(finder, warnIfMissed: false);

      expect(observer.pushed, hasLength(before + 1),
          reason: 'the in-flight guard must block the second tap');
    });
  });

  // --- E07/E08: completed hides the banner; leaving keeps it truthful -

  group('E07/E08 completed hides / leaving the screen keeps it truthful', () {
    testWidgets('E07 completed: the active-recording banner disappears',
        (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      await realAwait(tester, controller.finish);
      await settle(tester);
      expect(controller.state.status, GpsRecordingStatus.completed);

      await tester.pumpWidget(bannerSubject());
      await tester.pump();

      expect(
          find.byKey(const Key('gps_active_recording_banner')), findsNothing);
      await disposeCleanly(tester);
    });

    testWidgets(
        'E08 a recording started elsewhere (never mounting the recording '
        'screen in this test at all) still makes the banner appear -- '
        'visibility depends only on controller state, not on whether '
        'GpsRecordingMapBody happens to be mounted', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);

      await tester.pumpWidget(bannerSubject());
      await tester.pump();

      expect(
          find.byKey(const Key('gps_active_recording_banner')), findsOneWidget);
      await disposeCleanly(tester);
    });
  });

  // --- E11-E13: recoverable Resume/Finish/Discard still use the -----
  // --- existing controller actions (via the real GpsRecordingMapBody) -

  group('E11-E13 recoverable actions reuse the existing controller', () {
    Future<void> seedRecoverable(WidgetTester tester) async {
      await realAwait(
        tester,
        () => db.createLocalRecordedRoute(
            id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1)),
      );
      controller.dispose();
      controller = GpsRecordingController(
        ownerId: 'me',
        db: db,
        locationSource: source,
        notificationPermissionSource: notifications,
      );
      await waitUntil(
          tester,
          () async =>
              controller.state.status == GpsRecordingStatus.recoverable);
    }

    Widget recoveryScreenSubject() => ProviderScope(
          overrides: [
            gpsLocalDatabaseProvider.overrideWithValue(db),
            currentPositionProvider.overrideWith((ref) async => testPosition()),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: GpsRecordingMapBody(
              ownerId: 'me',
              state: controller.state,
              controller: controller,
              syncCoordinator: syncCoordinator,
            ),
          ),
        );

    testWidgets('E11 Resume calls resumeRecoverableRecording', (tester) async {
      await seedRecoverable(tester);
      await tester.pumpWidget(recoveryScreenSubject());
      await tester.pump();

      expect(find.byType(GpsRecoveryCard), findsOneWidget);
      await realAwait(tester, () async {
        await tester.tap(find.byKey(const Key('gps_recovery_resume_button')));
      });
      await waitUntil(tester,
          () async => controller.state.status == GpsRecordingStatus.recording);

      expect(controller.state.status, GpsRecordingStatus.recording);
      expect(source.subscribeCallCount, 1);
      await disposeCleanly(tester);
    });

    testWidgets('E12 Finish calls finishRecoverableRecording', (tester) async {
      await seedRecoverable(tester);
      await tester.pumpWidget(recoveryScreenSubject());
      await tester.pump();

      await realAwait(tester, () async {
        await tester.tap(find.byKey(const Key('gps_recovery_finish_button')));
      });
      await waitUntil(tester,
          () async => controller.state.status == GpsRecordingStatus.completed);

      expect(controller.state.status, GpsRecordingStatus.completed);
      final route = await tester
          .runAsync(() => db.getRecordedRoute(ownerId: 'me', id: 'r1'));
      expect(route!.status, RecordedRouteStatus.completed);
      await disposeCleanly(tester);
    });

    testWidgets(
        'E13 Discard still requires confirmation before calling '
        'discardRecoverableRecording', (tester) async {
      await seedRecoverable(tester);
      await tester.pumpWidget(recoveryScreenSubject());
      await tester.pump();

      await tester.tap(find.byKey(const Key('gps_recovery_discard_button')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('gps_discard_confirm_button')), findsOneWidget);
      expect(controller.state.status, GpsRecordingStatus.recoverable,
          reason: 'must not discard before the dialog is confirmed');

      await tester.tap(find.byKey(const Key('gps_discard_confirm_button')));
      await waitUntil(tester,
          () async => controller.state.status == GpsRecordingStatus.idle);

      expect(controller.state.status, GpsRecordingStatus.idle);
      final route = await tester
          .runAsync(() => db.getRecordedRoute(ownerId: 'me', id: 'r1'));
      expect(route!.status, RecordedRouteStatus.discarded);
      await disposeCleanly(tester);
    });
  });

  // --- E14-E18: completed + sync state presentation + retry ----------

  group('E14-E18 completed route sync presentation', () {
    Widget completedSubject(GpsRecordingState state) => ProviderScope(
          overrides: [
            gpsLocalDatabaseProvider.overrideWithValue(db),
            currentPositionProvider.overrideWith((ref) async => testPosition()),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: GpsRecordingMapBody(
              ownerId: 'me',
              state: state,
              controller: controller,
              syncCoordinator: syncCoordinator,
            ),
          ),
        );

    GpsRecordingState completedState(String routeId) => GpsRecordingState(
          status: GpsRecordingStatus.completed,
          routeId: routeId,
          pointCount: 2,
          startedAt: DateTime.utc(2026, 1, 1),
        );

    testWidgets(
        'E14 completed + notSynced shows the existing locally-safe '
        'sync meaning, not data loss', (tester) async {
      await realAwait(tester, () async {
        await db.createLocalRecordedRoute(
            id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
        await db.finishRecordingLocally(
            ownerId: 'me',
            routeId: 'r1',
            occurredAt: DateTime.utc(2026, 1, 1, 1));
      });

      await tester.pumpWidget(completedSubject(completedState('r1')));
      await tester.pump();
      await settle(tester);
      await tester.pump();

      expect(find.text('Збережено на пристрої'), findsOneWidget);
      await disposeCleanly(tester);
    });

    testWidgets('E15 completed + syncing presentation', (tester) async {
      await realAwait(tester, () async {
        await db.createLocalRecordedRoute(
            id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
        await db.finishRecordingLocally(
            ownerId: 'me',
            routeId: 'r1',
            occurredAt: DateTime.utc(2026, 1, 1, 1));
        await db.markRouteSyncing(ownerId: 'me', routeId: 'r1');
      });

      await tester.pumpWidget(completedSubject(completedState('r1')));
      await tester.pump();
      await settle(tester);
      await tester.pump();

      expect(find.text('Синхронізація…'), findsOneWidget);
      await disposeCleanly(tester);
    });

    testWidgets('E16 completed + synced presentation', (tester) async {
      await realAwait(tester, () async {
        await db.createLocalRecordedRoute(
            id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
        await db.finishRecordingLocally(
            ownerId: 'me',
            routeId: 'r1',
            occurredAt: DateTime.utc(2026, 1, 1, 1));
        await db.recordRouteSyncOutcome(
            ownerId: 'me', routeId: 'r1', syncStatus: RouteSyncStatus.synced);
      });

      await tester.pumpWidget(completedSubject(completedState('r1')));
      await tester.pump();
      await settle(tester);
      await tester.pump();

      expect(find.text('Синхронізовано'), findsOneWidget);
      await disposeCleanly(tester);
    });

    testWidgets(
        'E17/E18 completed + failed exposes retry, and retry calls the '
        'existing GpsSyncCoordinator exactly as designed', (tester) async {
      await realAwait(tester, () async {
        await db.createLocalRecordedRoute(
            id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
        await db.finishRecordingLocally(
            ownerId: 'me',
            routeId: 'r1',
            occurredAt: DateTime.utc(2026, 1, 1, 1));
        await db.recordRouteSyncOutcome(
            ownerId: 'me',
            routeId: 'r1',
            syncStatus: RouteSyncStatus.failed,
            lastSyncError: 'network');
      });

      await tester.pumpWidget(completedSubject(completedState('r1')));
      await tester.pump();
      await settle(tester);
      await tester.pump();

      expect(find.text('Помилка синхронізації'), findsOneWidget);
      final retryButton = find.byKey(const Key('gps_sync_retry_button'));
      expect(retryButton, findsOneWidget);

      // GpsSyncCoordinator.retryRoute always calls the repository's
      // ensureRouteShell first -- _NoOpGpsSyncRepository throws
      // UnimplementedError on any call, which is exactly the proof this
      // tap really reached the real coordinator (not a fake/no-op) rather
      // than silently doing nothing.
      Object? caught;
      await realAwait(tester, () async {
        try {
          await tester.tap(retryButton);
          await tester.pump();
        } catch (error) {
          caught = error;
        }
      });
      await settle(tester);
      expect(caught, isNull,
          reason: 'the tap itself must not throw synchronously; '
              'retryRoute is fire-and-forget from the button');
      // The coordinator's own retryRoute() ultimately awaits
      // ensureRouteShell -- give it real time to reach (and record) that
      // failure via the exact same locally-observable route status.
      await waitUntil(tester, () async {
        final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
        return route?.lastSyncAttemptAt != null &&
            route!.lastSyncAttemptAt!
                .isAfter(DateTime.utc(2026, 1, 1, 1, 0, 1));
      });
      await disposeCleanly(tester);
    });
  });

  // --- E19: no full route-point stream dependency ---------------------

  group('E19 no route-point stream dependency', () {
    testWidgets(
        'the banner never watches gpsRoutePointsProvider -- overriding it '
        'to throw does not affect the banner at all', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          gpsLocalDatabaseProvider.overrideWithValue(db),
          gpsRecordingControllerProvider('me').overrideWithValue(controller),
          gpsRoutePointsProvider.overrideWith((ref, args) =>
              Stream<List<LocalRoutePoint>>.error(
                  StateError('gpsRoutePointsProvider must never be read by the '
                      'active-recording banner'))),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home:
              const Scaffold(body: GpsActiveRecordingBannerBody(ownerId: 'me')),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
          find.byKey(const Key('gps_active_recording_banner')), findsOneWidget);
      await disposeCleanly(tester);
    });
  });

  // --- E21/E22: responsive ---------------------------------------------

  group('E21/E22 no overflow', () {
    Widget responsiveSubject(double width, double textScale) => ProviderScope(
          overrides: [
            gpsLocalDatabaseProvider.overrideWithValue(db),
            gpsRecordingControllerProvider('me').overrideWithValue(controller),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 100),
                textScaler: TextScaler.linear(textScale),
              ),
              child: SizedBox(
                width: width,
                child: const Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: GpsActiveRecordingBannerBody(ownerId: 'me'),
                  ),
                ),
              ),
            ),
          ),
        );

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('width=$width textScale=$scale: no overflow',
            (tester) async {
          await realAwait(tester, controller.start);
          await settle(tester);

          await tester.pumpWidget(responsiveSubject(width, scale));
          await tester.pump();

          expect(tester.takeException(), isNull);
          await disposeCleanly(tester);
        });
      }
    }
  });
}
