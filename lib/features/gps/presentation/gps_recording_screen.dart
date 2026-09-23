import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_design.dart';
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

/// Phase 4C — the polished, production-oriented GPS recording shell.
///
/// This is NOT yet reachable from anywhere in the app (no Map toolbar
/// entry, no navigation wiring — that is Phase 4D). It exists as a
/// complete, independently-testable screen so 4D only has to add an
/// entry point and a real map, without rewriting any control/status
/// logic.
///
/// Every visible action calls the real, already-proven
/// [GpsRecordingController]/[GpsSyncCoordinator] — this screen adds
/// zero new business logic of its own beyond mapping engine state to
/// the Phase 4B presentation contract ([mapGpsRecordingUiState]/
/// [mapGpsSyncUiState]) and wiring buttons to the matching controller
/// method. `gps_recording_debug_screen.dart` remains untouched and
/// still reachable from Settings — it is the proven fallback until this
/// screen passes physical QA (4G).
///
/// No map is embedded here at all (Phase 4D's job) — the body below
/// this header/status/controls stack is a plain, empty, themed surface
/// so a real `ClusteredLocationMap` can be dropped in later without
/// restructuring anything above it.
class GpsRecordingScreen extends ConsumerWidget {
  const GpsRecordingScreen({super.key});

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
    // Constructed alongside the recording controller so a sync pass is
    // always attempted whenever this screen is open -- matches
    // gps_recording_debug_screen.dart's own established rationale.
    final syncCoordinator = ref.read(gpsSyncCoordinatorProvider(userId));

    return Scaffold(
      body: SafeArea(
        child: stateAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => const Center(
            child: Text('Не вдалося завантажити стан запису.'),
          ),
          data: (state) => _GpsRecordingBody(
            ownerId: userId,
            state: state,
            controller: controller,
            syncCoordinator: syncCoordinator,
          ),
        ),
      ),
    );
  }
}

class _GpsRecordingBody extends ConsumerWidget {
  const _GpsRecordingBody({
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

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GpsRecordingHeader(
            uiState: uiState,
            onBack: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(child: _buildContent(context, uiState, sync)),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    GpsRecordingUiState uiState,
    GpsSyncUiState? sync,
  ) {
    switch (uiState.status) {
      case GpsRecordingStatus.idle:
        return GpsStartView(
          key: const Key('gps_start_view'),
          label: 'Почати запис',
          onStart: controller.start,
        );

      case GpsRecordingStatus.completed:
        return GpsStartView(
          key: const Key('gps_start_view'),
          label: 'Новий запис',
          statusCard: GpsRecordingStatusCard(uiState: uiState, sync: sync),
          onStart: controller.start,
        );

      case GpsRecordingStatus.preparing:
        return const GpsStartView(
          key: Key('gps_start_view'),
          label: 'Підготовка…',
          onStart: null, // prevents duplicate start taps while preparing
        );

      case GpsRecordingStatus.recording:
      case GpsRecordingStatus.paused:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GpsRecordingStatusCard(
              uiState: uiState,
              sync: sync,
              onRetrySync: state.routeId == null
                  ? null
                  : () => syncCoordinator.retryRoute(state.routeId!),
            ),
            const SizedBox(height: AppSpacing.lg),
            GpsRecordingControls(
              uiState: uiState,
              onPause: controller.pause,
              onResume: controller.resume,
              onFinish: controller.finish,
              onAddWaypoint: () =>
                  controller.addWaypoint(waypointType: 'custom'),
              onDiscard: controller.discard,
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
        return GpsRecordingErrorView(
          kind: uiState.errorKind!,
          detail: uiState.errorDetail,
          onRetry: controller.start,
        );
    }
  }
}
