import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/osrm_routing_service.dart';
import '../domain/route.dart';

enum RouteStatus { idle, loading, success, failure }

class RouteState {
  const RouteState({
    this.status = RouteStatus.idle,
    this.start,
    this.end,
    this.points = const [],
    this.distanceMeters,
    this.durationSeconds,
    this.errorMessage,
  });

  final RouteStatus status;
  final RoutePoint? start;
  final RoutePoint? end;
  final List<RoutePoint> points;
  final double? distanceMeters;
  final double? durationSeconds;
  final String? errorMessage;

  bool get hasRoute => status == RouteStatus.success && points.length >= 2;
}

final routingHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final routingServiceProvider = Provider<OsrmRoutingService>((ref) {
  return OsrmRoutingService(ref.watch(routingHttpClientProvider));
});

final routeProvider = NotifierProvider<RouteNotifier, RouteState>(
  RouteNotifier.new,
);

class RouteNotifier extends Notifier<RouteState> {
  int _requestId = 0;

  @override
  RouteState build() => const RouteState();

  Future<void> buildRoute({
    required RoutePoint start,
    required RoutePoint end,
  }) async {
    final requestId = ++_requestId;
    state = RouteState(status: RouteStatus.loading, start: start, end: end);
    try {
      final route = await ref.read(routingServiceProvider).buildRoute(
            start: start,
            end: end,
          );
      if (requestId != _requestId) return;
      state = RouteState(
        status: RouteStatus.success,
        start: start,
        end: end,
        points: route.points,
        distanceMeters: route.distanceMeters,
        durationSeconds: route.durationSeconds,
      );
    } catch (error) {
      if (requestId != _requestId) return;
      state = RouteState(
        status: RouteStatus.failure,
        start: start,
        end: end,
        errorMessage: error.toString(),
      );
    }
  }

  void clear() {
    _requestId++;
    state = const RouteState();
  }
}
