import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import 'gps_recording_ui_state.dart';

/// Phase 4C — renders the Phase 4B [GpsRecordingErrorKind]
/// classification as an understandable, non-technical explanation.
/// [detail] (when present) is always the already-short, already-
/// debug-safe string [GpsRecordingUiState.errorDetail] already provides
/// (never a raw exception/stack trace — that filtering happens upstream
/// in the engine and in the Phase 4B contract; this widget only ever
/// displays what it is given, in small, de-emphasized text, never as
/// the headline).
class GpsRecordingErrorView extends StatelessWidget {
  const GpsRecordingErrorView({
    super.key,
    required this.kind,
    this.detail,
    this.onRetry,
  });

  final GpsRecordingErrorKind kind;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, explanation) = switch (kind) {
      GpsRecordingErrorKind.permissionProblem => (
          Icons.location_disabled,
          'Немає дозволу на геолокацію',
          'Щоб почати запис маршруту, дозвольте застосунку доступ до '
              'вашого місцезнаходження в налаштуваннях пристрою.',
        ),
      GpsRecordingErrorKind.locationServiceDisabled => (
          Icons.location_off,
          'Службу геолокації вимкнено',
          'Увімкніть геолокацію в налаштуваннях пристрою, щоб '
              'продовжити запис маршруту.',
        ),
      GpsRecordingErrorKind.otherError => (
          Icons.error_outline,
          'Помилка запису',
          'Не вдалося продовжити запис маршруту. Спробуйте ще раз.',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              key: const Key('gps_error_title'),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              explanation,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail!,
                key: const Key('gps_error_detail'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('gps_error_retry_button'),
                onPressed: onRetry,
                child: const Text('Спробувати ще раз'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
