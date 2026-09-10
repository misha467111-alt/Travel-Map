import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/osrm_routing_service.dart';
import '../data/routes_repository.dart';
import '../domain/route.dart';

enum RouteStatus { idle, loading, success, failure }

final savedRoutesProvider = FutureProvider.autoDispose<List<SavedRoute>>(
  (ref) => RoutesRepository(Supabase.instance.client).fetchOwn(),
);

class RouteState {
  const RouteState({
    this.status = RouteStatus.idle,
    this.start,
    this.end,
    this.points = const [],
    this.distanceMeters,
    this.durationSeconds,
    this.waypoints = const [],
    this.segments = const [],
    this.transportMode = RouteTransportMode.driving,
    this.errorMessage,
  });

  final RouteStatus status;
  final RoutePoint? start;
  final RoutePoint? end;
  final List<RoutePoint> points;
  final double? distanceMeters;
  final double? durationSeconds;
  final List<RoutePoint> waypoints;
  final List<RouteSegment> segments;
  final RouteTransportMode transportMode;
  final String? errorMessage;

  bool get hasRoute => status == RouteStatus.success && points.length >= 2;
  bool get usesFallback => segments.any((segment) => segment.isFallback);
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
  final Map<String, RouteSegment> _segmentCache = {};

  @override
  RouteState build() => const RouteState();

  Future<void> buildRoute({
    required RoutePoint start,
    required RoutePoint end,
  }) =>
      setWaypoints([start, end]);

  Future<void> setWaypoints(List<RoutePoint> waypoints) async {
    final normalized = List<RoutePoint>.unmodifiable(waypoints);
    if (normalized.length < 2) {
      _requestId++;
      state = RouteState(
        start: normalized.isEmpty ? null : normalized.first,
        end: normalized.isEmpty ? null : normalized.last,
        waypoints: normalized,
        transportMode: state.transportMode,
      );
      return;
    }
    final requestId = ++_requestId;
    final mode = state.transportMode;
    state = RouteState(
      status: RouteStatus.loading,
      start: normalized.first,
      end: normalized.last,
      waypoints: normalized,
      segments: state.segments,
      transportMode: mode,
    );
    final segments = <RouteSegment>[];
    try {
      for (var index = 0; index < normalized.length - 1; index++) {
        final start = normalized[index];
        final end = normalized[index + 1];
        final key = _cacheKey(start, end, mode);
        final cached = _segmentCache[key];
        if (cached != null) {
          segments.add(cached);
          continue;
        }
        try {
          final route = await ref.read(routingServiceProvider).buildRoute(
                start: start,
                end: end,
                transportMode: mode,
              );
          final segment = RouteSegment(
            start: start,
            end: end,
            points: route.points,
            distanceMeters: route.distanceMeters,
            durationSeconds: route.durationSeconds,
          );
          _segmentCache[key] = segment;
          segments.add(segment);
        } catch (_) {
          segments.add(_directFallback(start, end));
        }
      }
      if (requestId != _requestId) return;
      final points = <RoutePoint>[
        for (var index = 0; index < segments.length; index++)
          ...segments[index].points.skip(index == 0 ? 0 : 1),
      ];
      state = RouteState(
        status: RouteStatus.success,
        start: normalized.first,
        end: normalized.last,
        points: List.unmodifiable(points),
        distanceMeters: segments.fold<double>(
            0, (sum, segment) => sum + segment.distanceMeters),
        durationSeconds: segments.fold<double>(
            0, (sum, segment) => sum + segment.durationSeconds),
        waypoints: normalized,
        segments: List.unmodifiable(segments),
        transportMode: mode,
      );
    } catch (error) {
      if (requestId != _requestId) return;
      state = RouteState(
        status: RouteStatus.failure,
        start: normalized.first,
        end: normalized.last,
        waypoints: normalized,
        transportMode: mode,
        errorMessage: error.toString(),
      );
    }
  }

  Future<void> addWaypoint(RoutePoint point) =>
      setWaypoints([...state.waypoints, point]);

  Future<void> removeWaypoint(int index) {
    final next = [...state.waypoints]..removeAt(index);
    return setWaypoints(next);
  }

  Future<void> moveWaypoint(int index, RoutePoint point) {
    final next = [...state.waypoints]..[index] = point;
    return setWaypoints(next);
  }

  Future<void> setTransportMode(RouteTransportMode mode) {
    if (mode == state.transportMode) return Future.value();
    final waypoints = state.waypoints;
    state = RouteState(waypoints: waypoints, transportMode: mode);
    return setWaypoints(waypoints);
  }

  Future<void> restoreWaypoints(
    List<RoutePoint> waypoints, {
    RouteTransportMode transportMode = RouteTransportMode.driving,
  }) {
    state = RouteState(waypoints: waypoints, transportMode: transportMode);
    return setWaypoints(waypoints);
  }

  void clear() {
    _requestId++;
    state = const RouteState();
  }

  String _cacheKey(RoutePoint start, RoutePoint end, RouteTransportMode mode) =>
      '${mode.name}:${start.latitude.toStringAsFixed(6)},${start.longitude.toStringAsFixed(6)}:'
      '${end.latitude.toStringAsFixed(6)},${end.longitude.toStringAsFixed(6)}';

  RouteSegment _directFallback(RoutePoint start, RoutePoint end) {
    const earthRadius = 6371000.0;
    final lat1 = start.latitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final deltaLat = (end.latitude - start.latitude) * math.pi / 180;
    final deltaLng = (end.longitude - start.longitude) * math.pi / 180;
    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final distance =
        earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return RouteSegment(
      start: start,
      end: end,
      points: [start, end],
      distanceMeters: distance,
      durationSeconds: distance / 1.35,
      isFallback: true,
    );
  }
}
