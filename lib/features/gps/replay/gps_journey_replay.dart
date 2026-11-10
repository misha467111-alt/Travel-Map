import 'dart:typed_data';

import 'package:geolocator/geolocator.dart' show Geolocator;

import '../local/gps_local_database.dart';
import '../recording/gps_journey_details.dart';
import '../recording/gps_journey_statistics.dart';

/// Journey Phase 1I-A -- the pure replay foundation for ONE completed
/// Journey: an immutable, deterministic [GpsReplayTimeline] that answers
/// "where is the replay at playback time T?" and lists the Moment / photo
/// markers aligned to the same clock.
///
/// Nothing here draws, animates, ticks, subscribes, reads the network or
/// touches the location services. It is built once from already-local
/// Drift data (see [loadGpsJourneyReplay]) and then only queried.
///
/// ### Two clocks
///  - RECORDED (wall) time: the persisted timestamps of points, events,
///    Moments and photos.
///  - PLAYBACK (active) time: a replay position measured from the start of
///    the Journey with every recording pause removed. `Duration.zero` is
///    the `start` event; [GpsReplayTimeline.activeDuration] is the
///    canonical `moving` time.
///
/// ### Pause semantics are NOT re-implemented
/// Pause accounting (collapsing repeated pause/resume, pairing a pause with
/// the next resume or with the finish, ...) lives privately in
/// `gps_journey_statistics.dart` and exposes only totals. Rather than copy
/// it, the wall->active mapping is obtained by asking the canonical
/// [calculateGpsJourneyStatistics] -- in its documented "active recording at
/// `now`" mode -- what the Journey's `moving` time was at each event
/// boundary: `moving(t) = canonical(events recorded by t, now: t).moving`.
/// Between two consecutive boundaries the set of events is fixed, so for a
/// well-formed (chronological) journal `moving` is linear there -- slope 1
/// while running, 0 while paused -- and two probes describe the segment
/// exactly.
///
/// That equivalence is NOT assumed. [GpsReplayTimeline.isConsistentWithStatistics]
/// is true only when it was verified: the lifecycle events are logged in
/// non-decreasing time order, every pause / resume lies inside the Journey
/// window, every finish sits at the window end, the probe chain is
/// continuous at every boundary, every segment is a pure plateau or a
/// pure running stretch, and the axis totals equal the canonical totals.
/// For any other journal (clock rollback, an event stamped before the start
/// or after the finish, out-of-order pause / resume, a finish in the middle)
/// the flag is false: the axis is still deterministic, monotone, never
/// negative and clamped, but between boundaries it may differ from the
/// canonical `moving` time -- do not present it as canonical.
///
/// ### Position semantics (never a fabricated bridge)
/// Samples keep the persisted `seq` order and are never re-sorted. A
/// sample that cannot sit on a monotone time axis is rejected and counted:
///  - non-finite / out-of-range coordinates;
///  - a timestamp strictly AFTER the Journey's finish (never clamped onto the
///    axis end; a sample exactly at the finish is kept);
///  - a timestamp earlier than the previous accepted sample, which is
///    normally the late sample itself -- but when the accepted TAIL is a
///    short run (at most [GpsReplayTimeline.maxSpikeRunLength]) that is
///    contradicted by strictly more later samples, in non-decreasing order
///    and (when the run opens the route) not earlier than the Journey start,
///    the TAIL is rejected instead, so one bad timestamp cannot discard the
///    rest of the route. The rule cannot tell a future-stamped tail from a
///    clock that was corrected backwards when both sides are internally
///    consistent: it keeps the strictly LARGER agreeing group (at most
///    [GpsReplayTimeline.maxSpikeRunLength] samples are ever given up this
///    way, always fewer than are kept, always counted in
///    [GpsReplayDiagnostics.futureSpikePoints], never bridged over).
///    Whenever that evidence is absent the earlier samples are kept, the
///    late one is dropped and the discontinuity is reported
///    ([GpsReplayDiagnostics.outOfOrderPoints]).
/// The segment between two adjacent
/// accepted samples is INTERPOLABLE only if all of these hold:
///  - no sample was dropped between them;
///  - the wall-clock duration is positive;
///  - no recording pause lies inside it (its active duration equals its
///    wall duration);
///  - its implied speed is within [gpsImpossibleJumpThresholdMps] (the
///    same threshold and the same ellipsoidal distance helper the
///    statistics use).
/// Every other segment is a DISCONTINUITY: playback time inside it reports
/// the last known position with [GpsReplayPositionKind.held]; the next
/// sample then appears exactly at its own playback time. A consumer must
/// not draw a line across a held stretch.
///
/// There is deliberately no maximum-gap rule: the canonical statistics have
/// none either, so a long silent gap at a plausible speed is interpolated.
class GpsReplayTimeline {
  GpsReplayTimeline._({
    required this.elapsed,
    required this.activeDuration,
    required this.pausedDuration,
    required this.isConsistentWithStatistics,
    required this.startedAt,
    required this.finishedAt,
    required this.diagnostics,
    required Int64List breakWall,
    required Int64List breakActive,
    required bool hasTimeAxis,
    required int sampleCount,
    required Float64List latitudes,
    required Float64List longitudes,
    required Int64List wallMicros,
    required Int64List activeMicros,
    required Uint8List continuousFromPrevious,
    required List<GpsReplayMarker> markers,
    required Int64List markerActiveMicros,
  })  : _breakWall = breakWall,
        _breakActive = breakActive,
        _hasTimeAxis = hasTimeAxis,
        _count = sampleCount,
        _lat = latitudes,
        _lng = longitudes,
        _wall = wallMicros,
        _active = activeMicros,
        _continuous = continuousFromPrevious,
        markers = List.unmodifiable(markers),
        _markerActive = markerActiveMicros;

  /// Tolerance (microseconds) for comparing durations that the canonical
  /// calculator rounds independently to whole microseconds.
  static const toleranceMicros = 2;

  /// The longest run of consecutive samples that may be rejected as a
  /// future-stamped spike (see the class documentation). A longer run is
  /// never "isolated": it is treated as ambiguous and reported instead.
  static const maxSpikeRunLength = 8;

  /// Builds the timeline from raw persisted data, all of one Journey.
  ///
  /// [route] must be `completed` ([ArgumentError] otherwise). Points, events,
  /// Moments and media that do not belong to `route.ownerId` AND `route.id`
  /// are excluded and counted in [diagnostics]; tombstoned (`pendingDelete`)
  /// Moments / media are excluded too. [points] and [events] are expected in
  /// the shape `getRoutePoints` / `getRouteEvents` return (`seq` ascending)
  /// and are not re-sorted. [now] is only the canonical calculator's
  /// fallback boundary for a Journey with no `finish` event; it is never
  /// read from the clock here.
  factory GpsReplayTimeline.build({
    required LocalRecordedRoute route,
    required List<LocalRoutePoint> points,
    required List<LocalRouteEvent> events,
    List<LocalWaypoint> moments = const [],
    List<LocalJourneyMediaItem> media = const [],
    required DateTime now,
  }) {
    if (route.status != RecordedRouteStatus.completed) {
      throw ArgumentError.value(route.status, 'route.status',
          'a replay is only defined for a completed Journey');
    }

    var foreign = 0;
    var tombstoned = 0;
    bool mine(String ownerId, String routeId) =>
        ownerId == route.ownerId && routeId == route.id;

    final scopedEvents = <LocalRouteEvent>[];
    for (final event in events) {
      if (mine(event.ownerId, event.recordedRouteId)) {
        scopedEvents.add(event);
      } else {
        foreign++;
      }
    }
    final scopedPoints = <LocalRoutePoint>[];
    for (final point in points) {
      if (mine(point.ownerId, point.recordedRouteId)) {
        scopedPoints.add(point);
      } else {
        foreign++;
      }
    }
    final scopedMoments = <LocalWaypoint>[];
    for (final moment in moments) {
      if (!mine(moment.ownerId, moment.recordedRouteId)) {
        foreign++;
      } else if (moment.syncStatus == WaypointSyncStatus.pendingDelete) {
        tombstoned++;
      } else {
        scopedMoments.add(moment);
      }
    }
    final scopedMedia = <LocalJourneyMediaItem>[];
    for (final item in media) {
      if (!mine(item.ownerId, item.recordedRouteId)) {
        foreign++;
      } else if (item.syncStatus == JourneyMediaSyncStatus.pendingDelete) {
        tombstoned++;
      } else {
        scopedMedia.add(item);
      }
    }

    // Canonical totals. `points` is irrelevant to the time totals, so none
    // are passed -- the (more expensive) distance walk is not repeated.
    final totals = calculateGpsJourneyStatistics(
        points: const [], events: scopedEvents, now: now);

    // The documented definition of the Journey window (see
    // GpsJourneyStatistics.elapsed): earliest `start` .. latest
    // `finish`/`discard`, else `now`.
    DateTime? startAt;
    DateTime? latestFinish;
    for (final event in scopedEvents) {
      if (event.eventType == RouteEventType.start) {
        if (startAt == null || event.occurredAt.isBefore(startAt)) {
          startAt = event.occurredAt;
        }
      } else if (event.eventType == RouteEventType.finish ||
          event.eventType == RouteEventType.discard) {
        if (latestFinish == null || event.occurredAt.isAfter(latestFinish)) {
          latestFinish = event.occurredAt;
        }
      }
    }
    final hasAxis = startAt != null;
    final startUs = startAt?.microsecondsSinceEpoch ?? 0;
    var finishUs = (latestFinish ?? now).microsecondsSinceEpoch;
    if (finishUs < startUs) finishUs = startUs;

    // Structural conditions under which the boundary probes below ARE the
    // canonical value (see [isConsistentWithStatistics]):
    //  - the lifecycle events are logged in non-decreasing time order (no
    //    clock rollback, no event stamped before one logged earlier);
    //  - every pause / resume lies inside the Journey window [start, finish];
    //  - every finish / discard sits exactly at the window end (an earlier
    //    one would end the canonical timeline early inside a probe).
    // Under these, every paused interval lies inside the window, the
    // canonical clamp "moving >= 0" never engages, and between two boundaries
    // the moving time is exactly linear with slope 0 or 1.
    var wellFormed = hasAxis;
    if (hasAxis) {
      int? lastUs;
      for (final event in scopedEvents) {
        final type = event.eventType;
        final isPauseResume =
            type == RouteEventType.pause || type == RouteEventType.resume;
        final isFinish =
            type == RouteEventType.finish || type == RouteEventType.discard;
        if (!isPauseResume && !isFinish && type != RouteEventType.start) {
          continue;
        }
        final us = event.occurredAt.microsecondsSinceEpoch;
        if (lastUs != null && us < lastUs) wellFormed = false;
        lastUs = us;
        if (isPauseResume && (us < startUs || us > finishUs)) {
          wellFormed = false;
        }
        if (isFinish && us != finishUs) wellFormed = false;
      }
    }

    // Break points: the Journey window plus every event time inside it.
    var axisExact = true;
    final breakWall = <int>[];
    final breakActive = <int>[];
    if (!hasAxis) {
      breakWall.add(0);
      breakActive.add(0);
    } else {
      final times = <int>{startUs, finishUs};
      for (final event in scopedEvents) {
        final us = event.occurredAt.microsecondsSinceEpoch;
        if (us >= startUs && us <= finishUs) times.add(us);
      }
      final sorted = times.toList()..sort();
      breakWall.addAll(sorted);
      breakActive.add(0);
      var previousEnd = 0; // raw canonical value at the previous boundary
      for (var k = 0; k + 1 < sorted.length; k++) {
        final known = scopedEvents
            .where((e) => e.occurredAt.microsecondsSinceEpoch <= sorted[k])
            .toList(growable: false);
        int movingAt(int wallUs) => calculateGpsJourneyStatistics(
              points: const [],
              events: known,
              now: DateTime.fromMicrosecondsSinceEpoch(wallUs, isUtc: true),
            ).moving.inMicroseconds;
        final atStart = movingAt(sorted[k]);
        final atEnd = movingAt(sorted[k + 1]);
        final dWall = sorted[k + 1] - sorted[k];
        final dActive = atEnd - atStart;
        // Verified, not assumed: the probe chain is continuous across the
        // boundary, and the segment is a plateau (slope 0) or running
        // (slope 1) -- the only shapes the linear mapping can represent.
        if ((atStart - previousEnd).abs() > toleranceMicros) axisExact = false;
        if (dActive.abs() > toleranceMicros &&
            (dActive - dWall).abs() > toleranceMicros) {
          axisExact = false;
        }
        previousEnd = atEnd;
        // Monotone by construction; never negative.
        breakActive.add(atEnd > breakActive.last ? atEnd : breakActive.last);
      }
    }
    final canonicalMoving = totals.moving.inMicroseconds;
    final lastActive = breakActive.last;
    final totalsMatch =
        (lastActive - canonicalMoving).abs() <= toleranceMicros &&
            (finishUs - startUs - totals.elapsed.inMicroseconds).abs() <=
                toleranceMicros;
    // Conservative: true only when EVERY condition holds. Without a start
    // event there is no axis to disagree, so only the (zero) totals count.
    final consistent =
        hasAxis ? (wellFormed && axisExact && totalsMatch) : totalsMatch;
    if (consistent &&
        breakActive.length > 1 &&
        canonicalMoving >= breakActive[breakActive.length - 2]) {
      breakActive[breakActive.length - 1] = canonicalMoving;
    }
    final bw = Int64List.fromList(breakWall);
    final ba = Int64List.fromList(breakActive);

    // Samples.
    var invalidCoordinates = 0;
    var outOfOrder = 0;
    var outsideFinish = 0;
    var futureSpikes = 0;
    final n = scopedPoints.length;
    final capacity = hasAxis ? n : 0;
    final lat = Float64List(capacity);
    final lng = Float64List(capacity);
    final wall = Int64List(capacity);
    final active = Int64List(capacity);
    final continuous = Uint8List(capacity);
    // 0 = continuous, 1 = pause, 2 = impossible jump, 3 = other. Diagnostics
    // are counted from the FINAL samples, so a rejected sample's own
    // segment is never counted.
    final gapKind = Uint8List(capacity);
    // wallOf / usable let a rejection decision look ahead without re-reading
    // the points: usable = valid coordinates AND not after the finish.
    final wallOf = Int64List(capacity);
    final usable = Uint8List(capacity);
    if (hasAxis) {
      for (var i = 0; i < n; i++) {
        final p = scopedPoints[i];
        wallOf[i] = p.recordedAt.microsecondsSinceEpoch;
        usable[i] =
            _isValidCoordinate(p.latitude, p.longitude) && wallOf[i] <= finishUs
                ? 1
                : 0;
      }
    }
    var count = 0;
    var brokenSinceLast = false;
    if (hasAxis) {
      for (var i = 0; i < n; i++) {
        final point = scopedPoints[i];
        if (!_isValidCoordinate(point.latitude, point.longitude)) {
          invalidCoordinates++;
          brokenSinceLast = true;
          continue;
        }
        final wallUs = wallOf[i];
        // Strictly after the Journey's finish: not part of the Journey. It is
        // rejected (never clamped onto the axis end) and breaks continuity.
        if (wallUs > finishUs) {
          outsideFinish++;
          brokenSinceLast = true;
          continue;
        }
        if (count > 0 && wallUs < wall[count - 1]) {
          // Earlier than the last accepted sample. Either THIS sample is late
          // (dropped), or the already-accepted tail is a future-stamped spike
          // that would otherwise poison every later sample. The tail is
          // rejected only when that is demonstrable: it is a short run, and
          // strictly MORE later samples agree with each other and with the
          // sample before the run than the run has members. Anything less
          // clear keeps the earlier-accepted samples and reports a drop.
          final firstLater = _upperBound(wall, count, wallUs);
          final run = count - firstLater;
          if (run <= maxSpikeRunLength &&
              _confirmedBy(
                usable,
                wallOf,
                i,
                run + 1,
                firstLater > 0 ? wall[firstLater - 1] : startUs,
                wall[firstLater],
              )) {
            count = firstLater;
            futureSpikes += run;
            brokenSinceLast = true; // never bridge the rejected spike
          } else {
            outOfOrder++;
            brokenSinceLast = true;
            continue;
          }
        }
        final activeUs = _activeAt(bw, ba, wallUs);
        var kind = 0;
        if (count > 0) {
          final wallDelta = wallUs - wall[count - 1];
          final activeDelta = activeUs - active[count - 1];
          if (brokenSinceLast || wallDelta <= 0 || activeDelta <= 0) {
            kind = 3;
          } else if (wallDelta - activeDelta > toleranceMicros) {
            kind = 1;
          } else {
            final meters = Geolocator.distanceBetween(lat[count - 1],
                lng[count - 1], point.latitude, point.longitude);
            final seconds = wallDelta / Duration.microsecondsPerSecond;
            final speed = meters / seconds;
            if (!(speed.isFinite && speed <= gpsImpossibleJumpThresholdMps)) {
              kind = 2;
            }
          }
        }
        lat[count] = point.latitude;
        lng[count] = point.longitude;
        wall[count] = wallUs;
        active[count] = activeUs;
        gapKind[count] = kind;
        continuous[count] = count > 0 && kind == 0 ? 1 : 0;
        count++;
        brokenSinceLast = false;
      }
    }
    var pauseGaps = 0;
    var jumpGaps = 0;
    var otherGaps = 0;
    for (var i = 1; i < count; i++) {
      switch (gapKind[i]) {
        case 1:
          pauseGaps++;
        case 2:
          jumpGaps++;
        case 3:
          otherGaps++;
      }
    }

    // Markers.
    final markers = <_PendingMarker>[];
    final momentIds = {for (final m in scopedMoments) m.id};
    final attached = <String, List<LocalJourneyMediaItem>>{};
    final standalone = <LocalJourneyMediaItem>[];
    for (final item in scopedMedia) {
      final waypointId = item.waypointId;
      if (waypointId != null && momentIds.contains(waypointId)) {
        (attached[waypointId] ??= []).add(item);
      } else {
        // Same rule as the Timeline: a photo whose Moment is not part of
        // this Journey is shown standalone rather than silently dropped.
        standalone.add(item);
      }
    }
    for (final moment in scopedMoments) {
      final photos = (attached[moment.id] ?? const <LocalJourneyMediaItem>[])
          .toList()
        ..sort(_compareMedia);
      final us = moment.recordedAt.microsecondsSinceEpoch;
      markers.add(_PendingMarker(
        wallUs: us,
        rank: 0,
        marker: GpsReplayMarker._(
          id: 'moment_${moment.id}',
          kind: GpsReplayMarkerKind.moment,
          recordedAt: DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true),
          playbackTime:
              Duration(microseconds: hasAxis ? _activeAt(bw, ba, us) : 0),
          latitude: _isValidCoordinate(moment.latitude, moment.longitude)
              ? moment.latitude
              : null,
          longitude: _isValidCoordinate(moment.latitude, moment.longitude)
              ? moment.longitude
              : null,
          moment: moment,
          photos: List.unmodifiable(photos),
        ),
      ));
    }
    for (final item in standalone) {
      final us = item.capturedAt.microsecondsSinceEpoch;
      final lat = item.latitude;
      final lng = item.longitude;
      final located =
          lat != null && lng != null && _isValidCoordinate(lat, lng);
      markers.add(_PendingMarker(
        wallUs: us,
        rank: 1,
        marker: GpsReplayMarker._(
          id: 'media_${item.id}',
          kind: GpsReplayMarkerKind.photo,
          recordedAt: DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true),
          playbackTime:
              Duration(microseconds: hasAxis ? _activeAt(bw, ba, us) : 0),
          latitude: located ? lat : null,
          longitude: located ? lng : null,
          moment: null,
          photos: List.unmodifiable([item]),
        ),
      ));
    }
    markers.sort((a, b) {
      final byTime = a.wallUs.compareTo(b.wallUs);
      if (byTime != 0) return byTime;
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      return a.marker.id.compareTo(b.marker.id);
    });
    final markerActive = Int64List(markers.length);
    for (var i = 0; i < markers.length; i++) {
      markerActive[i] = markers[i].marker.playbackTime.inMicroseconds;
    }

    return GpsReplayTimeline._(
      elapsed: totals.elapsed,
      activeDuration: Duration(microseconds: ba.last),
      pausedDuration: totals.paused,
      isConsistentWithStatistics: consistent,
      startedAt: hasAxis
          ? DateTime.fromMicrosecondsSinceEpoch(startUs, isUtc: true)
          : null,
      finishedAt: hasAxis
          ? DateTime.fromMicrosecondsSinceEpoch(finishUs, isUtc: true)
          : null,
      diagnostics: GpsReplayDiagnostics(
        invalidCoordinatePoints: invalidCoordinates,
        outOfOrderPoints: outOfOrder,
        excludedForeignItems: foreign,
        excludedTombstones: tombstoned,
        pauseGapSegments: pauseGaps,
        impossibleJumpSegments: jumpGaps,
        otherGapSegments: otherGaps,
        outsideFinishPoints: outsideFinish,
        futureSpikePoints: futureSpikes,
      ),
      breakWall: bw,
      breakActive: ba,
      hasTimeAxis: hasAxis,
      sampleCount: count,
      latitudes: Float64List.sublistView(lat, 0, count),
      longitudes: Float64List.sublistView(lng, 0, count),
      wallMicros: Int64List.sublistView(wall, 0, count),
      activeMicros: Int64List.sublistView(active, 0, count),
      continuousFromPrevious: Uint8List.sublistView(continuous, 0, count),
      markers: [for (final m in markers) m.marker],
      markerActiveMicros: markerActive,
    );
  }

  /// Builds the timeline from the canonical Journey Details read model.
  /// [GpsJourneyDetails] carries the lifecycle events only inside its
  /// Timeline entries (without `seq`), so the persisted [events] -- the exact
  /// list the canonical statistics consumed -- are supplied separately.
  factory GpsReplayTimeline.fromDetails(
    GpsJourneyDetails details, {
    required List<LocalRouteEvent> events,
    required DateTime now,
  }) =>
      GpsReplayTimeline.build(
        route: details.route,
        points: details.points,
        events: events,
        moments: details.moments,
        media: details.media,
        now: now,
      );

  /// Wall-clock length of the Journey (canonical `elapsed`): start -> finish,
  /// pauses included.
  final Duration elapsed;

  /// Length of the playback axis. Equals the canonical `moving` time
  /// (elapsed - paused) when [isConsistentWithStatistics]; otherwise it is the
  /// end of the best-effort axis and may differ from it. Every playback time
  /// is clamped into `[0, activeDuration]`.
  final Duration activeDuration;

  /// Total time spent paused: the canonical `paused` value, always. When
  /// [isConsistentWithStatistics] is false `elapsed - activeDuration` may
  /// differ from it.
  final Duration pausedDuration;

  /// What a TRUE value guarantees: for every recorded instant in the Journey
  /// window, [playbackTimeAtRecordedTime] equals the canonical `moving` time
  /// the statistics report when only the events recorded by that instant
  /// exist (within [toleranceMicros], the canonical calculator rounding every
  /// duration to whole microseconds on its own), and [activeDuration] equals
  /// the canonical `moving` total. It is only ever true for a well-formed
  /// journal (chronological events inside the window, finish at its end,
  /// continuous probe chain, plateau / running segments only).
  ///
  /// What FALSE means: that guarantee is not given. The axis is still
  /// deterministic, monotone, non-negative and clamped, but it must not be
  /// presented as equal to the canonical statistics, and
  /// [recordedTimeAtPlaybackTime] is then only a best-effort inverse: it
  /// returns a recorded instant on the same axis, which may not map back to
  /// exactly the requested playback time. When the flag is true the inverse
  /// is exact under the plateau convention described on
  /// [recordedTimeAtPlaybackTime]. A Journey without a
  /// `start` event has no axis; the flag then only reflects the zero totals.
  final bool isConsistentWithStatistics;

  /// UTC start / finish of the Journey window; `null` without a `start` event.
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// What was excluded or treated as a discontinuity while building.
  final GpsReplayDiagnostics diagnostics;

  /// Moment and standalone-photo markers, ordered by recorded time, then
  /// Moments before photos, then id. A Moment is ONE marker however many
  /// photos are attached ([GpsReplayMarker.photos]).
  final List<GpsReplayMarker> markers;

  final Int64List _breakWall;
  final Int64List _breakActive;
  final bool _hasTimeAxis;
  final int _count;
  final Float64List _lat;
  final Float64List _lng;
  final Int64List _wall;
  final Int64List _active;
  final Uint8List _continuous;
  final Int64List _markerActive;

  /// Number of usable positioned samples.
  int get sampleCount => _count;

  /// Whether the Journey has a `start` event, i.e. a playback axis at all.
  bool get hasTimeAxis => _hasTimeAxis;

  /// Maps a recorded (wall) instant to playback time, clamped into
  /// `[0, activeDuration]`. Recorded times inside a pause all map to the
  /// playback time at which the pause began.
  Duration playbackTimeAtRecordedTime(DateTime recordedAt) => Duration(
      microseconds: _hasTimeAxis
          ? _activeAt(
              _breakWall, _breakActive, recordedAt.microsecondsSinceEpoch)
          : 0);

  /// Maps playback time (clamped) back to the recorded (wall) instant.
  /// Inside a pause the playback time is flat, so the EARLIEST recorded
  /// instant with that playback time is returned (the moment the pause
  /// began). `null` when the Journey has no `start` event.
  DateTime? recordedTimeAtPlaybackTime(Duration playback) {
    if (!_hasTimeAxis) return null;
    final end = _breakActive.last;
    final t = _clamp(playback.inMicroseconds, end);
    if (t <= 0) {
      return DateTime.fromMicrosecondsSinceEpoch(_breakWall.first, isUtc: true);
    }
    final j = _lowerBound(_breakActive, _breakActive.length, t);
    final k = j - 1;
    final dActive = _breakActive[j] - _breakActive[k];
    final dWall = _breakWall[j] - _breakWall[k];
    final into = t - _breakActive[k];
    final offset = dActive == dWall ? into : (into / dActive * dWall).round();
    return DateTime.fromMicrosecondsSinceEpoch(_breakWall[k] + offset,
        isUtc: true);
  }

  /// The replay position at [playback] (clamped into `[0, activeDuration]`).
  /// O(log n); allocates only the returned value.
  ///
  /// See the class documentation for the meaning of each
  /// [GpsReplayPositionKind]; in short: a stored sample is `exact`, a point
  /// inside a continuous segment is `interpolated`, anywhere else the last
  /// known sample is carried as `held` (across a pause, a rejected GPS jump,
  /// a dropped sample, or after the last sample), `leading` is the first
  /// sample reported for a time before it exists, and `unavailable` means
  /// the Journey has no usable sample.
  GpsReplayPosition positionAt(Duration playback) {
    final t = _clamp(playback.inMicroseconds, _breakActive.last);
    final clamped = Duration(microseconds: t);
    if (_count == 0) {
      return GpsReplayPosition._(
          kind: GpsReplayPositionKind.unavailable, playbackTime: clamped);
    }
    final idx = _upperBound(_active, _count, t) - 1;
    if (idx < 0) {
      return _at(GpsReplayPositionKind.leading, 0, clamped);
    }
    if (_active[idx] == t) {
      return _at(GpsReplayPositionKind.exact, idx, clamped);
    }
    if (idx == _count - 1 || _continuous[idx + 1] == 0) {
      return _at(GpsReplayPositionKind.held, idx, clamped);
    }
    final fraction = (t - _active[idx]) / (_active[idx + 1] - _active[idx]);
    final wallUs =
        _wall[idx] + ((_wall[idx + 1] - _wall[idx]) * fraction).round();
    final dLng = _shortestLongitudeDelta(_lng[idx], _lng[idx + 1]);
    return GpsReplayPosition._(
      kind: GpsReplayPositionKind.interpolated,
      playbackTime: clamped,
      latitude: _lat[idx] + (_lat[idx + 1] - _lat[idx]) * fraction,
      longitude: _normalizeLongitude(_lng[idx] + dLng * fraction),
      recordedAt: DateTime.fromMicrosecondsSinceEpoch(wallUs, isUtc: true),
    );
  }

  /// How many [markers] have been reached at [playback] (their playback time
  /// is `<= playback`); `markers.take(n)` are the reached ones. O(log m).
  int reachedMarkerCount(Duration playback) =>
      _upperBound(_markerActive, _markerActive.length, playback.inMicroseconds);

  GpsReplayPosition _at(
          GpsReplayPositionKind kind, int index, Duration playback) =>
      GpsReplayPosition._(
        kind: kind,
        playbackTime: playback,
        latitude: _lat[index],
        longitude: _lng[index],
        recordedAt:
            DateTime.fromMicrosecondsSinceEpoch(_wall[index], isUtc: true),
      );

  static int _clamp(int value, int max) =>
      value < 0 ? 0 : (value > max ? max : value);

  /// Wall -> active via the break table (linear between break points).
  static int _activeAt(Int64List bw, Int64List ba, int wallUs) {
    if (wallUs <= bw.first) return 0;
    if (wallUs >= bw.last) return ba.last;
    final k = _upperBound(bw, bw.length, wallUs) - 1;
    final dWall = bw[k + 1] - bw[k];
    final dActive = ba[k + 1] - ba[k];
    final into = wallUs - bw[k];
    if (dActive == dWall) return ba[k] + into;
    if (dActive == 0) return ba[k];
    return ba[k] + (into / dWall * dActive).round();
  }

  /// Whether at least [need] consecutive USABLE samples starting at [from]
  /// (unusable ones are skipped) are in non-decreasing time order, none
  /// earlier than [floor] and all strictly earlier than [ceiling]. Stops as
  /// soon as [need] is reached, so it costs O(need), never O(n).
  static bool _confirmedBy(Uint8List usable, Int64List wallOf, int from,
      int need, int floor, int ceiling) {
    var confirmed = 0;
    var previous = floor;
    for (var j = from; j < usable.length && confirmed < need; j++) {
      if (usable[j] == 0) continue;
      final w = wallOf[j];
      if (w < previous || w >= ceiling) break;
      previous = w;
      confirmed++;
    }
    return confirmed >= need;
  }

  /// First index in `[0, length)` whose value is greater than [value].
  static int _upperBound(Int64List list, int length, int value) {
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// First index in `[0, length)` whose value is at least [value].
  static int _lowerBound(Int64List list, int length, int value) {
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] < value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static bool _isValidCoordinate(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Signed longitude difference taking the short way round the globe.
  static double _shortestLongitudeDelta(double from, double to) {
    var delta = to - from;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return delta;
  }

  static double _normalizeLongitude(double longitude) {
    if (longitude > 180) return longitude - 360;
    if (longitude < -180) return longitude + 360;
    return longitude;
  }

  static int _compareMedia(LocalJourneyMediaItem a, LocalJourneyMediaItem b) {
    final byTime = a.capturedAt.compareTo(b.capturedAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }
}

/// How trustworthy a [GpsReplayPosition] is.
enum GpsReplayPositionKind {
  /// A stored sample, at exactly its own playback time.
  exact,

  /// Inside a continuous segment: linearly interpolated between two samples.
  interpolated,

  /// Inside a discontinuity (pause, rejected GPS jump, dropped sample,
  /// zero-length segment) or after the last sample: the last known
  /// sample's position, carried unchanged. Never a bridged guess.
  held,

  /// Before the first sample exists: the first sample's position.
  leading,

  /// The Journey has no usable sample; no coordinates.
  unavailable,
}

/// The replay position at one playback time.
class GpsReplayPosition {
  const GpsReplayPosition._({
    required this.kind,
    required this.playbackTime,
    this.latitude,
    this.longitude,
    this.recordedAt,
  });

  final GpsReplayPositionKind kind;

  /// The requested playback time clamped into `[0, activeDuration]`.
  final Duration playbackTime;

  /// `null` only for [GpsReplayPositionKind.unavailable].
  final double? latitude;
  final double? longitude;

  /// UTC recorded instant the coordinates belong to: the sample's own time
  /// for `exact` / `held` / `leading`, the interpolated instant otherwise.
  final DateTime? recordedAt;

  bool get hasCoordinates => latitude != null && longitude != null;
}

enum GpsReplayMarkerKind { moment, photo }

/// A Moment or a standalone photo aligned to the playback clock.
class GpsReplayMarker {
  const GpsReplayMarker._({
    required this.id,
    required this.kind,
    required this.recordedAt,
    required this.playbackTime,
    required this.latitude,
    required this.longitude,
    required this.moment,
    required this.photos,
  });

  /// Same ids as the Timeline: `moment_<waypointId>` / `media_<mediaId>`.
  final String id;
  final GpsReplayMarkerKind kind;

  /// Moment `recordedAt` / photo `capturedAt` (UTC).
  final DateTime recordedAt;

  /// Position on the playback axis (clamped into it). A marker recorded
  /// during a pause sits at the playback time the pause began.
  final Duration playbackTime;

  /// A Moment's own telemetry, or a standalone photo's own optional position.
  /// Photos attached to a Moment never carry or copy a position.
  final double? latitude;
  final double? longitude;

  /// Set for [GpsReplayMarkerKind.moment] only.
  final LocalWaypoint? moment;

  /// Media metadata, `capturedAt` ascending (id tie-break): every photo
  /// attached to a Moment marker, or the one standalone photo. Metadata
  /// only -- no file is touched.
  final List<LocalJourneyMediaItem> photos;

  bool get hasCoordinates => latitude != null && longitude != null;
}

/// Counts of what the builder excluded or treated as a discontinuity.
class GpsReplayDiagnostics {
  const GpsReplayDiagnostics({
    required this.invalidCoordinatePoints,
    required this.outOfOrderPoints,
    required this.excludedForeignItems,
    required this.excludedTombstones,
    required this.pauseGapSegments,
    required this.impossibleJumpSegments,
    required this.otherGapSegments,
    this.outsideFinishPoints = 0,
    this.futureSpikePoints = 0,
  });

  /// Points dropped for non-finite / out-of-range coordinates.
  final int invalidCoordinatePoints;

  /// Points dropped because their timestamp precedes the previous accepted
  /// point and there was no demonstrable future-stamped spike to blame
  /// instead (the canonical contract: never re-sorted).
  final int outOfOrderPoints;

  /// Points / events / Moments / media of another owner or another route.
  final int excludedForeignItems;

  /// Tombstoned (`pendingDelete`) Moments and media.
  final int excludedTombstones;

  /// Segments that contain a recording pause.
  final int pauseGapSegments;

  /// Segments implying a speed above [gpsImpossibleJumpThresholdMps].
  final int impossibleJumpSegments;

  /// Segments after a dropped sample, or with zero wall / active duration.
  final int otherGapSegments;

  /// Points with valid coordinates stamped strictly after the Journey's
  /// finish. Rejected, never clamped; a point exactly at the finish is kept.
  final int outsideFinishPoints;

  /// Already-accepted samples later rejected as a future-stamped spike
  /// because strictly more later samples contradicted them (see
  /// [GpsReplayTimeline.maxSpikeRunLength]).
  final int futureSpikePoints;

  int get discontinuousSegments =>
      pauseGapSegments + impossibleJumpSegments + otherGapSegments;
}

class _PendingMarker {
  const _PendingMarker(
      {required this.wallUs, required this.rank, required this.marker});
  final int wallUs;
  final int rank;
  final GpsReplayMarker marker;
}

/// Loads the replay for ONE completed Journey from local Drift data only,
/// scoped by [ownerId] + [routeId]. `null` for an unknown route, another
/// owner's route, or one that is not `completed` (same rule as
/// [loadGpsJourneyDetails]). Reads through the existing public readers; adds
/// no query of its own.
Future<GpsReplayTimeline?> loadGpsJourneyReplay({
  required GpsLocalDatabase db,
  required String ownerId,
  required String routeId,
  required DateTime now,
}) async {
  final details = await loadGpsJourneyDetails(
      db: db, ownerId: ownerId, routeId: routeId, now: now);
  if (details == null) return null;
  final events =
      await db.getRouteEvents(ownerId: ownerId, recordedRouteId: routeId);
  return GpsReplayTimeline.fromDetails(details, events: events, now: now);
}
