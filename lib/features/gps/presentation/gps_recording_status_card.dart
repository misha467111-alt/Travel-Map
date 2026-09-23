import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import '../recording/gps_recording_state.dart' show GpsRecordingStatus;
import 'gps_recording_stats.dart';
import 'gps_recording_ui_state.dart';
import 'gps_sync_badge.dart';
import 'gps_sync_ui_state.dart';

/// Phase 4C — the main content card while a recording session exists:
/// status headline + stats + (when a synced-or-syncing route exists) the
/// [GpsSyncBadge]. Uses the theme's own [CardTheme] (elevation/color/
/// radius/border all come from `Theme.of(context)` — nothing hardcoded
/// here), matching every other `Card` in the app.
class GpsRecordingStatusCard extends StatelessWidget {
  const GpsRecordingStatusCard({
    super.key,
    required this.uiState,
    this.sync,
    this.onRetrySync,
    this.now = DateTime.now,
  });

  final GpsRecordingUiState uiState;

  /// `null` until a route id exists / its sync row hasn't loaded yet —
  /// the caller ([GpsRecordingScreen]) is responsible for resolving this
  /// via the existing `gpsRouteSyncStateProvider`; this widget never
  /// watches a provider itself.
  final GpsSyncUiState? sync;
  final VoidCallback? onRetrySync;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status label and sync badge are stacked, not placed side by
            // side in one Row: their combined text (e.g. "Запис триває" +
            // "Збережено на пристрої" + "Повторити") is long enough in
            // Ukrainian that a single Row can genuinely overflow at
            // narrow widths/larger text scales -- caught by this phase's
            // own C18/C19 responsive tests. Stacking removes the risk
            // entirely rather than fighting it with ever-smaller flex.
            Text(
              uiState.statusLabel,
              key: const Key('gps_status_card_label'),
              style: theme.textTheme.titleMedium,
            ),
            if (sync != null) ...[
              const SizedBox(height: AppSpacing.xs),
              GpsSyncBadge(sync: sync!, onRetry: onRetrySync),
            ],
            const SizedBox(height: AppSpacing.lg),
            GpsRecordingStats(
              stats: uiState.stats,
              isTicking: uiState.status == GpsRecordingStatus.recording,
              now: now,
            ),
          ],
        ),
      ),
    );
  }
}
