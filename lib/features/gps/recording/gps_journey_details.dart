import '../local/gps_local_database.dart';
import 'gps_journey_statistics.dart';

/// Journey Phase 1G/1H-D -- the kinds of Timeline entry: the persisted
/// lifecycle events that can occur in a completed Journey, Moments, and
/// STANDALONE photos (media not attached to a Moment).
/// `RouteEventType.discard` is deliberately not represented: a completed
/// Journey never has one, and nothing is fabricated for it.
enum GpsTimelineEntryKind { started, paused, resumed, moment, media, finished }

/// One chronological Timeline entry. [id] is stable across rebuilds
/// (`event_<seq>` / `moment_<waypointId>` / `media_<mediaId>`), so it can
/// key list rows today and correlate with route points in a future Replay.
class GpsTimelineEntry {
  const GpsTimelineEntry._({
    required this.id,
    required this.kind,
    required this.timestamp,
    this.moment,
    this.photos = const [],
  });

  final String id;
  final GpsTimelineEntryKind kind;

  /// The persisted, untouched timestamp (UTC as stored): the event time, the
  /// Moment's `recordedAt`, or a standalone photo's `capturedAt`.
  final DateTime timestamp;

  /// Set only for [GpsTimelineEntryKind.moment]: the persisted waypoint
  /// (type/title/note/coordinates/time), read-only here.
  final LocalWaypoint? moment;

  /// Media metadata for this entry, `capturedAt` ascending (id tie-break).
  /// For a [GpsTimelineEntryKind.moment] entry: every photo attached to that
  /// Moment (the Moment stays ONE entry however many photos it has). For a
  /// [GpsTimelineEntryKind.media] entry: exactly that one standalone photo.
  /// Empty otherwise. Metadata only -- no file has been touched.
  final List<LocalJourneyMediaItem> photos;
}

int _kindRank(GpsTimelineEntryKind kind) => switch (kind) {
      GpsTimelineEntryKind.started => 0,
      GpsTimelineEntryKind.paused => 1,
      GpsTimelineEntryKind.resumed => 1,
      GpsTimelineEntryKind.moment => 2,
      GpsTimelineEntryKind.media => 3,
      GpsTimelineEntryKind.finished => 4,
    };

int _compareMedia(LocalJourneyMediaItem a, LocalJourneyMediaItem b) {
  final byTime = a.capturedAt.compareTo(b.capturedAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}

/// Builds the chronological Timeline from persisted [events], [moments] and
/// [media].
///
/// Ordering is total and deterministic, independent of input order:
///   1. `timestamp` ascending;
///   2. for equal timestamps, kind rank: `started`, then pause/resume
///      events, then Moments, then standalone photos, then `finished` -- so
///      a Journey always opens with its start and closes with its finish;
///   3. among pause/resume events with equal timestamps, the persisted
///      event `seq` (the append-only log's own order);
///   4. among Moments, and among standalone photos, with equal timestamps,
///      the waypoint / media `id`.
///
/// Media semantics (Phase 1H-D): a Moment with 0..N photos remains ONE
/// Moment entry exposing them in [GpsTimelineEntry.photos]; a photo with no
/// Moment becomes its own `media_<id>` entry stamped with `capturedAt`.
/// A photo whose `waypointId` matches no supplied Moment cannot be shown
/// under it, so it is treated as standalone rather than silently dropped
/// (normal deletion retires a Moment's photos, so this is purely
/// defensive). Photo position/time are never copied from a Moment.
///
/// Only persisted `start`/`pause`/`resume`/`finish` events become entries;
/// pause/resume are shown exactly as logged (not collapsed or inferred).
///
/// Complexity: O(n) to project (photos are grouped by Moment id with one
/// hash map) plus O(n log n) to sort, n = events + Moments + media.
List<GpsTimelineEntry> buildGpsJourneyTimeline({
  required List<LocalRouteEvent> events,
  required List<LocalWaypoint> moments,
  List<LocalJourneyMediaItem> media = const [],
}) {
  // `tieSeq` orders pause/resume events; `tieId` orders Moments and photos.
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

  final momentIds = {for (final m in moments) m.id};
  final attached = <String, List<LocalJourneyMediaItem>>{};
  final standalone = <LocalJourneyMediaItem>[];
  for (final item in media) {
    final waypointId = item.waypointId;
    if (waypointId != null && momentIds.contains(waypointId)) {
      (attached[waypointId] ??= []).add(item);
    } else {
      standalone.add(item);
    }
  }

  for (final moment in moments) {
    final photos = (attached[moment.id] ?? const <LocalJourneyMediaItem>[])
        .toList()
      ..sort(_compareMedia);
    items.add((
      entry: GpsTimelineEntry._(
        id: 'moment_${moment.id}',
        kind: GpsTimelineEntryKind.moment,
        timestamp: moment.recordedAt,
        moment: moment,
        photos: List.unmodifiable(photos),
      ),
      tieSeq: 0,
      tieId: moment.id,
    ));
  }
  for (final item in standalone) {
    items.add((
      entry: GpsTimelineEntry._(
        id: 'media_${item.id}',
        kind: GpsTimelineEntryKind.media,
        timestamp: item.capturedAt,
        photos: List.unmodifiable([item]),
      ),
      tieSeq: 0,
      tieId: item.id,
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
/// its ordered points, its Moments, its photos' metadata, Phase 0
/// statistics and the Timeline. Composed on read from Drift -- nothing here
/// is persisted or cached.
class GpsJourneyDetails {
  const GpsJourneyDetails({
    required this.route,
    required this.points,
    required this.moments,
    required this.statistics,
    required this.timeline,
    this.media = const [],
  });

  final LocalRecordedRoute route;

  /// Route points in canonical recording order (`seq` ascending),
  /// unmodified, unsimplified. Together with [timeline] this is the shape a
  /// future Replay correlates (point `recordedAt` vs entry `timestamp`).
  final List<LocalRoutePoint> points;

  /// Non-tombstoned Moments, oldest first.
  final List<LocalWaypoint> moments;

  /// This owner's, this Journey's non-tombstoned media METADATA
  /// (`capturedAt` ascending, id tie-break): id, owner, route, optional
  /// `waypointId`, `mediaType`, `capturedAt`, optional standalone position
  /// and the canonical RELATIVE path. Local availability of the file is
  /// resolved lazily where a photo is actually shown, never here, so
  /// building this model reads no image file. A future Replay correlates
  /// attached media with their Moment through `waypointId`.
  final List<LocalJourneyMediaItem> media;

  final GpsJourneyStatistics statistics;
  final List<GpsTimelineEntry> timeline;
}

/// Loads [GpsJourneyDetails] entirely from local Drift data, scoped by
/// [ownerId] + [routeId]. Returns `null` for an unknown route, another
/// owner's route, or any route that is not `completed` (recording, paused
/// and discarded Journeys never expose Details).
///
/// Statistics come from the canonical [calculateGpsJourneyStatistics];
/// this function adds no formulas of its own, and media never feeds it.
/// [now] is only the engine's fallback boundary and is ignored for a
/// completed Journey.
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
  // Owner + route scoped; tombstones excluded by the query itself.
  final media =
      await db.getJourneyMedia(ownerId: ownerId, recordedRouteId: routeId);
  return GpsJourneyDetails(
    route: route,
    points: points,
    moments: moments,
    media: media,
    statistics: calculateGpsJourneyStatistics(
      points: points,
      events: events,
      now: now,
    ),
    timeline:
        buildGpsJourneyTimeline(events: events, moments: moments, media: media),
  );
}
