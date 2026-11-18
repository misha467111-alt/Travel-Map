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
    this.onOpenDetails,
  });

  final String ownerId;
  final String routeId;
  final VoidCallback onDone;
  final GpsSyncUiState? sync;
  final VoidCallback? onRetrySync;
  final VoidCallback? onOpenDetails;

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
              onOpenDetails: onOpenDetails,
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

/// The Summary surface: a success hero, the two primary metrics (distance and
/// total time), a compact list of secondary metrics, the synchronization
/// state in its own section, and the exit actions pinned below the scrolling
/// content so they stay reachable at any text scale.
///
/// Honest by construction: the hero never claims recorded GPS samples when
/// [GpsJourneySummary.pointCount] is zero; unavailable metrics show `—`.
class GpsJourneySummaryView extends StatelessWidget {
  const GpsJourneySummaryView({
    super.key,
    required this.summary,
    required this.onDone,
    this.sync,
    this.onRetrySync,
    this.onOpenDetails,
  });

  final GpsJourneySummary summary;
  final VoidCallback onDone;
  final GpsSyncUiState? sync;
  final VoidCallback? onRetrySync;

  /// Opens the saved Journey's Details; the button is shown only when set.
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final GpsJourneyStatistics stats = summary.statistics;
    // Distance and total time are the primary metrics (shown once, large);
    // the rest are secondary.
    final secondary = <(String, String)>[
      ('Час у русі', formatGpsDuration(stats.moving)),
      ('Час на паузі', formatGpsDuration(stats.paused)),
      ('Середня швидкість', formatGpsSpeed(stats.averageSpeedMps)),
      ('Макс. швидкість', formatGpsSpeed(stats.maxSpeedMps)),
      ('Набір висоти', formatGpsElevation(stats.elevationGainMeters)),
      ('Спуск', formatGpsElevation(stats.elevationLossMeters)),
      ('Темп', formatGpsPace(stats.paceSecondsPerKilometer)),
      ('Точки подорожі', '${summary.momentCount}'),
    ];
    final hasTrack = summary.pointCount > 0;

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
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.16),
                      ),
                      child: Icon(Icons.check_rounded,
                          size: 44, color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Подорож завершено',
                    key: const Key('gps_summary_title'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    hasTrack
                        ? 'Записано GPS-точок: ${summary.pointCount}'
                        : 'GPS-точок не записано, маршрут порожній',
                    key: const Key('gps_summary_track_note'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _PrimaryMetric(
                            key: const Key('gps_summary_distance'),
                            label: 'Відстань',
                            value: formatGpsDistance(stats.totalDistanceMeters),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _PrimaryMetric(
                            key: const Key('gps_summary_duration'),
                            label: 'Загальний час',
                            value: formatGpsDuration(stats.elapsed),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                      child: Column(
                        children: [
                          for (final (label, value) in secondary)
                            _MetricRow(label: label, value: value),
                        ],
                      ),
                    ),
                  ),
                  if (sync != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Card(
                      key: const Key('gps_summary_sync_section'),
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            Text('Синхронізація',
                                style: theme.textTheme.bodyMedium),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: GpsSyncBadge(
                                    sync: sync!, onRetry: onRetrySync),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onOpenDetails != null) ...[
                  OutlinedButton.icon(
                    key: const Key('gps_summary_open_button'),
                    onPressed: onOpenDetails,
                    icon: const Icon(Icons.route_outlined),
                    label: const Text('Відкрити подорож'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                FilledButton(
                  key: const Key('gps_summary_done_button'),
                  onPressed: onDone,
                  child: const Text('Готово'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryMetric extends StatelessWidget {
  const _PrimaryMetric({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary),
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
