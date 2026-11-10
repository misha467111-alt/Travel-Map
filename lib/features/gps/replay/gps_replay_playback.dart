import 'gps_journey_replay.dart' show GpsReplayTimeline;

/// The playback speeds a Journey Replay offers, as multipliers of the
/// presentation rate.
enum GpsReplaySpeed {
  half(0.5),
  one(1),
  two(2),
  four(4);

  const GpsReplaySpeed(this.multiplier);

  final double multiplier;
}

/// Journey Phase 1I-B1A -- the deterministic playback clock of a Journey
/// Replay. Pure Dart: it owns no ticker, no timer, no stream and never reads
/// the wall clock. The caller drives it by passing the time that has elapsed
/// since the previous frame to [advance], so a test (or a future screen) fully
/// controls time.
///
/// ### Two durations
///  - [activeDuration]: the recorded active length of the Journey (the end of
///    the playback axis of a `GpsReplayTimeline`).
///  - [presentationDuration]: how long the replay takes to watch at 1x. The
///    ratio of the two is the base rate, so a 3-hour Journey and a 10-minute
///    one can both play in about a minute. [defaultPresentationDuration] is
///    the proposed product default; nothing here depends on it.
///
/// [position] is always a playback time on the Journey's active axis, ready
/// to hand to `GpsReplayTimeline.positionAt` and friends. At speed `s` the
/// position grows by `elapsed * s * activeDuration / presentationDuration`.
///
/// ### Rules
///  - The position is clamped into `[0, activeDuration]`.
///  - Reaching the end stops playback ([isPlaying] becomes false,
///    [isAtEnd] true). [play] at the end restarts from the beginning.
///  - [seek] never changes the play / pause intent, except that seeking to
///    the end stops playback by the same rule.
///  - A zero-length Journey is permanently at its end and cannot play.
class GpsReplayPlayback {
  GpsReplayPlayback({
    required this.activeDuration,
    this.presentationDuration = defaultPresentationDuration,
    GpsReplaySpeed speed = GpsReplaySpeed.one,
  })  : _speed = speed,
        _end = activeDuration.inMicroseconds.toDouble(),
        _rate = activeDuration.inMicroseconds /
            (presentationDuration.inMicroseconds == 0
                ? 1
                : presentationDuration.inMicroseconds) {
    if (activeDuration.isNegative) {
      throw ArgumentError.value(
          activeDuration, 'activeDuration', 'must not be negative');
    }
    if (presentationDuration <= Duration.zero) {
      throw ArgumentError.value(
          presentationDuration, 'presentationDuration', 'must be positive');
    }
  }

  /// A clock for [timeline]'s whole playback axis.
  factory GpsReplayPlayback.forTimeline(
    GpsReplayTimeline timeline, {
    Duration presentationDuration = defaultPresentationDuration,
    GpsReplaySpeed speed = GpsReplaySpeed.one,
  }) =>
      GpsReplayPlayback(
        activeDuration: timeline.activeDuration,
        presentationDuration: presentationDuration,
        speed: speed,
      );

  /// The proposed product default: a Journey replays in about a minute at 1x.
  static const defaultPresentationDuration = Duration(seconds: 60);

  /// Recorded active length of the Journey (the end of the axis).
  final Duration activeDuration;

  /// How long the whole Journey takes to watch at 1x.
  final Duration presentationDuration;

  final double _end; // microseconds
  final double _rate; // active microseconds per presentation microsecond
  GpsReplaySpeed _speed;
  double _position = 0; // microseconds, always within [0, _end]
  bool _playing = false;

  GpsReplaySpeed get speed => _speed;
  bool get isPlaying => _playing;

  /// Current playback time on the active axis (microsecond resolution).
  ///
  /// The clock keeps fractional microseconds, but this value is whole
  /// microseconds: it equals [activeDuration] if and only if [isAtEnd]. A
  /// clock that is not yet at the end but within half a microsecond of it
  /// reports the last microsecond before the end instead of rounding up to
  /// it, so [position], [isAtEnd] and [isPlaying] never disagree.
  Duration get position {
    if (isAtEnd) return activeDuration;
    final rounded = _position.round();
    final last = activeDuration.inMicroseconds - 1;
    return Duration(microseconds: rounded > last ? last : rounded);
  }

  /// Whether the end of the Journey has been reached.
  bool get isAtEnd => _position >= _end;

  /// Position as a fraction of [activeDuration] in `[0, 1]`; `1` for a
  /// zero-length Journey (it is already at its end).
  double get progress => _end == 0 ? 1 : _position / _end;

  /// Starts (or resumes) playback. At the end it restarts from the
  /// beginning. Does nothing for a zero-length Journey.
  void play() {
    if (_end == 0) return;
    if (isAtEnd) _position = 0;
    _playing = true;
  }

  void pause() => _playing = false;

  /// Moves to [target] (clamped into the axis). Keeps playing if it was
  /// playing, unless the end is reached.
  void seek(Duration target) {
    _position = _clampMicros(target.inMicroseconds.toDouble());
    _stopAtEnd();
  }

  /// Moves to [fraction] of the axis (clamped into `[0, 1]`), for a slider.
  void seekToFraction(double fraction) {
    if (fraction.isNaN) {
      throw ArgumentError.value(fraction, 'fraction', 'must not be NaN');
    }
    _position = _clampMicros(fraction.clamp(0.0, 1.0) * _end);
    _stopAtEnd();
  }

  void setSpeed(GpsReplaySpeed value) => _speed = value;

  /// Advances the clock by [elapsed] of presentation time (the time since the
  /// previous frame) and returns the new [position]. A no-op while paused.
  /// An arbitrarily large [elapsed] (for example after the app was
  /// suspended) simply reaches the end.
  Duration advance(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
    if (!_playing || elapsed == Duration.zero) return position;
    _position = _clampMicros(
        _position + elapsed.inMicroseconds * _speed.multiplier * _rate);
    _stopAtEnd();
    return position;
  }

  double _clampMicros(double value) =>
      value < 0 ? 0 : (value > _end ? _end : value);

  void _stopAtEnd() {
    if (isAtEnd) _playing = false;
  }
}
