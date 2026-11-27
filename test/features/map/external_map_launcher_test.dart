import 'package:flutter_application_1/features/map/presentation/external_map_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3.4-C1: the URL and the launch of "open this coordinate in an
/// external map" are shared by Location Details and (later) "Мої місця".
void main() {
  group('externalMapUri', () {
    test('is the same Google Maps search URL as before the extraction', () {
      final uri = externalMapUri(50.4547, 30.5238);
      expect(uri.toString(),
          'https://www.google.com/maps/search/?api=1&query=50.4547%2C30.5238');
      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search/');
      expect(uri.queryParameters, {'api': '1', 'query': '50.4547,30.5238'});
    });

    test('latitude comes first, longitude second (not swapped)', () {
      final query = externalMapUri(49.9935, 36.2304).queryParameters['query']!;
      expect(query.split(',').first, '49.9935');
      expect(query.split(',').last, '36.2304');
    });

    test('negative coordinates are kept as they are', () {
      expect(externalMapUri(-33.8688, -151.2093).queryParameters['query'],
          '-33.8688,-151.2093');
    });
  });

  group('openExternalMap', () {
    test('passes the real coordinates to the launcher and reports success',
        () async {
      Uri? received;
      final ok = await openExternalMap(49.9935, 36.2304, launcher: (uri) async {
        received = uri;
        return true;
      });
      expect(ok, isTrue);
      expect(received, externalMapUri(49.9935, 36.2304));
    });

    test('a launcher that refuses (false) is reported as not launched',
        () async {
      expect(
          await openExternalMap(1, 2, launcher: (_) async => false), isFalse);
    });

    test('a launcher that throws never throws out: it is "not launched"',
        () async {
      expect(
        await openExternalMap(1, 2,
            launcher: (_) async => throw Exception('no handler')),
        isFalse,
      );
    });

    test('a missing coordinate is never launched', () async {
      var calls = 0;
      Future<bool> launcher(Uri _) async {
        calls++;
        return true;
      }

      expect(await openExternalMap(null, 2, launcher: launcher), isFalse);
      expect(await openExternalMap(1, null, launcher: launcher), isFalse);
      expect(await openExternalMap(null, null, launcher: launcher), isFalse);
      expect(calls, 0);
    });

    test('an invalid coordinate is never launched', () async {
      var calls = 0;
      Future<bool> launcher(Uri _) async {
        calls++;
        return true;
      }

      for (final (lat, lng) in [
        (double.nan, 2.0),
        (1.0, double.nan),
        (double.infinity, 2.0),
        (1.0, double.negativeInfinity),
        (90.1, 2.0),
        (-90.1, 2.0),
        (1.0, 180.1),
        (1.0, -180.1),
      ]) {
        expect(await openExternalMap(lat, lng, launcher: launcher), isFalse,
            reason: '$lat, $lng');
      }
      expect(calls, 0);
    });

    test('the boundary coordinates are launched', () async {
      final seen = <Uri>[];
      Future<bool> launcher(Uri uri) async {
        seen.add(uri);
        return true;
      }

      expect(await openExternalMap(90, 180, launcher: launcher), isTrue);
      expect(await openExternalMap(-90, -180, launcher: launcher), isTrue);
      expect(await openExternalMap(0, 0, launcher: launcher), isTrue);
      expect(seen, hasLength(3));
    });

    test('a synchronously failing launcher is handled too', () async {
      expect(
        await openExternalMap(1, 2, launcher: (_) => throw StateError('boom')),
        isFalse,
      );
    });
  });
}
