class RoutePoint {
  const RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  Map<String, double> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory RoutePoint.fromJson(Map<String, dynamic> json) => RoutePoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}

enum RouteTransportMode { driving, walking, cycling }

class RouteSegment {
  const RouteSegment({
    required this.start,
    required this.end,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.isFallback = false,
  });

  final RoutePoint start;
  final RoutePoint end;
  final List<RoutePoint> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool isFallback;
}

class CalculatedRoute {
  const CalculatedRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<RoutePoint> points;
  final double distanceMeters;
  final double durationSeconds;
}
