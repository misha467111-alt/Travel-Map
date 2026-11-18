import 'package:geolocator/geolocator.dart' show Geolocator;

import '../local/gps_local_database.dart';
import 'gps_journey_statistics.dart' show gpsImpossibleJumpThresholdMps;

/// Journey Phase 2.5 -- GPS signal-quality protection.
///
/// A pure, deterministic read-time classification of already-persisted raw
/// route points. NOTHING is written, deleted or rewritten: every raw point
/// stays in `local_route_points` for diagnostics and recovery; this only
/// decides which of them are CONFIRMED track for distance / statistics /
/// geometry. No schema change, no recorder change.
///
/// What it can and cannot tell
/// ---------------------------
/// It recognises coordinates that are *physically impossible or unreliable*
/// given the surrounding measurements (accuracy, time interval, implied
/// speed, reported speed, acceleration). It does NOT detect GPS spoofing or
/// jamming as such: a perfectly self-consistent fake track at plausible
/// speed is indistinguishable from a real one. Ambiguous situations are
/// reported as `unconfirmed`, never as "spoofed".
///
/// Rules (all thresholds are named constants below)
///  1. A point with non-finite / out-of-range coordinates, or a horizontal
///     accuracy worse than [maxReliableAccuracyMeters], is excluded
///     (`invalidCoordinates` / `lowAccuracy`). A missing accuracy is not a
///     reason to exclude.
///  2. Every other point is judged against the last CONFIRMED point (the
///     anchor), not against the previous raw point, so one bad sample does
///     not cut the track in two: the next good sample links to the anchor.
///  3. The link anchor -> point must be physically reachable: its implied
///     speed must not exceed [gpsImpossibleJumpThresholdMps] AND the
///     displacement must fit the speed the device itself reported
///     (`max` of the two end points), plus what acceleration over the
///     interval can add, plus the stated position error. There is no single
///     global speed limit: a car at 30 m/s reporting 30 m/s is fine, the
///     same displacement for a walker reporting 1.5 m/s is not. When no
///     reported speed is available, only the absolute ceiling applies.
///  4. A reachable link after a long silence ([gapMinSeconds]) that covers
///     real ground ([gapMinMeters]) is a `gap`: the track continues from the
///     new point, but the distance across the gap is NOT counted and no line
///     is drawn over it (we do not know the path that was travelled).
///  5. A point that is unreachable from the anchor goes to a quarantine
///     chain of mutually consistent points. If the signal returns to the
///     anchor's neighbourhood the quarantine is dropped (the points stay
///     `unconfirmed`); only if the other place stays consistent for
///     [quarantinePromoteSeconds] is it adopted as the new track, starting
///     with a discontinuity (never a straight line from the old place).
///  6. A timestamp that does not increase cannot be judged: the point
///     becomes the new anchor behind a `discontinuity` and no distance is
///     counted for that link (the same effect as the canonical statistics'
///     "non-positive duration segment" rule).
const gpsMaxReliableAccuracyMeters = 200.0;

/// Longest silence (seconds) over which a displacement is still treated as
/// an ordinary link, see [GpsTrackAnalysis].
const gpsGapMinSeconds = 60.0;

/// Minimum displacement (metres) for a long silence to count as a `gap`.
/// A stationary pause (long interval, tiny displacement) is not a gap.
const gpsGapMinMeters = 300.0;

/// Acceleration (m/s^2) the plausibility budget allows between two samples.
const gpsAssumedAccelerationMps2 = 8.0;

/// Extra metres of tolerance added to the stated accuracies.
const gpsPositionErrorFloorMeters = 5.0;

/// Accuracy (metres) assumed for a sample that did not report one.
const gpsUnknownAccuracyMeters = 30.0;

/// How long (seconds) an alternative, mutually consistent chain must hold
/// before it replaces the old track.
const gpsQuarantinePromoteSeconds = 600.0;

/// Fewest samples an alternative chain needs before it can replace the old
/// track.
const gpsQuarantinePromoteMinPoints = 10;

/// Why a raw point is or is not part of the confirmed track.
enum GpsPointVerdict {
  /// Part of the confirmed track.
  trusted,

  /// Reported horizontal accuracy worse than [gpsMaxReliableAccuracyMeters].
  lowAccuracy,

  /// Non-finite or out-of-range coordinates.
  invalidCoordinates,

  /// Plausible on its own, but not reachable from the confirmed track and
  /// not (yet) confirmed as a new one. Not claimed to be spoofed.
  unconfirmed,
}

/// How a trusted point connects to the previous trusted point.
enum GpsLinkKind {
  /// First point of the confirmed track (or any non-trusted point).
  none,

  /// Ordinary segment: counted in the confirmed distance, may be drawn.
  connected,

  /// Reachable, but across a long silence: not counted, not drawn.
  gap,

  /// Time did not advance, or an alternative chain was adopted: not
  /// counted, not drawn.
  discontinuity,
}

/// Result of [analyzeGpsTrack]; parallel to the analysed point list.
class GpsTrackAnalysis {
  GpsTrackAnalysis._(
    this._points,
    this.verdicts,
    this.links,
    this.confirmedDistanceMeters,
  );

  final List<LocalRoutePoint> _points;

  /// Verdict per input point (same index).
  final List<GpsPointVerdict> verdicts;

  /// Link of each trusted point to the previous trusted point (same index);
  /// [GpsLinkKind.none] for a non-trusted point.
  final List<GpsLinkKind> links;

  /// Sum of the `connected` segments only.
  final double confirmedDistanceMeters;

  int _count(GpsPointVerdict v) => verdicts.where((e) => e == v).length;

  int get trustedCount => _count(GpsPointVerdict.trusted);
  int get lowAccuracyCount => _count(GpsPointVerdict.lowAccuracy);
  int get invalidCoordinateCount => _count(GpsPointVerdict.invalidCoordinates);
  int get unconfirmedCount => _count(GpsPointVerdict.unconfirmed);

  /// Points that are not part of the confirmed track, for any reason.
  int get excludedCount => verdicts.length - trustedCount;

  /// Trusted links that are a `gap` or a `discontinuity`.
  int get brokenLinkCount => links
      .where((e) => e == GpsLinkKind.gap || e == GpsLinkKind.discontinuity)
      .length;

  /// The confirmed track as runs of consecutive `connected` points. A gap or
  /// discontinuity starts a new run; excluded points appear in no run. Safe
  /// to draw: no run ever bridges an unconfirmed jump or a long gap.
  List<List<LocalRoutePoint>> trustedRuns() {
    final runs = <List<LocalRoutePoint>>[];
    List<LocalRoutePoint>? current;
    for (var i = 0; i < _points.length; i++) {
      if (verdicts[i] != GpsPointVerdict.trusted) continue;
      if (links[i] != GpsLinkKind.connected || current == null) {
        current = <LocalRoutePoint>[];
        runs.add(current);
      }
      current.add(_points[i]);
    }
    return runs;
  }

  /// Trusted points only, in order.
  List<LocalRoutePoint> trustedPoints() => [
        for (var i = 0; i < _points.length; i++)
          if (verdicts[i] == GpsPointVerdict.trusted) _points[i],
      ];
}

enum _Link { connected, gap, unreachable, notIncreasing }

class _Judged {
  const _Judged(this.link, this.meters);
  final _Link link;
  final double meters;
}

bool _finiteCoordinate(LocalRoutePoint p) =>
    p.latitude.isFinite &&
    p.longitude.isFinite &&
    p.latitude >= -90 &&
    p.latitude <= 90 &&
    p.longitude >= -180 &&
    p.longitude <= 180;

double? _reportedSpeed(LocalRoutePoint p) {
  final s = p.speed;
  return s != null && s.isFinite && s >= 0 ? s : null;
}

double _accuracyOf(LocalRoutePoint p) {
  final a = p.horizontalAccuracy;
  return a != null && a.isFinite && a >= 0 ? a : gpsUnknownAccuracyMeters;
}

_Judged _judge(LocalRoutePoint from, LocalRoutePoint to) {
  final seconds = to.recordedAt.difference(from.recordedAt).inMicroseconds /
      Duration.microsecondsPerSecond;
  if (seconds <= 0) return const _Judged(_Link.notIncreasing, 0);
  final meters = Geolocator.distanceBetween(
      from.latitude, from.longitude, to.latitude, to.longitude);
  if (!(meters / seconds <= gpsImpossibleJumpThresholdMps)) {
    return _Judged(_Link.unreachable, meters);
  }
  final a = _reportedSpeed(from);
  final b = _reportedSpeed(to);
  // No reported speed at all: only the absolute ceiling (already checked).
  final knownSpeed = a == null && b == null
      ? gpsImpossibleJumpThresholdMps
      : (a ?? 0) > (b ?? 0)
          ? (a ?? 0)
          : (b ?? 0);
  final budget =
      (knownSpeed + gpsAssumedAccelerationMps2 * seconds / 2) * seconds +
          _accuracyOf(from) +
          _accuracyOf(to) +
          gpsPositionErrorFloorMeters;
  if (meters > budget) return _Judged(_Link.unreachable, meters);
  if (seconds >= gpsGapMinSeconds && meters >= gpsGapMinMeters) {
    return _Judged(_Link.gap, meters);
  }
  return _Judged(_Link.connected, meters);
}

class _Pending {
  _Pending(this.index, this.link, this.meters);
  final int index;
  final GpsLinkKind link;
  final double meters;
}

/// Classifies [points] (oldest-first, one Journey) -- see the library docs.
/// O(points); never throws; does not modify [points].
GpsTrackAnalysis analyzeGpsTrack(List<LocalRoutePoint> points) {
  final n = points.length;
  final verdicts = List<GpsPointVerdict>.filled(n, GpsPointVerdict.unconfirmed);
  final links = List<GpsLinkKind>.filled(n, GpsLinkKind.none);
  var distance = 0.0;
  var anchor = -1;
  final pending = <_Pending>[];

  for (var i = 0; i < n; i++) {
    final p = points[i];
    if (!_finiteCoordinate(p)) {
      verdicts[i] = GpsPointVerdict.invalidCoordinates;
      continue;
    }
    final accuracy = p.horizontalAccuracy;
    if (accuracy != null &&
        (!accuracy.isFinite || accuracy > gpsMaxReliableAccuracyMeters)) {
      verdicts[i] = GpsPointVerdict.lowAccuracy;
      continue;
    }
    if (anchor < 0) {
      verdicts[i] = GpsPointVerdict.trusted;
      links[i] = GpsLinkKind.none;
      anchor = i;
      continue;
    }

    final judged = _judge(points[anchor], p);
    if (judged.link != _Link.unreachable) {
      pending.clear();
      verdicts[i] = GpsPointVerdict.trusted;
      anchor = i;
      switch (judged.link) {
        case _Link.connected:
          links[i] = GpsLinkKind.connected;
          distance += judged.meters;
        case _Link.gap:
          links[i] = GpsLinkKind.gap;
        case _Link.notIncreasing:
        case _Link.unreachable:
          links[i] = GpsLinkKind.discontinuity;
      }
      continue;
    }

    // Unreachable from the confirmed track: quarantine.
    if (pending.isNotEmpty) {
      final step = _judge(points[pending.last.index], p);
      if (step.link == _Link.connected || step.link == _Link.gap) {
        pending.add(_Pending(
            i,
            step.link == _Link.connected
                ? GpsLinkKind.connected
                : GpsLinkKind.gap,
            step.meters));
      } else {
        pending
          ..clear()
          ..add(_Pending(i, GpsLinkKind.discontinuity, 0));
      }
    } else {
      pending.add(_Pending(i, GpsLinkKind.discontinuity, 0));
    }

    final spanSeconds = p.recordedAt
            .difference(points[pending.first.index].recordedAt)
            .inMicroseconds /
        Duration.microsecondsPerSecond;
    if (pending.length >= gpsQuarantinePromoteMinPoints &&
        spanSeconds >= gpsQuarantinePromoteSeconds) {
      for (var k = 0; k < pending.length; k++) {
        final item = pending[k];
        verdicts[item.index] = GpsPointVerdict.trusted;
        links[item.index] = item.link;
        if (item.link == GpsLinkKind.connected) distance += item.meters;
      }
      anchor = i;
      pending.clear();
    }
  }

  return GpsTrackAnalysis._(points, verdicts, links, distance);
}
