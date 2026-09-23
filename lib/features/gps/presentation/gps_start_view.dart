import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';

/// Phase 4C — the "no active session" surface: idle (ready to record),
/// preparing (permission/service check in flight — [onStart] is `null`
/// here specifically to prevent a duplicate start tap while a request is
/// already outstanding), and completed (just-finished session, offering
/// a fresh start).
class GpsStartView extends StatelessWidget {
  const GpsStartView({
    super.key,
    required this.label,
    required this.onStart,
    this.statusCard,
  });

  final String label;

  /// `null` disables the button and shows a small progress indicator
  /// instead of the record icon — used for
  /// `GpsRecordingStatus.preparing` so a second tap can never start a
  /// second session while the first request is still in flight.
  final VoidCallback? onStart;

  /// Shown above the button only for `GpsRecordingStatus.completed` —
  /// lets the user see the just-finished session's stats/sync state one
  /// more time before starting a new one.
  final Widget? statusCard;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (statusCard != null) ...[
              statusCard!,
              const SizedBox(height: AppSpacing.xl),
            ],
            FilledButton.icon(
              key: const Key('gps_start_button'),
              onPressed: onStart,
              icon: onStart == null
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fiber_manual_record),
              label: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
