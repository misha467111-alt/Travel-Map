import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import '../local/gps_local_database.dart' show RouteSyncStatus;
import 'gps_sync_ui_state.dart';

/// Phase 4C — the one reusable sync-status indicator, built purely on
/// top of the Phase 4B [GpsSyncUiState] contract (never re-derives its
/// own notion of what `notSynced`/`syncing`/`synced`/`failed` means).
/// Reusable later by the "Записані маршрути" list (Phase 4E/4J) without
/// change, since it takes no provider/context dependency beyond
/// [Theme.of].
///
/// Never relies on color alone: every state has both a distinct icon
/// (or spinner) AND a text label, matching this phase's accessibility
/// requirement.
class GpsSyncBadge extends StatelessWidget {
  const GpsSyncBadge({super.key, required this.sync, this.onRetry});

  final GpsSyncUiState sync;

  /// Wired by the caller to the existing `GpsSyncCoordinator.retryRoute`
  /// — this widget never talks to the sync coordinator itself. Only
  /// rendered when [GpsSyncUiState.canRetry] is true.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    final Widget indicator;
    switch (sync.syncStatus) {
      case RouteSyncStatus.syncing:
        color = theme.colorScheme.onSurfaceVariant;
        indicator = SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        );
      case RouteSyncStatus.synced:
        color = theme.colorScheme.primary;
        indicator = Icon(Icons.check_circle_outline, size: 16, color: color);
      case RouteSyncStatus.failed:
        color = theme.colorScheme.error;
        indicator = Icon(Icons.error_outline, size: 16, color: color);
      default: // notSynced (and any future/unknown status, defensively)
        color = theme.colorScheme.onSurfaceVariant;
        indicator = Icon(Icons.save_outlined, size: 16, color: color);
    }

    return Semantics(
      label: 'Синхронізація: ${sync.label}',
      // Plain Row with the label wrapped in Flexible+ellipsis, NOT a
      // Row(mainAxisSize.min) inside a Wrap: a `mainAxisSize.min` Row
      // demands its *intrinsic* (unwrapped, one-line) width regardless
      // of the space actually available, which a Wrap cannot shrink for
      // a single child -- the longer Ukrainian labels (e.g. "Збережено
      // на пристрої") genuinely exceed a narrow screen's width that way.
      // A Flexible Text correctly shrinks/ellipsizes instead, while the
      // fixed-size icon and retry button keep their natural size. Caught
      // by this phase's own C18/C19 responsive tests.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              sync.label,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (sync.canRetry && onRetry != null) ...[
            const SizedBox(width: AppSpacing.xs),
            TextButton(
              key: const Key('gps_sync_retry_button'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSizes.touchTarget),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: const Text('Повторити'),
            ),
          ],
        ],
      ),
    );
  }
}
