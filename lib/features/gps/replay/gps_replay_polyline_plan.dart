import 'dart:math' as math;
import 'dart:typed_data';

import 'gps_journey_replay.dart';
import 'gps_replay_route_progress.dart';

/// What a planned line is for.
enum GpsReplayLineKind {
  /// The whole route of one run, simplified, drawn faintly as a preview.
  ghost,

  /// A piece (chunk) of the already travelled route of one run.
  progress,

  /// The segment from the last completed vertex to the current position.
  head,
}

/// One polyline to draw, independent of any map SDK. Immutable: the
/// coordinates are private and read through accessors.
///
/// A line NEVER contains vertices of two different runs.
class GpsReplayPlannedLine {
  GpsReplayPlannedLine._({
    required this.id,
    required this.kind,
    required this.runIndex,
    required Float64List latitudes,
    required Float64List longitudes,
  })  : _lat = latitudes,
        _lng = longitudes;

  /// Stable identifier (`g<run>`, `p<run>_<chunk>`, `head`): drawing a line
  /// with the same id replaces the previous one.
  final String id;
  final GpsReplayLineKind kind;

  /// Index into `GpsReplayTimeline.runs` the line belongs to.
  final int runIndex;

  final Float64List _lat;
  final Float64List _lng;

  /// Number of vertices (at least 2).
  int get length => _lat.length;

  double latitudeAt(int index) => _lat[index];
  double longitudeAt(int index) => _lng[index];
}

/// What a renderer must change after [GpsReplayPolylinePlanner.apply].
class GpsReplayPolylineChanges {
  GpsReplayPolylineChanges._({
    required List<GpsReplayPlannedLine> upserted,
    required List<String> removedIds,
    required this.head,
    required this.headChanged,
  })  : upserted = List.unmodifiable(upserted),
        removedIds = List.unmodifiable(removedIds);

  /// Progress chunks to create or replace (same id = replace).
  final List<GpsReplayPlannedLine> upserted;

  /// Ids of progress chunks to remove.
  final List<String> removedIds;

  /// The current head segment (id `head`), or `null` when the replay is not
  /// inside a continuous stretch (before the first sample, in a GPS gap, at
  /// the end of a run).
  final GpsReplayPlannedLine? head;

  /// Whether [head] differs from the head of the previous [apply]; when
  /// false the renderer need not touch the head.
  final bool headChanged;

  bool get isEmpty => upserted.isEmpty && removedIds.isEmpty && !headChanged;
}

/// Journey Phase 1I-B1B-1 -- turns the run-aware route progress of a
/// `GpsReplayTimeline` into polylines a map can draw, without knowing any
/// map SDK.
///
/// ### Progressive route
/// Every run is cut into CHUNKS of [chunkVertexCount] vertices; consecutive
/// chunks share one vertex, so the drawn line has no gap. A chunk is a line
/// of its currently completed vertices (a chunk with fewer than two
/// completed vertices is not drawn). Chunks behind the replay are never
/// touched again; one update changes only the chunks its spans reach, so a
/// frame during normal playback creates or replaces ONE chunk of at most
/// [chunkVertexCount] vertices -- never the whole route, whatever its length.
/// A large seek touches proportionally many chunks (and nothing else).
///
/// ### Gaps
/// Chunks are cut inside one run only, so a pause, a rejected GPS sample, an
/// impossible jump or any other discontinuity is never bridged. The [head]
/// segment exists only inside a continuous run.
///
/// ### Contract with the progress API
/// [apply] must receive every `GpsReplayProgressUpdate` of one
/// `GpsReplayRouteProgress`, in order, starting with the first one (a delta
/// from an empty drawing). A mismatch throws [StateError]. After
/// `resync()` of the progress, call [reset] first and clear the renderer's
/// progress lines: the resync update then rebuilds everything.
///
/// ### Ghost route
/// [ghostLines] is the complete route, one line per run with at least two
/// vertices, simplified once (radial-distance filter, O(n) per pass) to
/// about [ghostToleranceMeters] and then, if needed, coarsened until at
/// most [ghostVertexBudget] vertices remain. Every vertex is an accepted
/// sample; endpoints of each run are kept. The budget is a soft limit: each
/// run keeps at least its two endpoints.
class GpsReplayPolylinePlanner {
  GpsReplayPolylinePlanner(
    this.timeline, {
    this.chunkVertexCount = defaultChunkVertexCount,
    this.ghostToleranceMeters = defaultGhostToleranceMeters,
    this.ghostVertexBudget = defaultGhostVertexBudget,
  })  : _runs = timeline.runs,
        _drawn = Int32List(timeline.runs.length) {
    if (chunkVertexCount < 2) {
      throw ArgumentError.value(
          chunkVertexCount, 'chunkVertexCount', 'must be at least 2');
    }
    if (!(ghostToleranceMeters > 0)) {
      throw ArgumentError.value(
          ghostToleranceMeters, 'ghostToleranceMeters', 'must be positive');
    }
    if (ghostVertexBudget < 2) {
      throw ArgumentError.value(
          ghostVertexBudget, 'ghostVertexBudget', 'must be at least 2');
    }
  }

  static const defaultChunkVertexCount = 256;
  static const defaultGhostToleranceMeters = 4.0;
  static const defaultGhostVertexBudget = 4000;

  static const headId = 'head';

  /// Stable id of the progress chunk [chunk] of run [run].
  static String progressLineId(int run, int chunk) => 'p${run}_$chunk';

  /// Stable id of the ghost line of run [run].
  static String ghostLineId(int run) => 'g$run';

  final GpsReplayTimeline timeline;
  final int chunkVertexCount;
  final double ghostToleranceMeters;
  final int ghostVertexBudget;

  final List<GpsReplayRun> _runs;
  // Completed vertices per run, as last applied.
  final Int32List _drawn;
  int _completed = 0;
  GpsReplayPlannedLine? _head;

  int get _stride => chunkVertexCount - 1;

  /// The simplified complete route, built on first use, immutable.
  late final List<GpsReplayPlannedLine> ghostLines = _buildGhost();

  /// Forgets everything applied so far. Call it before applying the update
  /// of a `resync()`; the renderer must clear its progress lines itself.
  void reset() {
    _drawn.fillRange(0, _drawn.length, 0);
    _completed = 0;
    _head = null;
  }

  /// Plans the drawing changes for [update]. Cost: the chunks the update's
  /// spans reach, plus O(log n) for the head.
  GpsReplayPolylineChanges apply(GpsReplayProgressUpdate update) {
    if (update.fromCompletedSampleCount != _completed) {
      throw StateError('update starts at ${update.fromCompletedSampleCount} '
          'completed samples but the planner is at $_completed: apply every '
          'update in order, and call reset() before a resync');
    }
    final upserted = <GpsReplayPlannedLine>[];
    final removed = <String>[];
    for (final span in update.removedSpans) {
      final run = _runs[span.runIndex];
      _change(span.runIndex, span.endIndex - run.startIndex,
          span.startIndex - run.startIndex, upserted, removed);
    }
    for (final span in update.addedSpans) {
      final run = _runs[span.runIndex];
      _change(span.runIndex, span.startIndex - run.startIndex,
          span.endIndex - run.startIndex, upserted, removed);
    }
    _completed = update.cursor.completedSampleCount;

    final head = _headFor(update.cursor);
    final headChanged = !_sameLine(_head, head);
    _head = head;
    return GpsReplayPolylineChanges._(
      upserted: upserted,
      removedIds: removed,
      head: head,
      headChanged: headChanged,
    );
  }

  // Run [run] goes from [oldDrawn] to [newDrawn] completed vertices.
  void _change(int run, int oldDrawn, int newDrawn,
      List<GpsReplayPlannedLine> upserted, List<String> removed) {
    if (_drawn[run] != oldDrawn) {
      throw StateError('run $run is drawn up to ${_drawn[run]} vertices but '
          'the update expects $oldDrawn');
    }
    final low = math.min(oldDrawn, newDrawn);
    final high = math.max(oldDrawn, newDrawn);
    // Chunks that are full both before and after are unchanged.
    final first =
        low >= chunkVertexCount ? (low - chunkVertexCount) ~/ _stride + 1 : 0;
    final last = high >= 2 ? (high - 2) ~/ _stride : -1;
    for (var c = first; c <= last; c++) {
      final before = _visible(oldDrawn, c);
      final after = _visible(newDrawn, c);
      if (before == after) continue;
      if (after >= 2) {
        upserted.add(_chunkLine(run, c, after));
      } else if (before >= 2) {
        removed.add(progressLineId(run, c));
      }
    }
    _drawn[run] = newDrawn;
  }

  int _visible(int drawn, int chunk) {
    final v = drawn - chunk * _stride;
    return v < 0 ? 0 : (v > chunkVertexCount ? chunkVertexCount : v);
  }

  GpsReplayPlannedLine _chunkLine(int run, int chunk, int vertices) {
    final start = _runs[run].startIndex + chunk * _stride;
    final lat = Float64List(vertices);
    final lng = Float64List(vertices);
    for (var i = 0; i < vertices; i++) {
      lat[i] = timeline.latitudeAt(start + i);
      lng[i] = timeline.longitudeAt(start + i);
    }
    return GpsReplayPlannedLine._(
      id: progressLineId(run, chunk),
      kind: GpsReplayLineKind.progress,
      runIndex: run,
      latitudes: lat,
      longitudes: lng,
    );
  }

  GpsReplayPlannedLine? _headFor(GpsReplayCursor cursor) {
    if (!cursor.headExtendsLine ||
        cursor.sampleIndex < 0 ||
        !cursor.position.hasCoordinates) {
      return null;
    }
    final i = cursor.sampleIndex;
    return GpsReplayPlannedLine._(
      id: headId,
      kind: GpsReplayLineKind.head,
      runIndex: timeline.runIndexOfSample(i),
      latitudes: Float64List.fromList(
          [timeline.latitudeAt(i), cursor.position.latitude!]),
      longitudes: Float64List.fromList(
          [timeline.longitudeAt(i), cursor.position.longitude!]),
    );
  }

  static bool _sameLine(GpsReplayPlannedLine? a, GpsReplayPlannedLine? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a.latitudeAt(i) != b.latitudeAt(i) ||
          a.longitudeAt(i) != b.longitudeAt(i)) {
        return false;
      }
    }
    return true;
  }

  // ---- ghost -----------------------------------------------------------

  List<GpsReplayPlannedLine> _buildGhost() {
    final lines = <int>[
      for (var r = 0; r < _runs.length; r++)
        if (_runs[r].length >= 2) r
    ];
    if (lines.isEmpty) return const [];

    var tolerance = ghostToleranceMeters;
    late List<List<int>> kept;
    for (var pass = 0; pass < 40; pass++) {
      kept = [for (final r in lines) _radial(_runs[r], tolerance)];
      final total = kept.fold<int>(0, (a, k) => a + k.length);
      final minimal = kept.every((k) => k.length == 2);
      if (total <= ghostVertexBudget || minimal) break;
      tolerance *= 2;
    }
    return List.unmodifiable([
      for (var k = 0; k < lines.length; k++)
        GpsReplayPlannedLine._(
          id: ghostLineId(lines[k]),
          kind: GpsReplayLineKind.ghost,
          runIndex: lines[k],
          latitudes: Float64List.fromList(
              [for (final i in kept[k]) timeline.latitudeAt(i)]),
          longitudes: Float64List.fromList(
              [for (final i in kept[k]) timeline.longitudeAt(i)]),
        ),
    ]);
  }

  // Radial-distance simplification of one run: keep a vertex once it is at
  // least [tolerance] metres from the last kept one; always keep both
  // endpoints. Every dropped vertex is within [tolerance] of a kept one.
  List<int> _radial(GpsReplayRun run, double tolerance) {
    final kept = <int>[run.startIndex];
    var last = run.startIndex;
    for (var i = run.startIndex + 1; i < run.endIndex - 1; i++) {
      if (_meters(last, i) >= tolerance) {
        kept.add(i);
        last = i;
      }
    }
    kept.add(run.endIndex - 1);
    return kept;
  }

  // Equirectangular distance in metres, taking the short way round the
  // antimeridian.
  double _meters(int a, int b) {
    const metersPerDegree = 111320.0;
    final latA = timeline.latitudeAt(a);
    final latB = timeline.latitudeAt(b);
    var dLng = timeline.longitudeAt(b) - timeline.longitudeAt(a);
    if (dLng > 180) dLng -= 360;
    if (dLng < -180) dLng += 360;
    final dy = (latB - latA) * metersPerDegree;
    final dx =
        dLng * metersPerDegree * math.cos((latA + latB) / 2 * math.pi / 180);
    return math.sqrt(dx * dx + dy * dy);
  }
}
