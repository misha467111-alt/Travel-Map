import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Debug-only measurement of the Replay render path (never active in
/// release): the interval between map renders, the cost of planning and
/// applying an update, how many map objects change per render, and the
/// Flutter frame timings. Summaries go to the log (`REPLAY_PERF`).
class ReplayPerfProbe {
  ReplayPerfProbe({required this.label}) {
    if (kDebugMode) {
      _watch.start();
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
    }
  }

  final String label;
  final _watch = Stopwatch();
  int _lastAtUs = -1;
  final _intervals = <int>[];
  final _applyUs = <int>[];
  int _upserted = 0, _removed = 0, _head = 0, _renders = 0, _dirtyRenders = 0;
  final _build = <int>[];
  final _raster = <int>[];
  int _slowFrames = 0;

  void dispose() {
    if (kDebugMode) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  /// One render. [applyUs] is the time spent planning and applying the update
  /// (0 when nothing was dirty).
  void render({
    required int applyUs,
    required int upserted,
    required int removed,
    required bool headChanged,
    required bool dirty,
  }) {
    if (!kDebugMode) return;
    final now = _watch.elapsedMicroseconds;
    if (_lastAtUs >= 0) _intervals.add(now - _lastAtUs);
    _lastAtUs = now;
    _renders++;
    if (dirty) {
      _dirtyRenders++;
      _applyUs.add(applyUs);
      _upserted += upserted;
      _removed += removed;
      if (headChanged) _head++;
    }
    if (_renders % 90 == 0) _flush();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds;
      final r = t.rasterDuration.inMicroseconds;
      _build.add(b);
      _raster.add(r);
      if (t.totalSpan.inMicroseconds > 16700) _slowFrames++;
    }
  }

  static int _pct(List<int> v, double p) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[((s.length - 1) * p).round()];
  }

  void _flush() {
    String ms(int us) => (us / 1000).toStringAsFixed(1);
    debugPrint('REPLAY_PERF[$label] renders=$_renders dirty=$_dirtyRenders '
        'interval_ms p50=${ms(_pct(_intervals, .5))} '
        'p90=${ms(_pct(_intervals, .9))} max=${ms(_pct(_intervals, 1))} '
        'apply_ms p50=${ms(_pct(_applyUs, .5))} p90=${ms(_pct(_applyUs, .9))} '
        'max=${ms(_pct(_applyUs, 1))} '
        'lines/render upserted=${(_upserted / (_dirtyRenders == 0 ? 1 : _dirtyRenders)).toStringAsFixed(2)} '
        'removed=$_removed headChanges=$_head '
        'frames=${_build.length} slow(>16.7ms)=$_slowFrames '
        'build_ms p50=${ms(_pct(_build, .5))} p90=${ms(_pct(_build, .9))} '
        'raster_ms p50=${ms(_pct(_raster, .5))} p90=${ms(_pct(_raster, .9))}');
    _intervals.clear();
    _applyUs.clear();
    _build.clear();
    _raster.clear();
    _upserted = _removed = _head = _renders = _dirtyRenders = _slowFrames = 0;
  }
}
