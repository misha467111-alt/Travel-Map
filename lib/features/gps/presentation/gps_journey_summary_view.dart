import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../local/gps_local_database_provider.dart';
import '../recording/gps_journey_statistics.dart';
import '../recording/gps_journey_summary.dart';
import 'gps_sync_badge.dart';
import 'gps_sync_ui_state.dart';

/// Journey Phase 1E -- the completed Journey's Summary, loaded purely from
/// local persisted data via [loadGpsJourneySummary]. `.autoDispose`: only
/// watched while the Summary is on screen.
final gpsJourneySummaryProvider = FutureProvider.autoDispose
    .family<GpsJourneySummary?, ({String ownerId, String routeId})>(
        (ref, args) {
  final db = ref.watch(gpsLocalDatabaseProvider);
  return loadGpsJourneySummary(
    db: db,
    ownerId: args.ownerId,
    routeId: args.routeId,
    now: DateTime.now().toUtc(),
  );
});

const _unavailable = '—';

/// Metric formatters. Every one maps a non-finite/negative input to
/// [_unavailable] rather than rendering NaN/Infinity, and the optional
/// Phase 0 metrics (null = "not derivable") are shown as [_unavailable],
/// never as a fabricated zero.
String formatGpsDistance(double meters) {
  if (!meters.isFinite || meters < 0) return _unavailable;
  if (meters < 1000) return '${meters.round()} м';
  return '${(meters / 1000).toStringAsFixed(2)} км';
}

String formatGpsDuration(Duration duration) {
  final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '$h год $m хв';
  if (m > 0) return '$m хв $s с';
  return '$s с';
}

String formatGpsSpeed(double? metersPerSecond) {
  if (metersPerSecond == null ||
      !metersPerSecond.isFinite ||
      metersPerSecond < 0) {
    return _unavailable;
  }
  return '${(metersPerSecond * 3.6).toStringAsFixed(1)} км/год';
}

String formatGpsElevation(double meters) {
  if (!meters.isFinite || meters < 0) return _unavailable;
  return '${meters.round()} м';
}

String formatGpsPace(double? secondsPerKilometer) {
  if (secondsPerKilometer == null ||
      !secondsPerKilometer.isFinite ||
      secondsPerKilometer <= 0) {
    return _unavailable;
  }
  final total = secondsPerKilometer.round();
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s /км';
}

/// Loads and renders the Summary for [routeId]. Offline-first by
/// construction: its only dependency is the local Drift database.
class GpsJourneySummaryPanel extends ConsumerWidget {
  const GpsJourneySummaryPanel({
    super.key,
    required this.ownerId,
    required this.routeId,
    required this.onDone,
    this.sync,
    this.onRetrySync,
  });

  final String ownerId;
  final String routeId;
  final VoidCallback onDone;
  final GpsSyncUiState? sync;
  final VoidCallback? onRetrySync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(
      gpsJourneySummaryProvider((ownerId: ownerId, routeId: routeId)),
    );
    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _SummaryMessage(
        message: 'Не вдалося завантажити підсумок подорожі.',
        onDone: onDone,
      ),
      data: (summary) => summary == null
          ? _SummaryMessage(
              message: 'Підсумок подорожі недоступний.',
              onDone: onDone,
            )
          : GpsJourneySummaryView(
              summary: summary,
              onDone: onDone,
              sync: sync,
              onRetrySync: onRetrySync,
            ),
    );
  }
}

class _SummaryMessage extends StatelessWidget {
  const _SummaryMessage({required this.message, required this.onDone});
  final String message;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('gps_summary_done_button'),
              onPressed: onDone,
              child: const Text('Готово'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The structural Summary surface: a scrolling metric list with the exit
/// action pinned below it, so the action stays reachable at any text scale.
class GpsJourneySummaryView extends StatelessWidget {
  const GpsJourneySummaryView({
    super.key,
    required this.summary,
    required this.onDone,
    this.sync,
    this.onRetrySync,
  });

  final GpsJourneySummary summary;
  final VoidCallback onDone;
  final GpsSyncUiState? sync;
  final VoidCallback? onRetrySync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final GpsJourneyStatistics stats = summary.statistics;
    final metrics = <(String, String)>[
      ('Відстань', formatGpsDistance(stats.totalDistanceMeters)),
      ('Загальний час', formatGpsDuration(stats.elapsed)),
      ('Час у русі', formatGpsDuration(stats.moving)),
      ('Час на паузі', formatGpsDuration(stats.paused)),
      ('Середня швидкість', formatGpsSpeed(stats.averageSpeedMps)),
      ('Макс. швидкість', formatGpsSpeed(stats.maxSpeedMps)),
      ('Набір висоти', formatGpsElevation(stats.elevationGainMeters)),
      ('Спуск', formatGpsElevation(stats.elevationLossMeters)),
      ('Темп', formatGpsPace(stats.paceSecondsPerKilometer)),
      ('Точки подорожі', '${summary.momentCount}'),
    ];

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const Key('gps_summary_scroll'),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: theme.colorScheme.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Подорож завершено',
                          key: const Key('gps_summary_title'),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  if (sync != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GpsSyncBadge(sync: sync!, onRetry: onRetrySync),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          for (final (label, value) in metrics)
                            _MetricRow(label: label, value: value),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: FilledButton(
              key: const Key('gps_summary_done_button'),
              onPressed: onDone,
              child: const Text('Готово'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
