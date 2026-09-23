import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import 'gps_discard_confirmation.dart';

/// Phase 4C — shown only when the engine reports
/// `GpsRecordingStatus.recoverable` (an unfinished recording/paused
/// route was found on app start). Offers exactly the three actions
/// Phase 4B's contract supports for this state —
/// `resumeRecoverableRecording`/`finishRecoverableRecording`/
/// `discardRecoverableRecording` — and no new recovery semantics.
class GpsRecoveryCard extends StatelessWidget {
  const GpsRecoveryCard({
    super.key,
    this.pointCount,
    required this.onResume,
    required this.onFinish,
    required this.onDiscard,
  });

  /// Optional -- shown when the caller already knows how many points
  /// the recoverable route has (cheap, from a one-shot query the
  /// controller already performs on recovery-detection), purely as
  /// reassurance ("your data is still here"). Never re-queried by this
  /// widget itself.
  final int? pointCount;

  final VoidCallback onResume;
  final VoidCallback onFinish;

  /// Called at most once, only after the shared discard-confirmation
  /// dialog is explicitly confirmed.
  final VoidCallback onDiscard;

  Future<void> _handleDiscard(BuildContext context) async {
    final confirmed = await showGpsDiscardConfirmation(context);
    if (confirmed) onDiscard();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Знайдено незавершений запис',
                    key: const Key('gps_recovery_title'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              pointCount != null
                  ? 'Збережено точок: $pointCount. Продовжити запис, '
                      'завершити його зараз чи скасувати?'
                  : 'Продовжити запис, завершити його зараз чи скасувати?',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  key: const Key('gps_recovery_resume_button'),
                  onPressed: onResume,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Відновити'),
                ),
                OutlinedButton.icon(
                  key: const Key('gps_recovery_finish_button'),
                  onPressed: onFinish,
                  icon: const Icon(Icons.check),
                  label: const Text('Завершити'),
                ),
                TextButton.icon(
                  key: const Key('gps_recovery_discard_button'),
                  onPressed: () => _handleDiscard(context),
                  icon: Icon(Icons.close, color: theme.colorScheme.error),
                  label: Text('Скасувати',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
