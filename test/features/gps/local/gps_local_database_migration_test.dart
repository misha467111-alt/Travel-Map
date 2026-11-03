import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_service.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_storage.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

/// Journey Phase 1H-B: the local Drift v1 -> v2 upgrade (adds
/// `local_journey_media`). A genuine v1 database is simulated on a real
/// SQLite file: build the current schema, DROP the new table and reset
/// `user_version` to 1 -- exactly the shape a v1 install has -- then reopen
/// with the current class so Drift runs `onUpgrade(1, 3)`.
///
/// Journey Phase 1H-E2B: v2 -> v3 adds only the partial
/// `local_journey_media_actionable_idx` (see the M01 tests), simulated the
/// same way: DROP that index and reset `user_version` to 2.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 1, 1, 10);
  late Directory dir;
  late File dbFile;

  GpsLocalDatabase open() =>
      GpsLocalDatabase.forTesting(NativeDatabase(dbFile));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gps_migration_test_');
    dbFile = File('${dir.path}/gps_local.sqlite');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<int> userVersion(GpsLocalDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .first as int;

  Future<List<String>> mediaSchemaObjects(GpsLocalDatabase db) async =>
      (await db
              .customSelect("SELECT name FROM sqlite_master WHERE name LIKE "
                  "'local_journey_media%' ORDER BY name")
              .get())
          .map((r) => r.read<String>('name'))
          .toList();

  /// A v1-shaped database holding real route/point/event/waypoint rows.
  Future<void> seedV1() async {
    final db = open();
    await db.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', title: 'Old trip', startedAt: t0);
    await db.appendRoutePoint(
        ownerId: 'me',
        recordedRouteId: 'r1',
        latitude: 50,
        longitude: 30,
        recordedAt: t0);
    await db.addWaypoint(
        id: 'm1',
        ownerId: 'me',
        recordedRouteId: 'r1',
        waypointType: 'custom',
        title: 'Spot',
        latitude: 50,
        longitude: 30,
        recordedAt: t0);
    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: t0.add(const Duration(minutes: 5)));
    await db.customStatement('DROP TABLE local_journey_media');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();
  }

  test('A fresh installs are created at schema v3 with the media table',
      () async {
    final db = open();
    addTearDown(db.close);

    expect(db.schemaVersion, 3);
    expect(await userVersion(db), 3);
    expect(await mediaSchemaObjects(db), [
      'local_journey_media',
      'local_journey_media_actionable_idx',
      'local_journey_media_route_idx',
      'local_journey_media_waypoint_idx',
    ]);
  });

  test(
      'A a v1 database upgrades: data survives, media table and indexes '
      'appear', () async {
    await seedV1();

    final db = open();
    addTearDown(db.close);

    expect(await userVersion(db), 3);
    expect(await mediaSchemaObjects(db), [
      'local_journey_media',
      'local_journey_media_actionable_idx',
      'local_journey_media_route_idx',
      'local_journey_media_waypoint_idx',
    ]);
    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.title, 'Old trip');
    expect(route.status, RecordedRouteStatus.completed);
    expect(await db.getRoutePoints(ownerId: 'me', recordedRouteId: 'r1'),
        hasLength(1));
    expect(
        (await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1'))
            .single
            .title,
        'Spot');
    expect(
        (await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1')).length,
        2);
    expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
        isEmpty);
  });

  test('A the upgraded database accepts media for pre-existing data', () async {
    await seedV1();
    final db = open();
    addTearDown(db.close);

    // The v1 Journey r1 is completed (immutable for media); a new active
    // Journey in the upgraded database accepts media.
    await db.createLocalRecordedRoute(id: 'r2', ownerId: 'me', startedAt: t0);
    await db.addWaypoint(
        id: 'm2',
        ownerId: 'me',
        recordedRouteId: 'r2',
        waypointType: 'custom',
        latitude: 50,
        longitude: 30,
        recordedAt: t0);
    final item = await db.insertJourneyMedia(
      id: 'x1',
      ownerId: 'me',
      recordedRouteId: 'r2',
      waypointId: 'm2',
      capturedAt: t0,
      localRelativePath: 'journey_media/r2/x1.jpg',
    );

    expect(item.syncStatus, JourneyMediaSyncStatus.pending);
    expect(item.waypointId, 'm2');
    await expectLater(
        db.insertJourneyMedia(
            id: 'x2',
            ownerId: 'me',
            recordedRouteId: 'r1',
            capturedAt: t0,
            localRelativePath: 'journey_media/r1/x2.jpg'),
        throwsA(isA<JourneyMediaRouteNotActiveException>()),
        reason: 'a pre-existing completed Journey stays closed to media');
  });

  test('A the migration is deterministic and idempotent across reopenings',
      () async {
    await seedV1();
    final first = open();
    final firstObjects = await mediaSchemaObjects(first);
    await first.createLocalRecordedRoute(
        id: 'r2', ownerId: 'me', startedAt: t0);
    await first.insertJourneyMedia(
        id: 'x1',
        ownerId: 'me',
        recordedRouteId: 'r2',
        capturedAt: t0,
        localRelativePath: 'journey_media/r2/x1.jpg');
    await first.close();

    final second = open();
    addTearDown(second.close);

    expect(await userVersion(second), 3);
    expect(await mediaSchemaObjects(second), firstObjects);
    expect(
        (await second.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r2'))
            .single
            .id,
        'x1',
        reason: 'reopening at v3 must not re-run or clear anything');
  });

  // -------------------------------------------------------------------
  // M01 -- Journey Phase 1H-E2B: v2 -> v3 adds ONLY the partial
  // `local_journey_media_actionable_idx`.
  // -------------------------------------------------------------------

  const actionableIdx = 'local_journey_media_actionable_idx';

  Future<int> actionableIndexCount(GpsLocalDatabase db) async => (await db
          .customSelect("SELECT count(*) AS n FROM sqlite_master "
              "WHERE type = 'index' AND name = '$actionableIdx'")
          .getSingle())
      .read<int>('n');

  /// A genuine v2 database (Phases 1H-B..1H-E1): today's schema minus the v3
  /// index, `user_version = 2`, holding route/point/event/waypoint rows and
  /// media in several sync states.
  Future<void> seedV2() async {
    final db = open();
    await db.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', title: 'V2 trip', startedAt: t0);
    await db.appendRoutePoint(
        ownerId: 'me',
        recordedRouteId: 'r1',
        latitude: 50,
        longitude: 30,
        recordedAt: t0);
    await db.addWaypoint(
        id: 'm1',
        ownerId: 'me',
        recordedRouteId: 'r1',
        waypointType: 'custom',
        latitude: 50,
        longitude: 30,
        recordedAt: t0);
    for (final id in ['x1', 'x2', 'x3']) {
      await db.insertJourneyMedia(
          id: id,
          ownerId: 'me',
          recordedRouteId: 'r1',
          capturedAt: t0,
          localRelativePath: 'journey_media/r1/$id.jpg');
    }
    await db.customStatement(
        "UPDATE local_journey_media SET sync_status = 'failed' WHERE id = 'x2'");
    await db.customStatement(
        "UPDATE local_journey_media SET sync_status = 'synced' WHERE id = 'x3'");
    await db.finishRecordingLocally(
        ownerId: 'me',
        routeId: 'r1',
        occurredAt: t0.add(const Duration(minutes: 5)));
    await db.recordRouteSyncOutcome(
        ownerId: 'me', routeId: 'r1', syncStatus: RouteSyncStatus.synced);
    await db.customStatement('DROP INDEX $actionableIdx');
    await db.customStatement('PRAGMA user_version = 2');
    await db.close();
  }

  test(
      'M01 a v2 database upgrades to v3: additive, every row preserved, the '
      'partial index created exactly once', () async {
    await seedV2();

    final db = open();
    addTearDown(db.close);

    expect(await userVersion(db), 3);
    expect(await actionableIndexCount(db), 1);
    final sql = (await db
            .customSelect(
                "SELECT sql FROM sqlite_master WHERE name = '$actionableIdx'")
            .getSingle())
        .read<String>('sql');
    expect(sql, contains('(owner_id, recorded_route_id)'));
    expect(sql, contains("WHERE sync_status = 'pending'"));
    expect(sql, isNot(contains('pendingDelete')));

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route!.title, 'V2 trip');
    expect(route.status, RecordedRouteStatus.completed);
    expect(route.syncStatus, RouteSyncStatus.synced);
    expect(await db.getRoutePoints(ownerId: 'me', recordedRouteId: 'r1'),
        hasLength(1));
    expect(
        (await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1')).single.id,
        'm1');
    expect(
        (await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1')).length,
        2);
    final media =
        await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1');
    expect({
      for (final m in media) m.id: m.syncStatus
    }, {
      'x1': JourneyMediaSyncStatus.pending,
      'x2': JourneyMediaSyncStatus.failed,
      'x3': JourneyMediaSyncStatus.synced,
    });
    expect(await db.getRouteIdsWithActionableMedia(ownerId: 'me'), ['r1']);
  });

  test('M01 fresh install at v3 has the index once; reopening is safe',
      () async {
    final first = open();
    expect(await userVersion(first), 3);
    expect(await actionableIndexCount(first), 1);
    await first.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', startedAt: t0);
    await first.insertJourneyMedia(
        id: 'x1',
        ownerId: 'me',
        recordedRouteId: 'r1',
        capturedAt: t0,
        localRelativePath: 'journey_media/r1/x1.jpg');
    await first.close();

    final second = open();
    addTearDown(second.close);
    expect(await userVersion(second), 3);
    expect(await actionableIndexCount(second), 1);
    expect(
        (await second.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'))
            .single
            .id,
        'x1');
  });

  test('M01 an upgraded v3 database reopens without re-running the step',
      () async {
    await seedV2();
    final first = open();
    expect(await actionableIndexCount(first), 1);
    await first.close();

    final second = open();
    addTearDown(second.close);
    expect(await userVersion(second), 3);
    expect(await actionableIndexCount(second), 1);
    expect(await second.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
        hasLength(3));
  });

  test('I media metadata and its file survive reopening the database',
      () async {
    final root = Directory('${dir.path}/documents')..createSync();
    final storage = JourneyMediaStorage(rootDirectory: () async => root);
    final image = img.Image(width: 20, height: 20, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(1, 2, 3));

    final first = open();
    await first.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', startedAt: t0);
    final item = await JourneyMediaService(db: first, storage: storage)
        .addImageBytes(
            ownerId: 'me',
            recordedRouteId: 'r1',
            sourceBytes: Uint8List.fromList(img.encodeJpg(image)),
            capturedAt: t0);
    await first.close();

    final second = open();
    addTearDown(second.close);
    final rows =
        await second.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1');

    expect(rows.single.id, item.id);
    expect(rows.single.capturedAt, t0);
    expect(rows.single.localRelativePath, item.localRelativePath);
    expect(
        await storage.existingFile(rows.single.localRelativePath), isNotNull);
  });
}
