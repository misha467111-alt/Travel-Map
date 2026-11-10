import 'gps_journey_replay.dart';

/// Journey Phase 1I-B1A -- where a replay has got to along the route, in a
/// compact form a renderer can draw incrementally. Immutable.
///
/// The drawn route is described WITHOUT copying any coordinates:
///  - the first [completedRunCount] runs of `GpsReplayTimeline.runs` are
///    complete (draw each as one line);
///  - run [partialRunIndex] (if not -1) is partly reached: its first
///    [partialVertexCount] samples are the completed vertices;
///  - when [headExtendsLine] is true, one more segment runs from the last
///    completed vertex (sample [sampleIndex]) to [position], the current
///    interpolated point. It is never true across a GPS gap, so a line is
///    never drawn between two different runs.
///
/// Lone single-sample runs (for example samples recorded inside a pause) are
/// complete runs of one vertex: nothing to draw as a line.
class GpsReplayCursor {
  const GpsReplayCursor._({
    required this.playbackTime,
    required this.sampleIndex,
    required this.completedRunCount,
    required this.partialRunIndex,
    required this.partialVertexCount,
    required this.position,
    required this.headExtendsLine,
  });

  /// The requested playback time, clamped into the timeline's axis.
  final Duration playbackTime;

  /// Index of the last accepted sample the replay has passed (as
  /// `GpsReplayTimeline.sampleIndexAt`), or `-1` before the first one.
  final int sampleIndex;

  /// Accepted samples passed so far (`sampleIndex + 1`).
  int get completedSampleCount => sampleIndex + 1;

  /// Number of leading runs that are entirely behind the replay.
  final int completedRunCount;

  /// Index of the run the replay is inside, or `-1` when it is not inside a
  /// run (before the first sample, or exactly after a run's last sample).
  final int partialRunIndex;

  /// Samples of the partial run that are already behind the replay (0 when
  /// [partialRunIndex] is -1).
  final int partialVertexCount;

  /// The current position (same value as `GpsReplayTimeline.positionAt`);
  /// kept separate from the completed vertices.
  final GpsReplayPosition position;

  /// Whether a segment from sample [sampleIndex] to [position] is part of
  /// the route (the head is interpolated inside a continuous run).
  final bool headExtendsLine;
}

/// A contiguous range of accepted samples `[startIndex, endIndex)` that lies
/// inside ONE run. A renderer keeps one polyline per run, so a span is the
/// unit of every change: spans of different runs are never one polyline.
class GpsReplayRunSpan {
  const GpsReplayRunSpan._({
    required this.runIndex,
    required this.startIndex,
    required this.endIndex,
    required this.startsInsideRun,
  });

  /// Index into `GpsReplayTimeline.runs`.
  final int runIndex;

  /// First sample index of the span (read coordinates with
  /// `GpsReplayTimeline.latitudeAt` / `longitudeAt`).
  final int startIndex;

  /// One past the last sample index of the span.
  final int endIndex;

  /// Whether the span does not begin at the first sample of its run, so the
  /// run's polyline keeps the vertices before [startIndex]:
  ///  - in an ADDED span: append to the existing polyline of the run (its
  ///    vertex count is exactly `startIndex - run.startIndex`); `false` means
  ///    the run's polyline does not exist yet and must be started;
  ///  - in a REMOVED span: truncate the polyline to `startIndex -
  ///    run.startIndex` vertices; `false` means remove the polyline entirely.
  final bool startsInsideRun;

  int get length => endIndex - startIndex;
}

/// What a renderer must change to go from the vertices it was last told
/// about to the vertices completed at the new playback time.
///
/// ### Contract
/// A renderer starts with NOTHING drawn. The first
/// [GpsReplayRouteProgress.update] is a delta from that empty state, so it
/// already contains every vertex completed at the requested time (including
/// all samples at playback time zero, duplicates included): no separate
/// initialization is needed and nothing can be drawn twice. Each later
/// update is relative to the previous one. A renderer that lost its drawing
/// calls [GpsReplayRouteProgress.resync] to get the whole drawn set again.
///
/// Removed spans are applied first, then added spans. Only one of the two
/// lists is non-empty in any update. Each span lies inside one run.
class GpsReplayProgressUpdate {
  const GpsReplayProgressUpdate._({
    required this.cursor,
    required this.fromCompletedSampleCount,
    required this.addedSpans,
    required this.removedSpans,
  });

  /// The cursor at the requested playback time.
  final GpsReplayCursor cursor;

  /// Completed samples the renderer had before this update (0 for the
  /// first update after creation or [GpsReplayRouteProgress.resync]).
  final int fromCompletedSampleCount;

  /// Newly completed vertices, one span per touched run, in ascending run
  /// order. Within a run the spans are contiguous with what was drawn.
  final List<GpsReplayRunSpan> addedSpans;

  /// Vertices no longer completed, one span per touched run, in DESCENDING
  /// run order (latest first).
  final List<GpsReplayRunSpan> removedSpans;

  /// The replay moved backwards past at least one completed sample.
  bool get rewound => removedSpans.isNotEmpty;

  /// Total completed vertices gained / lost, across all spans.
  int get addedSampleCount =>
      cursor.completedSampleCount > fromCompletedSampleCount
          ? cursor.completedSampleCount - fromCompletedSampleCount
          : 0;

  int get removedSampleCount =>
      fromCompletedSampleCount > cursor.completedSampleCount
          ? fromCompletedSampleCount - cursor.completedSampleCount
          : 0;
}

/// Journey Phase 1I-B1A -- maps playback time to a [GpsReplayCursor] using
/// only the public geometry of a `GpsReplayTimeline`: the accepted samples,
/// their runs and gaps, `sampleIndexAt` and `positionAt`. Nothing is
/// re-filtered or recomputed, and no route data is copied.
///
/// [cursorAt] is O(log n) (a few binary searches) and allocates only the
/// returned cursor. [update] adds the run-aware delta described on
/// [GpsReplayProgressUpdate]; its cost is O(log n) plus the number of runs
/// the change touches (typically zero or one per frame; a large seek touches
/// as many runs as it crosses, never the rest of the route).
class GpsReplayRouteProgress {
  GpsReplayRouteProgress(this.timeline)
      // Materialize the runs now, not inside the first frame.
      : _runs = timeline.runs {
    _cursor = cursorAt(Duration.zero);
  }

  final GpsReplayTimeline timeline;
  final List<GpsReplayRun> _runs;
  late GpsReplayCursor _cursor;

  // Completed samples the renderer has been told about. Starts at 0: an
  // empty drawing, NOT the state at playback time zero.
  int _reportedCount = 0;

  /// The latest cursor (initially at playback time zero). This is the
  /// current state, not what a renderer has been told: updates are relative
  /// to [reportedSampleCount].
  GpsReplayCursor get cursor => _cursor;

  /// Completed samples the last [update] / [resync] reported (0 before the
  /// first one).
  int get reportedSampleCount => _reportedCount;

  /// The cursor for [playback] without changing any state.
  GpsReplayCursor cursorAt(Duration playback) {
    final position = timeline.positionAt(playback);
    final sampleIndex = timeline.sampleIndexAt(playback);
    var completedRuns = 0;
    var partialRun = -1;
    var partialVertices = 0;
    if (sampleIndex >= 0) {
      final runIndex = timeline.runIndexOfSample(sampleIndex);
      final run = _runs[runIndex];
      if (sampleIndex == run.endIndex - 1) {
        completedRuns = runIndex + 1;
      } else {
        completedRuns = runIndex;
        partialRun = runIndex;
        partialVertices = sampleIndex - run.startIndex + 1;
      }
    }
    return GpsReplayCursor._(
      playbackTime: position.playbackTime,
      sampleIndex: sampleIndex,
      completedRunCount: completedRuns,
      partialRunIndex: partialRun,
      partialVertexCount: partialVertices,
      position: position,
      headExtendsLine: position.kind == GpsReplayPositionKind.interpolated,
    );
  }

  /// Moves to [playback] and reports the change relative to the previous
  /// update (the first one: relative to an empty drawing).
  GpsReplayProgressUpdate update(Duration playback) {
    final next = cursorAt(playback);
    final from = _reportedCount;
    final to = next.completedSampleCount;
    _cursor = next;
    _reportedCount = to;
    return GpsReplayProgressUpdate._(
      cursor: next,
      fromCompletedSampleCount: from,
      addedSpans: to > from ? _spans(from, to, ascending: true) : const [],
      removedSpans: to < from ? _spans(to, from, ascending: false) : const [],
    );
  }

  /// Reports the whole drawn set at the current playback time again, as a
  /// delta from an empty drawing. For a renderer that lost its drawing (for
  /// example a recreated map). Cost is proportional to the drawn route.
  GpsReplayProgressUpdate resync() {
    _reportedCount = 0;
    return update(_cursor.playbackTime);
  }

  // Splits samples [lo, hi) at run boundaries. Touches only the runs the
  // range crosses.
  List<GpsReplayRunSpan> _spans(int lo, int hi, {required bool ascending}) {
    final spans = <GpsReplayRunSpan>[];
    var runIndex = timeline.runIndexOfSample(lo);
    var at = lo;
    while (at < hi) {
      final run = _runs[runIndex];
      final end = run.endIndex < hi ? run.endIndex : hi;
      spans.add(GpsReplayRunSpan._(
        runIndex: runIndex,
        startIndex: at,
        endIndex: end,
        startsInsideRun: at > run.startIndex,
      ));
      at = end;
      runIndex++;
    }
    return List.unmodifiable(ascending ? spans : spans.reversed);
  }
}
