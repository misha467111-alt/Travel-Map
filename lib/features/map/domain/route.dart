class RoutePoint {
  const RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
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
