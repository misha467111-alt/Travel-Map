import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../local/gps_local_database_provider.dart';
import '../replay/gps_journey_replay.dart';
import '../replay/gps_replay_playback.dart';
import '../replay/gps_replay_polyline_plan.dart';
import '../replay/gps_replay_route_progress.dart';
import '../replay/gps_replay_session.dart';
import 'gps_journey_details_view.dart' show gpsJourneyDetailsProvider;
import 'gps_journey_replay_controls.dart';
import 'gps_journey_replay_map.dart';

/// Journey Phase 1I-B1B-2 -- the Replay timeline of one completed Journey.
///
/// Reuses the Journey Details provider (so the Journey is NOT read from Drift
/// a second time) and adds only the one read Details does not keep: the
/// persisted route events, which `GpsReplayTimeline.fromDetails` needs.
final gpsJourneyReplayTimelineProvider = FutureProvider.autoDispose
    .family<GpsReplayTimeline?, ({String ownerId, String routeId})>(
        (ref, args) async {
  final details = await ref.watch(gpsJourneyDetailsProvider(args).future);
  if (details == null) return null;
  final db = ref.watch(gpsLocalDatabaseProvider);
  final events = await db.getRouteEvents(
      ownerId: args.ownerId, recordedRouteId: args.routeId);
  return GpsReplayTimeline.fromDetails(details,
      events: events, now: DateTime.now().toUtc());
});

/// Full-screen Journey Replay. Loading, error and empty states are handled
/// here; the replay itself lives in [GpsJourneyReplayView].
class GpsJourneyReplayScreen extends ConsumerWidget {
  const GpsJourneyReplayScreen({
    super.key,
    required this.ownerId,
    required this.routeId,
  });

  final String ownerId;
  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (ownerId: ownerId, routeId: routeId);
    return Scaffold(
      appBar: AppBar(title: const Text('Відтворення подорожі')),
      body: ref.watch(gpsJourneyReplayTimelineProvider(args)).when(
            loading: () => const Center(
              child: CircularProgressIndicator(key: Key('gps_replay_loading')),
            ),
            error: (_, __) => const _ReplayMessage(
              messageKey: Key('gps_replay_error'),
              text: 'Не вдалося завантажити подорож.',
            ),
            data: (timeline) {
              if (timeline == null) {
                return const _ReplayMessage(
                  messageKey: Key('gps_replay_unavailable'),
                  text: 'Подорож недоступна.',
                );
              }
              if (timeline.sampleCount == 0) {
                return const _ReplayMessage(
                  messageKey: Key('gps_replay_empty'),
                  text: 'У цій подорожі немає збережених точок маршруту.',
                );
              }
              return GpsJourneyReplayView(timeline: timeline);
            },
          ),
    );
  }
}

class _ReplayMessage extends StatelessWidget {
  const _ReplayMessage({required this.messageKey, required this.text});
  final Key messageKey;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(text, key: messageKey, textAlign: TextAlign.center),
        ),
      );
}

/// The replay itself: map + controls driven by one [GpsReplaySession].
///
/// ### Time
/// One `Ticker` runs ONLY while the session is playing and feeds its
/// cumulative `elapsed` into [GpsReplaySession.onTick] -- the single place
/// the clock advances. Every start of the ticker is preceded by
/// `restartTicker()`, so a restarted ticker never counts as negative time.
///
/// ### Rendering
/// Map updates are decoupled from the ticker: at most one render per
/// [renderInterval] of ticker time (plus one on every user action and at the
/// end). A render takes `session.takeUpdate()` -- relative to the previous
/// take, so skipped ticks lose nothing -- applies it to the planner in order
/// and hands the result to [GpsReplayRenderModel], whose listeners (the map)
/// are the only widgets rebuilt. The control bar has its own notifier.
///
/// ### Scrub / lifecycle
/// The scrub is closed by the slider's end, by a cancelled pointer, when the
/// app leaves the foreground, and on dispose. The app going inactive pauses
/// and NEVER resumes by itself; on return the drawing is rebuilt with a
/// resync (planner and renderer reset together).
class GpsJourneyReplayView extends StatefulWidget {
  const GpsJourneyReplayView({
    super.key,
    required this.timeline,
    this.renderInterval = const Duration(milliseconds: 33),
  });

  final GpsReplayTimeline timeline;

  /// Minimum ticker time between two map renders.
  final Duration renderInterval;

  @override
  State<GpsJourneyReplayView> createState() => _GpsJourneyReplayViewState();
}

class _GpsJourneyReplayViewState extends State<GpsJourneyReplayView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final GpsReplaySession _session = GpsReplaySession(widget.timeline);
  late final GpsReplayPolylinePlanner _planner =
      GpsReplayPolylinePlanner(widget.timeline);
  late final Ticker _ticker = createTicker(_onTick);
  late final ValueNotifier<GpsReplayControlsState> _controls =
      ValueNotifier(_controlsState());
  GpsReplayRenderModel? _model;
  Duration _lastRender = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_model != null) return;
    final primary = Theme.of(context).colorScheme.primary;
    _model = GpsReplayRenderModel(
      ghostLines: _planner.ghostLines,
      progressColor: primary,
      ghostColor: primary.withValues(alpha: 0.3),
    );
    _render();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.pauseForLifecycle();
    _session.endScrub();
    _ticker.stop();
    _ticker.dispose();
    _controls.dispose();
    _model?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The native map may have been recreated: redraw from scratch.
      _resync();
      return;
    }
    // inactive, hidden, paused, detached: stop, close any scrub, never resume.
    _session.pauseForLifecycle();
    _session.endScrub();
    _afterAction();
  }

  // ---- clock ---------------------------------------------------------

  void _onTick(Duration elapsed) {
    _session.onTick(elapsed);
    if (!_session.isPlaying) _syncTicker();
    if (elapsed - _lastRender >= widget.renderInterval || !_session.isPlaying) {
      _lastRender = elapsed;
      _render();
    }
  }

  // Keeps the ticker running exactly while the session plays.
  void _syncTicker() {
    if (_session.isPlaying && !_ticker.isActive) {
      _session.restartTicker();
      _lastRender = Duration.zero;
      _ticker.start();
    } else if (!_session.isPlaying && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _afterAction() {
    _syncTicker();
    _render();
  }

  // ---- rendering -----------------------------------------------------

  void _render() {
    if (_session.isDirty) _apply(_session.takeUpdate());
    _publish();
  }

  void _apply(GpsReplayProgressUpdate update) {
    _model?.apply(_planner.apply(update), update.cursor);
  }

  void _resync() {
    _planner.reset();
    _model?.reset();
    _apply(_session.resync());
    _publish();
  }

  GpsReplayControlsState _controlsState() {
    final total = _session.presentationDuration;
    return GpsReplayControlsState(
      current: Duration(
          microseconds: (total.inMicroseconds * _session.fraction).round()),
      total: total,
      fraction: _session.fraction,
      isPlaying: _session.isPlaying,
      speed: _session.speed,
      canPlay: _session.canPlay,
    );
  }

  void _publish() => _controls.value = _controlsState();

  // ---- user actions --------------------------------------------------

  void _onPlayPause() {
    _session.togglePlayPause();
    _afterAction();
  }

  void _onSpeed(GpsReplaySpeed speed) {
    _session.setSpeed(speed);
    _publish();
  }

  void _onScrubStart() {
    _session.beginScrub();
    _afterAction();
  }

  void _onScrub(double value) {
    if (!_session.isScrubbing) _session.beginScrub();
    _session.scrubToFraction(value);
    _render();
  }

  void _onScrubEnd() {
    _session.endScrub();
    _afterAction();
  }

  @override
  Widget build(BuildContext context) {
    final model = _model!;
    final bounds = gpsReplayRouteBounds(widget.timeline)!;
    return Stack(
      children: [
        Positioned.fill(
          child: GpsJourneyReplayMap(
            key: const Key('gps_replay_map'),
            model: model,
            bounds: bounds,
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
              child: ValueListenableBuilder<GpsReplayControlsState>(
                valueListenable: _controls,
                builder: (context, state, _) => GpsJourneyReplayControls(
                  state: state,
                  onPlayPause: _onPlayPause,
                  onSpeed: _onSpeed,
                  onScrubStart: _onScrubStart,
                  onScrub: _onScrub,
                  onScrubEnd: _onScrubEnd,
                  onScrubCancel: _onScrubEnd,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
