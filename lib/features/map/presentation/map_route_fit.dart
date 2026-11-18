import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Phase 2.3 -- the pure logic behind "show the whole route": what to fit
/// ([planRouteFit]), a request to do it ([MapFitRequest]) and the
/// coordinator that runs each request exactly once, whenever the map is
/// ready ([MapFitCoordinator]). No widgets and no map controller here, so
/// the whole lifecycle is unit-testable.

/// How the camera should frame a route.
class MapFitPlan {
  const MapFitPlan.bounds(LatLngBounds this.bounds)
      : center = null,
        zoom = null;
  const MapFitPlan.point(LatLng this.center, {this.zoom = pointZoom})
      : bounds = null;

  /// Zoom used when the route has no extent (all points coincide).
  static const double pointZoom = 16;

  final LatLngBounds? bounds;
  final LatLng? center;
  final double? zoom;

  bool get isPoint => center != null;
}

/// The frame for [points]: their bounding box, or a single centre when they
/// all coincide. `null` for no usable point. Non-finite or out-of-range
/// coordinates are ignored. A route that crosses the antimeridian is framed
/// the short way round (the bounds then have west > east, which Google Maps
/// supports).
MapFitPlan? planRouteFit(Iterable<LatLng> points) {
  final valid = [
    for (final p in points)
      if (p.latitude.isFinite &&
          p.longitude.isFinite &&
          p.latitude >= -90 &&
          p.latitude <= 90 &&
          p.longitude >= -180 &&
          p.longitude <= 180)
        p,
  ];
  if (valid.isEmpty) return null;

  var minLat = valid.first.latitude, maxLat = minLat;
  var minLng = valid.first.longitude, maxLng = minLng;
  for (final p in valid) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLng = math.min(minLng, p.longitude);
    maxLng = math.max(maxLng, p.longitude);
  }

  // Antimeridian: when the plain span is over half the globe, the short way
  // round is the other side. Shift the western points east by 360, then take
  // the extent and wrap it back.
  if (maxLng - minLng > 180) {
    var wMin = double.infinity, wMax = -double.infinity;
    for (final p in valid) {
      final lng = p.longitude < 0 ? p.longitude + 360 : p.longitude;
      wMin = math.min(wMin, lng);
      wMax = math.max(wMax, lng);
    }
    if (wMax - wMin < maxLng - minLng) {
      minLng = wMin > 180 ? wMin - 360 : wMin;
      maxLng = wMax > 180 ? wMax - 360 : wMax;
    }
  }

  const epsilon = 1e-6; // ~0.1 m: no usable extent
  if ((maxLat - minLat).abs() < epsilon &&
      ((maxLng - minLng).abs() < epsilon)) {
    return MapFitPlan.point(LatLng(minLat, minLng));
  }
  return MapFitPlan.bounds(LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  ));
}

/// One request to show a route. A request is identified by [id]: a new id is
/// a new request (a new route, or the "whole route" button), the same id is
/// never run twice.
///
/// [padding] is the comfort margin (logical pixels) the camera leaves on
/// every side. The header and the route card are NOT counted here: they are
/// already excluded from the map's visible area by `GoogleMap.padding`
/// (top and bottom), so adding them again would shrink the route twice.
class MapFitRequest {
  const MapFitRequest(this.id, this.points, {this.padding = defaultPadding});

  static const double defaultPadding = 64;

  final int id;
  final List<LatLng> points;
  final double padding;
}

/// What the coordinator drives: the real map controller in the app, a fake
/// in tests.
abstract class MapCameraPort {
  Future<void> fit(MapFitPlan plan, double padding);
}

/// Runs [MapFitRequest]s against a [MapCameraPort]:
///  - every request id at most once (rebuilds never re-centre the map; only
///    a new id does, e.g. a new route or the "whole route" button);
///  - nothing runs until a port is attached (the map is created and laid
///    out), then the pending request runs;
///  - a failed attempt (for example "map size is 0") is retried on the next
///    idle camera, up to [maxAttempts] times, then dropped;
///  - a cleared or replaced request is never run, even if an older attempt is
///    still in flight.
class MapFitCoordinator {
  static const maxAttempts = 3;

  MapCameraPort? _port;
  MapFitRequest? _request;
  int _handledId = -1;
  int _attempts = 0;
  bool _running = false;

  /// Requests run to completion so far (diagnostics and tests).
  int completedCount = 0;

  /// Sets the current request; `null` cancels (route reset). The same id
  /// again is ignored.
  void request(MapFitRequest? request) {
    if (request == null) {
      _request = null;
      return;
    }
    if (_request?.id == request.id) return;
    _request = request;
    _attempts = 0;
    _tryRun();
  }

  /// The map is ready to take camera commands.
  void attach(MapCameraPort port) {
    _port = port;
    _tryRun();
  }

  void detach() => _port = null;

  /// A camera idle event: a good moment to retry a failed attempt.
  void onCameraIdle() {
    final r = _request;
    if (r != null && r.id != _handledId && _attempts < maxAttempts) _tryRun();
  }

  Future<void> _tryRun() async {
    final r = _request;
    final port = _port;
    if (r == null || port == null || r.id == _handledId || _running) return;
    final plan = planRouteFit(r.points);
    if (plan == null) {
      _handledId = r.id; // nothing to show
      return;
    }
    _running = true;
    _attempts++;
    try {
      await port.fit(plan, r.padding);
      if (_request?.id == r.id) {
        _handledId = r.id;
        completedCount++;
      }
    } catch (_) {
      // Retried from [onCameraIdle].
    } finally {
      _running = false;
    }
    // A newer request arrived while this one was running.
    final next = _request;
    if (next != null && next.id != r.id && next.id != _handledId) {
      _attempts = 0;
      _tryRun();
    }
  }
}

/// The route-camera lifecycle of the Map screen, without widgets: decides
/// WHEN a [MapFitRequest] exists.
///  - a new successful route (or a replaced geometry) becomes pending and is
///    released by the first card measurement after it, so the camera is
///    framed for the final map padding;
///  - a reset, a failure or a loading state cancels everything pending;
///  - [showWhole] issues a fresh request for the same route.
class RouteFitScheduler {
  List<LatLng>? _pending;
  int _id = 0;

  /// The request the map should currently honour (`null`: none).
  MapFitRequest? request;

  /// The route state changed. [success]: a usable route exists; [isNew]: it
  /// is a different route than the previous state (not just a rebuild).
  void routeChanged({
    required bool success,
    required bool isNew,
    required List<LatLng> Function() points,
  }) {
    if (success && isNew) {
      _pending = points();
      request = null;
    } else if (!success) {
      _pending = null;
      request = null;
    }
  }

  /// The route card has been laid out. Returns whether a request was
  /// created (the screen must rebuild to pass it to the map).
  bool cardMeasured() {
    final pending = _pending;
    if (pending == null) return false;
    _pending = null;
    request = MapFitRequest(++_id, pending);
    return true;
  }

  /// The "whole route" action: a new request for [points].
  void showWhole(List<LatLng> points) {
    if (points.isEmpty) return;
    _pending = null;
    request = MapFitRequest(++_id, points);
  }
}
