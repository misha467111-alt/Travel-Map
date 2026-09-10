import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/route.dart';

class SavedRoute {
  const SavedRoute({
    required this.id,
    required this.title,
    required this.points,
    this.transportMode = RouteTransportMode.driving,
  });

  final String id;
  final String title;
  final List<RoutePoint> points;
  final RouteTransportMode transportMode;

  factory SavedRoute.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? const [];
    return SavedRoute(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Маршрут',
      points: rawPoints
          .map((point) =>
              RoutePoint.fromJson(Map<String, dynamic>.from(point as Map)))
          .toList(growable: false),
      transportMode: _parseTransportMode(json['transport_mode']),
    );
  }

  static RouteTransportMode _parseTransportMode(Object? value) {
    if (value == 'walking') return RouteTransportMode.walking;
    if (value == 'cycling') return RouteTransportMode.cycling;
    return RouteTransportMode.driving;
  }
}

class RoutesRepository {
  const RoutesRepository(this._client);

  final SupabaseClient _client;

  Future<SavedRoute> save({
    required String title,
    required List<RoutePoint> points,
    RouteTransportMode transportMode = RouteTransportMode.driving,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Потрібна авторизація.');
    final row = await _client
        .from('routes')
        .insert({
          'title': title,
          'author_id': user.id,
          'points': points.map((point) => point.toJson()).toList(),
          'transport_mode': _transportModeToJson(transportMode),
        })
        .select('id,title,points,transport_mode')
        .single();
    return SavedRoute.fromJson(row);
  }

  Future<List<SavedRoute>> fetchOwn() async {
    final rows = await _client
        .from('routes')
        .select('id,title,points,transport_mode')
        .order('id', ascending: false);
    return rows
        .map((row) => SavedRoute.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  String _transportModeToJson(RouteTransportMode mode) => switch (mode) {
        RouteTransportMode.walking => 'walking',
        RouteTransportMode.driving => 'driving',
        RouteTransportMode.cycling => 'driving',
      };
}
