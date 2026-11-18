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
    this.onRetryStream,
    this.now = DateTime.now,
  });

  final GpsRecordingUiState uiState;

  /// `null` until a route id exists / its sync row hasn't loaded yet —
  /// the caller is responsible for resolving this via the existing
  /// `gpsRouteSyncStateProvider`; this widget never watches a provider
  /// itself.
  final GpsSyncUiState? sync;
  final VoidCallback? onRetrySync;

  /// Set only while an ACTIVE recording's GPS stream reported an error: the
  /// recording (and Pause/Finish) continue, this re-subscribes the same
  /// session.
  final VoidCallback? onRetryStream;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotColor = switch (uiState.status) {
      GpsRecordingStatus.recording => const Color(0xFF4CAF50),
      GpsRecordingStatus.paused => theme.colorScheme.primary,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return Card(
      color: theme.cardTheme.color?.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
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
            Row(
              children: [
                // Status is never colour-only: the label always accompanies
                // the dot.
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    uiState.statusLabel,
                    key: const Key('gps_status_card_label'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (sync != null) ...[
              const SizedBox(height: AppSpacing.xs),
              GpsSyncBadge(sync: sync!, onRetry: onRetrySync),
            ],
            if (onRetryStream != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                key: const Key('gps_stream_error_row'),
                children: [
                  Icon(Icons.gps_off, size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text('Помилка GPS-сигналу, точки збережено'),
                  ),
                  TextButton(
                    key: const Key('gps_stream_retry_button'),
                    onPressed: onRetryStream,
                    child: const Text('Повторити'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
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
