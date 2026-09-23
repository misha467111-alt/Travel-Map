import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database_provider.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_controls.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_header.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_map_screen.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_status_card.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';
import 'package:flutter_application_1/features/gps/sync/domain/gps_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/gps_sync_coordinator.dart';
import 'package:flutter_application_1/features/map/providers/map_provider.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

/// Never actually invoked by these tests (none tap "Повторити" / trigger
/// an automatic pass -- every [GpsSyncCoordinator] here is constructed
/// with `autoSyncOnInit: false`); throwing loudly on any use catches a
/// test accidentally exercising a real sync path instead of silently
/// succeeding against a fake network.
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
    // db.close() goes through GpsLocalDatabase's real (isolate-backed)
    // NativeDatabase executor -- see settle()'s own doc comment just below
    // for why that needs runAsync under testWidgets(). tearDown() has no
    // WidgetTester of its own, so this uses the binding directly, exactly
    // equivalent to WidgetTester.runAsync.
    await TestWidgetsFlutterBinding.instance.runAsync(() => db.close());
    await source.dispose();
  });

  /// Flushes microtasks and advances the fake clock by a zero duration.
  /// Deliberately `tester.pump(Duration.zero)`, not a bare `tester.pump()`:
  /// a bare `pump()` never calls `elapse()` on the fake-async zone at all,
  /// so it does not fire even an *already-pending* zero-duration `Timer`
  /// (confirmed empirically: disposing a mounted `GpsRecordingMapBody`
  /// makes Drift's `StreamQueryStore.markAsClosed` schedule exactly such a
  /// timer, and a bare `pump()` left it dangling, tripping
  /// `AutomatedTestWidgetsFlutterBinding`'s own end-of-test
  /// `!timersPending` invariant). `pump(Duration.zero)` still stays
  /// entirely inside the fake zone (unlike `realAwait`/`runAsync` below),
  /// so it does not risk the `GoogleMap` platform-view side effect
  /// documented on `realAwait`. This still cannot substitute for
  /// `pumpEventQueue()`'s real-time `Future.delayed` under plain `test()`,
  /// nor for `realAwait` where genuinely real (isolate-backed) work needs
  /// to complete.
  Future<void> settle(WidgetTester tester) => tester.pump(Duration.zero);

  /// `GpsLocalDatabase`'s real `NativeDatabase` executor does work that
  /// never completes on its own inside `testWidgets()`'s fake-clock zone
  /// -- confirmed empirically while building this file (a direct
  /// `await db.<query>(...)` call, and likewise a direct
  /// `await controller.start()`, hung indefinitely until stepped outside
  /// the fake zone). `tester.runAsync` is the correct, documented escape
  /// for exactly this. Kept to a single, narrow call per use (never
  /// reused as a general-purpose "settle" called many times across one
  /// test) and, where possible, invoked before any `ClusteredLocationMap`/
  /// `GoogleMap` is mounted -- repeated/interleaved `runAsync` escapes
  /// while a real `GoogleMap` is live were observed to eventually let a
  /// real frame reach `RenderAndroidView._sizePlatformView`, which then
  /// throws `MissingPluginException` (there is no platform-view channel
  /// mock in a plain `flutter test` run). A single, isolated `runAsync`
  /// call with a live `GoogleMap` already mounted (see D03/D06/D07/D08/
  /// D09-D12 below) does not trigger that.
  Future<T?> realAwait<T>(WidgetTester tester, Future<T> Function() action) =>
      tester.runAsync(action);

  /// Must be the last thing any test does once it has mounted a
  /// `GpsRecordingMapBody` for a route with an id (i.e. `_LiveTrackMap`
  /// watched `gpsRoutePointsProvider`, and/or `gpsRouteSyncStateProvider`
  /// was watched): `flutter_test` unmounts whatever is still pumped
  /// *after* the test body returns, entirely outside this file's control,
  /// and that automatic teardown does not itself flush the same
  /// zero-duration Drift cleanup `Timer` `settle()` documents above --
  /// only `AutomatedTestWidgetsFlutterBinding`'s own end-of-test
  /// `!timersPending` invariant sees it, and fails the test. Disposing
  /// deterministically here, while this test body still controls pumping,
  /// and then flushing with `settle()`, avoids ever reaching that
  /// automatic path with a live stream still attached.
  Future<void> disposeCleanly(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await settle(tester);
    }
  }

  /// Polls a real query (never a fixed real-time delay -- see the
  /// D08/D09 comments on why an explicit `Future.delayed` inside
  /// `runAsync` risks `MissingPluginException` once a live `GoogleMap` is
  /// mounted) until [check] is satisfied or the attempt budget runs out.
  ///
  /// Each attempt is its own, separate `runAsync` call, with a plain
  /// `tester.pump()` in between -- deliberately NOT one continuous loop
  /// inside a single `runAsync` callback. A tap's fire-and-forget async
  /// chain (e.g. `controller.discard()`) is *created* in the fake-clock
  /// zone; empirically, its pending continuation only actually advances
  /// when control returns to that zone via a real `pump()` -- a second
  /// real query issued back-to-back inside the same `runAsync` callback,
  /// with no intervening fake-zone pump, was observed to hang forever
  /// (the first query resolved and printed the still-stale value; a
  /// second one right after it, still inside that same callback, never
  /// even printed). Exiting to `pump()` between attempts avoids that.
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

  Widget subject(GpsRecordingState state, {double? width, double? height}) {
    Widget body = GpsRecordingMapBody(
      ownerId: 'me',
      state: state,
      controller: controller,
      syncCoordinator: syncCoordinator,
    );
    if (width != null && height != null) {
      body = SizedBox(width: width, height: height, child: body);
    }
    return ProviderScope(
      // currentPositionProvider hits the real Geolocator plugin, which
      // has no platform-channel mock registered under `flutter test` --
      // left un-overridden, awaiting it hangs the test run indefinitely
      // instead of failing fast. Overridden here with an always-resolved
      // fake position so _LiveTrackMap's `ref.watch` settles immediately,
      // exactly like `currentPositionProvider` behaves on a real device.
      overrides: [
        gpsLocalDatabaseProvider.overrideWithValue(db),
        currentPositionProvider.overrideWith((ref) async => testPosition()),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: body),
    );
  }

  GoogleMap map(WidgetTester tester) => tester.widget<GoogleMap>(
        find.descendant(
          of: find.byKey(const Key('gps_recording_map')),
          matching: find.byType(GoogleMap),
        ),
      );

  group('D03 no duplicate recording on open', () {
    testWidgets('mounting the screen with an idle state never auto-starts',
        (tester) async {
      await tester.pumpWidget(subject(GpsRecordingState.idle));
      await tester.pump();
      await settle(tester);

      expect(controller.state.status, GpsRecordingStatus.idle);
      expect(source.subscribeCallCount, 0);
      final recoverable =
          await tester.runAsync(() => db.getRecoverableRecording('me'));
      expect(recoverable, isNull);
    });
  });

  group('D04 explicit start', () {
    testWidgets(
        '"Почати запис" is wired directly to controller.start -- exactly '
        'once, never wrapped or duplicated', (tester) async {
      await tester.pumpWidget(subject(GpsRecordingState.idle));
      await tester.pump();

      // Asserts the exact wiring rather than tapping-and-waiting: Dart
      // guarantees two tear-offs of the same method off the same receiver
      // compare equal, so this proves GpsStartView's onStart is *exactly*
      // controller.start (not a closure that could call it twice, log it,
      // or call something else) without needing a real GPS-permission
      // round-trip through the actual button tap. D05-D09 already prove
      // controller.start() itself, called directly, really does reach
      // `recording` -- this test isolates the *wiring*.
      final button = tester
          .widget<FilledButton>(find.byKey(const Key('gps_start_button')));
      expect(button.onPressed, equals(controller.start));
    });
  });

  group('D05 active-session re-entry', () {
    testWidgets(
        'mounting the body with an existing session never creates a '
        'second route or re-subscribes the position stream', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      expect(source.subscribeCallCount, 1);
      final routeId = controller.state.routeId!;

      await tester.pumpWidget(subject(controller.state));
      await tester.pump();
      // "Leave": mount something that doesn't reference the recording at
      // all. Disposes the previous ProviderScope's gpsRoutePointsProvider
      // stream subscription, which schedules a zero-duration cleanup
      // Timer (see settle()'s own doc comment) -- settle(), not a bare
      // pump(), is required right after to flush it.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await settle(tester);
      // "Re-enter" the same Map action.
      await tester.pumpWidget(subject(controller.state));
      await tester.pump();

      expect(source.subscribeCallCount, 1,
          reason: 'no second start()/subscribe from merely re-mounting the '
              'screen over an existing session');
      final active =
          await tester.runAsync(() => db.getRecoverableRecording('me'));
      expect(active?.id, routeId,
          reason: 'the one-active-recording invariant holds: still exactly '
              'the same route, not a second one');
      await disposeCleanly(tester);
    });
  });

  group('D06/D07 back/minimize never discards', () {
    // Deliberately no real Navigator.push/pop here: GpsRecordingMapBody's
    // onBack is exactly `() => Navigator.of(context).maybePop()` (see its
    // own doc comment), and MaterialApp already supplies a root Navigator
    // with nothing to pop, so tapping back exercises that *exact* callback
    // -- maybePop() simply returns false/no-ops -- without needing a
    // second pushed route. A real push+pop was tried first; popping a
    // route that owns an active gpsRoutePointsProvider/
    // gpsRouteSyncStateProvider watch interacts with Riverpod's
    // `.autoDispose` scheduling and Drift's own cleanup Timer in a way
    // that never reliably drained within a bounded number of test pumps.
    // This simpler mount avoids that entirely while still proving the one
    // thing that actually matters: tapping back never reaches
    // controller.discard()/finish().
    Future<void> tapBack(WidgetTester tester) async {
      await tester.pumpWidget(subject(controller.state));
      await tester.pump();
      await settle(tester);

      await tester.tap(find.byKey(const Key('gps_recording_back_button')));
      // Bounded pumps, not pumpAndSettle(): while status is `recording`,
      // GpsRecordingStats runs a real repeating 1-second Timer (the
      // elapsed-time ticker) that never itself settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('D06 back while recording does not discard', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      final routeId = controller.state.routeId!;

      await tapBack(tester);

      expect(controller.state.status, GpsRecordingStatus.recording,
          reason: 'the recording must still be running after back');
      final route = await tester
          .runAsync(() => db.getRecordedRoute(ownerId: 'me', id: routeId));
      expect(route!.status, RecordedRouteStatus.recording);
      await disposeCleanly(tester);
    });

    testWidgets('D07 back while paused does not discard', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      await realAwait(tester, controller.pause);
      await settle(tester);
      final routeId = controller.state.routeId!;

      await tapBack(tester);

      expect(controller.state.status, GpsRecordingStatus.paused,
          reason: 'the paused recording must still exist after back');
      final route = await tester
          .runAsync(() => db.getRecordedRoute(ownerId: 'me', id: routeId));
      expect(route!.status, RecordedRouteStatus.paused);
      await disposeCleanly(tester);
    });
  });

  group('D08 discard still requires confirmation', () {
    testWidgets(
        'discard from the recording map screen is blocked until the '
        'shared confirmation dialog is confirmed', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      final routeId = controller.state.routeId!;

      await tester.pumpWidget(subject(controller.state));
      await tester.pump();

      // Bounded pumps, not pumpAndSettle() -- see pushBodyAndTapBack's own
      // comment above: the recording-status elapsed-time ticker never
      // lets pumpAndSettle() reach quiescence.
      await tester.tap(find.byKey(const Key('gps_recording_discard_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.byKey(const Key('gps_discard_confirm_button')), findsOneWidget);
      expect(controller.state.status, GpsRecordingStatus.recording,
          reason: 'must not discard before the dialog is confirmed');

      await tester.tap(find.byKey(const Key('gps_discard_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The confirmed tap fires controller.discard() -- a real DB write --
      // as a fire-and-forget call from the button's onPressed. waitUntil
      // polls (no artificial real-time delay -- see its own doc comment)
      // until the DB actually reflects the discard.
      await waitUntil(tester, () async {
        final route = await db.getRecordedRoute(ownerId: 'me', id: routeId);
        return route?.status == RecordedRouteStatus.discarded;
      });
      await settle(tester);

      expect(controller.state.status, GpsRecordingStatus.idle);
      final route = await tester
          .runAsync(() => db.getRecordedRoute(ownerId: 'me', id: routeId));
      expect(route!.status, RecordedRouteStatus.discarded);
      await disposeCleanly(tester);
    });
  });

  group('D09-D12 live polyline: real, ordered, no synthetic points, offline',
      () {
    // This entire group runs against an in-memory Drift database, with no
    // Supabase client, no NetworkStatus/isOnlineProvider override, and no
    // network of any kind reachable from the test process -- the live
    // track updating correctly here is itself the proof it needs no
    // connectivity (D12).
    testWidgets(
        'starts empty, then grows in exact recorded order as real points '
        'are accepted -- with no re-mount of the parent widget required',
        (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);

      await tester.pumpWidget(subject(controller.state));
      await tester.pump();
      await settle(tester);
      await tester.pump();

      expect(map(tester).polylines, isEmpty,
          reason: 'no points yet -- no fake/placeholder polyline');

      final routeId = controller.state.routeId!;

      source.emitPosition(testPosition(
        latitude: 50.40,
        longitude: 30.50,
        timestamp: DateTime.utc(2026, 1, 1, 10, 0, 0),
      ));
      // waitUntil polls real queries (no artificial real-time delay -- see
      // its own doc comment) until the write actually lands.
      await waitUntil(tester, () async {
        final points =
            await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
        return points.isNotEmpty;
      });
      await tester.pump();

      var track = map(tester).polylines.single;
      expect(track.points, const [LatLng(50.40, 30.50)]);

      source.emitPosition(testPosition(
        latitude: 50.401,
        longitude: 30.501,
        timestamp: DateTime.utc(2026, 1, 1, 10, 0, 5),
      ));
      await waitUntil(tester, () async {
        final points =
            await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
        return points.length >= 2;
      });
      await tester.pump();

      track = map(tester).polylines.single;
      expect(
        track.points,
        const [LatLng(50.40, 30.50), LatLng(50.401, 30.501)],
        reason: 'oldest-first, exactly matching real acceptance order -- '
            'the parent GpsRecordingMapBody was never re-pumped with a new '
            '`state`, proving the polyline updates via its own isolated '
            'gpsRoutePointsProvider subscription, not a whole-screen '
            'rebuild',
      );

      // Matches the real, persisted local data -- never a synthetic point.
      final persisted = await tester.runAsync(() => db.getRoutePoints(
          ownerId: 'me', recordedRouteId: controller.state.routeId!));
      expect(persisted!.map((p) => LatLng(p.latitude, p.longitude)).toList(),
          track.points);
      await disposeCleanly(tester);
    });

    testWidgets('a malformed/rejected sample never reaches the live track',
        (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      await tester.pumpWidget(subject(controller.state));
      await tester.pump();
      await settle(tester);
      await tester.pump();

      source.emitPosition(testPosition(latitude: double.nan));
      // No runAsync/real wait needed here: validateGpsSample rejects a
      // NaN coordinate synchronously, before any DB call is ever reached
      // (see gps_recording_controller.dart's _onPosition), so there is no
      // pending real (isolate-backed) write to wait for -- a plain
      // in-fake-zone settle() is enough to flush the rejection.
      await settle(tester);
      await tester.pump();

      expect(map(tester).polylines, isEmpty,
          reason: 'validateGpsSample already rejects this sample -- the '
              'live track must never show a point that was never accepted');
      await disposeCleanly(tester);
    });
  });

  group('D13/D14 camera policy is preserved across live updates', () {
    testWidgets(
        'the map keeps the same Element across every polyline update, so '
        'InitialGpsCameraPolicy\'s one-shot latch and the native view are '
        'never recreated by a later point', (tester) async {
      await realAwait(tester, controller.start);
      await settle(tester);
      await tester.pumpWidget(subject(controller.state));
      await tester.pump();
      await settle(tester);
      await tester.pump();

      final firstElement =
          tester.element(find.byKey(const Key('gps_recording_map')));
      final routeId = controller.state.routeId!;

      for (var i = 0; i < 3; i++) {
        final expectedCount = i + 1;
        source.emitPosition(testPosition(
          latitude: 50.40 + i * 0.001,
          timestamp: DateTime.utc(2026, 1, 1, 10, 0, i),
        ));
        // waitUntil polls real queries (no real-time delay -- see its own
        // doc comment and D08/D09's) until the write actually lands.
        await waitUntil(tester, () async {
          final points =
              await db.getRoutePoints(ownerId: 'me', recordedRouteId: routeId);
          return points.length >= expectedCount;
        });
        await tester.pump();
      }

      final laterElement =
          tester.element(find.byKey(const Key('gps_recording_map')));
      expect(identical(firstElement, laterElement), isTrue,
          reason: 'later GPS points must never "steal"/reset the camera by '
              'recreating the map widget\'s State');
      await disposeCleanly(tester);
    });
  });

  group('D15 reuses the exact Phase 4C contract, no redesign', () {
    testWidgets('recording status renders the real 4C header/status/controls',
        (tester) async {
      // routeId deliberately null: this test is pure widget-composition
      // (does the recording status render the real 4C header/status/
      // controls?), so it never needs an actual route at all. A non-null
      // synthetic routeId that was never created via controller.start()
      // was tried first -- it makes GpsRecordingMapBody watch
      // gpsRoutePointsProvider/gpsRouteSyncStateProvider's real Drift
      // `.watch()` streams for a route that will never exist, and those
      // streams' first-emission setup never gets a single real event-loop
      // turn anywhere else in this test, which left a cleanup Timer
      // un-flushable at disposal no matter how many settle()/runAsync
      // calls were added around it. With routeId: null, GpsRecordingMapBody
      // never watches either provider at all (see its own `if (routeId !=
      // null)` guards), matching exactly how D03/D04's idle state (also
      // routeId: null) never hits this either.
      await tester.pumpWidget(subject(const GpsRecordingState(
        status: GpsRecordingStatus.recording,
        routeId: null,
        pointCount: 3,
      )));
      await tester.pump();

      expect(find.byType(GpsRecordingHeader), findsOneWidget);
      expect(find.byType(GpsRecordingStatusCard), findsOneWidget);
      expect(find.byType(GpsRecordingControls), findsOneWidget);
      expect(
          find.byKey(const Key('gps_recording_pause_button')), findsOneWidget);
      expect(find.byKey(const Key('gps_recording_discard_button')),
          findsOneWidget);
      await disposeCleanly(tester);
    });
  });

  group('D19/D20 no overflow with the real map + overlay layout', () {
    Widget responsiveSubject(
      double width,
      double textScale,
      GpsRecordingState state,
    ) =>
        ProviderScope(
          overrides: [
            gpsLocalDatabaseProvider.overrideWithValue(db),
            currentPositionProvider.overrideWith((ref) async => testPosition()),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 760),
                textScaler: TextScaler.linear(textScale),
              ),
              child: SizedBox(
                width: width,
                height: 760,
                child: GpsRecordingMapBody(
                  ownerId: 'me',
                  state: state,
                  controller: controller,
                  syncCoordinator: syncCoordinator,
                ),
              ),
            ),
          ),
        );

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets(
            'width=$width textScale=$scale: recording overlay renders with '
            'no overflow', (tester) async {
          // routeId deliberately null -- see D15's own comment on why: a
          // synthetic routeId that was never created via controller.start()
          // leaves gpsRoutePointsProvider/gpsRouteSyncStateProvider's Drift
          // `.watch()` streams unable to cleanly flush their disposal
          // Timer, and this group runs 9 variations of it.
          await tester.pumpWidget(responsiveSubject(
            width,
            scale,
            const GpsRecordingState(
              status: GpsRecordingStatus.recording,
              routeId: null,
              pointCount: 42,
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await disposeCleanly(tester);
        });
      }
    }
  });
}
