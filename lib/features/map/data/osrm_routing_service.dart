import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/route.dart';

class RoutingException implements Exception {
  const RoutingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OsrmRoutingService {
  const OsrmRoutingService(this._client);

  final http.Client _client;

  Future<CalculatedRoute> buildRoute({
    required RoutePoint start,
    required RoutePoint end,
  }) async {
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/'
          '${start.longitude},${start.latitude};'
          '${end.longitude},${end.latitude}',
      const {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      },
    );

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 20));
    } catch (error) {
      throw RoutingException(
          'Не вдалося з’єднатися із сервісом маршрутів: $error');
    }

    if (response.statusCode != 200) {
      throw RoutingException(
        'Сервіс маршрутів повернув помилку ${response.statusCode}.',
      );
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code'] != 'Ok') {
        throw RoutingException(
          json['message'] as String? ?? 'Маршрут між цими точками не знайдено.',
        );
      }
      final routes = json['routes'] as List<dynamic>;
      if (routes.isEmpty) {
        throw const RoutingException('Маршрут між цими точками не знайдено.');
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List<dynamic>;
      final points = coordinates.map((coordinate) {
        final pair = coordinate as List<dynamic>;
        return RoutePoint(
          latitude: (pair[1] as num).toDouble(),
          longitude: (pair[0] as num).toDouble(),
        );
      }).toList(growable: false);
      if (points.length < 2) {
        throw const RoutingException(
            'Сервіс повернув некоректну геометрію маршруту.');
      }

      return CalculatedRoute(
        points: points,
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toDouble(),
      );
    } on RoutingException {
      rethrow;
    } catch (_) {
      throw const RoutingException(
          'Не вдалося прочитати відповідь сервісу маршрутів.');
    }
  }
}
