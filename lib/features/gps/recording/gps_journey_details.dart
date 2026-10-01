import '../local/gps_local_database.dart';
import 'gps_journey_statistics.dart';

/// Journey Phase 1G -- the kinds of Timeline entry. Exactly the persisted
/// lifecycle events that can occur in a completed Journey, plus Moments.
/// `RouteEventType.discard` is deliberately not represented: a completed
/// Journey never has one, and nothing is fabricated for it.
enum GpsTimelineEntryKind { started, paused, resumed, moment, finished }

/// One chronological Timeline entry. [id] is stable across rebuilds
/// (`event_<seq>` / `moment_<waypointId>`), so it can key list rows today
/// and correlate with route points in a future Replay.
class GpsTimelineEntry {
  const GpsTimelineEntry._({
    required this.id,
    required this.kind,
    required this.timestamp,
    this.moment,
  });

  final String id;
  final GpsTimelineEntryKind kind;

  /// The persisted, untouched timestamp (UTC as stored).
  final DateTime timestamp;

  /// Set only for [GpsTimelineEntryKind.moment]: the persisted waypoint
  /// (type/title/note/coordinates/time), read-only here.
  final LocalWaypoint? moment;
}

int _kindRank(GpsTimelineEntryKind kind) => switch (kind) {
      GpsTimelineEntryKind.started => 0,
      GpsTimelineEntryKind.paused => 1,
      GpsTimelineEntryKind.resumed => 1,
      GpsTimelineEntryKind.moment => 2,
      GpsTimelineEntryKind.finished => 3,
    };

/// Builds the chronological Timeline from persisted [events] and [moments].
///
/// Ordering is total and deterministic, independent of input order:
///   1. `timestamp` ascending;
///   2. for equal timestamps, kind rank: `started`, then pause/resume
///      events, then Moments, then `finished` -- so a Journey always opens
///      with its start and closes with its finish;
///   3. among pause/resume events with equal timestamps, the persisted
///      event `seq` (the append-only log's own order);
///   4. among Moments with equal timestamps, the waypoint `id`.
///
/// Only persisted `start`/`pause`/`resume`/`finish` events become entries;
/// pause/resume are shown exactly as logged (not collapsed or inferred).
///
/// Complexity: O(n) to project plus O(n log n) to sort, n = events + Moments.
List<GpsTimelineEntry> buildGpsJourneyTimeline({
  required List<LocalRouteEvent> events,
  required List<LocalWaypoint> moments,
}) {
  // `tieSeq` orders pause/resume events; `tieId` orders Moments.
  final items = <({GpsTimelineEntry entry, int tieSeq, String tieId})>[];
  for (final event in events) {
    final kind = switch (event.eventType) {
      RouteEventType.start => GpsTimelineEntryKind.started,
      RouteEventType.pause => GpsTimelineEntryKind.paused,
      RouteEventType.resume => GpsTimelineEntryKind.resumed,
      RouteEventType.finish => GpsTimelineEntryKind.finished,
      _ => null,
    };
    if (kind == null) continue;
    items.add((
      entry: GpsTimelineEntry._(
        id: 'event_${event.seq}',
        kind: kind,
        timestamp: event.occurredAt,
      ),
      tieSeq: event.seq,
      tieId: '',
    ));
  }
  for (final moment in moments) {
    items.add((
      entry: GpsTimelineEntry._(
        id: 'moment_${moment.id}',
        kind: GpsTimelineEntryKind.moment,
        timestamp: moment.recordedAt,
        moment: moment,
      ),
      tieSeq: 0,
      tieId: moment.id,
    ));
  }

  items.sort((a, b) {
    final byTime = a.entry.timestamp.compareTo(b.entry.timestamp);
    if (byTime != 0) return byTime;
    final byRank = _kindRank(a.entry.kind).compareTo(_kindRank(b.entry.kind));
    if (byRank != 0) return byRank;
    final bySeq = a.tieSeq.compareTo(b.tieSeq);
    if (bySeq != 0) return bySeq;
    return a.tieId.compareTo(b.tieId);
  });
  return List.unmodifiable([for (final i in items) i.entry]);
}

/// The canonical read model for ONE completed Journey: the persisted route,
/// its ordered points, its Moments, Phase 0 statistics and the Timeline.
/// Composed on read from Drift -- nothing here is persisted or cached.
class GpsJourneyDetails {
  const GpsJourneyDetails({
    required this.route,
    required this.points,
    required this.moments,
    required this.statistics,
    required this.timeline,
  });

  final LocalRecordedRoute route;

  /// Route points in canonical recording order (`seq` ascending),
  /// unmodified, unsimplified. Together with [timeline] this is the shape a
  /// future Replay correlates (point `recordedAt` vs entry `timestamp`).
  final List<LocalRoutePoint> points;

  /// Non-tombstoned Moments, oldest first.
  final List<LocalWaypoint> moments;

  final GpsJourneyStatistics statistics;
  final List<GpsTimelineEntry> timeline;
}

/// Loads [GpsJourneyDetails] entirely from local Drift data, scoped by
/// [ownerId] + [routeId]. Returns `null` for an unknown route, another
/// owner's route, or any route that is not `completed` (recording, paused
/// and discarded Journeys never expose Details).
///
/// Statistics come from the canonical [calculateGpsJourneyStatistics];
/// this function adds no formulas of its own. [now] is only the engine's
/// fallback boundary and is ignored for a completed Journey.
Future<GpsJourneyDetails?> loadGpsJourneyDetails({
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
  return GpsJourneyDetails(
    route: route,
    points: points,
    moments: moments,
    statistics: calculateGpsJourneyStatistics(
      points: points,
      events: events,
      now: now,
    ),
    timeline: buildGpsJourneyTimeline(events: events, moments: moments),
  );
}
