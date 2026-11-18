import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/features/map/presentation/clustered_location_map.dart';
import 'package:flutter_application_1/features/map/presentation/map_route_fit.dart';

class _FakePort implements MapCameraPort {
  final plans = <MapFitPlan>[];
  final paddings = <double>[];
  Future<void> Function()? onFit;
  int failuresLeft = 0;

  @override
  Future<void> fit(MapFitPlan plan, double padding) async {
    plans.add(plan);
    paddings.add(padding);
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError("Map size can't be 0");
    }
    await onFit?.call();
  }
}

const _a = LatLng(50.0, 30.0);
const _b = LatLng(50.1, 30.2);
const _c = LatLng(49.95, 30.1);

List<LatLng> _route([int n = 3]) => [_a, _c, _b].take(n).toList();

void main() {
  group('planRouteFit', () {
    test('B01 bounds cover every point, turns included', () {
      final plan = planRouteFit([_a, const LatLng(50.2, 29.9), _b, _c])!;
      expect(plan.isPoint, false);
      expect(plan.bounds!.southwest, const LatLng(49.95, 29.9));
      expect(plan.bounds!.northeast, const LatLng(50.2, 30.2));
    });

    test('B02 empty input and invalid coordinates', () {
      expect(planRouteFit(const []), isNull);
      expect(planRouteFit(const [LatLng(double.nan, 1)]), isNull);
      // Invalid points are ignored, valid ones still frame.
      final plan = planRouteFit([const LatLng(double.nan, 1), _a, _b])!;
      expect(plan.bounds!.southwest, _a);
      expect(plan.bounds!.northeast, _b);
    });

    test('B03 coinciding points frame a single centre, not zero bounds', () {
      final plan = planRouteFit(const [_a, _a, _a])!;
      expect(plan.isPoint, true);
      expect(plan.center, _a);
      expect(plan.zoom, MapFitPlan.pointZoom);
      expect(planRouteFit(const [_a])!.isPoint, true);
    });

    test('B04 a straight horizontal or vertical route still has bounds', () {
      final h = planRouteFit(const [LatLng(50, 30), LatLng(50, 30.5)])!;
      expect(h.isPoint, false);
      final v = planRouteFit(const [LatLng(50, 30), LatLng(50.5, 30)])!;
      expect(v.isPoint, false);
    });

    test('B05 two points (the OSRM fallback line) frame both ends', () {
      final plan = planRouteFit(const [_a, _b])!;
      expect(plan.bounds!.contains(_a), true);
      expect(plan.bounds!.contains(_b), true);
    });

    test('B06 a route across the antimeridian is framed the short way', () {
      final plan = planRouteFit(const [
        LatLng(10, 179.5),
        LatLng(11, -179.5),
        LatLng(10.5, 180),
      ])!;
      final b = plan.bounds!;
      expect(b.southwest.longitude, 179.5);
      expect(b.northeast.longitude, -179.5);
      expect(b.contains(const LatLng(10.5, 180)), true);
    });

    test('B07 poles and extreme valid latitudes are accepted', () {
      final plan = planRouteFit(const [LatLng(-90, 0), LatLng(90, 10)])!;
      expect(plan.bounds!.southwest.latitude, -90);
      expect(plan.bounds!.northeast.latitude, 90);
    });
  });

  group('padding', () {
    test('P01 the request carries only the comfort margin', () {
      // The header and the route card are excluded from the visible map by
      // GoogleMap.padding; the camera margin is a separate, fixed value.
      final r = MapFitRequest(1, _route());
      expect(r.padding, MapFitRequest.defaultPadding);
      expect(MapFitRequest.defaultPadding, 64);
    });

    test('P02 the coordinator hands the request padding to the camera',
        () async {
      final port = _FakePort();
      final c = MapFitCoordinator()..attach(port);
      c.request(MapFitRequest(1, _route(), padding: 40));
      await pumpEventQueue();
      expect(port.paddings, [40]);
    });

    testWidgets('P03 top and bottom chrome reach GoogleMap.padding, once',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 360,
          height: 640,
          child: ClusteredLocationMap(
            initialTarget: const LatLng(50, 30),
            userPosition: null,
            locations: const [],
            polylines: const {},
            onLocationTap: (_) {},
            onLongPress: (_) {},
            onViewportChanged: (_) {},
            topMapPadding: 88,
            bottomMapPadding: 140,
            fitRequest: MapFitRequest(1, _route()),
          ),
        ),
      ));
      final p = tester.widget<GoogleMap>(find.byType(GoogleMap)).padding;
      expect(p.top, 88);
      expect(p.bottom, 140);
      expect(p.left, 0);
      expect(p.right, 0);
    });
  });

  group('MapFitCoordinator', () {
    test('C01 nothing runs until the map is ready, then it runs once',
        () async {
      final port = _FakePort();
      final c = MapFitCoordinator();
      c.request(MapFitRequest(1, _route()));
      await pumpEventQueue();
      expect(port.plans, isEmpty);
      c.attach(port);
      await pumpEventQueue();
      expect(port.plans.length, 1);
      expect(c.completedCount, 1);
    });

    test('C02 rebuilds with the same request never re-centre', () async {
      final port = _FakePort();
      final c = MapFitCoordinator()..attach(port);
      final r = MapFitRequest(7, _route());
      for (var i = 0; i < 5; i++) {
        c.request(r);
        c.request(MapFitRequest(7, _route())); // same id, new object
        c.onCameraIdle(); // the user moved the map: idle events
      }
      await pumpEventQueue();
      expect(port.plans.length, 1);
      // Re-attaching (a rebuilt platform view) does not re-run a handled id.
      c.detach();
      c.attach(port);
      await pumpEventQueue();
      expect(port.plans.length, 1);
    });

    test('C03 the whole-route button (a new id) frames again', () async {
      final port = _FakePort();
      final c = MapFitCoordinator()..attach(port);
      c.request(MapFitRequest(1, _route()));
      await pumpEventQueue();
      c.onCameraIdle(); // manual pan: no re-centre
      await pumpEventQueue();
      expect(port.plans.length, 1);
      c.request(MapFitRequest(2, _route())); // "Увесь маршрут"
      await pumpEventQueue();
      expect(port.plans.length, 2);
    });

    test('C04 a reset cancels a pending request', () async {
      final port = _FakePort();
      final c = MapFitCoordinator();
      c.request(MapFitRequest(1, _route()));
      c.request(null); // route reset before the map was ready
      c.attach(port);
      await pumpEventQueue();
      expect(port.plans, isEmpty);
    });

    test('C05 a request replaced while running: only the new one remains',
        () async {
      final gate = Completer<void>();
      final port = _FakePort()..onFit = () => gate.future;
      final c = MapFitCoordinator()..attach(port);
      c.request(MapFitRequest(1, _route(2)));
      await pumpEventQueue();
      expect(port.plans.length, 1);
      c.request(MapFitRequest(2, _route(3))); // new route replaces it
      port.onFit = null;
      gate.complete();
      await pumpEventQueue();
      expect(port.plans.length, 2);
      expect(c.completedCount, 1, reason: 'the stale one is not counted');
      c.onCameraIdle();
      await pumpEventQueue();
      expect(port.plans.length, 2);
    });

    test('C06 a reset during an animation: the stale one never completes',
        () async {
      final gate = Completer<void>();
      final port = _FakePort()..onFit = () => gate.future;
      final c = MapFitCoordinator()..attach(port);
      c.request(MapFitRequest(1, _route()));
      await pumpEventQueue();
      c.request(null);
      gate.complete();
      await pumpEventQueue();
      expect(c.completedCount, 0);
      c.onCameraIdle();
      await pumpEventQueue();
      expect(port.plans.length, 1, reason: 'no new camera command');
    });

    test('C07 a failed animation is retried on idle, then stops', () async {
      final port = _FakePort()..failuresLeft = 99;
      final c = MapFitCoordinator()..attach(port);
      c.request(MapFitRequest(1, _route()));
      await pumpEventQueue();
      for (var i = 0; i < 10; i++) {
        c.onCameraIdle();
        await pumpEventQueue();
      }
      expect(port.plans.length, MapFitCoordinator.maxAttempts);
      expect(c.completedCount, 0);
    });

    test('C08 a transient failure succeeds on the retry, exactly once',
        () async {
      final port = _FakePort()..failuresLeft = 1;
      final c = MapFitCoordinator()..attach(port);
      c.request(MapFitRequest(1, _route()));
      await pumpEventQueue();
      expect(c.completedCount, 0);
      c.onCameraIdle();
      await pumpEventQueue();
      expect(c.completedCount, 1);
      c.onCameraIdle();
      await pumpEventQueue();
      expect(port.plans.length, 2);
    });

    test('C09 geometry with nothing to show makes no camera call', () async {
      final port = _FakePort();
      final c = MapFitCoordinator()..attach(port);
      c.request(const MapFitRequest(1, [LatLng(double.nan, double.nan)]));
      await pumpEventQueue();
      expect(port.plans, isEmpty);
    });

    test('C10 a single-point route uses the point framing', () async {
      final port = _FakePort();
      final c = MapFitCoordinator()..attach(port);
      c.request(const MapFitRequest(1, [_a, _a]));
      await pumpEventQueue();
      expect(port.plans.single.isPoint, true);
    });
  });

  group('RouteFitScheduler (screen lifecycle)', () {
    List<LatLng> pts() => _route();

    test('S01 a new successful route waits for the card measurement', () {
      final s = RouteFitScheduler();
      s.routeChanged(success: true, isNew: true, points: pts);
      expect(s.request, isNull);
      expect(s.cardMeasured(), true);
      expect(s.request!.id, 1);
      expect(s.request!.points, pts());
      // Later measurements (text scale change) do not request again.
      expect(s.cardMeasured(), false);
      expect(s.request!.id, 1);
    });

    test('S02 a rebuild of the same route does not request again', () {
      final s = RouteFitScheduler();
      s.routeChanged(success: true, isNew: true, points: pts);
      s.cardMeasured();
      s.routeChanged(success: true, isNew: false, points: pts);
      expect(s.request!.id, 1);
      expect(s.cardMeasured(), false);
    });

    test('S03 reopening the same route (a new state) frames it again', () {
      final s = RouteFitScheduler();
      s.routeChanged(success: true, isNew: true, points: pts);
      s.cardMeasured();
      s.routeChanged(success: false, isNew: false, points: pts); // loading
      expect(s.request, isNull);
      s.routeChanged(success: true, isNew: true, points: pts);
      s.cardMeasured();
      expect(s.request!.id, 2);
    });

    test('S04 a reset or failure cancels a pending request', () {
      final s = RouteFitScheduler();
      s.routeChanged(success: true, isNew: true, points: pts);
      s.routeChanged(success: false, isNew: false, points: pts); // reset
      expect(s.cardMeasured(), false);
      expect(s.request, isNull);
    });

    test('S05 a replaced route (new geometry) cancels the old request', () {
      final s = RouteFitScheduler();
      s.routeChanged(success: true, isNew: true, points: () => _route(2));
      s.cardMeasured();
      expect(s.request!.points.length, 2);
      s.routeChanged(success: true, isNew: true, points: () => _route(3));
      expect(s.request, isNull, reason: 'old one withdrawn until measured');
      s.cardMeasured();
      expect(s.request!.points.length, 3);
      expect(s.request!.id, 2);
    });

    test('S06 "Увесь маршрут" issues a fresh request for the same route', () {
      final s = RouteFitScheduler();
      s.routeChanged(success: true, isNew: true, points: pts);
      s.cardMeasured();
      final first = s.request!.id;
      s.showWhole(pts());
      expect(s.request!.id, first + 1);
      s.showWhole(const []);
      expect(s.request!.id, first + 1, reason: 'nothing to show: ignored');
    });
  });

  group('end to end (scheduler -> coordinator)', () {
    test('E01 new route, manual pan, button, reset', () async {
      final port = _FakePort();
      final coordinator = MapFitCoordinator()..attach(port);
      final scheduler = RouteFitScheduler();
      void sync() => coordinator.request(scheduler.request);

      scheduler.routeChanged(success: true, isNew: true, points: _route);
      scheduler.cardMeasured();
      sync();
      await pumpEventQueue();
      expect(port.plans.length, 1);

      // The user pans and zooms: idle events and rebuilds never re-centre.
      for (var i = 0; i < 4; i++) {
        coordinator.onCameraIdle();
        sync();
      }
      await pumpEventQueue();
      expect(port.plans.length, 1);

      scheduler.showWhole(_route()); // "Увесь маршрут"
      sync();
      await pumpEventQueue();
      expect(port.plans.length, 2);

      scheduler.routeChanged(success: false, isNew: false, points: _route);
      sync(); // reset
      coordinator.onCameraIdle();
      await pumpEventQueue();
      expect(port.plans.length, 2);

      // A brand-new route frames again.
      scheduler.routeChanged(success: true, isNew: true, points: _route);
      scheduler.cardMeasured();
      sync();
      await pumpEventQueue();
      expect(port.plans.length, 3);
    });
  });
}
