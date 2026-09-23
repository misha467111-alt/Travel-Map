import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import 'gps_recording_ui_state.dart';

/// Phase 4C — the top-of-screen chrome: a back/minimize affordance,
/// "Запис маршруту", and the current status headline
/// ([GpsRecordingUiState.statusLabel] — never re-derived here). Reuses
/// theme typography (`titleLarge`/`bodyMedium`) rather than hardcoded
/// font sizes.
class GpsRecordingHeader extends StatelessWidget {
  const GpsRecordingHeader({super.key, required this.uiState, this.onBack});

  final GpsRecordingUiState uiState;

  /// Minimizing/backing out of the screen must never discard the
  /// recording — this callback is expected to just navigate away
  /// (`GpsRecordingController` survives navigation by design, see
  /// `gps_recording_controller.dart`'s own non-autoDispose doc comment),
  /// never call `controller.discard()`.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            key: const Key('gps_recording_back_button'),
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Згорнути',
          ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Запис маршруту', style: theme.textTheme.titleLarge),
              Text(
                uiState.statusLabel,
                key: const Key('gps_recording_status_label'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
