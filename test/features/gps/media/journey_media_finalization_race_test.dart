import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:image/image.dart' as img;
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_service.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_storage.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_controller.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';

import '../location/fake_location_source.dart';
import '../location/fake_notification_permission_source.dart';

/// Holds the final media insert open (after the controller accepted the
/// request and the canonical file was written) until the test releases it --
/// the deterministic seam for "Finish commits while a photo is in flight".
class _GatedMediaDb extends GpsLocalDatabase {
  _GatedMediaDb(super.executor) : super.forTesting();

  Completer<void>? _gate;
  Completer<void> _entered = Completer<void>();
  int insertCalls = 0;

  /// Completes when a gated insert has been reached.
  Future<void> get insertEntered => _entered.future;

  void arm() {
    _gate = Completer<void>();
    _entered = Completer<void>();
  }

  void release() => _gate!.complete();

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
  }) async {
    insertCalls++;
    final gate = _gate;
    if (gate != null) {
      if (!_entered.isCompleted) _entered.complete();
      await gate.future;
    }
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

Uint8List _jpeg() {
  final image = img.Image(width: 40, height: 30, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 1, 1, 10);
  late Directory root;
  late _GatedMediaDb db;
  late FakeLocationSource source;
  late JourneyMediaStorage storage;
  late JourneyMediaService service;
  late GpsRecordingController controller;

  List<String> files() => root.existsSync()
      ? root
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toList()
      : <String>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('journey_media_race_');
    db = _GatedMediaDb(NativeDatabase.memory());
    source = FakeLocationSource()..permission = LocationPermission.whileInUse;
    storage = JourneyMediaStorage(rootDirectory: () async => root);
    service = JourneyMediaService(db: db, storage: storage);
    controller = GpsRecordingController(
      ownerId: 'me',
      db: db,
      locationSource: source,
      notificationPermissionSource: FakeNotificationPermissionSource(),
      mediaStorage: storage,
      mediaService: service,
    );
    await controller.start();
    await pumpEventQueue();
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
    await source.dispose();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  String currentRoute() => controller.state.routeId!;

  Future<List<LocalJourneyMediaItem>> media({String owner = 'me'}) =>
      db.getJourneyMedia(ownerId: owner, recordedRouteId: currentRoute());

  Future<List<LocalJourneyMediaItem>> allMediaIncludingTombstones() async => [
        ...await media(),
        ...await db.getTombstonedJourneyMedia(
            ownerId: 'me', recordedRouteId: currentRoute()),
      ];

  /// Starts an add whose final insert is held, waits (deterministically)
  /// until the file exists and the insert is about to run, finishes the
  /// Journey, then releases the insert. Returns what the add produced.
  Future<Object?> addPhotoRacingFinish({
    String? waypointId,
    bool pauseFirst = false,
  }) async {
    if (pauseFirst) {
      await controller.pause();
      await pumpEventQueue();
    }
    db.arm();
    final inFlight = controller
        .addPhoto(sourceBytes: _jpeg(), waypointId: waypointId)
        .then<Object?>((item) => item, onError: (Object e) => e);
    await db.insertEntered;
    expect(files(), hasLength(1),
        reason: 'the canonical file is already written when Finish wins');

    expect(await controller.finish(), isTrue);
    expect(controller.state.status, GpsRecordingStatus.completed);

    db.release();
    return inFlight;
  }

  test('R01 a photo committed before Finish stays part of the Journey',
      () async {
    final item = await controller.addPhoto(sourceBytes: _jpeg());

    expect(item, isNotNull);
    expect(await controller.finish(), isTrue);
    expect((await media()).map((m) => m.id), [item!.id]);
    expect(files(), hasLength(1));
    expect(
        (await db.getRecordedRoute(ownerId: 'me', id: currentRoute()))!.status,
        RecordedRouteStatus.completed);
  });

  test(
      'R02 an in-flight photo whose insert runs after Finish is rejected, '
      'row absent, file cleaned', () async {
    final result = await addPhotoRacingFinish();

    expect(result, isA<JourneyMediaRouteNotActiveException>());
    expect(await allMediaIncludingTombstones(), isEmpty,
        reason: 'no row and no tombstone for an item never inserted');
    expect(files(), isEmpty, reason: 'the newly written file is removed');
    expect(controller.state.status, GpsRecordingStatus.completed);
    expect(source.activeSubscriptionCount, 0);
  });

  test(
      'R03 the same race while paused: Journey completes, no resume, no '
      'media', () async {
    final result = await addPhotoRacingFinish(pauseFirst: true);

    expect(result, isA<JourneyMediaRouteNotActiveException>());
    expect(await allMediaIncludingTombstones(), isEmpty);
    expect(files(), isEmpty);
    final events =
        await db.getRouteEvents(ownerId: 'me', recordedRouteId: currentRoute());
    expect(events.map((e) => e.eventType), [
      RouteEventType.start,
      RouteEventType.pause,
      RouteEventType.finish,
    ]);
    expect(source.activeSubscriptionCount, 0);
  });

  test('R04 direct DB and service attempts on a completed route are rejected',
      () async {
    await controller.finish();
    await pumpEventQueue();

    await expectLater(
        db.insertJourneyMedia(
            id: 'x',
            ownerId: 'me',
            recordedRouteId: currentRoute(),
            capturedAt: t0,
            localRelativePath: 'journey_media/${currentRoute()}/x.jpg'),
        throwsA(isA<JourneyMediaRouteNotActiveException>()));
    await expectLater(
        service.addImageBytes(
            ownerId: 'me',
            recordedRouteId: currentRoute(),
            sourceBytes: _jpeg()),
        throwsA(isA<JourneyMediaRouteNotActiveException>()));

    expect(await allMediaIncludingTombstones(), isEmpty);
    expect(files(), isEmpty,
        reason: 'the service validates the route before writing any file');
  });

  test('R05 a discarded route rejects media too', () async {
    final discarded = currentRoute();
    await controller.discard();
    await pumpEventQueue();

    await expectLater(
        service.addImageBytes(
            ownerId: 'me', recordedRouteId: discarded, sourceBytes: _jpeg()),
        throwsA(isA<JourneyMediaRouteNotActiveException>()));
    await expectLater(
        db.insertJourneyMedia(
            id: 'x',
            ownerId: 'me',
            recordedRouteId: discarded,
            capturedAt: t0,
            localRelativePath: 'journey_media/$discarded/x.jpg'),
        throwsA(isA<JourneyMediaRouteNotActiveException>()));

    expect(await db.getJourneyMedia(ownerId: 'me', recordedRouteId: discarded),
        isEmpty);
    expect(files(), isEmpty);
  });

  test(
      'R06 isolation: Finish of one Journey never affects another owner, '
      'and nobody else can target this one', () async {
    await db.createLocalRecordedRoute(
        id: 'theirs', ownerId: 'other', startedAt: t0);
    final finished = currentRoute();
    await controller.finish();
    await pumpEventQueue();

    final theirs = await service.addImageBytes(
        ownerId: 'other', recordedRouteId: 'theirs', sourceBytes: _jpeg());
    expect(theirs.recordedRouteId, 'theirs');

    await expectLater(
        service.addImageBytes(
            ownerId: 'other', recordedRouteId: finished, sourceBytes: _jpeg()),
        throwsA(isA<JourneyMediaTargetException>()));
    expect(
        (await db.getJourneyMedia(ownerId: 'other', recordedRouteId: 'theirs'))
            .single
            .id,
        theirs.id);
    expect(files(), hasLength(1), reason: "only the other owner's photo");
  });

  test('R07 a rejected late photo leaves its intended Moment untouched',
      () async {
    await db.addWaypoint(
      id: 'm1',
      ownerId: 'me',
      recordedRouteId: currentRoute(),
      waypointType: 'viewpoint',
      title: 'Spot',
      latitude: 50.5,
      longitude: 30.5,
      altitude: 120,
      recordedAt: t0,
    );
    final before =
        (await db.getWaypoints(ownerId: 'me', recordedRouteId: currentRoute()))
            .single;

    final result = await addPhotoRacingFinish(waypointId: 'm1');

    expect(result, isA<JourneyMediaRouteNotActiveException>());
    final after =
        (await db.getWaypoints(ownerId: 'me', recordedRouteId: currentRoute()))
            .single;
    expect(after, before, reason: 'every Moment column is unchanged');
    expect(await allMediaIncludingTombstones(), isEmpty);
    expect(files(), isEmpty);
  });

  test('R08 retries and failures never create duplicate rows or files',
      () async {
    final first = await addPhotoRacingFinish();
    expect(first, isA<JourneyMediaRouteNotActiveException>());

    for (var i = 0; i < 3; i++) {
      await expectLater(
          service.addImageBytes(
              ownerId: 'me',
              recordedRouteId: currentRoute(),
              sourceBytes: _jpeg()),
          throwsA(isA<JourneyMediaRouteNotActiveException>()));
    }

    expect(await allMediaIncludingTombstones(), isEmpty);
    expect(files(), isEmpty);
  });

  test('R09 ordinary photo creation while recording and paused still works',
      () async {
    final recording = await controller.addPhoto(sourceBytes: _jpeg());
    await controller.pause();
    await pumpEventQueue();
    final paused = await controller.addPhoto(sourceBytes: _jpeg());

    expect(recording, isNotNull);
    expect(paused, isNotNull);
    expect(controller.state.status, GpsRecordingStatus.paused);
    expect(await media(), hasLength(2));
    expect(files(), hasLength(2));
  });

  test('R10 the Phase 1E invariant still holds: no GPS point after Finish',
      () async {
    await controller.finish();
    await pumpEventQueue();

    final appended = await db.appendRoutePoint(
        ownerId: 'me',
        recordedRouteId: currentRoute(),
        latitude: 1,
        longitude: 1,
        recordedAt: t0);

    expect(appended, isFalse);
    expect(
        await db.getRoutePoints(ownerId: 'me', recordedRouteId: currentRoute()),
        isEmpty);
  });

  test('a failed Finish leaves the Journey active, so media still works',
      () async {
    // Gate released before Finish: the insert commits first, as in R01, and
    // the Journey remains active for later photos.
    db.arm();
    final inFlight = controller.addPhoto(sourceBytes: _jpeg());
    await db.insertEntered;
    db.release();
    final item = await inFlight;

    expect(item, isNotNull);
    expect(controller.state.status, GpsRecordingStatus.recording);
    expect(await controller.addPhoto(sourceBytes: _jpeg()), isNotNull);
    expect(await media(), hasLength(2));
  });
}
