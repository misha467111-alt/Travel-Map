import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import 'gps_recording_ui_state.dart';

/// Phase 4C — an isolated ticker so the elapsed-time readout can update
/// once a second without rebuilding anything else on screen (the
/// `Timer.periodic` lives entirely inside this one `StatefulWidget`).
///
/// Deliberately displays plain wall-clock time since [startedAt] — NOT
/// "active recording time" with paused segments excluded. Phase 4B
/// established that [startedAt] is the only cheap timestamp
/// [GpsRecordingState] exposes; there is no cheap way to reconstruct how
/// much of that time was spent paused without reading the full local
/// route-event history (`LocalRouteEvents`), which Phase 4C is
/// explicitly instructed not to query just for this display. Excluding
/// paused time would therefore require either an expensive query or a
/// widget-local pause/resume accumulator that silently produces a wrong
/// number the moment this widget is freshly mounted mid-session (e.g.
/// after an app restart recovers a `recoverable` route) — exactly the
/// "fabricated accuracy" this phase forbids. So instead: the ticker only
/// *runs* while [isTicking] is true (i.e. while actually recording,
/// matching real engine semantics), and freezes the last displayed value
/// the instant recording stops ticking (pause/finish/anything else) —
/// but the *value itself* is always the honest, simple "time since
/// start", clearly labelled as such by the caller.
class GpsElapsedTimeText extends StatefulWidget {
  const GpsElapsedTimeText({
    super.key,
    required this.startedAt,
    required this.isTicking,
    this.style,
    this.now = DateTime.now,
  });

  final DateTime? startedAt;

  /// True only while the engine is actually in
  /// [GpsRecordingStatus.recording] — the one moment new elapsed time is
  /// genuinely accruing. Passing `false` (e.g. while `paused`) stops the
  /// internal timer entirely rather than merely not calling it.
  final bool isTicking;

  final TextStyle? style;

  /// Injectable clock, defaulting to the real [DateTime.now] in
  /// production. Exists purely so widget tests can advance a
  /// deterministic virtual clock in lockstep with `tester.pump(...)`'s
  /// own virtualized `Timer`s, instead of depending on real wall-clock
  /// time elapsing during test execution.
  final DateTime Function() now;

  @override
  State<GpsElapsedTimeText> createState() => _GpsElapsedTimeTextState();
}

class _GpsElapsedTimeTextState extends State<GpsElapsedTimeText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant GpsElapsedTimeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isTicking != widget.isTicking ||
        oldWidget.startedAt != widget.startedAt) {
      _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.isTicking && widget.startedAt != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = widget.startedAt;
    if (startedAt == null) {
      return Text('--:--', style: widget.style);
    }
    final elapsed = widget.now().toUtc().difference(startedAt.toUtc());
    return Text(_formatDuration(elapsed), style: widget.style);
  }
}

String _formatDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Phase 4C — the cheap-stats row: elapsed time (ticking, see
/// [GpsElapsedTimeText]), point count (straight from
/// [GpsRecordingStatsUiState.pointCount] — never a Drift query), and a
/// plain, honestly-labelled accuracy readout. Deliberately has NO
/// distance field at all: Phase 4B established live distance is not
/// cheaply available, and Phase 4C is explicitly forbidden from
/// inventing one — there is simply no widget for it here.
class GpsRecordingStats extends StatelessWidget {
  const GpsRecordingStats({
    super.key,
    required this.stats,
    required this.isTicking,
    this.now = DateTime.now,
  });

  final GpsRecordingStatsUiState stats;
  final bool isTicking;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Тривалість',
            value: GpsElapsedTimeText(
              key: const Key('gps_recording_elapsed_time'),
              startedAt: stats.startedAt,
              isTicking: isTicking,
              now: now,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        Expanded(
          child: _StatTile(
            label: 'Точок',
            value: Text(
              '${stats.pointCount}',
              key: const Key('gps_recording_point_count'),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        Expanded(
          child: _StatTile(
            label: 'Точність',
            value: Text(
              stats.lastHorizontalAccuracyMeters != null
                  ? '±${stats.lastHorizontalAccuracyMeters!.round()} м'
                  : '—',
              key: const Key('gps_recording_accuracy'),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.xs),
        value,
      ],
    );
  }
}
