import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_design.dart';
import '../replay/gps_journey_replay.dart';
import '../replay/gps_replay_polyline_plan.dart';
import '../replay/gps_replay_route_progress.dart';

/// Journey Phase 1I-B1B-2 -- what the Replay map draws, as `Polyline` /
/// `Marker` sets, fed ONLY by the output of [GpsReplayPolylinePlanner].
///
/// ### Truth and drawing
/// The model keeps EVERY planned progress chunk it was given (vertex arrays
/// only; nothing is ever evicted for being old) and derives the drawn
/// polylines from them. Separate GPS runs are never joined, in any mode.
///
/// ### Drawing modes (progress)
///  - EXACT, while the chunk count is within [maxProgressLines]: one cached
///    `Polyline` per planner chunk, replaced only when the planner replaces
///    it. Completed geometry is drawn exactly.
///  - COMPACT, above that: every run is drawn as ONE polyline of its
///    completed chunks merged (same run only) and radially simplified to at
///    most [mergedVertexBudget] vertices. The run the replay is currently in
///    keeps its newest chunk as a separate live polyline, so a frame still
///    changes only a small line. A single very long run therefore costs two
///    lines however long it is.
///  - If there are more runs than lines, the runs with the greatest drawn
///    LENGTH IN METRES keep a progress line (ties: the more recent run);
///    the smallest fragments are not drawn as progress
///    ([droppedRunCount]). Showing every run as its own polyline is
///    impossible beyond the line budget; this is the documented degradation,
///    and the route is then NOT fully visible.
///
/// ### Ghost preview
/// At most [maxGhostLines] lines, chosen by length in metres (ties: the
/// earlier run), so a dropped fragment may still show faintly
/// ([ghostTruncated] tells that some runs have no preview).
///
/// ### Cost
/// A change recomputes only what it touched; the map plugin diff walks all
/// current ids, so the object count is bounded by roughly
/// [maxGhostLines] + [maxProgressLines] + 2. No device performance claim is
/// made here. The model is a [ChangeNotifier]: only the map widget listening
/// to it is rebuilt on a change, never the whole screen.
class GpsReplayRenderModel extends ChangeNotifier {
  GpsReplayRenderModel({
    required List<GpsReplayPlannedLine> ghostLines,
    required this.progressColor,
    required this.ghostColor,
    this.maxGhostLines = defaultMaxGhostLines,
    this.maxProgressLines = defaultMaxProgressLines,
    this.mergedVertexBudget = defaultMergedVertexBudget,
  }) {
    if (maxGhostLines < 1 || maxProgressLines < 4 || mergedVertexBudget < 2) {
      throw ArgumentError('line limits are too small');
    }
    final kept = _limitGhost(ghostLines);
    ghostTruncated = kept.length < ghostLines.length;
    _ghost = [
      for (final line in kept) _polyline(line, ghostColor, width: 4, zIndex: 0),
    ];
    _rebuild();
  }

  static const defaultMaxGhostLines = 150;
  static const defaultMaxProgressLines = 600;
  static const defaultMergedVertexBudget = 1500;

  static const positionMarkerId = MarkerId('gps_replay_position');

  final Color progressColor;
  final Color ghostColor;
  final int maxGhostLines;
  final int maxProgressLines;
  final int mergedVertexBudget;

  late final List<Polyline> _ghost;

  // Truth: run -> chunk index -> chunk.
  final SplayTreeMap<int, SplayTreeMap<int, _Chunk>> _runs = SplayTreeMap();
  int _chunkCount = 0;

  // Compact-mode caches.
  final Map<int, Polyline> _mergedFull = {}; // whole run (non-live runs)
  final Map<int, Polyline> _mergedBody = {}; // live run without newest chunk
  final Map<int, int> _bodyHighest = {};

  Polyline? _head;
  Marker? _marker;
  List<Polyline> _progressDrawn = const [];
  Set<Polyline> _polylines = const {};
  int _dropped = 0;
  bool _compact = false;

  /// Whether some runs have no ghost preview because of [maxGhostLines].
  late final bool ghostTruncated;

  Set<Polyline> get polylines => _polylines;
  Set<Marker> get markers => {if (_marker != null) _marker!};

  int get ghostLineCount => _ghost.length;

  /// Progress polylines currently drawn (excluding the head).
  int get progressLineCount => _progressDrawn.length;

  /// Planner chunks held (the truth), whatever is drawn.
  int get chunkCount => _chunkCount;

  /// Whether the compact mode is active.
  bool get isCompacted => _compact;

  /// Runs with completed geometry that have no progress line because the
  /// line budget was exceeded (always 0 in exact mode).
  int get droppedRunCount => _dropped;
  bool get hasHead => _head != null;

  /// The exact progress polyline of planner chunk [id], in exact mode.
  Polyline? progressLine(String id) {
    if (_compact) return null;
    final i = id.indexOf('_');
    final run = int.tryParse(id.substring(1, i));
    final chunk = int.tryParse(id.substring(i + 1));
    if (run == null || chunk == null) return null;
    return _runs[run]?[chunk]?.polyline(progressColor);
  }

  /// Forgets all progress (planner `reset()` goes together with this).
  void reset() {
    _runs.clear();
    _chunkCount = 0;
    _mergedFull.clear();
    _mergedBody.clear();
    _bodyHighest.clear();
    _head = null;
    _marker = null;
    _rebuild();
    notifyListeners();
  }

  /// Applies one planner result and moves the position marker.
  void apply(GpsReplayPolylineChanges changes, GpsReplayCursor cursor) {
    final lowestTouched = <int, int>{}; // run -> lowest touched chunk
    void touch(int run, int chunk) =>
        lowestTouched[run] = math.min(lowestTouched[run] ?? chunk, chunk);

    for (final id in changes.removedIds) {
      final i = id.indexOf('_');
      final run = int.parse(id.substring(1, i));
      final chunk = int.parse(id.substring(i + 1));
      final chunks = _runs[run];
      if (chunks != null && chunks.remove(chunk) != null) {
        _chunkCount--;
        if (chunks.isEmpty) _runs.remove(run);
        touch(run, chunk);
      }
    }
    for (final line in changes.upserted) {
      final chunk = int.parse(line.id.substring(line.id.indexOf('_') + 1));
      final chunks = _runs.putIfAbsent(line.runIndex, SplayTreeMap.new);
      if (chunks.containsKey(chunk)) {
        chunks[chunk] = _Chunk(line);
      } else {
        chunks[chunk] = _Chunk(line);
        _chunkCount++;
      }
      touch(line.runIndex, chunk);
    }
    for (final e in lowestTouched.entries) {
      _invalidate(e.key, e.value);
    }

    if (changes.headChanged) {
      final head = changes.head;
      _head = head == null
          ? null
          : _polyline(head, progressColor, width: 6, zIndex: 1);
    }
    final position = cursor.position;
    _marker = position.hasCoordinates
        ? Marker(
            markerId: positionMarkerId,
            position: LatLng(position.latitude!, position.longitude!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            anchor: const Offset(0.5, 0.5),
            flat: true,
            zIndexInt: 10,
          )
        : null;
    _rebuild();
    notifyListeners();
  }

  // A run changed from chunk [lowest] upwards: drop the merged polylines that
  // include it. The live run's body survives a change of its newest chunk.
  void _invalidate(int run, int lowest) {
    _mergedFull.remove(run);
    final chunks = _runs[run];
    if (chunks == null) {
      _mergedBody.remove(run);
      _bodyHighest.remove(run);
      return;
    }
    final newest = chunks.lastKey()!;
    if (_bodyHighest[run] != newest || lowest < newest) {
      _mergedBody.remove(run);
      _bodyHighest.remove(run);
    }
  }

  void _rebuild() {
    _compact = _chunkCount > maxProgressLines;
    final drawn = <Polyline>[];
    _dropped = 0;
    if (!_compact) {
      for (final chunks in _runs.values) {
        for (final c in chunks.values) {
          drawn.add(c.polyline(progressColor));
        }
      }
      _mergedFull.clear();
      _mergedBody.clear();
      _bodyHighest.clear();
    } else {
      final live = _runs.lastKey()!;
      // One slot per run; the live run needs two (body + newest chunk).
      final slots = maxProgressLines - 2;
      final others = _runs.keys.where((r) => r != live).toList()
        ..sort((a, b) {
          final byLength = _runMeters(b).compareTo(_runMeters(a));
          return byLength != 0 ? byLength : b.compareTo(a);
        });
      final chosen = others.take(slots).toSet();
      _dropped = others.length - chosen.length;
      for (final r in _runs.keys) {
        if (r == live) continue;
        if (chosen.contains(r)) {
          drawn.add(_mergedFull[r] ??= _merge(r, _runs[r]!.values));
        } else {
          _mergedFull.remove(r);
        }
      }
      final liveChunks = _runs[live]!;
      final newest = liveChunks.lastKey()!;
      if (liveChunks.length > 1) {
        final body = _mergedBody[live] ??=
            _merge(live, liveChunks.values.take(liveChunks.length - 1));
        _bodyHighest[live] = newest;
        drawn.add(body);
      } else {
        _mergedBody.remove(live);
        _bodyHighest.remove(live);
      }
      drawn.add(liveChunks[newest]!.polyline(progressColor));
      _mergedFull.remove(live);
    }
    _progressDrawn = drawn;
    _polylines = {
      ..._ghost,
      ...drawn,
      if (_head != null) _head!,
    };
  }

  double _runMeters(int run) {
    var total = 0.0;
    for (final c in _runs[run]!.values) {
      total += c.meters;
    }
    return total;
  }

  // The chunks of ONE run (consecutive, overlapping by one vertex) as one
  // simplified polyline. Never mixes runs.
  Polyline _merge(int run, Iterable<_Chunk> chunks) {
    final lat = <double>[];
    final lng = <double>[];
    var first = true;
    for (final c in chunks) {
      for (var i = first ? 0 : 1; i < c.line.length; i++) {
        lat.add(c.line.latitudeAt(i));
        lng.add(c.line.longitudeAt(i));
      }
      first = false;
    }
    final keep = _simplify(lat, lng, mergedVertexBudget);
    return Polyline(
      polylineId: PolylineId('m$run'),
      points: [for (final i in keep) LatLng(lat[i], lng[i])],
      color: progressColor,
      width: 6,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
      zIndex: 1,
    );
  }

  List<GpsReplayPlannedLine> _limitGhost(List<GpsReplayPlannedLine> lines) {
    if (lines.length <= maxGhostLines) return lines;
    final meters = {for (final l in lines) l.id: _lineMeters(l)};
    final ranked = [...lines]..sort((a, b) {
        final c = meters[b.id]!.compareTo(meters[a.id]!);
        return c != 0 ? c : a.runIndex.compareTo(b.runIndex);
      });
    final keep = ranked.take(maxGhostLines).map((l) => l.id).toSet();
    return [
      for (final line in lines)
        if (keep.contains(line.id)) line,
    ];
  }

  static Polyline _polyline(GpsReplayPlannedLine line, Color color,
          {required double width, required int zIndex}) =>
      Polyline(
        polylineId: PolylineId(line.id),
        points: [
          for (var i = 0; i < line.length; i++)
            LatLng(line.latitudeAt(i), line.longitudeAt(i)),
        ],
        color: color,
        width: width.round(),
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: zIndex,
      );
}

class _Chunk {
  _Chunk(this.line) : meters = _lineMeters(line);
  final GpsReplayPlannedLine line;
  final double meters;
  Polyline? _cached;

  Polyline polyline(Color color) => _cached ??=
      GpsReplayRenderModel._polyline(line, color, width: 6, zIndex: 1);
}

const _metersPerDegree = 111320.0;

double _segmentMeters(double latA, double lngA, double latB, double lngB) {
  var dLng = lngB - lngA;
  if (dLng > 180) dLng -= 360;
  if (dLng < -180) dLng += 360;
  final dy = (latB - latA) * _metersPerDegree;
  final dx =
      dLng * _metersPerDegree * math.cos((latA + latB) / 2 * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

double _lineMeters(GpsReplayPlannedLine line) {
  var total = 0.0;
  for (var i = 1; i < line.length; i++) {
    total += _segmentMeters(line.latitudeAt(i - 1), line.longitudeAt(i - 1),
        line.latitudeAt(i), line.longitudeAt(i));
  }
  return total;
}

// Radial-distance simplification to at most [budget] vertices (both ends are
// always kept): the tolerance doubles until the budget is met.
List<int> _simplify(List<double> lat, List<double> lng, int budget) {
  final n = lat.length;
  if (n <= budget) return [for (var i = 0; i < n; i++) i];
  var tolerance = 2.0;
  while (true) {
    final kept = <int>[0];
    var last = 0;
    for (var i = 1; i < n - 1; i++) {
      if (_segmentMeters(lat[last], lng[last], lat[i], lng[i]) >= tolerance) {
        kept.add(i);
        last = i;
      }
    }
    kept.add(n - 1);
    if (kept.length <= budget || kept.length <= 2) return kept;
    tolerance *= 2;
  }
}

/// The route's bounding box, or `null` without samples. Longitudes are not
/// unwrapped across the antimeridian (such a Journey gets a very wide box).
LatLngBounds? gpsReplayRouteBounds(GpsReplayTimeline timeline) {
  final n = timeline.sampleCount;
  if (n == 0) return null;
  var minLat = timeline.latitudeAt(0), maxLat = minLat;
  var minLng = timeline.longitudeAt(0), maxLng = minLng;
  for (var i = 1; i < n; i++) {
    final lat = timeline.latitudeAt(i);
    final lng = timeline.longitudeAt(i);
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }
  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}

/// The Replay map: a plain `GoogleMap` (the shared clustered map exposes no
/// camera API) with a STATIC initial camera fitted to the route. Manual
/// gestures stay enabled; the camera never follows the replay.
class GpsJourneyReplayMap extends StatefulWidget {
  const GpsJourneyReplayMap({
    super.key,
    required this.model,
    required this.bounds,
    this.bottomPadding = 0,
    this.fitReady = true,
  });

  final GpsReplayRenderModel model;
  final LatLngBounds bounds;

  /// Official `GoogleMap.padding` at the bottom: the Google logo and
  /// attribution (and the route fit) stay above the control panel.
  final double bottomPadding;

  /// The route is fitted once this is true (after the panel is measured, so
  /// the frame accounts for the final padding).
  final bool fitReady;

  @override
  State<GpsJourneyReplayMap> createState() => _GpsJourneyReplayMapState();
}

class _GpsJourneyReplayMapState extends State<GpsJourneyReplayMap> {
  GoogleMapController? _controller;
  String? _style;
  bool _fitted = false;

  bool get _isPoint =>
      widget.bounds.southwest.latitude == widget.bounds.northeast.latitude &&
      widget.bounds.southwest.longitude == widget.bounds.northeast.longitude;

  LatLng get _center => LatLng(
        (widget.bounds.southwest.latitude + widget.bounds.northeast.latitude) /
            2,
        (widget.bounds.southwest.longitude +
                widget.bounds.northeast.longitude) /
            2,
      );

  @override
  void initState() {
    super.initState();
    rootBundle.loadString(AppMapStyle.assetPath).then((style) {
      if (mounted) setState(() => _style = style);
    }).catchError((Object _) {});
  }

  @override
  void didUpdateWidget(covariant GpsJourneyReplayMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fitReady && !oldWidget.fitReady) _fit();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Fits the route into the viewport. `newLatLngBounds` fails when the map has
  // no size yet; the attempt is then repeated once on the first idle camera.
  Future<void> _fit() async {
    final controller = _controller;
    if (controller == null || _fitted || !widget.fitReady) return;
    try {
      await controller.moveCamera(_isPoint
          ? CameraUpdate.newLatLngZoom(_center, 16)
          : CameraUpdate.newLatLngBounds(widget.bounds, 56));
      _fitted = true;
    } catch (_) {
      // Retried from onCameraIdle.
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) => GoogleMap(
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          initialCameraPosition: CameraPosition(
            target: _center,
            zoom: _isPoint ? 16 : 13,
          ),
          style: _style,
          polylines: widget.model.polylines,
          markers: widget.model.markers,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          onMapCreated: (controller) {
            _controller = controller;
            _fit();
          },
          onCameraIdle: _fit,
        ),
      );
}
