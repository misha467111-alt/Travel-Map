import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_design.dart';
import '../../map/presentation/clustered_location_map.dart';
import '../../map/providers/map_provider.dart';
import '../local/gps_local_database.dart';
import '../local/gps_local_database_provider.dart';
import '../recording/gps_recording_controller.dart';
import '../recording/gps_recording_state.dart';
import '../sync/gps_sync_coordinator.dart';
import 'gps_recording_controls.dart';
import 'gps_recording_error_view.dart';
import 'gps_recording_header.dart';
import 'gps_recording_status_card.dart';
import 'gps_recording_ui_state.dart';
import 'gps_recovery_card.dart';
import 'gps_start_view.dart';
import 'gps_sync_ui_state.dart';

/// Phase 4D — reactive view of one route's local GPS points, oldest-first.
/// Reuses [GpsLocalDatabase.watchRoutePoints] directly (already existed
/// before this phase -- no new DAO method, no schema change, no engine
/// file touched) rather than inventing a parallel query.
///
/// `.autoDispose`: only ever watched while the recording map screen is on
/// screen (see [_LiveTrackMap]) -- the underlying recording itself is
/// entirely unaffected by this provider's lifetime, exactly like
/// [gpsRouteSyncStateProvider] in `gps_sync_coordinator.dart`.
final gpsRoutePointsProvider = StreamProvider.autoDispose
    .family<List<LocalRoutePoint>, ({String ownerId, String routeId})>(
        (ref, args) {
  final db = ref.watch(gpsLocalDatabaseProvider);
  return db.watchRoutePoints(
      ownerId: args.ownerId, recordedRouteId: args.routeId);
});

const _fallbackMapTarget = LatLng(50.4501, 30.5234);

/// Phase 4D — the dedicated, full-screen GPS recording mode reached from
/// Map's "Записати маршрут" toolbar action. Thin outer wrapper only (same
/// shape as `GpsRecordingScreen`/`MapScreen`'s own auth-gated wrappers):
/// resolves the owner id and delegates everything else to
/// [GpsRecordingMapBody], which is what tests actually exercise (a live
/// Supabase session cannot be simulated in a widget test, matching the
/// exact reasoning `GpsRecordingScreen` itself was already built with in
/// Phase 4C).
class GpsRecordingMapScreen extends ConsumerWidget {
  const GpsRecordingMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Потрібно увійти в акаунт.')),
      );
    }

    final stateAsync = ref.watch(gpsRecordingStateProvider(userId));
    final controller = ref.read(gpsRecordingControllerProvider(userId));
    // Constructed alongside the recording controller, matching
    // GpsRecordingScreen's own established rationale: a sync pass is
    // always attempted whenever a GPS recording surface is open.
    final syncCoordinator = ref.read(gpsSyncCoordinatorProvider(userId));

    return Scaffold(
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Text('Не вдалося завантажити стан запису.'),
        ),
        data: (state) => GpsRecordingMapBody(
          ownerId: userId,
          state: state,
          controller: controller,
          syncCoordinator: syncCoordinator,
        ),
      ),
    );
  }
}

/// The real, testable body: a live [ClusteredLocationMap] with overlaid
/// Phase 4C controls. Public only so tests can construct it directly with
/// an injected [state]/[controller]/[syncCoordinator] -- exactly the same
/// reason `map_screen.dart` keeps `LocationDetailsContent` public.
///
/// CRITICAL PERFORMANCE NOTE (Phase 4A's own P0 risk): [state] changes on
/// every accepted GPS point (see `GpsRecordingController._onPosition`),
/// so this widget's own `build()` re-running per point is unavoidable and
/// already an accepted Phase 4C behavior (it is exactly what drives the
/// live point-count/accuracy stat text). What is NOT acceptable is that
/// re-run recomputing the header/status/controls tree needlessly, or the
/// map recomputing its *own* per-point cost more than once. This widget
/// solves both: [GpsRecordingHeader]/[GpsRecordingStatusCard]/
/// [GpsRecordingControls] are cheap, stateless mappings of [state] (no
/// avoiding their rebuild, and it is inexpensive). The map itself is
/// isolated into [_LiveTrackMap], a *separate* `ConsumerWidget` that
/// watches [gpsRoutePointsProvider] independently of this widget's own
/// rebuild cycle -- so a rebuild of this body (e.g. from a sync-status
/// change) never forces an extra, redundant polyline recomputation, and
/// [_LiveTrackMap]'s own rebuild never forces the header/status/controls
/// to redo any work either. [ClusteredLocationMap] always keeps the same
/// `Key` here, so Flutter reuses its `State` (and therefore the native
/// Google Maps platform view and the one-shot [InitialGpsCameraPolicy]
/// latch) across every one of these rebuilds rather than recreating it.
///
/// Documented, accepted tradeoff: [gpsRoutePointsProvider] re-runs a full
/// ordered `SELECT` over every point of the route and remaps the entire
/// list to `LatLng` on every single new point (inherited as-is from the
/// already-existing [GpsLocalDatabase.watchRoutePoints] -- not a new
/// query written for this phase). This is O(n) work per point and O(n^2)
/// over a whole session. For a typical recording (samples roughly every
/// few seconds, sessions of minutes to a few hours -> low thousands of
/// points) this is microseconds of local SQLite/list work per update and
/// not a real-world problem. A genuinely unbounded, many-hour recording
/// with tens of thousands of points would eventually make this
/// measurable; a cursor-based incremental/append-only polyline cache
/// would be the fix, but building that now would be exactly the kind of
/// speculative complexity Phase 4D's own scope explicitly excludes ("no
/// route simplification needed yet"). Left as an explicit open issue.
class GpsRecordingMapBody extends ConsumerWidget {
  const GpsRecordingMapBody({
    super.key,
    required this.ownerId,
    required this.state,
    required this.controller,
    required this.syncCoordinator,
  });

  final String ownerId;
  final GpsRecordingState state;
  final GpsRecordingController controller;
  final GpsSyncCoordinator syncCoordinator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiState = mapGpsRecordingUiState(state);
    final routeId = state.routeId;

    GpsSyncUiState? sync;
    if (routeId != null) {
      final routeAsync = ref.watch(
        gpsRouteSyncStateProvider((ownerId: ownerId, routeId: routeId)),
      );
      final route = routeAsync.value;
      if (route != null) sync = mapGpsSyncUiState(route.syncStatus);
    }

    return Stack(
      children: [
        _LiveTrackMap(ownerId: ownerId, routeId: routeId),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _OverlayPanel(
              child: GpsRecordingHeader(
                uiState: uiState,
                // Minimizing/backing out must never discard or stop an
                // active recording -- GpsRecordingController survives
                // navigation by design (non-autoDispose provider), so a
                // plain pop is the entire, correct behavior. No
                // confirmation is required here (unlike discard):
                // leaving this screen does not affect the recording.
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: 0,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: SingleChildScrollView(
                child: _buildContent(context, uiState, sync),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    GpsRecordingUiState uiState,
    GpsSyncUiState? sync,
  ) {
    final routeId = state.routeId;

    switch (uiState.status) {
      case GpsRecordingStatus.idle:
        return _OverlayPanel(
          child: GpsStartView(
            key: const Key('gps_start_view'),
            label: 'Почати запис',
            onStart: controller.start,
          ),
        );

      case GpsRecordingStatus.completed:
        return _OverlayPanel(
          child: GpsStartView(
            key: const Key('gps_start_view'),
            label: 'Новий запис',
            statusCard: GpsRecordingStatusCard(
              uiState: uiState,
              sync: sync,
              // Phase 4E fix: the just-finished route's own sync retry
              // was never wired here (only the recording/paused case
              // passed onRetrySync) -- a failed sync on a completed
              // route had no way to be retried from this screen. state
              // .routeId is still set after finish() (copyWith retains
              // it), so this is the same wiring the active case already
              // uses, just extended to the completed case.
              onRetrySync: routeId == null
                  ? null
                  : () => syncCoordinator.retryRoute(routeId),
            ),
            onStart: controller.start,
          ),
        );

      case GpsRecordingStatus.preparing:
        return const _OverlayPanel(
          child: GpsStartView(
            key: Key('gps_start_view'),
            label: 'Підготовка…',
            onStart: null, // prevents duplicate start taps while preparing
          ),
        );

      case GpsRecordingStatus.recording:
      case GpsRecordingStatus.paused:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GpsRecordingStatusCard(
              uiState: uiState,
              sync: sync,
              onRetrySync: routeId == null
                  ? null
                  : () => syncCoordinator.retryRoute(routeId),
            ),
            const SizedBox(height: AppSpacing.sm),
            _OverlayPanel(
              child: GpsRecordingControls(
                uiState: uiState,
                onPause: controller.pause,
                onResume: controller.resume,
                onFinish: controller.finish,
                onAddWaypoint: () =>
                    controller.addWaypoint(waypointType: 'custom'),
                onDiscard: controller.discard,
              ),
            ),
          ],
        );

      case GpsRecordingStatus.finishing:
        // No controls at all while finishing -- prevents a duplicate
        // finish tap; the transition is normally near-instant.
        return GpsRecordingStatusCard(uiState: uiState, sync: sync);

      case GpsRecordingStatus.recoverable:
        return GpsRecoveryCard(
          pointCount: uiState.stats.pointCount,
          onResume: controller.resumeRecoverableRecording,
          onFinish: controller.finishRecoverableRecording,
          onDiscard: controller.discardRecoverableRecording,
        );

      case GpsRecordingStatus.permissionError:
      case GpsRecordingStatus.serviceError:
      case GpsRecordingStatus.otherError:
        return _OverlayPanel(
          child: GpsRecordingErrorView(
            kind: uiState.errorKind!,
            detail: uiState.errorDetail,
            onRetry: controller.start,
          ),
        );
    }
  }
}

class _OverlayPanel extends StatelessWidget {
  const _OverlayPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: child,
        ),
      );
}

/// Phase 4D — the only widget that watches [gpsRoutePointsProvider] (and,
/// for the current-position marker, [currentPositionProvider]). Isolating
/// both into this small, separate `ConsumerWidget` (rather than watching
/// them in [GpsRecordingMapBody] itself) means a new GPS point never
/// forces the header/status card/controls to redo any work, and vice
/// versa -- see [GpsRecordingMapBody]'s own doc comment for the full
/// reasoning. [ClusteredLocationMap] keeps a stable [Key] across every
/// rebuild of this widget so its `State` (native map view, one-shot
/// camera-recenter latch) is never recreated.
///
/// [userPosition] reuses [currentPositionProvider] exactly as the normal
/// [MapScreen] does (a one-shot fetch, not a continuous stream) -- the
/// same existing "current position" marker/halo behavior, no duplicate or
/// competing indicator invented for recording mode.
///
/// POIs are suppressed during recording (`locations: const []`), matching
/// `LocationPickScreen`'s established "isolated mode" precedent; `onTap`/
/// `onLongPress` are no-ops here since neither location creation nor
/// route planning is available from this screen.
class _LiveTrackMap extends ConsumerWidget {
  const _LiveTrackMap({required this.ownerId, required this.routeId});

  final String ownerId;
  final String? routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionAsync = ref.watch(currentPositionProvider);
    final position = positionAsync.value;
    final userPosition =
        position == null ? null : LatLng(position.latitude, position.longitude);

    var polylines = const <Polyline>{};
    final currentRouteId = routeId;
    if (currentRouteId != null) {
      final pointsAsync = ref.watch(
        gpsRoutePointsProvider((ownerId: ownerId, routeId: currentRouteId)),
      );
      final points = pointsAsync.value;
      if (points != null && points.isNotEmpty) {
        polylines = {
          Polyline(
            polylineId: const PolylineId('gps_live_track'),
            points: points
                .map((point) => LatLng(point.latitude, point.longitude))
                .toList(growable: false),
            color: Theme.of(context).colorScheme.primary,
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };
      }
    }

    return ClusteredLocationMap(
      key: const Key('gps_recording_map'),
      initialTarget: userPosition ?? _fallbackMapTarget,
      userPosition: userPosition,
      locations: const [],
      polylines: polylines,
      onLocationTap: (_) {},
      onLongPress: (_) {},
      onViewportChanged: (_) {},
    );
  }
}

@visibleForTesting
const gpsRecordingMapFallbackTarget = _fallbackMapTarget;
