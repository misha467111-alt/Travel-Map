import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import 'gps_discard_confirmation.dart';
import 'gps_recording_ui_state.dart';

/// Phase 4C — the primary/secondary/destructive control row for an
/// active (recording/paused) session. Every button's visibility is
/// derived *only* from the Phase 4B [GpsRecordingUiState] flags
/// (`canPause`/`canResume`/`canFinish`/`canAddWaypoint`/`canDiscard`) —
/// there is no local `if (recording) ... else if (paused) ...` logic
/// here at all, so this widget cannot drift out of sync with the
/// accepted contract.
///
/// Discard always requires confirmation
/// ([GpsRecordingUiState.discardRequiresConfirmation] is always true
/// whenever [GpsRecordingUiState.canDiscard] is true) via the shared
/// [showGpsDiscardConfirmation] dialog — [onDiscard] is only ever
/// invoked after the user explicitly confirms.
class GpsRecordingControls extends StatelessWidget {
  const GpsRecordingControls({
    super.key,
    required this.uiState,
    this.onPause,
    this.onResume,
    this.onFinish,
    this.onAddWaypoint,
    this.onDiscard,
  });

  final GpsRecordingUiState uiState;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onFinish;
  final VoidCallback? onAddWaypoint;

  /// Called at most once per confirmed tap -- only after the user
  /// explicitly confirms the discard dialog.
  final VoidCallback? onDiscard;

  Future<void> _handleDiscard(BuildContext context) async {
    final confirmed = await showGpsDiscardConfirmation(context);
    if (confirmed) onDiscard?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (uiState.canPause)
          FilledButton.icon(
            key: const Key('gps_recording_pause_button'),
            onPressed: onPause,
            icon: const Icon(Icons.pause),
            label: const Text('Пауза'),
          ),
        if (uiState.canResume)
          FilledButton.icon(
            key: const Key('gps_recording_resume_button'),
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Продовжити'),
          ),
        if (uiState.canAddWaypoint)
          OutlinedButton.icon(
            key: const Key('gps_recording_add_waypoint_button'),
            onPressed: onAddWaypoint,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Додати точку'),
          ),
        if (uiState.canFinish)
          FilledButton.icon(
            key: const Key('gps_recording_finish_button'),
            onPressed: onFinish,
            icon: const Icon(Icons.check),
            label: const Text('Завершити'),
          ),
        if (uiState.canDiscard)
          TextButton.icon(
            key: const Key('gps_recording_discard_button'),
            onPressed: () => _handleDiscard(context),
            icon: Icon(Icons.close, color: theme.colorScheme.error),
            label: Text('Скасувати',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}
