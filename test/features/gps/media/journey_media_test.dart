import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:image/image.dart' as img;
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_service.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_storage.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/map/domain/location_photo_normalizer.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

/// Fails the media insert while [failInsert] is set -- the only seam needed
/// to prove file cleanup when the database write fails.
class _FlakyMediaDb extends GpsLocalDatabase {
  _FlakyMediaDb(super.executor) : super.forTesting();
  bool failInsert = false;

  @override
  Future<LocalJourneyMediaItem> insertJourneyMedia({
    required String id,
    required String ownerId,
    required String recordedRouteId,
    String? waypointId,
    String mediaType = JourneyMediaType.image,
    required DateTime capturedAt,
    double? latitude,
    double? longitude,
    required String localRelativePath,
  }) {
    if (failInsert) return Future.error(StateError('disk full'));
    return super.insertJourneyMedia(
      id: id,
      ownerId: ownerId,
      recordedRouteId: recordedRouteId,
      waypointId: waypointId,
      mediaType: mediaType,
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
      localRelativePath: localRelativePath,
    );
  }
}

Uint8List _jpeg({int w = 40, int h = 30, bool gps = false, int? orientation}) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(200, 40, 40));
  if (gps) {
    image.exif.gpsIfd.setGpsLocation(latitude: 50.4501, longitude: 30.5234);
  }
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 1, 1, 10);
  late Directory root;
  late _FlakyMediaDb db;
  late JourneyMediaStorage storage;
  late JourneyMediaService service;
  var counter = 0;

  List<String> filesUnder(Directory dir) => dir.existsSync()
      ? dir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList()
      : <String>[];

  setUp(() async {
    counter = 0;
    root = await Directory.systemTemp.createTemp('journey_media_test_');
    db = _FlakyMediaDb(NativeDatabase.memory());
    storage = JourneyMediaStorage(rootDirectory: () async => root);
    service = JourneyMediaService(
      db: db,
      storage: storage,
      newMediaId: () => 'media-${++counter}',
      clock: () => t0,
    );
    await db.createLocalRecordedRoute(id: 'r1', ownerId: 'me', startedAt: t0);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> addMoment(String id,
      {String route = 'r1', String owner = 'me'}) async {
    await db.addWaypoint(
      id: id,
      ownerId: owner,
      recordedRouteId: route,
      waypointType: 'viewpoint',
      latitude: 50.1,
      longitude: 30.2,
      altitude: 111,
      recordedAt: t0,
    );
  }

  Future<LocalJourneyMediaItem> addImage({
    String owner = 'me',
    String route = 'r1',
    String? waypointId,
    double? lat,
    double? lng,
    DateTime? capturedAt,
  }) =>
      service.addImageBytes(
        ownerId: owner,
        recordedRouteId: route,
        sourceBytes: _jpeg(),
        waypointId: waypointId,
        latitude: lat,
        longitude: lng,
        capturedAt: capturedAt,
      );

  Future<void> setStatus(String id, String status) =>
      (db.update(db.localJourneyMedia)..where((t) => t.id.equals(id)))
          .write(LocalJourneyMediaCompanion(syncStatus: Value(status)));

  group('creation', () {
    test(
        'B standalone image: pending row, normalized app-owned file, '
        'relative path', () async {
      final item = await addImage(lat: 50.0, lng: 30.0);

      expect(item.id, 'media-1');
      expect(item.ownerId, 'me');
      expect(item.recordedRouteId, 'r1');
      expect(item.waypointId, isNull);
      expect(item.mediaType, JourneyMediaType.image);
      expect(item.syncStatus, JourneyMediaSyncStatus.pending);
      expect(item.latitude, 50.0);
      expect(item.capturedAt, t0);
      expect(item.localRelativePath, 'journey_media/r1/media-1.jpg');
      expect(item.localRelativePath, isNot(startsWith('/')));
      expect(item.localRelativePath, isNot(contains(root.path)));
      expect(item.localRelativePath, isNot(contains(r'\')));
      final file = await storage.existingFile(item.localRelativePath);
      expect(file, isNotNull);
      expect(file!.path.startsWith(root.path), isTrue);
      expect(img.decodeJpg(await file.readAsBytes()), isNotNull);
      expect(
          (await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'))
              .single
              .id,
          'media-1');
    });

    test(
        'B Moment-attached image carries no own position and leaves the '
        'Moment untouched', () async {
      await addMoment('m1');
      final before =
          (await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1')).single;

      final item = await addImage(waypointId: 'm1');

      final after =
          (await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1')).single;
      expect(item.waypointId, 'm1');
      expect(item.latitude, isNull);
      expect(item.longitude, isNull);
      expect(after, before, reason: 'every Moment column is unchanged');
      expect(
          (await db.getJourneyMediaForMoment(
                  ownerId: 'me', recordedRouteId: 'r1', waypointId: 'm1'))
              .map((m) => m.id),
          ['media-1']);
    });

    test('a Moment-attached image must not carry its own position', () async {
      await addMoment('m1');

      await expectLater(addImage(waypointId: 'm1', lat: 1, lng: 2),
          throwsA(isA<JourneyMediaTargetException>()));
      expect(filesUnder(root), isEmpty);
    });

    test('latitude and longitude must come together', () async {
      await expectLater(
          addImage(lat: 1), throwsA(isA<JourneyMediaTargetException>()));
      expect(filesUnder(root), isEmpty);
    });
  });

  group('image handling', () {
    test(
        'C EXIF/GPS is stripped and orientation baked by the existing '
        'normalizer', () async {
      final item = await service.addImageBytes(
        ownerId: 'me',
        recordedRouteId: 'r1',
        sourceBytes: _jpeg(gps: true, orientation: 6),
      );
      final stored = img.decodeJpg(
          await (await storage.existingFile(item.localRelativePath))!
              .readAsBytes())!;

      expect(stored.exif.isEmpty, isTrue);
      expect(stored.exif.gpsIfd.hasGPSLatitude, isFalse);
      expect(stored.width, 30);
      expect(stored.height, 40);
    });

    test('C oversized images are bounded by the normalizer contract', () async {
      final item = await service.addImageBytes(
        ownerId: 'me',
        recordedRouteId: 'r1',
        sourceBytes: _jpeg(w: 2400, h: 1200),
      );
      final stored = img.decodeJpg(
          await (await storage.existingFile(item.localRelativePath))!
              .readAsBytes())!;

      expect(stored.width, locationPhotoMaxLongEdgePx);
      expect(stored.height, 800);
    });

    test('C the canonical file is independent of the source file', () async {
      final source = File('${root.path}/picked.jpg')
        ..writeAsBytesSync(_jpeg(gps: true));
      final item = await service.addImageFile(
          ownerId: 'me', recordedRouteId: 'r1', source: source);

      source.deleteSync();

      final canonical = await storage.existingFile(item.localRelativePath);
      expect(canonical, isNotNull);
      expect(canonical!.path, isNot(source.path));
      expect(img.decodeJpg(await canonical.readAsBytes()), isNotNull);
    });
  });

  group('failure handling', () {
    test('D a DB insert failure removes the file it just created', () async {
      db.failInsert = true;

      await expectLater(addImage(), throwsA(isA<StateError>()));

      expect(filesUnder(root), isEmpty);
      expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
          isEmpty);
    });

    test('D insert failure never touches an unrelated existing file', () async {
      final keep = await addImage();
      db.failInsert = true;

      await expectLater(addImage(), throwsA(isA<StateError>()));

      expect(filesUnder(root), hasLength(1));
      expect(await storage.existingFile(keep.localRelativePath), isNotNull);
    });

    test('D a non-image source leaves no row and no file', () async {
      await expectLater(
        service.addImageBytes(
            ownerId: 'me',
            recordedRouteId: 'r1',
            sourceBytes: Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<UnsupportedLocationPhotoFormat>()),
      );

      expect(filesUnder(root), isEmpty);
      expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
          isEmpty);
    });

    test('D unrelated normalizer failures are not reported as bad images',
        () async {
      final brokenService = JourneyMediaService(
        db: db,
        storage: storage,
        normalizer: (_) => throw StateError('normalizer bug'),
      );

      await expectLater(
        brokenService.addImageBytes(
          ownerId: 'me',
          recordedRouteId: 'r1',
          sourceBytes: _jpeg(),
        ),
        throwsA(isA<StateError>()),
      );
      final rangeBrokenService = JourneyMediaService(
        db: db,
        storage: storage,
        normalizer: (_) => throw RangeError('normalizer bug'),
      );
      await expectLater(
        rangeBrokenService.addImageBytes(
          ownerId: 'me',
          recordedRouteId: 'r1',
          sourceBytes: _jpeg(),
        ),
        throwsA(isA<RangeError>()),
      );
      expect(filesUnder(root), isEmpty);
      expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
          isEmpty);
    });

    test('D a missing source file leaves no row and no file', () async {
      await expectLater(
        service.addImageFile(
            ownerId: 'me',
            recordedRouteId: 'r1',
            source: File('${root.path}/nope.jpg')),
        throwsA(isA<FileSystemException>()),
      );

      expect(filesUnder(root), isEmpty);
      expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
          isEmpty);
    });

    test('D a missing canonical file never crashes reads or deletes the row',
        () async {
      final item = await addImage();
      (await storage.existingFile(item.localRelativePath))!.deleteSync();

      expect(await service.resolveFile(item), isNull);
      expect(await storage.existingFile('../../etc/passwd'), isNull);
      final rows =
          await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1');
      expect(rows.single.id, item.id, reason: 'the row is never auto-deleted');
    });

    test('an id collision never overwrites an existing file', () async {
      final first = await addImage();
      final bytesBefore =
          await (await storage.existingFile(first.localRelativePath))!
              .readAsBytes();
      counter = 0; // the next generated id collides with media-1

      await expectLater(addImage(), throwsA(isA<FileSystemException>()));

      expect(
          await (await storage.existingFile(first.localRelativePath))!
              .readAsBytes(),
          bytesBefore);
      expect(filesUnder(root), hasLength(1));
    });
  });

  group('isolation and Moment validation', () {
    test('E media cannot target another owner or an unknown route', () async {
      await expectLater(addImage(owner: 'intruder'),
          throwsA(isA<JourneyMediaTargetException>()));
      await expectLater(
          addImage(route: 'nope'), throwsA(isA<JourneyMediaTargetException>()));
      expect(filesUnder(root), isEmpty);
    });

    test('E cannot attach to a Moment of another Journey', () async {
      await db.createLocalRecordedRoute(
          id: 'r2', ownerId: 'me2', startedAt: t0);
      await db.finishRecordingLocally(
          ownerId: 'me', routeId: 'r1', occurredAt: t0);
      await db.createLocalRecordedRoute(id: 'r3', ownerId: 'me', startedAt: t0);
      await addMoment('onR1');

      await expectLater(addImage(route: 'r3', waypointId: 'onR1'),
          throwsA(isA<JourneyMediaTargetException>()));
      expect(filesUnder(root), isEmpty);
    });

    test("E cannot attach to another owner's Moment", () async {
      await db.createLocalRecordedRoute(
          id: 'r2', ownerId: 'other', startedAt: t0);
      await addMoment('theirs', route: 'r2', owner: 'other');

      await expectLater(addImage(waypointId: 'theirs'),
          throwsA(isA<JourneyMediaTargetException>()));
      await expectLater(
          addImage(owner: 'other', route: 'r2', waypointId: 'nope'),
          throwsA(isA<JourneyMediaTargetException>()));
    });

    test('E cannot attach to a Moment that is a deletion tombstone', () async {
      await addMoment('m1');
      await (db.update(db.localWaypoints)..where((t) => t.id.equals('m1')))
          .write(const LocalWaypointsCompanion(
              syncStatus: Value(WaypointSyncStatus.synced)));
      await db.deleteWaypoint(ownerId: 'me', recordedRouteId: 'r1', id: 'm1');

      await expectLater(addImage(waypointId: 'm1'),
          throwsA(isA<JourneyMediaTargetException>()));
    });

    test('a media id alone never reaches another owner/route', () async {
      final item = await addImage();

      expect(
          await db.getJourneyMediaItem(
              ownerId: 'intruder', recordedRouteId: 'r1', id: item.id),
          isNull);
      expect(
          await db.deleteJourneyMedia(
              ownerId: 'intruder', recordedRouteId: 'r1', id: item.id),
          JourneyMediaDeleteOutcome.notFound);
      expect(
          await db.deleteJourneyMedia(
              ownerId: 'me', recordedRouteId: 'other-route', id: item.id),
          JourneyMediaDeleteOutcome.notFound);
      expect(await storage.existingFile(item.localRelativePath), isNotNull);
    });
  });

  group('deletion lifecycle', () {
    test('F never-synced media: row and file are removed', () async {
      final item = await addImage();

      final outcome = await service.deleteMedia(
          ownerId: 'me', recordedRouteId: 'r1', mediaId: item.id);

      expect(outcome, JourneyMediaDeleteOutcome.removed);
      expect(
          await db.getJourneyMediaItem(
              ownerId: 'me', recordedRouteId: 'r1', id: item.id),
          isNull);
      expect(filesUnder(root), isEmpty);
    });

    for (final status in [
      JourneyMediaSyncStatus.synced,
      JourneyMediaSyncStatus.failed,
    ]) {
      test('F $status media becomes a tombstone, hidden but retained',
          () async {
        final item = await addImage();
        await setStatus(item.id, status);

        final outcome = await service.deleteMedia(
            ownerId: 'me', recordedRouteId: 'r1', mediaId: item.id);

        expect(outcome, JourneyMediaDeleteOutcome.tombstoned);
        expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
            isEmpty);
        final tombstones = await db.getTombstonedJourneyMedia(
            ownerId: 'me', recordedRouteId: 'r1');
        expect(tombstones.single.id, item.id);
        expect(
            tombstones.single.syncStatus, JourneyMediaSyncStatus.pendingDelete);
        expect(tombstones.single.recordedRouteId, 'r1');
        expect(filesUnder(root), isEmpty,
            reason: 'the removed photo no longer lingers on the device');
      });
    }

    test(
        'F nothing acknowledges a tombstone; only the explicit primitive '
        'purges it', () async {
      final item = await addImage();
      await setStatus(item.id, JourneyMediaSyncStatus.synced);
      await service.deleteMedia(
          ownerId: 'me', recordedRouteId: 'r1', mediaId: item.id);

      await expectLater(
          db.markJourneyMediaSynced(
              ownerId: 'me', recordedRouteId: 'r1', id: item.id),
          throwsStateError);
      expect(
          await db.getTombstonedJourneyMedia(
              ownerId: 'me', recordedRouteId: 'r1'),
          hasLength(1));

      await db.purgeAcknowledgedJourneyMediaTombstone(
          ownerId: 'me', recordedRouteId: 'r1', id: item.id);
      expect(
          await db.getTombstonedJourneyMedia(
              ownerId: 'me', recordedRouteId: 'r1'),
          isEmpty);
    });

    test('purge never removes a live (non-tombstone) row', () async {
      final item = await addImage();

      await db.purgeAcknowledgedJourneyMediaTombstone(
          ownerId: 'me', recordedRouteId: 'r1', id: item.id);

      expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
          hasLength(1));
    });

    test('pending media is exposed to a future sync, tombstones are not',
        () async {
      final a = await addImage();
      final b = await addImage();
      await setStatus(b.id, JourneyMediaSyncStatus.synced);

      expect(
          (await db.getPendingJourneyMedia(
                  ownerId: 'me', recordedRouteId: 'r1'))
              .map((m) => m.id),
          [a.id]);
    });
  });

  group('Moment deletion interaction', () {
    late FakeLocationSource source;
    late GpsRecordingController controller;

    setUp(() async {
      source = FakeLocationSource()..permission = LocationPermission.whileInUse;
      await db.discardRecording(ownerId: 'me', routeId: 'r1', occurredAt: t0);
      controller = GpsRecordingController(
        ownerId: 'me',
        db: db,
        locationSource: source,
        notificationPermissionSource: FakeNotificationPermissionSource(),
        mediaStorage: storage,
      );
      await controller.start();
      await pumpEventQueue();
    });

    tearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    Future<String> momentOnActiveRoute(String id) async {
      final routeId = controller.state.routeId!;
      await db.addWaypoint(
        id: id,
        ownerId: 'me',
        recordedRouteId: routeId,
        waypointType: 'custom',
        latitude: 50,
        longitude: 30,
        recordedAt: t0,
      );
      return routeId;
    }

    test('G deleting a Moment removes its never-synced media and files only',
        () async {
      final routeId = await momentOnActiveRoute('m1');
      await momentOnActiveRoute('m2');
      final owned = await addImage(route: routeId, waypointId: 'm1');
      final unrelated = await addImage(route: routeId, waypointId: 'm2');
      final standalone = await addImage(route: routeId);

      expect(await controller.deleteWaypoint(waypointId: 'm1'), isTrue);

      final left =
          await db.getJourneyMedia(ownerId: 'me', recordedRouteId: routeId);
      expect(left.map((m) => m.id),
          unorderedEquals([unrelated.id, standalone.id]));
      expect(await storage.existingFile(owned.localRelativePath), isNull);
      expect(
          await storage.existingFile(unrelated.localRelativePath), isNotNull);
      expect(
          await storage.existingFile(standalone.localRelativePath), isNotNull);
    });

    test('G deleting a Moment tombstones its synced/failed media', () async {
      final routeId = await momentOnActiveRoute('m1');
      final synced = await addImage(route: routeId, waypointId: 'm1');
      final failed = await addImage(route: routeId, waypointId: 'm1');
      final pending = await addImage(route: routeId, waypointId: 'm1');
      await setStatus(synced.id, JourneyMediaSyncStatus.synced);
      await setStatus(failed.id, JourneyMediaSyncStatus.failed);

      await controller.deleteWaypoint(waypointId: 'm1');

      expect(
          (await db.getTombstonedJourneyMedia(
                  ownerId: 'me', recordedRouteId: routeId))
              .map((m) => m.id),
          unorderedEquals([synced.id, failed.id]));
      expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: routeId),
          isEmpty);
      expect(
          await db.getJourneyMediaItem(
              ownerId: 'me', recordedRouteId: routeId, id: pending.id),
          isNull);
      expect(filesUnder(root), isEmpty);
    });

    test('G the Moment keeps the existing waypoint lifecycle', () async {
      final routeId = await momentOnActiveRoute('m1');
      await addImage(route: routeId, waypointId: 'm1');
      await (db.update(db.localWaypoints)..where((t) => t.id.equals('m1')))
          .write(const LocalWaypointsCompanion(
              syncStatus: Value(WaypointSyncStatus.synced)));

      await controller.deleteWaypoint(waypointId: 'm1');

      expect(
          (await db.getTombstonedWaypoints(
                  ownerId: 'me', recordedRouteId: routeId))
              .map((w) => w.id),
          ['m1']);
    });
  });

  group('reads and reactivity', () {
    test('H ordering is capturedAt ascending with id tie-break', () async {
      final late =
          await addImage(capturedAt: t0.add(const Duration(minutes: 5)));
      final early = await addImage(capturedAt: t0);
      final tieA =
          await addImage(capturedAt: t0.add(const Duration(minutes: 1)));
      final tieB =
          await addImage(capturedAt: t0.add(const Duration(minutes: 1)));

      final ids =
          (await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'))
              .map((m) => m.id)
              .toList();

      expect(ids, [early.id, tieA.id, tieB.id, late.id]);
    });

    test('H watch emits after create and delete', () async {
      final emissions = <List<String>>[];
      final sub = db
          .watchJourneyMedia(ownerId: 'me', recordedRouteId: 'r1')
          .listen((rows) => emissions.add(rows.map((r) => r.id).toList()));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      final item = await addImage();
      await pumpEventQueue();
      expect(emissions.last, [item.id]);

      await service.deleteMedia(
          ownerId: 'me', recordedRouteId: 'r1', mediaId: item.id);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
    });

    test('H another route and owner never appear in this watch', () async {
      await db.createLocalRecordedRoute(
          id: 'r9', ownerId: 'other', startedAt: t0);
      await addImage(owner: 'other', route: 'r9');
      await addImage();

      expect(
          (await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'))
              .map((m) => m.recordedRouteId),
          ['r1']);
    });
  });

  group('storage path contract', () {
    test('J path structure is deterministic and portable', () {
      expect(
          JourneyMediaStorage.relativePathFor(
              recordedRouteId: 'abc-1', mediaId: 'def_2'),
          'journey_media/abc-1/def_2.jpg');
    });

    test('J only the canonical relative shape is accepted', () {
      for (final bad in [
        '/journey_media/r1/m.jpg',
        'journey_media/../m.jpg',
        'journey_media/r1/../m.jpg',
        'journey_media/r1/m.png',
        r'journey_media\r1\m.jpg',
        'C:/Users/me/m.jpg',
        'other/r1/m.jpg',
        'journey_media/r1/sub/m.jpg',
        '',
      ]) {
        expect(JourneyMediaStorage.isValidRelativePath(bad), isFalse,
            reason: bad);
      }
      expect(
          () => JourneyMediaStorage.relativePathFor(
              recordedRouteId: '../x', mediaId: 'm'),
          throwsArgumentError);
    });

    test('J Drift rejects non-canonical and substituted persisted paths',
        () async {
      for (final bad in [
        '/journey_media/r1/media-x.jpg',
        r'journey_media\r1\media-x.jpg',
        'journey_media/r1/../media-x.jpg',
        'journey_media/other/media-x.jpg',
        'journey_media/r1/other-id.jpg',
        'journey_media/r1/media-x.png',
      ]) {
        await expectLater(
          db.insertJourneyMedia(
            id: 'media-x',
            ownerId: 'me',
            recordedRouteId: 'r1',
            capturedAt: t0,
            localRelativePath: bad,
          ),
          throwsArgumentError,
          reason: bad,
        );
      }
      expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1'),
          isEmpty);
    });

    test('I the relative path resolves under a different documents root',
        () async {
      final item = await addImage();
      final moved = await Directory.systemTemp.createTemp('journey_moved_');
      addTearDown(() => moved.delete(recursive: true));
      final target = File('${moved.path}/${item.localRelativePath}');
      target.parent.createSync(recursive: true);
      (await storage.existingFile(item.localRelativePath))!
          .copySync(target.path);

      final newStorage = JourneyMediaStorage(rootDirectory: () async => moved);

      final resolved = await newStorage.existingFile(item.localRelativePath);
      expect(resolved, isNotNull);
      expect(resolved!.path.startsWith(moved.path), isTrue);
    });

    test('production storage is rooted lazily at the app documents directory',
        () {
      // Constructing the provider-backed storage must not touch path_provider
      // (no platform channel exists under `flutter test`).
      expect(() => JourneyMediaStorage(rootDirectory: () async => root),
          returnsNormally);
      expect(journeyMediaStorageProvider, isNotNull);
    });
  });

  group('source guards', () {
    test('no network, remote or absolute-path code in the media files', () {
      for (final path in [
        'lib/features/gps/media/journey_media_storage.dart',
        'lib/features/gps/media/journey_media_service.dart',
      ]) {
        final source = File(path).readAsStringSync();
        final imports = source
            .split('\n')
            .where((l) => l.startsWith('import '))
            .join('\n')
            .toLowerCase();
        for (final banned in ['supabase', 'sync/', 'http', 'connectivity']) {
          expect(imports, isNot(contains(banned)), reason: path);
        }
        expect(source, isNot(contains('.storage.from')), reason: path);
        expect(source, isNot(contains('uploadBinary')), reason: path);
      }
    });
  });
}
