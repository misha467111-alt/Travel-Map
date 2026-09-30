import 'package:geolocator/geolocator.dart' show Geolocator;

import '../local/gps_local_database.dart';

/// Journey Phase 0 -- mirrors `finalize_recorded_route(uuid)`'s own
/// hardcoded literal (`supabase/migrations/202609140002_trips_gps_core.sql`,
/// "skip only when the implied speed exceeds 70 m/s (~252 km/h)"). The
/// server has no named constant for it either; if that literal is ever
/// changed there, this must be updated too.
const gpsImpossibleJumpThresholdMps = 70.0;

/// Journey Phase 0 -- the pure, deterministic Journey statistics result.
/// Field-for-field, this mirrors the derived columns
/// `finalize_recorded_route()` writes onto `recorded_routes`
/// (`total_distance_m`, `moving_time_s`, `avg_speed_mps`,
/// `max_speed_mps`, `elevation_gain_m`, `elevation_loss_m`) -- there is
/// no second, independently-invented definition of any of these numbers.
/// `bounding_box`/`simplified_geometry` (PostGIS geometry) are
/// deliberately out of scope: Phase 0 is statistics only.
class GpsJourneyStatistics {
  const GpsJourneyStatistics({
    required this.totalDistanceMeters,
    required this.elapsed,
    required this.moving,
    required this.paused,
    required this.averageSpeedMps,
    required this.maxSpeedMps,
    required this.elevationGainMeters,
    required this.elevationLossMeters,
  });

  /// Sum of consecutive-point geodesic distances -- see
  /// [calculateGpsJourneyStatistics]'s doc for the exact filtering this
  /// mirrors from `finalize_recorded_route`.
  final double totalDistanceMeters;

  /// The journey timeline: from the earliest `start` event to the latest
  /// `finish`/`discard` event, or the caller's `now` if neither exists
  /// yet (an active recording). Never negative.
  final Duration elapsed;

  /// `elapsed - paused`, clamped to zero. Never negative.
  final Duration moving;

  /// Sum of explicit pause/resume interval durations from the event log.
  /// Never negative.
  final Duration paused;

  /// `totalDistanceMeters / moving.inSeconds`, or null when there is no
  /// moving time to divide by -- mirrors `finalize_recorded_route`
  /// leaving `avg_speed_mps` unset (not zero) in that case.
  final double? averageSpeedMps;

  /// The maximum finite, non-negative per-point reported `speed`, or
  /// null if no point has a valid speed sample -- mirrors
  /// `finalize_recorded_route`'s `max(speed_mps)` over raw points (a
  /// reported-speed maximum, not a speed derived from position deltas).
  final double? maxSpeedMps;

  /// Sum of positive altitude deltas between consecutive
  /// *altitude-present* points (a null-altitude point is skipped, not
  /// treated as a break in the chain -- the next real sample's delta is
  /// still measured against the last real one). Mirrors
  /// `finalize_recorded_route` exactly, including its documented noise
  /// sensitivity ("a naive positive/negative delta sum ... will
  /// overcount on noisy GPS altitude" -- not smoothed here either, by
  /// design, not oversight).
  final double elevationGainMeters;

  /// Sum of the `abs()` of negative altitude deltas, same walk as
  /// [elevationGainMeters].
  final double elevationLossMeters;

  /// Derived, not stored -- deliberately not a field, so there is never
  /// a second, independently-settable source of truth for pace (Phase 0's
  /// own design decision: pace = moving time / distance). Seconds per
  /// kilometer, or null when there is no meaningful distance or moving
  /// time to derive it from (pace is undefined, not zero, for a
  /// stationary or zero-distance journey).
  double? get paceSecondsPerKilometer {
    if (totalDistanceMeters <= 0 || moving.inMicroseconds <= 0) return null;
    final movingSeconds =
        moving.inMicroseconds / Duration.microsecondsPerSecond;
    return movingSeconds / (totalDistanceMeters / 1000);
  }

  /// The result for a route with no recorded `start` event yet -- never
  /// thrown for; a live UI must be able to render *something* safe
  /// before any event exists, unlike `finalize_recorded_route`, which
  /// can safely raise on the same condition because it only ever runs
  /// against a route already known to have one (GPS-3's
  /// `createLocalRecordedRoute` always creates the `start` event in the
  /// same transaction as the route row).
  static const empty = GpsJourneyStatistics(
    totalDistanceMeters: 0,
    elapsed: Duration.zero,
    moving: Duration.zero,
    paused: Duration.zero,
    averageSpeedMps: null,
    maxSpeedMps: null,
    elevationGainMeters: 0,
    elevationLossMeters: 0,
  );
}

/// Journey Phase 0 -- computes [GpsJourneyStatistics] entirely from
/// already-local data. [points]/[events] are expected in the exact shape
/// [GpsLocalDatabase.getRoutePoints]/[GpsLocalDatabase.getRouteEvents]
/// already return (oldest-first, already this owner/route-scoped) --
/// this function does no filtering or re-sorting of its own beyond what
/// is documented below, and trusts the existing event/point semantics as
/// authoritative. Requires no internet, no Supabase, no RPC: entirely
/// offline-first, matching the recording engine's own contract.
///
/// [now] is the caller's own explicit boundary for an active (no
/// `finish`/`discard` event yet) recording -- e.g. `DateTime.now()` from
/// a live preview, or a fixed instant in a test. Deliberately never read
/// internally (no buried `DateTime.now()` call in this file): a
/// finished/discarded route ignores [now] entirely, since its own event
/// timestamp already bounds it, exactly like `finalize_recorded_route`'s
/// `v_finish_at` only falls back to `now()` when neither event exists.
///
/// Deliberate divergences from `finalize_recorded_route`, both required
/// because there is no PostGIS locally:
///   - Distance uses [Geolocator.distanceBetween] (the ellipsoidal/
///     geodesic Vincenty formula -- already the one distance helper this
///     codebase uses elsewhere, see `LocationDetailsContent`'s
///     distance-from-user display in `map_screen.dart`) in place of
///     PostGIS `st_distance` on `geography(Point,4326)`. Both are
///     geodesic-on-ellipsoid calculations, not a naive spherical
///     Haversine -- they agree to a very close tolerance for any real
///     GPS track, not byte-identical, but not a different definition.
///   - `bounding_box`/`simplified_geometry` (PostGIS geometry) are out of
///     scope entirely -- Phase 0 is statistics only, not geometry
///     generation.
GpsJourneyStatistics calculateGpsJourneyStatistics({
  required List<LocalRoutePoint> points,
  required List<LocalRouteEvent> events,
  required DateTime now,
}) {
  DateTime? startAt;
  for (final event in events) {
    if (event.eventType != RouteEventType.start) continue;
    if (startAt == null || event.occurredAt.isBefore(startAt)) {
      startAt = event.occurredAt;
    }
  }
  if (startAt == null) return GpsJourneyStatistics.empty;

  DateTime? finishAt;
  for (final event in events) {
    if (event.eventType != RouteEventType.finish &&
        event.eventType != RouteEventType.discard) {
      continue;
    }
    if (finishAt == null || event.occurredAt.isAfter(finishAt)) {
      finishAt = event.occurredAt;
    }
  }
  finishAt ??= now;

  var elapsed = finishAt.difference(startAt);
  if (elapsed.isNegative) elapsed = Duration.zero;

  final pausedSeconds = _pausedSeconds(events, finishAt);
  final elapsedSeconds =
      elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  final movingSeconds = (elapsedSeconds - pausedSeconds) < 0
      ? 0.0
      : elapsedSeconds - pausedSeconds;

  final walk = _walkPoints(points);
  final averageSpeedMps =
      movingSeconds > 0 ? walk.distanceMeters / movingSeconds : null;

  return GpsJourneyStatistics(
    totalDistanceMeters: walk.distanceMeters,
    elapsed: elapsed,
    moving: Duration(
      microseconds: (movingSeconds * Duration.microsecondsPerSecond).round(),
    ),
    paused: Duration(
      microseconds: (pausedSeconds * Duration.microsecondsPerSecond).round(),
    ),
    averageSpeedMps: averageSpeedMps,
    maxSpeedMps: walk.maxSpeedMps,
    elevationGainMeters: walk.gainMeters,
    elevationLossMeters: walk.lossMeters,
  );
}

/// Mirrors `finalize_recorded_route`'s pause accounting exactly:
/// collapse consecutive same-type pause/resume events (a repeated pause
/// or resume with nothing in between is a no-op), then pair each
/// surviving `pause` with the next `resume` -- or, if none follows
/// (a trailing, never-resumed pause), with [finishAt] -- and sum the
/// resulting durations. O(events) -- a single filter/collapse pass plus
/// one linear scan.
double _pausedSeconds(List<LocalRouteEvent> events, DateTime finishAt) {
  final pauseResumeOnly = events.where((e) =>
      e.eventType == RouteEventType.pause ||
      e.eventType == RouteEventType.resume);

  final collapsed = <LocalRouteEvent>[];
  for (final event in pauseResumeOnly) {
    if (collapsed.isNotEmpty && collapsed.last.eventType == event.eventType) {
      continue;
    }
    collapsed.add(event);
  }

  var pausedSeconds = 0.0;
  for (var i = 0; i < collapsed.length; i++) {
    if (collapsed[i].eventType != RouteEventType.pause) continue;
    final hasResume = i + 1 < collapsed.length &&
        collapsed[i + 1].eventType == RouteEventType.resume;
    final end = hasResume ? collapsed[i + 1].occurredAt : finishAt;
    final seconds = end.difference(collapsed[i].occurredAt).inMicroseconds /
        Duration.microsecondsPerSecond;
    if (seconds > 0) pausedSeconds += seconds;
  }
  return pausedSeconds;
}

class _PointWalkResult {
  const _PointWalkResult({
    required this.distanceMeters,
    required this.maxSpeedMps,
    required this.gainMeters,
    required this.lossMeters,
  });
  final double distanceMeters;
  final double? maxSpeedMps;
  final double gainMeters;
  final double lossMeters;
}

/// One O(points) pass computing distance (with the same impossible-jump
/// and non-positive-duration-segment filtering as
/// `finalize_recorded_route`), max reported speed, and elevation
/// gain/loss together -- deliberately a single loop, not three separate
/// ones, so this stays linear even for a many-thousand-point recording.
_PointWalkResult _walkPoints(List<LocalRoutePoint> points) {
  var distance = 0.0;
  double? maxSpeed;
  var gain = 0.0;
  var loss = 0.0;
  double? previousAltitude;
  LocalRoutePoint? previous;

  for (final point in points) {
    if (previous != null) {
      final segmentSeconds =
          point.recordedAt.difference(previous.recordedAt).inMicroseconds /
              Duration.microsecondsPerSecond;
      // Mirrors `finalize_recorded_route`: a non-positive segment
      // duration (duplicate or out-of-order timestamps) and a segment
      // implying a speed above the impossible-jump threshold are both
      // excluded from the distance sum, never specially handled.
      if (segmentSeconds > 0) {
        final segmentDistance = Geolocator.distanceBetween(
          previous.latitude,
          previous.longitude,
          point.latitude,
          point.longitude,
        );
        if (segmentDistance / segmentSeconds <= gpsImpossibleJumpThresholdMps) {
          distance += segmentDistance;
        }
      }
    }
    previous = point;

    final altitude = point.altitude;
    if (altitude != null && altitude.isFinite) {
      if (previousAltitude != null) {
        final diff = altitude - previousAltitude;
        if (diff > 0) {
          gain += diff;
        } else {
          loss += -diff;
        }
      }
      previousAltitude = altitude;
    }

    final speed = point.speed;
    if (speed != null && speed.isFinite && speed >= 0) {
      if (maxSpeed == null || speed > maxSpeed) maxSpeed = speed;
    }
  }

  return _PointWalkResult(
    distanceMeters: distance,
    maxSpeedMps: maxSpeed,
    gainMeters: gain,
    lossMeters: loss,
  );
}
