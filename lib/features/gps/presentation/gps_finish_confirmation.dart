import 'package:flutter/material.dart';

/// Journey Phase 1E -- the one shared confirmation for finishing a Journey,
/// used by both [GpsRecordingControls] (active) and `GpsRecoveryCard`
/// (recoverable), mirroring [showGpsDiscardConfirmation]. Returns `true`
/// only on an explicit "Завершити"; the caller invokes the real controller.
Future<bool> showGpsFinishConfirmation(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Завершити подорож?'),
      content: const Text(
        'Після завершення запис цієї подорожі буде зупинено.',
      ),
      actions: [
        TextButton(
          key: const Key('gps_finish_cancel_button'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          key: const Key('gps_finish_confirm_button'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Завершити'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
