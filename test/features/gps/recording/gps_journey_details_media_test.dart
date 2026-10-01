import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/media/journey_media_storage.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_details.dart';

/// Journey Phase 1H-D: media in the completed-Journey read model + Timeline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 1, 1, 10);
  DateTime at(int sec) => t0.add(Duration(seconds: sec));
  late GpsLocalDatabase db;

  setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A recording Journey (media can only be added while active); call
  /// [finish] when the fixture is complete.
  Future<void> start(String id, {String owner = 'me'}) =>
      db.createLocalRecordedRoute(id: id, ownerId: owner, startedAt: t0);

  Future<void> finish(String id, {String owner = 'me', int sec = 600}) => db
      .finishRecordingLocally(ownerId: owner, routeId: id, occurredAt: at(sec));

  Future<void> moment(String id, int sec, {String route = 'r1'}) =>
      db.addWaypoint(
        id: id,
        ownerId: 'me',
        recordedRouteId: route,
        waypointType: 'viewpoint',
        title: 'T $id',
        latitude: 50.5,
        longitude: 30.5,
        altitude: 100,
        recordedAt: at(sec),
      );

  Future<LocalJourneyMediaItem> photo(
    String id,
    int sec, {
    String route = 'r1',
    String owner = 'me',
    String? waypointId,
    double? lat,
    double? lng,
  }) =>
      db.insertJourneyMedia(
        id: id,
        ownerId: owner,
        recordedRouteId: route,
        waypointId: waypointId,
        capturedAt: at(sec),
        latitude: lat,
        longitude: lng,
        localRelativePath: 'journey_media/$route/$id.jpg',
      );

  Future<GpsJourneyDetails> load(
          {String id = 'r1', String owner = 'me'}) async =>
      (await loadGpsJourneyDetails(
          db: db, ownerId: owner, routeId: id, now: t0))!;

  List<String> ids(GpsJourneyDetails d) => d.timeline.map((e) => e.id).toList();

  group('read model', () {
    test(
        'D01 a Journey with no media has an empty media model and a '
        'media-free Timeline', () async {
      await start('r1');
      await finish('r1');
      final d = await load();

      expect(d.media, isEmpty);
      expect(
          d.timeline.where((e) =>
              e.kind == GpsTimelineEntryKind.media || e.photos.isNotEmpty),
          isEmpty);
    });

    test(
        'D02/D06/D07/D08 a standalone photo is its own entry, stamped '
        'capturedAt, with a media-id identity', () async {
      await start('r1');
      await photo('p1', 120, lat: 50.1, lng: 30.1);
      await finish('r1');
      final d = await load();

      final entry =
          d.timeline.singleWhere((e) => e.kind == GpsTimelineEntryKind.media);
      expect(entry.id, 'media_p1');
      expect(entry.timestamp, at(120));
      expect(entry.moment, isNull);
      expect(entry.photos.single.id, 'p1');
      expect(entry.photos.single.latitude, 50.1);
      expect(entry.photos.single.longitude, 30.1);
      expect(d.media.single.id, 'p1');
    });

    test(
        'D03/D05 an attached photo is exposed by its Moment entry, which '
        'gets no extra Timeline event', () async {
      await start('r1');
      await moment('m1', 100);
      await photo('p1', 130, waypointId: 'm1');
      await finish('r1');
      final d = await load();

      expect(d.timeline.where((e) => e.kind == GpsTimelineEntryKind.media),
          isEmpty);
      final entry = d.timeline.singleWhere((e) => e.id == 'moment_m1');
      expect(entry.photos.map((p) => p.id), ['p1']);
      expect(entry.timestamp, at(100),
          reason: 'the Moment keeps its own time, not the photo time');
      expect(d.timeline, hasLength(3), reason: 'start, Moment, finish');
    });

    test(
        'D04 several photos stay ONE Moment entry, ordered by capturedAt '
        'then id', () async {
      await start('r1');
      await moment('m1', 100);
      await photo('c', 300, waypointId: 'm1');
      await photo('b', 200, waypointId: 'm1');
      await photo('a', 200, waypointId: 'm1');
      await finish('r1');
      final d = await load();

      final moments =
          d.timeline.where((e) => e.kind == GpsTimelineEntryKind.moment);
      expect(moments, hasLength(1));
      expect(moments.single.photos.map((p) => p.id), ['a', 'b', 'c']);
    });

    test('D25/D26 a Moment keeps its identity and telemetry with media',
        () async {
      await start('r1');
      await moment('m1', 100);
      await finish('r1');
      final without = await load();

      await db.createLocalRecordedRoute(id: 'r2', ownerId: 'me', startedAt: t0);
      await moment('m1b', 100, route: 'r2');
      await photo('p1', 150, route: 'r2', waypointId: 'm1b');
      await finish('r2');
      final withMedia = await load(id: 'r2');

      final a = without.timeline.singleWhere((e) => e.id == 'moment_m1');
      final b = withMedia.timeline.singleWhere((e) => e.id == 'moment_m1b');
      expect(b.moment!.latitude, a.moment!.latitude);
      expect(b.moment!.longitude, a.moment!.longitude);
      expect(b.moment!.altitude, a.moment!.altitude);
      expect(b.moment!.recordedAt, a.moment!.recordedAt);
      expect(
          (await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r2'))
              .single
              .latitude,
          50.5,
          reason: 'attaching a photo wrote nothing to the Moment');
    });

    test('D27 photos never change the Phase 0 statistics', () async {
      Future<void> fixture(String id, {required bool withPhotos}) async {
        await db.createLocalRecordedRoute(id: id, ownerId: 'me', startedAt: t0);
        for (var i = 0; i < 3; i++) {
          await db.appendRoutePoint(
            ownerId: 'me',
            recordedRouteId: id,
            latitude: 50 + i * 0.001,
            longitude: 30,
            altitude: 100.0 + i * 5,
            speed: 1.5,
            recordedAt: at(i * 60),
          );
        }
        if (withPhotos) {
          await photo('p-$id', 30, route: id, lat: 9, lng: 9);
          await photo('q-$id', 90, route: id);
        }
        await finish(id);
      }

      await fixture('plain', withPhotos: false);
      await fixture('photos', withPhotos: true);
      final a = (await load(id: 'plain')).statistics;
      final b = (await load(id: 'photos')).statistics;

      expect(b.totalDistanceMeters, a.totalDistanceMeters);
      expect(b.elapsed, a.elapsed);
      expect(b.moving, a.moving);
      expect(b.paused, a.paused);
      expect(b.averageSpeedMps, a.averageSpeedMps);
      expect(b.maxSpeedMps, a.maxSpeedMps);
      expect(b.elevationGainMeters, a.elevationGainMeters);
      expect(b.elevationLossMeters, a.elevationLossMeters);
      expect(b.paceSecondsPerKilometer, a.paceSecondsPerKilometer);
    });
  });

  group('isolation', () {
    test('D11 tombstoned media is excluded', () async {
      await start('r1');
      await photo('live', 10);
      await photo('gone', 20);
      await (db.update(db.localJourneyMedia)..where((t) => t.id.equals('gone')))
          .write(const LocalJourneyMediaCompanion(
              syncStatus: Value(JourneyMediaSyncStatus.synced)));
      await db.deleteJourneyMedia(
          ownerId: 'me', recordedRouteId: 'r1', id: 'gone');
      await finish('r1');
      final d = await load();

      expect(d.media.map((m) => m.id), ['live']);
      expect(ids(d), contains('media_live'));
      expect(ids(d), isNot(contains('media_gone')));
    });

    test('D13 another Journey\'s media never appears', () async {
      await start('r1');
      await photo('mine', 10, route: 'r1');
      await finish('r1');
      await start('r2'); // one active Journey per owner at a time
      await photo('other-route', 10, route: 'r2');
      await finish('r2');

      expect((await load()).media.map((m) => m.id), ['mine']);
    });

    test(
        'D12 another owner\'s media rows never appear, even if one carries '
        'this route id', () async {
      await start('r1');
      await photo('mine', 10);
      await db.createLocalRecordedRoute(
          id: 'rx', ownerId: 'other', startedAt: t0);
      await photo('theirs', 10, route: 'rx', owner: 'other');
      // A corrupt/hostile row: another owner but this route id. Inserted
      // below the validated API to prove the read scoping on its own.
      await db
          .into(db.localJourneyMedia)
          .insert(LocalJourneyMediaCompanion.insert(
            id: 'forged',
            ownerId: 'other',
            recordedRouteId: 'r1',
            capturedAt: at(5),
            localRelativePath: 'journey_media/r1/forged.jpg',
            createdAt: t0,
            updatedAt: t0,
          ));
      await finish('r1');
      final d = await load();

      expect(d.media.map((m) => m.id), ['mine']);
      expect(ids(d), isNot(contains('media_forged')));
      expect(ids(d), isNot(contains('media_theirs')));
    });
  });

  group('Timeline ordering', () {
    test(
        'D09 equal timestamps: Moment, then standalone photos by id, with '
        'the Journey start first and finish last', () async {
      await start('r1');
      await moment('m1', 100);
      await photo('z', 100);
      await photo('a', 100);
      await finish('r1', sec: 100);
      final d = await load();

      expect(ids(d), [
        d.timeline.first.id, // started
        'moment_m1',
        'media_a',
        'media_z',
        d.timeline.last.id, // finished
      ]);
      expect(d.timeline.first.kind, GpsTimelineEntryKind.started);
      expect(d.timeline.last.kind, GpsTimelineEntryKind.finished);
    });

    test('D10 ordering is independent of the input order', () async {
      await start('r1');
      await moment('m1', 100);
      await moment('m2', 100);
      await photo('p1', 100, waypointId: 'm1');
      await photo('p2', 100);
      await photo('p3', 100);
      await photo('p4', 40);
      await db.pauseRecording(ownerId: 'me', routeId: 'r1', occurredAt: at(50));
      await db.resumeRecording(
          ownerId: 'me', routeId: 'r1', occurredAt: at(60));
      await finish('r1');
      final events =
          await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1');
      final moments =
          await db.getWaypoints(ownerId: 'me', recordedRouteId: 'r1');
      final media =
          await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1');

      final forward = buildGpsJourneyTimeline(
          events: events, moments: moments, media: media);
      final reversed = buildGpsJourneyTimeline(
          events: events.reversed.toList(),
          moments: moments.reversed.toList(),
          media: media.reversed.toList());
      final shuffled = buildGpsJourneyTimeline(
          events: [events[2], events[0], events[3], events[1]],
          moments: [moments[1], moments[0]],
          media: [media[2], media[0], media[3], media[1]]);

      expect(reversed.map((e) => e.id), forward.map((e) => e.id));
      expect(shuffled.map((e) => e.id), forward.map((e) => e.id));
      expect(forward.map((e) => e.id).toSet(), hasLength(forward.length),
          reason: 'ids are unique');
      expect(
          forward
              .firstWhere((e) => e.id == 'moment_m1')
              .photos
              .map((p) => p.id),
          ['p1']);
    });

    test(
        'a photo pointing at a Moment that is not present stays visible '
        'as a standalone entry', () async {
      await start('r1');
      await moment('m1', 100);
      await photo('p1', 150, waypointId: 'm1');
      await finish('r1');
      final events =
          await db.getRouteEvents(ownerId: 'me', recordedRouteId: 'r1');
      final media =
          await db.getJourneyMedia(ownerId: 'me', recordedRouteId: 'r1');

      final timeline = buildGpsJourneyTimeline(
          events: events, moments: const [], media: media);

      expect(timeline.map((e) => e.id), contains('media_p1'));
    });

    test('an unknown media type is carried through, not dropped or crashed',
        () async {
      await start('r1');
      await db
          .into(db.localJourneyMedia)
          .insert(LocalJourneyMediaCompanion.insert(
            id: 'v1',
            ownerId: 'me',
            recordedRouteId: 'r1',
            mediaType: const Value('video'),
            capturedAt: at(10),
            localRelativePath: 'journey_media/r1/v1.jpg',
            createdAt: t0,
            updatedAt: t0,
          ));
      await finish('r1');
      final d = await load();

      expect(d.media.single.mediaType, 'video');
      expect(ids(d), contains('media_v1'));
    });
  });

  group('missing files', () {
    test('D14/D16 a missing canonical file never changes or removes the row',
        () async {
      final root = await Directory.systemTemp.createTemp('details_media_');
      addTearDown(() => root.delete(recursive: true));
      final storage = JourneyMediaStorage(rootDirectory: () async => root);
      await start('r1');
      final item = await photo('p1', 10);
      await finish('r1');
      final before = await db.getJourneyMediaItem(
          ownerId: 'me', recordedRouteId: 'r1', id: 'p1');

      final d = await load();
      final file = await storage.existingFile(item.localRelativePath);

      expect(file, isNull, reason: 'the canonical file does not exist');
      expect(d.media.single.id, 'p1');
      expect(
          await db.getJourneyMediaItem(
              ownerId: 'me', recordedRouteId: 'r1', id: 'p1'),
          before,
          reason: 'row unchanged: same sync status and timestamps');
      expect(
          await db.getTombstonedJourneyMedia(
              ownerId: 'me', recordedRouteId: 'r1'),
          isEmpty);
    });
  });

  group('boundaries', () {
    test(
        'D19/D34 media read model and photo widgets use no network, GPS, '
        'recording or absolute-path code', () {
      for (final path in [
        'lib/features/gps/recording/gps_journey_details.dart',
        'lib/features/gps/presentation/gps_journey_details_view.dart',
        'lib/features/gps/presentation/gps_journey_photos.dart',
      ]) {
        final source = File(path).readAsStringSync();
        final imports = source
            .split('\n')
            .where((l) => l.startsWith('import '))
            .join('\n')
            .toLowerCase();
        for (final banned in [
          'supabase',
          'sync/',
          'http',
          'connectivity',
          'geolocator',
          'gps_recording_controller',
          'location_source',
          'image_picker',
        ]) {
          expect(imports, isNot(contains(banned)), reason: path);
        }
        for (final mutation in [
          'insertJourneyMedia',
          'deleteJourneyMedia',
          'markJourneyMediaSynced',
          'writeNew',
          'deleteFile',
          'addImageBytes',
          'getApplicationDocumentsDirectory',
        ]) {
          expect(source, isNot(contains(mutation)), reason: '$path $mutation');
        }
      }
    });
  });
}
