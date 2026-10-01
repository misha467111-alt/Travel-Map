import '../local/gps_local_database.dart';
import 'gps_journey_statistics.dart';

/// Journey Phase 1E -- the post-finish Summary's domain model. Pure data:
/// every number comes from the canonical Phase 0
/// [calculateGpsJourneyStatistics] over persisted Drift data; nothing here
/// recomputes distance/time/speed/elevation/pace.
class GpsJourneySummary {
  const GpsJourneySummary({
    required this.routeId,
    required this.statistics,
    required this.momentCount,
    required this.pointCount,
  });

  final String routeId;
  final GpsJourneyStatistics statistics;
  final int momentCount;
  final int pointCount;
}

/// Loads the Summary for one *completed* route, entirely from local
/// persisted data (no network, no Supabase). Returns `null` when the
/// route does not exist for [ownerId] or is not `completed` -- a
/// discarded/active route never yields a Summary, and another owner's
/// route is indistinguishable from a missing one.
///
/// Moments are the non-tombstoned local waypoints of this route
/// ([GpsLocalDatabase.getWaypoints] already excludes pending deletes).
/// [now] is only a fallback boundary required by the statistics engine's
/// signature; a completed route always has a `finish` event, so it is
/// ignored for a real completed Journey.
Future<GpsJourneySummary?> loadGpsJourneySummary({
  required GpsLocalDatabase db,
  required String ownerId,
  required String routeId,
  required DateTime now,
}) async {
  final route = await db.getRecordedRoute(ownerId: ownerId, id: routeId);
  if (route == null || route.status != RecordedRouteStatus.completed) {
    return null;
  }
  final points =
      await db.getRoutePoints(ownerId: ownerId, recordedRouteId: routeId);
  final events =
      await db.getRouteEvents(ownerId: ownerId, recordedRouteId: routeId);
  final moments =
      await db.getWaypoints(ownerId: ownerId, recordedRouteId: routeId);
  return GpsJourneySummary(
    routeId: routeId,
    statistics: calculateGpsJourneyStatistics(
      points: points,
      events: events,
      now: now,
    ),
    momentCount: moments.length,
    pointCount: points.length,
  );
}
