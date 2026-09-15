import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database_provider.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

/// GPS-4B1 regression coverage for `gpsRecordingControllerProvider`'s
/// ownership/lifetime change (`Provider.autoDispose.family` ->
/// `Provider.family`). These tests exercise the actual Riverpod provider,
/// not just the plain `GpsRecordingController` class already covered by
/// `gps_recording_controller_test.dart` — that file intentionally
/// constructs the class directly and never touches Riverpod at all, so it
/// cannot catch a provider-lifetime regression like the one this phase
/// fixes.
///
/// None of these tests call `start()`/`resume()`/anything that reaches
/// `LocationSource` — the production provider wires the real
/// `GeolocatorLocationSource`, which has no platform-channel mock in
/// `flutter test`. An active recording is instead *represented* by writing
/// directly to the local database (exactly like the existing
/// restart/crash-recovery tests in gps_recording_controller_test.dart do),
/// which a fresh controller picks up via its own construction-time
/// `_detectRecoverableRecording()` — no GPS dependency required.
void main() {
  late GpsLocalDatabase db;

  setUp(() {
    db = GpsLocalDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('provider ownership (GPS-4B1)', () {
    test(
        'TEST A -- the same ownerId resolves to the same controller '
        'instance within one container, across repeated reads', () {
      final container = makeContainer();

      final first = container.read(gpsRecordingControllerProvider('me'));
      final second = container.read(gpsRecordingControllerProvider('me'));
      final third = container.read(gpsRecordingControllerProvider('me'));

      expect(identical(first, second), isTrue);
      expect(identical(first, third), isTrue);
    });

    test(
        'TEST C -- different owners resolve to different controller '
        'instances with no shared state', () async {
      final container = makeContainer();
      await db.createLocalRecordedRoute(
          id: 'r-a', ownerId: 'accountA', startedAt: DateTime.utc(2026, 1, 1));

      final controllerA =
          container.read(gpsRecordingControllerProvider('accountA'));
      final controllerB =
          container.read(gpsRecordingControllerProvider('accountB'));
      await pumpEventQueue();

      expect(identical(controllerA, controllerB), isFalse);
      // account B must never see account A's recoverable route.
      expect(controllerB.state.status, GpsRecordingStatus.idle);
      expect(controllerA.state.status, GpsRecordingStatus.recoverable);
      expect(controllerA.state.routeId, 'r-a');
    });

    test('TEST D -- disposing the ProviderContainer disposes the controller',
        () {
      final container = ProviderContainer(
        overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)],
      );

      final controller = container.read(gpsRecordingControllerProvider('me'));
      expect(controller.isDisposed, isFalse);

      container.dispose();

      expect(controller.isDisposed, isTrue,
          reason: 'ref.onDispose must still run controller.dispose() at '
              'container teardown even though the provider is no longer '
              'autoDispose');
    });

    testWidgets(
        'TEST B -- navigating away from and back to the GPS screen does not '
        'recreate the controller, even while representing an active '
        'recording', (tester) async {
      await db.createLocalRecordedRoute(
          id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));

      GpsRecordingController? firstSeen;
      GpsRecordingController? secondSeen;

      Widget appWith(Widget home) => ProviderScope(
            overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)],
            child: MaterialApp(home: home),
          );

      // Mount a "GPS screen" that watches the controller provider --
      // mirrors GpsRecordingDebugScreen's own ref.watch usage.
      await tester.pumpWidget(appWith(Consumer(
        builder: (context, ref, _) {
          firstSeen = ref.watch(gpsRecordingControllerProvider('me'));
          return const SizedBox();
        },
      )));
      await tester.pump();
      expect(firstSeen, isNotNull);
      expect(firstSeen!.state.status, GpsRecordingStatus.recoverable);

      // "Navigate away": mount a screen that never watches the GPS
      // provider at all, same as Map/Explore/Profile/Settings today.
      await tester.pumpWidget(appWith(const SizedBox()));
      await tester.pump();

      // "Navigate back" to a GPS-watching screen.
      await tester.pumpWidget(appWith(Consumer(
        builder: (context, ref, _) {
          secondSeen = ref.watch(gpsRecordingControllerProvider('me'));
          return const SizedBox();
        },
      )));
      await tester.pump();

      expect(identical(firstSeen, secondSeen), isTrue,
          reason: 'the recording must not belong to any one screen');
      expect(secondSeen!.isDisposed, isFalse);
      expect(secondSeen!.state.status, GpsRecordingStatus.recoverable,
          reason: 'the represented recording must still be there, not reset');
      expect(secondSeen!.state.routeId, 'r1');
    });
  });
}
