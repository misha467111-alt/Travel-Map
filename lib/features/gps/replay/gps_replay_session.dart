import 'gps_journey_replay.dart';
import 'gps_replay_playback.dart';
import 'gps_replay_route_progress.dart';

/// Journey Phase 1I-B1B-1 -- the deterministic session behind a Journey
/// Replay screen: one object that owns the playback clock
/// ([GpsReplayPlayback]) and the route progress ([GpsReplayRouteProgress])
/// of one [GpsReplayTimeline], and turns the raw signals of a Flutter
/// `Ticker` (cumulative elapsed time) into correct playback steps.
///
/// Pure Dart: no widgets, no timers, no futures, no streams, no wall clock.
/// The caller feeds it time; everything else is a function of those inputs,
/// so every behavior below is reproducible in a plain unit test.
///
/// ### Ticker contract
/// A Flutter `Ticker` reports the CUMULATIVE time since it was started.
/// Call [onTick] with that value. The session converts it into a per-frame
/// delta against a baseline:
///  - the first tick after [play] (or after any other event that resets the
///    baseline) only ESTABLISHES the baseline and advances nothing. A freshly
///    started ticker reports `Duration.zero` on its first frame, so nothing is
///    lost; a ticker that kept running across a pause simply continues from
///    its current value;
///  - an `elapsed` smaller than the baseline means the ticker was restarted:
///    it is treated as a new baseline, never as negative time;
///  - ticks while paused, scrubbing or after the end are ignored.
/// [restartTicker] resets the baseline explicitly.
///
/// ### Large frame deltas (stall policy)
/// A delta up to [maxFrameDelta] is applied EXACTLY: any frame rate at or
/// above `1 / maxFrameDelta` (4 fps for the default 250 ms) plays in correct
/// time. A longer gap between two ticks is a STALL -- a dropped frame burst,
/// a debugger pause, or a suspended app whose ticker was not stopped. Only
/// [maxFrameDelta] of it is applied; the rest is NOT played catch-up. The
/// visible effect: during a stall the replay falls behind real time by the
/// excess instead of leaping forward, and it never jumps to the end because
/// the app was in the background. The excess is accumulated in
/// [stallTimeDiscarded] (diagnostics). The cap applies to PRESENTATION time
/// (the time the viewer watches), before speed and the Journey-length ratio
/// are applied.
///
/// ### Lifecycle
/// [pauseForLifecycle] pauses playback when the app goes to the background.
/// The session NEVER resumes by itself: only an explicit [play] (or the end
/// of a scrub that began while playing, unless a lifecycle pause happened in
/// between) starts the clock again, and it starts from a fresh baseline.
///
/// ### Renderer deltas
/// Route changes are reported by [takeUpdate], which produces the
/// [GpsReplayProgressUpdate] relative to the PREVIOUS [takeUpdate] -- not to
/// the previous tick. A renderer that draws at a lower rate than the ticker
/// therefore loses nothing: the skipped ticks accumulate into the next
/// delta. The first [takeUpdate] initializes an empty renderer.
class GpsReplaySession {
  GpsReplaySession(
    this.timeline, {
    Duration? presentationDuration,
    GpsReplaySpeed speed = GpsReplaySpeed.one,
    this.maxFrameDelta = defaultMaxFrameDelta,
  })  : _playback = GpsReplayPlayback.forTimeline(
          timeline,
          presentationDuration: presentationDuration ??
              defaultPresentationDurationFor(timeline.activeDuration),
          speed: speed,
        ),
        _progress = GpsReplayRouteProgress(timeline) {
    if (maxFrameDelta <= Duration.zero) {
      throw ArgumentError.value(
          maxFrameDelta, 'maxFrameDelta', 'must be positive');
    }
  }

  /// The longest watch time of a full replay at 1x by default.
  static const defaultPresentationCap = Duration(seconds: 60);

  /// Default stall threshold; see the class documentation.
  static const defaultMaxFrameDelta = Duration(milliseconds: 250);

  /// The approved default: `min(60 s, activeDuration)`, so a short Journey
  /// is never shown slower than real time. A zero-length Journey (which
  /// cannot play) gets a placeholder of one second, because the clock
  /// requires a positive presentation length.
  static Duration defaultPresentationDurationFor(Duration activeDuration) {
    if (activeDuration <= Duration.zero) return const Duration(seconds: 1);
    return activeDuration < defaultPresentationCap
        ? activeDuration
        : defaultPresentationCap;
  }

  final GpsReplayTimeline timeline;

  /// Longest tick-to-tick gap applied in full; see the stall policy.
  final Duration maxFrameDelta;

  final GpsReplayPlayback _playback;
  final GpsReplayRouteProgress _progress;

  Duration? _baseline;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  bool _dirty = true; // the first takeUpdate must initialize the renderer
  Duration _stallDiscarded = Duration.zero;

  // ---- state ----------------------------------------------------------

  Duration get position => _playback.position;
  Duration get activeDuration => _playback.activeDuration;
  Duration get presentationDuration => _playback.presentationDuration;

  /// Position as a fraction of the axis in `[0, 1]`.
  double get fraction => _playback.progress;

  GpsReplaySpeed get speed => _playback.speed;

  /// Whether the clock is running. False while scrubbing.
  bool get isPlaying => _playback.isPlaying;
  bool get isAtEnd => _playback.isAtEnd;
  bool get isScrubbing => _scrubbing;

  /// Whether the Journey has any time to play (a zero-length Journey is
  /// permanently at its end).
  bool get canPlay => activeDuration > Duration.zero;

  /// Whether at least one accepted GPS sample exists.
  bool get hasRoute => timeline.sampleCount > 0;

  /// Total playback time discarded by the stall policy.
  Duration get stallTimeDiscarded => _stallDiscarded;

  /// Whether the position changed since the last [takeUpdate] (always true
  /// before the first one).
  bool get isDirty => _dirty;

  /// The cursor at the current position; pure, changes no state.
  GpsReplayCursor get cursor => _progress.cursorAt(_playback.position);

  /// Markers reached at the current position (`timeline.markers.take(n)`).
  int get reachedMarkerCount => timeline.reachedMarkerCount(_playback.position);

  // ---- ticker ---------------------------------------------------------

  /// Feeds the cumulative [elapsed] time of the ticker. Returns whether the
  /// position changed. See the class documentation for the full policy.
  bool onTick(Duration elapsed) {
    if (_scrubbing || !_playback.isPlaying) {
      _baseline = null;
      return false;
    }
    final base = _baseline;
    if (base == null || elapsed < base) {
      _baseline = elapsed;
      return false;
    }
    _baseline = elapsed;
    var delta = elapsed - base;
    if (delta > maxFrameDelta) {
      _stallDiscarded += delta - maxFrameDelta;
      delta = maxFrameDelta;
    }
    return _moved(() => _playback.advance(delta));
  }

  /// Declares that the ticker was (or will be) restarted: the next tick
  /// only establishes a new baseline.
  void restartTicker() => _baseline = null;

  // ---- transport ------------------------------------------------------

  /// Starts or resumes playback from a fresh baseline; at the end it
  /// restarts from the beginning. Ignored while scrubbing and for a
  /// zero-length Journey.
  void play() {
    if (_scrubbing) return;
    _baseline = null;
    _moved(_playback.play);
  }

  /// Pauses. Ignored while scrubbing (use [pauseForLifecycle] to cancel a
  /// scrub's resume).
  void pause() {
    if (_scrubbing) return;
    _baseline = null;
    _playback.pause();
  }

  void togglePlayPause() => _playback.isPlaying ? pause() : play();

  /// Moves to [target] (clamped). Keeps playing unless the end is reached.
  void seek(Duration target) => _moved(() => _playback.seek(target));

  void seekToFraction(double value) =>
      _moved(() => _playback.seekToFraction(value));

  void setSpeed(GpsReplaySpeed value) => _playback.setSpeed(value);

  // ---- scrubbing ------------------------------------------------------

  /// Starts a scrub (the user holds the slider): pauses the clock, remembers
  /// whether it was playing, and ignores ticks until [endScrub]. Nothing
  /// advances while scrubbing.
  void beginScrub() {
    if (_scrubbing) return;
    _scrubbing = true;
    _resumeAfterScrub = _playback.isPlaying;
    _playback.pause();
    _baseline = null;
  }

  /// Moves to [value] of the axis while scrubbing. Throws [StateError] when
  /// no scrub is in progress.
  void scrubToFraction(double value) {
    if (!_scrubbing) {
      throw StateError('scrubToFraction requires beginScrub');
    }
    _moved(() => _playback.seekToFraction(value));
  }

  /// Ends the scrub. Resumes playback (from a fresh baseline) only if it was
  /// playing when the scrub began, the end was not reached, and no
  /// [pauseForLifecycle] happened meanwhile.
  void endScrub() {
    if (!_scrubbing) return;
    _scrubbing = false;
    final resume = _resumeAfterScrub;
    _resumeAfterScrub = false;
    if (resume && !_playback.isAtEnd) {
      _baseline = null;
      _playback.play();
    }
  }

  // ---- lifecycle ------------------------------------------------------

  /// The app is going to the background (or lost focus): pause. Also
  /// cancels the resume of a scrub in progress. The session never resumes
  /// by itself afterwards.
  void pauseForLifecycle() {
    _resumeAfterScrub = false;
    _baseline = null;
    _playback.pause();
  }

  // ---- renderer -------------------------------------------------------

  /// The route change since the previous [takeUpdate] (the first one:
  /// since an empty drawing). Clears [isDirty].
  GpsReplayProgressUpdate takeUpdate() {
    _dirty = false;
    return _progress.update(_playback.position);
  }

  /// Reports the whole drawn route again from an empty drawing, for a
  /// renderer that lost its drawing. Cost is proportional to the drawn
  /// route. Clears [isDirty].
  GpsReplayProgressUpdate resync() {
    _dirty = false;
    _progress.update(_playback.position);
    return _progress.resync();
  }

  bool _moved(void Function() change) {
    final before = _playback.position;
    change();
    final changed = _playback.position != before;
    if (changed) _dirty = true;
    return changed;
  }
}
