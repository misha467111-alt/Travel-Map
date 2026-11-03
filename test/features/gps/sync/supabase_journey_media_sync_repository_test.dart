import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/sync/data/supabase_journey_media_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/domain/journey_media_sync_repository.dart';
import 'package:flutter_application_1/features/gps/sync/journey_media_sync.dart';

/// Repository-level contract tests against a real [SupabaseClient] whose
/// HTTP layer is a [MockClient] -- so request shape and the installed
/// storage/postgrest clients' real error parsing are exercised, with no
/// network and no hosted service.
void main() {
  const owner = '00000000-0000-4000-8000-000000000900';
  const route = '00000000-0000-4000-8000-000000000001';
  const media = '00000000-0000-4000-8000-000000000101';
  const objectPath = '$owner/$route/$media.jpg';
  final jpegBytes =
      Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 0xFF, 0xD9]);

  late List<http.Request> requests;
  late FutureOr<http.Response> Function(http.Request request) handler;

  SupabaseJourneyMediaSyncRepository repository() {
    final client = SupabaseClient(
      'https://unit-test.supabase.invalid',
      'unit-test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await handler(request);
        // Real responses carry their request (postgrest reads it).
        return http.Response.bytes(response.bodyBytes, response.statusCode,
            headers: response.headers, request: request);
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return SupabaseJourneyMediaSyncRepository(client);
  }

  http.Response json(Object body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  http.Response storageError(int outer, Map<String, String> body) =>
      json(body, outer);

  Future<JourneyMediaSyncException> uploadFailure() async {
    try {
      await repository().uploadObject(objectPath: objectPath, bytes: jpegBytes);
    } on JourneyMediaSyncException catch (error) {
      return error;
    }
    fail('expected a JourneyMediaSyncException');
  }

  Map<String, dynamic> storedRow({
    String? waypointId,
    Object? position = '0101000020E6100000E5D022DBF9863E406F8104C58F394940',
    String capturedAt = '2026-03-01T09:00:00+00:00',
  }) =>
      {
        'id': media,
        'recorded_route_id': route,
        'owner_id': owner,
        'waypoint_id': waypointId,
        'media_type': 'image',
        'captured_at': capturedAt,
        'position': position,
      };

  setUp(() {
    requests = [];
    handler = (_) => http.Response('unexpected', 500);
  });

  test(
      'R01 upload: POST to journey_media/<uid>/<route>/<id>.jpg, x-upsert '
      'false, image/jpeg, local bytes', () async {
    handler = (_) => json({'Key': 'journey_media/$objectPath', 'Id': 'x'}, 200);

    await repository().uploadObject(objectPath: objectPath, bytes: jpegBytes);

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/storage/v1/object/journey_media/$objectPath');
    expect(request.headers['x-upsert'], 'false');
    final body = latin1.decode(request.bodyBytes).toLowerCase();
    expect(body, contains('content-type: image/jpeg'));
    expect(request.bodyBytes.length, greaterThan(jpegBytes.length));

    // A 2xx that does not report exactly our key is not proof.
    handler = (_) => json({'Key': 'journey_media/someone/else.jpg'}, 200);
    final error = await uploadFailure();
    expect(error.kind, JourneyMediaRemoteFailureKind.indeterminate);
  });

  test('R02 an outer HTTP 400 carrying body statusCode 409 is DUPLICATE',
      () async {
    handler = (_) => storageError(400, {
          'statusCode': '409',
          'error': 'Duplicate',
          'message': 'The resource already exists',
        });
    expect(
        (await uploadFailure()).kind, JourneyMediaRemoteFailureKind.duplicate);
  });

  test(
      'R03 body 413/415/invalid key are PERMANENT; body 401, 403 (RLS or '
      'jwt) and 404/NoSuchKey are INDETERMINATE', () async {
    final cases = <Map<String, String>, JourneyMediaRemoteFailureKind>{
      {'statusCode': '413', 'error': 'Payload too large', 'message': 'x'}:
          JourneyMediaRemoteFailureKind.permanent,
      {'statusCode': '415', 'error': 'invalid_mime_type', 'message': 'x'}:
          JourneyMediaRemoteFailureKind.permanent,
      {'statusCode': '400', 'error': 'InvalidKey', 'message': 'Invalid key'}:
          JourneyMediaRemoteFailureKind.permanent,
      {'statusCode': '401', 'error': 'Unauthorized', 'message': 'x'}:
          JourneyMediaRemoteFailureKind.indeterminate,
      {
        'statusCode': '403',
        'error': 'Unauthorized',
        'message': 'new row violates row-level security policy'
      }: JourneyMediaRemoteFailureKind.indeterminate,
      {'statusCode': '403', 'error': 'Unauthorized', 'message': 'jwt expired'}:
          JourneyMediaRemoteFailureKind.indeterminate,
      {'statusCode': '404', 'error': 'not_found', 'message': 'NoSuchKey'}:
          JourneyMediaRemoteFailureKind.indeterminate,
    };
    for (final entry in cases.entries) {
      handler = (_) => storageError(400, entry.key);
      expect((await uploadFailure()).kind, entry.value, reason: '${entry.key}');
    }

    // The same 404 on objectInfo / download is never absence.
    handler = (_) => storageError(
        400, {'statusCode': '404', 'error': 'not_found', 'message': 'x'});
    await expectLater(
        repository().objectInfo(objectPath),
        throwsA(isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
            JourneyMediaRemoteFailureKind.indeterminate)));
    await expectLater(
        repository().downloadObject(objectPath),
        throwsA(isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
            JourneyMediaRemoteFailureKind.indeterminate)));
  });

  test('R04 a 400 without a body statusCode, 429 and 5xx are INDETERMINATE',
      () async {
    for (final response in [
      http.Response('Bad Request', 400),
      json({'error': 'something'}, 400),
      json({'statusCode': '429', 'error': 'too many'}, 429),
      http.Response('<html>bad gateway</html>', 502),
      json({'statusCode': '500', 'error': 'internal'}, 500),
    ]) {
      handler = (_) => response;
      expect((await uploadFailure()).kind,
          JourneyMediaRemoteFailureKind.indeterminate,
          reason: '${response.statusCode} ${response.body}');
    }
  });

  test('R05 raw network failures are INDETERMINATE', () async {
    for (final error in <Object>[
      http.ClientException('connection reset'),
      const SocketException('no route to host'),
      TimeoutException('slow'),
    ]) {
      handler = (_) => throw error;
      expect((await uploadFailure()).kind,
          JourneyMediaRemoteFailureKind.indeterminate,
          reason: '$error');
      await expectLater(
          repository().insertRow(JourneyMediaRowPayload(
            id: media,
            recordedRouteId: route,
            waypointId: null,
            mediaType: 'image',
            capturedAt: DateTime.utc(2026, 3, 1, 9),
            latitude: null,
            longitude: null,
          )),
          throwsA(isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
              JourneyMediaRemoteFailureKind.indeterminate)),
          reason: 'insert $error');
    }
    // Reads (GET) may be retried by the client itself before failing --
    // idempotent, and still INDETERMINATE in the end. One case suffices.
    handler = (_) => throw http.ClientException('connection reset');
    await expectLater(
        repository().selectRow(media),
        throwsA(isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
            JourneyMediaRemoteFailureKind.indeterminate)));
  });

  test(
      'R06 insert never sends owner_id, asks for the stored row back, and '
      'sends position only for standalone media', () async {
    handler = (_) => json([storedRow()], 201);
    final row = await repository().insertRow(JourneyMediaRowPayload(
      id: media,
      recordedRouteId: route,
      waypointId: null,
      mediaType: 'image',
      capturedAt: DateTime.utc(2026, 3, 1, 9),
      latitude: 50.4501,
      longitude: 30.5234,
    ));

    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/rest/v1/route_media');
    expect(request.url.queryParameters['select'],
        'id,recorded_route_id,owner_id,waypoint_id,media_type,captured_at,position');
    expect(request.headers['Prefer'] ?? request.headers['prefer'],
        contains('return=representation'));
    final sent = jsonDecode(request.body) as Map<String, dynamic>;
    expect(sent.containsKey('owner_id'), isFalse);
    expect(sent, {
      'id': media,
      'recorded_route_id': route,
      'media_type': 'image',
      'captured_at': '2026-03-01T09:00:00.000Z',
      'position': 'SRID=4326;POINT(30.5234 50.4501)',
    });
    expect(row.ownerId, owner);

    requests.clear();
    handler = (_) => json([storedRow(waypointId: route, position: null)], 201);
    await repository().insertRow(JourneyMediaRowPayload(
      id: media,
      recordedRouteId: route,
      waypointId: route,
      mediaType: 'image',
      capturedAt: DateTime.utc(2026, 3, 1, 9),
      latitude: null,
      longitude: null,
    ));
    final moment = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(moment['waypoint_id'], route);
    expect(moment.containsKey('position'), isFalse);
    expect(moment.containsKey('owner_id'), isFalse);
  });

  test('R07 PostgREST error codes and empty/odd results are classified',
      () async {
    final payload = JourneyMediaRowPayload(
      id: media,
      recordedRouteId: route,
      waypointId: null,
      mediaType: 'image',
      capturedAt: DateTime.utc(2026, 3, 1, 9),
      latitude: null,
      longitude: null,
    );
    final cases = <Object, JourneyMediaRemoteFailureKind>{
      '23505': JourneyMediaRemoteFailureKind.duplicate,
      '23514': JourneyMediaRemoteFailureKind.permanent,
      '22023': JourneyMediaRemoteFailureKind.permanent,
      '22P02': JourneyMediaRemoteFailureKind.permanent,
      '23503': JourneyMediaRemoteFailureKind.permanent,
      // P2-3: with no session the client sends the anon key and route_media
      // answers 42501 -- indistinguishable from a real rejection.
      '42501': JourneyMediaRemoteFailureKind.indeterminate,
      'PGRST301': JourneyMediaRemoteFailureKind.indeterminate,
      '28000': JourneyMediaRemoteFailureKind.indeterminate,
      'XX000': JourneyMediaRemoteFailureKind.indeterminate,
    };
    for (final entry in cases.entries) {
      handler = (_) => json({
            'code': entry.key,
            'message': 'm',
            'details': null,
            'hint': null,
          }, 400);
      await expectLater(
          repository().insertRow(payload),
          throwsA(isA<JourneyMediaSyncException>()
              .having((e) => e.kind, 'kind', entry.value)),
          reason: '${entry.key}');
    }

    handler = (_) => json(<Object>[], 201);
    await expectLater(
        repository().insertRow(payload),
        throwsA(isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
            JourneyMediaRemoteFailureKind.indeterminate)),
        reason: 'success without the stored row proves nothing');

    handler = (_) => json(<Object>[], 200);
    expect(await repository().selectRow(media), isNull);

    handler = (_) => json([storedRow(), storedRow()], 200);
    await expectLater(
        repository().selectRow(media),
        throwsA(isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
            JourneyMediaRemoteFailureKind.indeterminate)));
  });

  test(
      'R08 positions decode from EWKB (both byte orders, with/without SRID) '
      'and GeoJSON; mismatches are detected; garbage is INDETERMINATE', () {
    String ewkb({required bool littleEndian, required bool srid}) {
      final data = ByteData(srid ? 25 : 21);
      final endian = littleEndian ? Endian.little : Endian.big;
      data.setUint8(0, littleEndian ? 1 : 0);
      data.setUint32(1, srid ? 0x20000001 : 1, endian);
      var offset = 5;
      if (srid) {
        data.setUint32(5, 4326, endian);
        offset = 9;
      }
      data.setFloat64(offset, 30.5234, endian);
      data.setFloat64(offset + 8, 50.4501, endian);
      return data.buffer
          .asUint8List()
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
    }

    for (final position in [
      ewkb(littleEndian: true, srid: true),
      ewkb(littleEndian: false, srid: true),
      ewkb(littleEndian: true, srid: false),
      ewkb(littleEndian: false, srid: false),
      {
        'type': 'Point',
        'coordinates': [30.5234, 50.4501]
      },
    ]) {
      final row = SupabaseJourneyMediaSyncRepository.parseRow(
          storedRow(position: position));
      expect(row.longitude, 30.5234, reason: '$position');
      expect(row.latitude, 50.4501, reason: '$position');
    }
    expect(
        SupabaseJourneyMediaSyncRepository.parseRow(storedRow(position: null))
            .latitude,
        isNull);
    expect(
        () => SupabaseJourneyMediaSyncRepository.parseRow(
            storedRow(position: 'not-a-point')),
        throwsA(isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
            JourneyMediaRemoteFailureKind.indeterminate)));

    final local = LocalJourneyMediaItem(
      id: media,
      ownerId: owner,
      recordedRouteId: route,
      waypointId: null,
      mediaType: 'image',
      capturedAt: DateTime.utc(2026, 3, 1, 9),
      latitude: 50.4501,
      longitude: 30.5234,
      localRelativePath: 'journey_media/$route/$media.jpg',
      syncStatus: JourneyMediaSyncStatus.pending,
      createdAt: DateTime.utc(2026, 3, 1, 9),
      updatedAt: DateTime.utc(2026, 3, 1, 9),
    );
    JourneyMediaRemoteRow remote(
            {double lat = 50.4501, double? lng = 30.5234}) =>
        JourneyMediaRemoteRow(
          id: media,
          recordedRouteId: route,
          ownerId: owner,
          waypointId: null,
          mediaType: 'image',
          capturedAt: DateTime.utc(2026, 3, 1, 9),
          latitude: lng == null ? null : lat,
          longitude: lng,
        );
    expect(JourneyMediaSync.rowMatches(remote(), local, owner), isTrue);
    expect(JourneyMediaSync.rowMatches(remote(lat: 50.4502), local, owner),
        isFalse);
    expect(
        JourneyMediaSync.rowMatches(remote(lng: null), local, owner), isFalse,
        reason: 'position presence must match');
    expect(JourneyMediaSync.rowMatches(remote(), local, '${owner}x'), isFalse,
        reason: 'owner must be the live uid');
  });

  test('R09 row parsing: captured_at is compared as an instant', () {
    for (final text in [
      '2026-03-01T09:00:00+00:00',
      '2026-03-01T11:00:00+02:00',
      '2026-03-01T09:00:00.000000+00:00',
    ]) {
      final row = SupabaseJourneyMediaSyncRepository.parseRow(
          storedRow(capturedAt: text));
      expect(
          row.capturedAt.isAtSameMomentAs(DateTime.utc(2026, 3, 1, 9)), isTrue,
          reason: text);
      expect(row.ownerId, owner);
      expect(row.recordedRouteId, route);
    }
    final shifted = SupabaseJourneyMediaSyncRepository.parseRow(
        storedRow(capturedAt: '2026-03-01T09:00:00.000001+00:00'));
    expect(shifted.capturedAt.isAtSameMomentAs(DateTime.utc(2026, 3, 1, 9)),
        isFalse);
    expect(
        () => SupabaseJourneyMediaSyncRepository.parseRow(
            {...storedRow(), 'owner_id': null}),
        throwsA(isA<JourneyMediaSyncException>()));
  });

  test(
      'R11 B3 objectInfo is proof only for exactly the intended object; '
      'anything else is INDETERMINATE, never success', () async {
    Map<String, dynamic> info({
      String name = objectPath,
      String bucket = 'journey_media',
      bool withVersion = true,
    }) =>
        {
          'id': 'object-id',
          if (withVersion) 'version': 'v1',
          'name': name,
          'bucket_id': bucket,
          'created_at': '2026-03-01T09:00:00Z',
          'size': 8,
          'content_type': 'image/jpeg',
        };

    handler = (_) => json(info(), 200);
    await repository().objectInfo(objectPath);
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path,
        '/storage/v1/object/info/journey_media/$objectPath');

    for (final bad in <Map<String, dynamic>>[
      info(bucket: 'avatars'), // wrong bucket
      info(name: '$media.jpg'), // bare file name, not the full key
      info(name: '$owner/00000000-0000-4000-8000-000000000002/$media.jpg'),
      info(withVersion: false), // malformed success
      {'unexpected': true}, // malformed success
    ]) {
      handler = (_) => json(bad, 200);
      await expectLater(
          repository().objectInfo(objectPath),
          throwsA(isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
              JourneyMediaRemoteFailureKind.indeterminate)),
          reason: '$bad');
    }
  });

  test('R12 download returns exactly the authenticated object bytes', () async {
    handler = (_) => http.Response.bytes(jpegBytes, 200,
        headers: {'content-type': 'image/jpeg'});

    final bytes = await repository().downloadObject(objectPath);

    expect(bytes, jpegBytes);
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path,
        '/storage/v1/object/journey_media/$objectPath');
  });

  test('R13 a TimeoutException is INDETERMINATE', () {
    expect(
        SupabaseJourneyMediaSyncRepository.classify(TimeoutException('slow'))
            .kind,
        JourneyMediaRemoteFailureKind.indeterminate);
  });

  testWidgets(
      'R14 the production bounds: 60 s for transfers, 20 s for metadata; a '
      'stalled call expires exactly then (fake time, no real wait)',
      (tester) async {
    const defaults = JourneyMediaTimeouts();
    expect(defaults.upload, const Duration(seconds: 60));
    expect(defaults.download, const Duration(seconds: 60));
    expect(defaults.info, const Duration(seconds: 20));
    expect(defaults.insert, const Duration(seconds: 20));
    expect(defaults.select, const Duration(seconds: 20));

    for (final (limit, op) in [
      (defaults.upload, 'upload'),
      (defaults.select, 'select'),
    ]) {
      Object? error;
      var done = false;
      unawaited(JourneyMediaSync.bounded(Completer<void>().future, limit, op)
          .then<void>((_) {
        done = true;
      }, onError: (Object e) {
        error = e;
        done = true;
      }));
      await tester.pump(limit - const Duration(seconds: 1));
      expect(done, isFalse, reason: '$op must still be waiting');
      await tester.pump(const Duration(seconds: 2));
      expect(done, isTrue, reason: '$op must have expired');
      expect(
          error,
          isA<JourneyMediaSyncException>().having((e) => e.kind, 'kind',
              JourneyMediaRemoteFailureKind.indeterminate));
    }
  });

  test(
      'R10 static scan: the media sync sources never overwrite, update, '
      'delete, probe existence, sign URLs or use a service key', () {
    final sources = {
      for (final path in [
        'lib/features/gps/sync/journey_media_sync.dart',
        'lib/features/gps/sync/domain/journey_media_sync_repository.dart',
        'lib/features/gps/sync/data/supabase_journey_media_sync_repository.dart',
      ])
        path: File(path).readAsStringSync(),
    };
    for (final entry in sources.entries) {
      for (final banned in [
        'upsert: true',
        '.update(',
        '.upsert(',
        '.delete(',
        '.remove(',
        'exists(',
        'createSignedUrl',
        'service_role',
        'serviceRole',
      ]) {
        expect(entry.value.contains(banned), isFalse,
            reason: '${entry.key} contains $banned');
      }
    }
    expect(
        sources[
            'lib/features/gps/sync/data/supabase_journey_media_sync_repository.dart'],
        contains('upsert: false'));
  });
}
