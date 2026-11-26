import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gps/local/gps_local_database.dart' show RecordedRouteStatus;
import '../../gps/local/gps_local_database_provider.dart';
import '../../gps/recording/gps_journey_statistics.dart';
import '../../gps/recording/gps_track_quality.dart';

/// Phase 3.4-B1 -- everything the profile shows about ONE finished Journey,
/// read from the owner's local Drift data ONCE: the canonical statistics (the
/// same [calculateGpsJourneyStatistics] the Summary uses, so the numbers are
/// identical) and the outline of the CONFIRMED track as separate runs.
///
/// Read-only. The recorder, the replay and the analysis algorithm are
/// untouched: [analyzeGpsTrack] / [calculateGpsJourneyStatistics] are only
/// called.
typedef SketchPoint = ({double lat, double lon});

/// One uninterrupted stretch of the confirmed track. Two runs are NEVER joined:
/// a long signal gap or an unconfirmed jump separates them.
typedef SketchRun = List<SketchPoint>;

/// At most this many points are kept for the whole outline (spread over its
/// runs).
const int routeSketchMaxPoints = 120;

/// A track whose longest side is shorter than this is GPS noise around one
/// spot, not a route: it is never stretched to fill the panel.
const double routeSketchMinExtentMeters = 30;

/// A very long run is pre-thinned to this many points before it is simplified,
/// so the work per Journey stays bounded.
const int _preThinCap = 3000;

const double _metersPerDegree = 111194.9266; // pi / 180 * 6371000

/// Longest side, in metres, of the bounding box of all [runs] (0 for none).
double sketchExtentMeters(List<SketchRun> runs) {
  double? minLat, maxLat, minLon, maxLon;
  for (final run in runs) {
    for (final p in run) {
      minLat = minLat == null ? p.lat : math.min(minLat, p.lat);
      maxLat = maxLat == null ? p.lat : math.max(maxLat, p.lat);
      minLon = minLon == null ? p.lon : math.min(minLon, p.lon);
      maxLon = maxLon == null ? p.lon : math.max(maxLon, p.lon);
    }
  }
  if (minLat == null || maxLat == null || minLon == null || maxLon == null) {
    return 0;
  }
  final latSpan = (maxLat - minLat) * _metersPerDegree;
  final lonSpan = (maxLon - minLon) *
      _metersPerDegree *
      math.cos((minLat + maxLat) / 2 * math.pi / 180);
  return math.max(latSpan, lonSpan);
}

/// Whether [runs] are too small (or too few points) to be a drawable route.
/// A track of exactly [routeSketchMinExtentMeters] is drawn.
bool isSketchTooSmall(List<SketchRun> runs) {
  final count = runs.fold<int>(0, (sum, run) => sum + run.length);
  if (count < 2) return true;
  return sketchExtentMeters(runs) + 1e-6 < routeSketchMinExtentMeters;
}

/// Reduces one [run] to at most [maxPoints] points with Ramer-Douglas-Peucker
/// (so the characteristic turns are kept, unlike an even stride), always
/// keeping the first and the last point. Pure.
SketchRun simplifySketchRun(SketchRun run,
    {int maxPoints = routeSketchMaxPoints}) {
  if (maxPoints < 2 || run.length <= maxPoints) return run;
  var work = run;
  if (work.length > _preThinCap) {
    final last = work.length - 1;
    work = [
      for (var i = 0; i < _preThinCap; i++)
        run[((i * last) / (_preThinCap - 1)).round()],
    ];
  }
  var minLat = work.first.lat, maxLat = work.first.lat;
  for (final p in work) {
    minLat = math.min(minLat, p.lat);
    maxLat = math.max(maxLat, p.lat);
  }
  final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
  final xs = [for (final p in work) p.lon * k * _metersPerDegree];
  final ys = [for (final p in work) p.lat * _metersPerDegree];
  var epsilon = 0.5;
  for (var attempt = 0; attempt < 40; attempt++) {
    final keep = _douglasPeucker(xs, ys, epsilon);
    final kept = keep.where((e) => e).length;
    if (kept <= maxPoints) {
      return [
        for (var i = 0; i < work.length; i++)
          if (keep[i]) work[i],
      ];
    }
    epsilon *= 1.5;
  }
  // Not reachable in practice (the tolerance outgrows any track); even stride.
  final last = work.length - 1;
  return [
    for (var i = 0; i < maxPoints; i++)
      work[((i * last) / (maxPoints - 1)).round()],
  ];
}

List<bool> _douglasPeucker(List<double> xs, List<double> ys, double epsilon) {
  final n = xs.length;
  final keep = List<bool>.filled(n, false);
  keep[0] = true;
  keep[n - 1] = true;
  final stack = <(int, int)>[(0, n - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    if (b <= a + 1) continue;
    var farthest = -1.0;
    var index = -1;
    for (var i = a + 1; i < b; i++) {
      final d = _distanceToSegment(xs[i], ys[i], xs[a], ys[a], xs[b], ys[b]);
      if (d > farthest) {
        farthest = d;
        index = i;
      }
    }
    if (farthest > epsilon && index > 0) {
      keep[index] = true;
      stack
        ..add((a, index))
        ..add((index, b));
    }
  }
  return keep;
}

double _distanceToSegment(
    double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) {
    return math.sqrt(math.pow(px - ax, 2) + math.pow(py - ay, 2));
  }
  final t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt(math.pow(px - cx, 2) + math.pow(py - cy, 2));
}

/// Simplifies every run on its own (never merging two), sharing the total point
/// budget [maxPoints] in proportion to the run lengths (at least 2 each).
List<SketchRun> buildSketchRuns(List<SketchRun> runs,
    {int maxPoints = routeSketchMaxPoints}) {
  final total = runs.fold<int>(0, (sum, run) => sum + run.length);
  if (total == 0) return const [];
  return [
    for (final run in runs)
      if (run.isNotEmpty)
        simplifySketchRun(run,
            maxPoints: math.max(2, (maxPoints * run.length / total).round())),
  ];
}

class ProfileJourneyData {
  const ProfileJourneyData({required this.statistics, required this.runs});

  /// The canonical statistics (confirmed distance, moving time, ...).
  final GpsJourneyStatistics statistics;

  /// The confirmed track as separate, simplified runs.
  final List<SketchRun> runs;
}

/// The profile data of one FINISHED Journey of [ownerId]; `null` if the route
/// is missing, not finished or not this owner's. Loaded once (the points are
/// read once and analysed here), off the build path, and shared by the
/// Journey cards and the profile totals. A finished Journey never changes, so
/// the result is valid for as long as it is watched.
final profileJourneyDataProvider = FutureProvider.autoDispose
    .family<ProfileJourneyData?, ({String ownerId, String routeId})>(
        (ref, args) async {
  final db = ref.watch(gpsLocalDatabaseProvider);
  final route =
      await db.getRecordedRoute(ownerId: args.ownerId, id: args.routeId);
  if (route == null || route.status != RecordedRouteStatus.completed) {
    return null;
  }
  final points = await db.getRoutePoints(
      ownerId: args.ownerId, recordedRouteId: args.routeId);
  final events = await db.getRouteEvents(
      ownerId: args.ownerId, recordedRouteId: args.routeId);
  final statistics = calculateGpsJourneyStatistics(
    points: points,
    events: events,
    now: DateTime.now().toUtc(),
  );
  final runs = [
    for (final run in analyzeGpsTrack(points).trustedRuns())
      [for (final p in run) (lat: p.latitude, lon: p.longitude)],
  ];
  return ProfileJourneyData(
      statistics: statistics, runs: buildSketchRuns(runs));
});
