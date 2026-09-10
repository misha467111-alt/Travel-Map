import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application_1/features/map/data/osrm_routing_service.dart';
import 'package:flutter_application_1/features/map/domain/route.dart';
import 'package:flutter_application_1/features/map/providers/route_provider.dart';

class _FakeRoutingService extends OsrmRoutingService {
  _FakeRoutingService({this.fail = false}) : super(http.Client());

  final bool fail;
  int calls = 0;

  @override
  Future<CalculatedRoute> buildRoute({
    required RoutePoint start,
    required RoutePoint end,
    RouteTransportMode transportMode = RouteTransportMode.driving,
  }) async {
    calls++;
    if (fail) throw const RoutingException('unroutable');
    return CalculatedRoute(
      points: [start, end],
      distanceMeters: 1000,
      durationSeconds: 600,
    );
  }
}

void main() {
  const a = RoutePoint(latitude: 50.1, longitude: 30.1);
  const b = RoutePoint(latitude: 50.2, longitude: 30.2);
  const c = RoutePoint(latitude: 50.3, longitude: 30.3);
  const d = RoutePoint(latitude: 50.4, longitude: 30.4);

  test('builds ordered segments and caches unchanged pairs', () async {
    final service = _FakeRoutingService();
    final container = ProviderContainer(overrides: [
      routingServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(routeProvider.notifier);

    await notifier.setWaypoints([a, b, c]);
    final initial = container.read(routeProvider);
    expect(initial.waypoints, [a, b, c]);
    expect(initial.segments.length, 2);
    expect(service.calls, 2);

    await notifier.removeWaypoint(2);
    expect(container.read(routeProvider).waypoints, [a, b]);
    expect(service.calls, 2, reason: 'A→B must come from the segment cache');

    await notifier.addWaypoint(c);
    expect(container.read(routeProvider).waypoints, [a, b, c]);
    expect(service.calls, 2, reason: 'both unchanged pairs are cached');
  });

  test('2 waypoints produce exactly 1 segment: 1→2', () async {
    final service = _FakeRoutingService();
    final container = ProviderContainer(overrides: [
      routingServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);

    await container.read(routeProvider.notifier).setWaypoints([a, b]);
    final segments = container.read(routeProvider).segments;
    expect(segments.length, 1);
    expect(segments[0].start, a);
    expect(segments[0].end, b);
  });

  test('3 waypoints produce exactly 2 segments: 1→2, 2→3', () async {
    final service = _FakeRoutingService();
    final container = ProviderContainer(overrides: [
      routingServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);

    await container.read(routeProvider.notifier).setWaypoints([a, b, c]);
    final segments = container.read(routeProvider).segments;
    expect(segments.length, 2);
    expect(segments[0].start, a);
    expect(segments[0].end, b);
    expect(segments[1].start, b);
    expect(segments[1].end, c);
  });

  test('4 waypoints produce exactly 3 segments: 1→2, 2→3, 3→4', () async {
    final service = _FakeRoutingService();
    final container = ProviderContainer(overrides: [
      routingServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);

    await container.read(routeProvider.notifier).setWaypoints([a, b, c, d]);
    final segments = container.read(routeProvider).segments;
    expect(segments.length, 3);
    expect(segments[0].start, a);
    expect(segments[0].end, b);
    expect(segments[1].start, b);
    expect(segments[1].end, c);
    expect(segments[2].start, c);
    expect(segments[2].end, d);
    expect(
      segments.any((s) => s.start == a && s.end == c),
      isFalse,
      reason: 'must never skip a waypoint (no 1→3 direct segment)',
    );
    expect(
      segments.any((s) => s.start == a && s.end == d),
      isFalse,
      reason: 'must never jump straight from the first to the last waypoint',
    );
  });

  test('removing a middle waypoint rebuilds 1→3→4 and drops 1→2, 2→3',
      () async {
    final service = _FakeRoutingService();
    final container = ProviderContainer(overrides: [
      routingServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(routeProvider.notifier);

    await notifier.setWaypoints([a, b, c, d]);
    await notifier.removeWaypoint(1); // remove b (the middle point)

    final state = container.read(routeProvider);
    expect(state.waypoints, [a, c, d]);
    expect(state.segments.length, 2);
    expect(state.segments[0].start, a);
    expect(state.segments[0].end, c);
    expect(state.segments[1].start, c);
    expect(state.segments[1].end, d);
  });

  test('restoreWaypoints preserves exact saved order and mode', () async {
    final service = _FakeRoutingService();
    final container = ProviderContainer(overrides: [
      routingServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);

    await container.read(routeProvider.notifier).restoreWaypoints(
      [c, a, d, b], // deliberately out-of-geographic-order input
      transportMode: RouteTransportMode.walking,
    );
    final state = container.read(routeProvider);
    expect(state.waypoints, [c, a, d, b],
        reason: 'restore must not reorder/sort the saved points');
    expect(state.transportMode, RouteTransportMode.walking);
    expect(state.segments.length, 3);
    expect(state.segments[0].start, c);
    expect(state.segments[0].end, a);
    expect(state.segments[1].start, a);
    expect(state.segments[1].end, d);
    expect(state.segments[2].start, d);
    expect(state.segments[2].end, b);
  });

  test('uses direct dashed fallback only after routing failure', () async {
    final service = _FakeRoutingService(fail: true);
    final container = ProviderContainer(overrides: [
      routingServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);

    await container.read(routeProvider.notifier).setWaypoints([a, b]);
    final route = container.read(routeProvider);
    expect(route.status, RouteStatus.success);
    expect(route.usesFallback, isTrue);
    expect(route.segments.single.points, [a, b]);
  });
}
