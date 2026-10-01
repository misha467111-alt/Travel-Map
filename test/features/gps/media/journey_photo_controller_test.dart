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
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';
import 'package:flutter_application_1/features/map/domain/location_photo_normalizer.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

Uint8List _jpeg() {
  final image = img.Image(width: 40, height: 30, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Journey Phase 1H-C: `GpsRecordingController.addPhoto` -- the controller
/// half of the photo creation flow, against a real database and a real
/// (temporary) media directory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late GpsLocalDatabase db;
  late FakeLocationSource source;
  late JourneyMediaStorage storage;
  late GpsRecordingController controller;

  GpsRecordingController buildController(String owner,
          {bool withMedia = true}) =>
      GpsRecordingController(
        ownerId: owner,
        db: db,
        locationSource: source,
        notificationPermissionSource: FakeNotificationPermissionSource(),
        mediaStorage: storage,
        mediaService:
            withMedia ? JourneyMediaService(db: db, storage: storage) : null,
      );

  List<String> files() => root.existsSync()
      ? root
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList()
      : <String>[];

  Future<void> settle() => pumpEventQueue();

  Future<String> startRecording() async {
    await controller.start();
    await settle();
    return controller.state.routeId!;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('journey_photo_ctrl_');
    db = GpsLocalDatabase.forTesting(NativeDatabase.memory());
    source = FakeLocationSource()..permission = LocationPermission.whileInUse;
    storage = JourneyMediaStorage(rootDirectory: () async => root);
    controller = buildController('me');
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
    await source.dispose();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<List<LocalJourneyMediaItem>> media(String route,
          [String owner = 'me']) =>
      db.getJourneyMedia(ownerId: owner, recordedRouteId: route);

  group('standalone photo', () {
    test('9/10 uses the latest accepted GPS position, waypointId stays null',
        () async {
      final routeId = await startRecording();
      source.emitPosition(testPosition(latitude: 50.1, longitude: 30.1));
      await settle();
      source.emitPosition(testPosition(latitude: 50.2, longitude: 30.2));
      await settle();

      final item = await controller.addPhoto(sourceBytes: _jpeg());

      expect(item, isNotNull);
      expect(item!.waypointId, isNull);
      expect(item.latitude, 50.2);
      expect(item.longitude, 30.2);
      expect(item.syncStatus, JourneyMediaSyncStatus.pending);
      expect((await media(routeId)).single.id, item.id);
    });

    test('11 with no accepted position the coordinates are null', () async {
      final routeId = await startRecording();

      final item = await controller.addPhoto(sourceBytes: _jpeg());

      expect(item!.latitude, isNull);
      expect(item.longitude, isNull);
      expect((await media(routeId)), hasLength(1));
    });

    test('24 only the canonical relative path is persisted', () async {
      await startRecording();
      final item = await controller.addPhoto(sourceBytes: _jpeg());

      expect(JourneyMediaStorage.isValidRelativePath(item!.localRelativePath),
          isTrue);
      expect(item.localRelativePath, isNot(contains(root.path)));
      expect(item.localRelativePath, isNot(contains('cache')));
      expect(item.localRelativePath, isNot(contains(r'\')));
      expect(files(), hasLength(1));
      expect(files().single.contains(root.path), isTrue);
    });
  });

  group('Moment photo', () {
    Future<String> momentOn(String routeId, {String id = 'm1'}) async {
      await db.addWaypoint(
        id: id,
        ownerId: 'me',
        recordedRouteId: routeId,
        waypointType: 'viewpoint',
        latitude: 50.5,
        longitude: 30.5,
        altitude: 123,
        recordedAt: DateTime.utc(2026, 1, 1, 10),
      );
      return id;
    }

    test('7/8 attaches to the Moment and leaves its telemetry untouched',
        () async {
      final routeId = await startRecording();
      source.emitPosition(testPosition(latitude: 1, longitude: 2));
      await settle();
      await momentOn(routeId);
      final before =
          (await db.getWaypoints(ownerId: 'me', recordedRouteId: routeId))
              .single;

      final item =
          await controller.addPhoto(sourceBytes: _jpeg(), waypointId: 'm1');

      final after =
          (await db.getWaypoints(ownerId: 'me', recordedRouteId: routeId))
              .single;
      expect(item!.waypointId, 'm1');
      expect(item.recordedRouteId, routeId);
      expect(item.latitude, isNull,
          reason: 'attached media never copies position, even with a fix');
      expect(after, before);
      expect(after.latitude, 50.5);
      expect(after.altitude, 123);
    });

    test('19 a tombstoned Moment is rejected and nothing is stored', () async {
      final routeId = await startRecording();
      await momentOn(routeId);
      await (db.update(db.localWaypoints)..where((t) => t.id.equals('m1')))
          .write(const LocalWaypointsCompanion(
              syncStatus: Value(WaypointSyncStatus.synced)));
      await db.deleteWaypoint(
          ownerId: 'me', recordedRouteId: routeId, id: 'm1');

      await expectLater(
          controller.addPhoto(sourceBytes: _jpeg(), waypointId: 'm1'),
          throwsA(isA<JourneyMediaTargetException>()));

      expect(await media(routeId), isEmpty);
      expect(files(), isEmpty);
    });

    test('a missing Moment is rejected and nothing is stored', () async {
      final routeId = await startRecording();

      await expectLater(
          controller.addPhoto(sourceBytes: _jpeg(), waypointId: 'ghost'),
          throwsA(isA<JourneyMediaTargetException>()));

      expect(await media(routeId), isEmpty);
      expect(files(), isEmpty);
    });

    test('17/18 another owner or another Journey cannot use this Moment',
        () async {
      final routeId = await startRecording();
      await momentOn(routeId);
      // The same Moment id reached through another owner's controller.
      final other = buildController('intruder');
      addTearDown(other.dispose);
      await other.start();
      await settle();

      await expectLater(other.addPhoto(sourceBytes: _jpeg(), waypointId: 'm1'),
          throwsA(isA<JourneyMediaTargetException>()));

      expect(await media(routeId), isEmpty);
      expect(await media(other.state.routeId!, 'intruder'), isEmpty);
      expect(files(), isEmpty);
    });
  });

  group('recording state', () {
    test('13 recording stays recording and adds no location subscription',
        () async {
      await startRecording();
      final subscribed = source.subscribeCallCount;
      final active = source.activeSubscriptionCount;

      await controller.addPhoto(sourceBytes: _jpeg());
      await settle();

      expect(controller.state.status, GpsRecordingStatus.recording);
      expect(source.subscribeCallCount, subscribed);
      expect(source.activeSubscriptionCount, active);
    });

    test('14 paused stays paused, creates a photo and subscribes to nothing',
        () async {
      final routeId = await startRecording();
      await controller.pause();
      await settle();

      final item = await controller.addPhoto(sourceBytes: _jpeg());
      await settle();

      expect(item, isNotNull);
      expect(controller.state.status, GpsRecordingStatus.paused);
      expect(source.activeSubscriptionCount, 0);
      final events =
          await db.getRouteEvents(ownerId: 'me', recordedRouteId: routeId);
      expect(events.map((e) => e.eventType),
          [RouteEventType.start, RouteEventType.pause],
          reason: 'no resume or any other lifecycle event was created');
    });

    test('15/16 completed, idle and discarded states offer no creation',
        () async {
      expect(await controller.addPhoto(sourceBytes: _jpeg()), isNull,
          reason: 'idle');

      final routeId = await startRecording();
      await controller.finish();
      await settle();
      expect(controller.state.status, GpsRecordingStatus.completed);
      expect(await controller.addPhoto(sourceBytes: _jpeg()), isNull,
          reason: 'completed');

      controller.dismissCompleted();
      await controller.start();
      await settle();
      await controller.discard();
      await settle();
      expect(await controller.addPhoto(sourceBytes: _jpeg()), isNull,
          reason: 'discarded -> idle');
      expect(await media(routeId), isEmpty);
      expect(files(), isEmpty);
    });

    test('recoverable Journeys offer no creation (no live session)', () async {
      await db.createLocalRecordedRoute(
          id: 'old', ownerId: 'ghost', startedAt: DateTime.utc(2026));
      final recovered = buildController('ghost');
      addTearDown(recovered.dispose);
      await settle();
      expect(recovered.state.status, GpsRecordingStatus.recoverable);

      expect(await recovered.addPhoto(sourceBytes: _jpeg()), isNull);
      expect(await media('old', 'ghost'), isEmpty);
    });

    test('without a configured media service creation is simply unavailable',
        () async {
      final bare = buildController('solo', withMedia: false);
      addTearDown(bare.dispose);
      await bare.start();
      await settle();

      expect(await bare.addPhoto(sourceBytes: _jpeg()), isNull);
    });
  });

  group('failures', () {
    test('4 a corrupt image fails cleanly: no row, no file, state intact',
        () async {
      final routeId = await startRecording();

      await expectLater(
          controller.addPhoto(sourceBytes: Uint8List.fromList([9, 9, 9])),
          throwsA(isA<UnsupportedLocationPhotoFormat>()));

      expect(await media(routeId), isEmpty);
      expect(files(), isEmpty);
      expect(controller.state.status, GpsRecordingStatus.recording);
    });

    test('a failed photo never affects later successful ones', () async {
      final routeId = await startRecording();
      await expectLater(
          controller.addPhoto(sourceBytes: Uint8List.fromList([1])),
          throwsA(isA<UnsupportedLocationPhotoFormat>()));

      final item = await controller.addPhoto(sourceBytes: _jpeg());

      expect(item, isNotNull);
      expect((await media(routeId)), hasLength(1));
    });
  });

  group('offline contract', () {
    test('22/23 creation code has no network or Supabase dependency', () {
      final source =
          File('lib/features/gps/presentation/gps_photo_capture.dart')
              .readAsStringSync();
      final imports = source
          .split('\n')
          .where((l) => l.startsWith('import '))
          .join('\n')
          .toLowerCase();
      for (final banned in ['supabase', 'sync/', 'http', 'connectivity']) {
        expect(imports, isNot(contains(banned)));
      }
      expect(source, isNot(contains('uploadBinary')));
      expect(source, isNot(contains('.storage.from')));
    });
  });
}
