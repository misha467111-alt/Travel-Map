import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_summary.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 1, 1, 10);
  late GpsLocalDatabase db;

  setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Creates a route in the requested lifecycle state. [endMin] is the
  /// minute (after [t0]) at which it finishes/discards.
  Future<void> route(
    String id, {
    String owner = 'me',
    String state = RecordedRouteStatus.completed,
    int startMin = 0,
    int endMin = 10,
  }) async {
    final start = t0.add(Duration(minutes: startMin));
    final end = t0.add(Duration(minutes: endMin));
    await db.createLocalRecordedRoute(id: id, ownerId: owner, startedAt: start);
    switch (state) {
      case RecordedRouteStatus.completed:
        await db.finishRecordingLocally(
            ownerId: owner, routeId: id, occurredAt: end);
      case RecordedRouteStatus.discarded:
        await db.discardRecording(ownerId: owner, routeId: id, occurredAt: end);
      case RecordedRouteStatus.paused:
        await db.pauseRecording(ownerId: owner, routeId: id, occurredAt: end);
    }
  }

  Future<List<String>> ids([String owner = 'me']) async =>
      (await db.getCompletedRoutes(owner)).map((r) => r.id).toList();

  test('H01 a completed Journey appears; H14 empty History is empty', () async {
    expect(await ids(), isEmpty);

    await route('a');

    expect(await ids(), ['a']);
  });

  test('H02/H03/H04 recording, paused and discarded Journeys are excluded',
      () async {
    await route('rec', owner: 'o1', state: RecordedRouteStatus.recording);
    await route('pau', owner: 'o2', state: RecordedRouteStatus.paused);
    await route('dis', owner: 'o3', state: RecordedRouteStatus.discarded);

    for (final owner in ['o1', 'o2', 'o3']) {
      expect(await ids(owner), isEmpty, reason: owner);
    }
  });

  test('H02 an active recording is excluded alongside completed ones',
      () async {
    await route('done', endMin: 5);
    await route('live', state: RecordedRouteStatus.recording, startMin: 10);

    expect(await ids(), ['done']);
  });

  test('H05 owner isolation', () async {
    await route('mine');
    await route('theirs', owner: 'other');

    expect(await ids('me'), ['mine']);
    expect(await ids('other'), ['theirs']);
    expect(await ids('nobody'), isEmpty);
  });

  test('H06 newest completed first (by completion time)', () async {
    // 'long' started first but finished last.
    await route('early', startMin: 0, endMin: 5);
    await route('long', startMin: 1, endMin: 90);
    await route('mid', startMin: 10, endMin: 30);

    expect(await ids(), ['long', 'mid', 'early']);
  });

  test('H07 identical completion times order deterministically by id',
      () async {
    for (final id in ['c', 'a', 'b']) {
      await route(id, endMin: 15);
    }

    expect(await ids(), ['a', 'b', 'c']);
    expect(await ids(), await ids(), reason: 'stable across reads');
  });

  test('H08/H09 unsynced, syncing, synced and failed Journeys all appear',
      () async {
    await route('ns', endMin: 1);
    await route('sy', endMin: 2);
    await route('ok', endMin: 3);
    await route('bad', endMin: 4);
    await db.markRouteSyncing(ownerId: 'me', routeId: 'sy');
    await db.recordRouteSyncOutcome(
        ownerId: 'me', routeId: 'ok', syncStatus: RouteSyncStatus.synced);
    await db.recordRouteSyncOutcome(
        ownerId: 'me', routeId: 'bad', syncStatus: RouteSyncStatus.failed);

    final byId = {
      for (final r in await db.getCompletedRoutes('me')) r.id: r.syncStatus
    };

    expect(byId, {
      'ns': RouteSyncStatus.notSynced,
      'sy': RouteSyncStatus.syncing,
      'ok': RouteSyncStatus.synced,
      'bad': RouteSyncStatus.failed,
    });
  });

  test('H10/H11 the watch stream reacts to completion and sync changes',
      () async {
    final emissions = <List<String>>[];
    final statuses = <String?>[];
    final sub = db.watchCompletedRoutes('me').listen((rows) {
      emissions.add(rows.map((r) => r.id).toList());
      statuses.add(rows.isEmpty ? null : rows.first.syncStatus);
    });
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emissions.last, isEmpty);

    await db.createLocalRecordedRoute(id: 'a', ownerId: 'me', startedAt: t0);
    await pumpEventQueue();
    expect(emissions.last, isEmpty, reason: 'still recording: not History');

    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'a',
        occurredAt: t0.add(const Duration(minutes: 5)));
    await pumpEventQueue();
    expect(emissions.last, ['a']);
    expect(statuses.last, RouteSyncStatus.notSynced);

    await db.recordRouteSyncOutcome(
        ownerId: 'me', routeId: 'a', syncStatus: RouteSyncStatus.synced);
    await pumpEventQueue();
    expect(statuses.last, RouteSyncStatus.synced);
  });

  test('H12/H13 Moment count and statistics come from the Summary loader',
      () async {
    await route('a');
    for (final id in ['m1', 'm2']) {
      await db.addWaypoint(
        id: id,
        ownerId: 'me',
        recordedRouteId: 'a',
        waypointType: 'custom',
        latitude: 50,
        longitude: 30,
        recordedAt: t0,
      );
    }

    final summary = (await loadGpsJourneySummary(
        db: db, ownerId: 'me', routeId: 'a', now: t0))!;

    expect(summary.momentCount, 2);
    expect(summary.statistics.elapsed, const Duration(minutes: 10));
  });

  test('H15/H16 History survives a new controller and is not recoverable',
      () async {
    final source = FakeLocationSource()
      ..permission = LocationPermission.whileInUse;
    addTearDown(source.dispose);
    final first = GpsRecordingController(
      ownerId: 'me',
      db: db,
      locationSource: source,
      notificationPermissionSource: FakeNotificationPermissionSource(),
    );
    await first.start();
    await pumpEventQueue();
    final routeId = first.state.routeId!;
    await first.finish();
    first.dismissCompleted();
    first.dispose();

    final second = GpsRecordingController(
      ownerId: 'me',
      db: db,
      locationSource: source,
      notificationPermissionSource: FakeNotificationPermissionSource(),
    );
    addTearDown(second.dispose);
    await pumpEventQueue();

    expect(await ids(), [routeId]);
    expect(second.state.status, GpsRecordingStatus.idle);
    expect(await db.getRecoverableRecording('me'), isNull);
  });

  test('H19/H20 a large History is stable, complete and uniquely keyed',
      () async {
    // Distinct owners are unnecessary: completed routes do not hit the
    // one-active-per-owner index.
    for (var i = 0; i < 150; i++) {
      await route('r${i.toString().padLeft(3, '0')}', endMin: i % 30);
    }

    final first = await ids();
    final second = await ids();

    expect(first, hasLength(150));
    expect(first.toSet(), hasLength(150), reason: 'route id is the identity');
    expect(second, first);
    final ended = (await db.getCompletedRoutes('me')).map((r) => r.endedAt!);
    expect(ended.toList(), [...ended]..sort((a, b) => b.compareTo(a)));
  });

  test('completed route immutability (Phase 1E guard) still holds', () async {
    await route('a');
    final appended = await db.appendRoutePoint(
        ownerId: 'me',
        recordedRouteId: 'a',
        latitude: 1,
        longitude: 1,
        recordedAt: t0);

    expect(appended, isFalse);
  });

  test('H17/H18 History sources have no fake data or network imports', () {
    const files = [
      'lib/features/gps/presentation/gps_journey_history_view.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      final imports = source
          .split('\n')
          .where((l) => l.startsWith('import '))
          .join('\n')
          .toLowerCase();
      for (final banned in ['supabase', 'sync/', 'http', 'connectivity']) {
        expect(imports, isNot(contains(banned)), reason: path);
      }
      expect(source, isNot(contains('distanceBetween')),
          reason: 'no second statistics implementation');
      for (final fake in ['demo', 'mock', 'sample journey']) {
        expect(source.toLowerCase(), isNot(contains(fake)), reason: path);
      }
    }
  });
}
