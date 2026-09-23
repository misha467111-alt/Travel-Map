import 'package:flutter/material.dart';

/// Phase 4C — the one shared destructive-confirmation dialog for
/// discarding a recording, used by both [GpsRecordingControls] (active
/// recording/paused) and `GpsRecoveryCard` (a recoverable session) so
/// the two never drift into slightly different copy/behavior.
///
/// Returns `true` only if the user explicitly confirmed. The caller is
/// responsible for calling the real `controller.discard()`/
/// `controller.discardRecoverableRecording()` — this function never
/// touches the controller itself, matching Phase 4B's "no BuildContext/
/// controller inside the contract" rule extended to this dialog too.
Future<bool> showGpsDiscardConfirmation(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Скасувати запис?'),
      content: const Text(
        'Запис маршруту буде зупинено. Уже збережені на пристрої дані '
        'залишаться — вони просто не будуть відправлені як завершений '
        'маршрут.',
      ),
      actions: [
        TextButton(
          key: const Key('gps_discard_cancel_button'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Ні, продовжити'),
        ),
        FilledButton(
          key: const Key('gps_discard_confirm_button'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Скасувати запис'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
