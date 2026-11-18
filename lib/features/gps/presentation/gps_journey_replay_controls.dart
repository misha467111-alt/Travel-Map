import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import '../replay/gps_replay_playback.dart';

/// Journey Phase 1I-B1B-2 -- what the Replay control bar shows. Immutable;
/// the screen publishes a new one through a `ValueNotifier`, so only the bar
/// is rebuilt on a frame.
class GpsReplayControlsState {
  const GpsReplayControlsState({
    required this.current,
    required this.total,
    required this.fraction,
    required this.isPlaying,
    required this.speed,
    required this.canPlay,
  });

  /// Presentation time watched so far / of the whole replay at 1x.
  final Duration current;
  final Duration total;

  /// Position on the axis in `[0, 1]`.
  final double fraction;
  final bool isPlaying;
  final GpsReplaySpeed speed;
  final bool canPlay;

  @override
  bool operator ==(Object other) =>
      other is GpsReplayControlsState &&
      other.current == current &&
      other.total == total &&
      other.fraction == fraction &&
      other.isPlaying == isPlaying &&
      other.speed == speed &&
      other.canPlay == canPlay;

  @override
  int get hashCode =>
      Object.hash(current, total, fraction, isPlaying, speed, canPlay);
}

/// `m:ss` (or `h:mm:ss`).
String formatGpsReplayTime(Duration value) {
  final total = value.inSeconds < 0 ? 0 : value.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

String _speedLabel(GpsReplaySpeed speed) => switch (speed) {
      GpsReplaySpeed.half => '0.5x',
      GpsReplaySpeed.one => '1x',
      GpsReplaySpeed.two => '2x',
      GpsReplaySpeed.four => '4x',
    };

/// Play/Pause, a seekable timeline, the times and the speed choice. Dumb:
/// it holds no playback state.
///
/// Scrub callbacks: [onScrubStart] / [onScrub] / [onScrubEnd] follow the
/// slider; [onScrubCancel] is also called when the pointer is cancelled (the
/// slider is not guaranteed to report the end of a cancelled drag), so the
/// owner can always close the scrub.
class GpsJourneyReplayControls extends StatefulWidget {
  const GpsJourneyReplayControls({
    super.key,
    required this.state,
    required this.onPlayPause,
    required this.onSpeed,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onScrubCancel,
  });

  final GpsReplayControlsState state;
  final VoidCallback onPlayPause;
  final ValueChanged<GpsReplaySpeed> onSpeed;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrub;
  final VoidCallback onScrubEnd;
  final VoidCallback onScrubCancel;

  @override
  State<GpsJourneyReplayControls> createState() =>
      _GpsJourneyReplayControlsState();
}

class _GpsJourneyReplayControlsState extends State<GpsJourneyReplayControls> {
  // Flutter skips a child only when the very same widget instance is passed
  // again, so the play button and the speed selector are cached and recreated
  // only when something about them changed.
  _PlayButton? _play;
  _SpeedSelector? _speed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final onPlayPause = widget.onPlayPause;
    final onSpeed = widget.onSpeed;
    final onScrubStart = widget.onScrubStart;
    final onScrub = widget.onScrub;
    final onScrubEnd = widget.onScrubEnd;
    final onScrubCancel = widget.onScrubCancel;
    final play = _play;
    if (play == null ||
        play.isPlaying != state.isPlaying ||
        play.canPlay != state.canPlay ||
        play.onPressed != onPlayPause) {
      _play = _PlayButton(
        isPlaying: state.isPlaying,
        canPlay: state.canPlay,
        onPressed: onPlayPause,
      );
    }
    final speed = _speed;
    if (speed == null ||
        speed.speed != state.speed ||
        speed.onSpeed != onSpeed) {
      _speed = _SpeedSelector(speed: state.speed, onSpeed: onSpeed);
    }
    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _play!,
                const SizedBox(width: AppSpacing.sm),
                Text(formatGpsReplayTime(state.current),
                    key: const Key('gps_replay_time_current'),
                    style: theme.textTheme.bodySmall),
                Expanded(
                  child: Listener(
                    onPointerCancel: (_) => onScrubCancel(),
                    child: Slider(
                      key: const Key('gps_replay_slider'),
                      value: state.fraction.clamp(0.0, 1.0),
                      onChangeStart:
                          state.canPlay ? (_) => onScrubStart() : null,
                      onChanged: state.canPlay ? onScrub : null,
                      onChangeEnd: state.canPlay ? (_) => onScrubEnd() : null,
                    ),
                  ),
                ),
                Text(formatGpsReplayTime(state.total),
                    key: const Key('gps_replay_time_total'),
                    style: theme.textTheme.bodySmall),
              ],
            ),
            _speed!,
          ],
        ),
      ),
    );
  }
}

// While a Replay plays, only the time texts and the slider change on a
// frame. The play button and the speed selector are separate widgets with
// value equality, so Flutter skips rebuilding them when nothing about them
// changed (measured on a Galaxy A50: rebuilding the whole bar on every
// render cost about 20 ms of UI-thread build time per frame).
@immutable
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.canPlay,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool canPlay;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
        key: const Key('gps_replay_play_pause'),
        tooltip: isPlaying ? 'Пауза' : 'Відтворити',
        onPressed: canPlay ? onPressed : null,
        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
      );
}

@immutable
class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector({required this.speed, required this.onSpeed});

  final GpsReplaySpeed speed;
  final ValueChanged<GpsReplaySpeed> onSpeed;

  @override
  Widget build(BuildContext context) => SegmentedButton<GpsReplaySpeed>(
        key: const Key('gps_replay_speed'),
        showSelectedIcon: false,
        segments: [
          for (final value in GpsReplaySpeed.values)
            ButtonSegment(
              value: value,
              label: Text(_speedLabel(value),
                  key: Key('gps_replay_speed_${_speedLabel(value)}')),
            ),
        ],
        selected: {speed},
        onSelectionChanged: (s) => onSpeed(s.first),
      );
}
