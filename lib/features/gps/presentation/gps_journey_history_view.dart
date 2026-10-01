import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../local/gps_local_database.dart';
import '../local/gps_local_database_provider.dart';
import 'gps_journey_summary_view.dart';
import 'gps_sync_badge.dart';
import 'gps_sync_ui_state.dart';

/// Journey Phase 1F -- this owner's completed Journeys, newest first,
/// straight from Drift ([GpsLocalDatabase.watchCompletedRoutes]). Only the
/// owner-scoped route rows are watched here; per-Journey statistics are
/// loaded lazily by each visible row through the existing
/// [gpsJourneySummaryProvider] (Phase 0 engine), so a long history never
/// computes statistics for off-screen Journeys. `.autoDispose`: only watched
/// while History is on screen.
final gpsJourneyHistoryProvider = StreamProvider.autoDispose
    .family<List<LocalRecordedRoute>, String>((ref, ownerId) {
  final db = ref.watch(gpsLocalDatabaseProvider);
  return db.watchCompletedRoutes(ownerId);
});

class GpsJourneyHistoryBody extends ConsumerWidget {
  const GpsJourneyHistoryBody({
    super.key,
    required this.ownerId,
    this.onOpenJourney,
  });

  final String ownerId;

  /// Stable seam for the future Journey Details screen. While `null` (no
  /// Details destination exists yet) rows are not tappable.
  final void Function(String routeId)? onOpenJourney;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(gpsJourneyHistoryProvider(ownerId));
    return historyAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(key: Key('gps_history_loading')),
      ),
      error: (_, __) => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Не вдалося завантажити історію подорожей.',
            key: Key('gps_history_error'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (routes) {
        if (routes.isEmpty) return const _EmptyHistory();
        return ListView.builder(
          key: const Key('gps_history_list'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: routes.length,
          itemBuilder: (context, index) {
            final route = routes[index];
            return GpsJourneyHistoryCard(
              key: ValueKey('gps_history_item_${route.id}'),
              ownerId: ownerId,
              route: route,
              onTap:
                  onOpenJourney == null ? null : () => onOpenJourney!(route.id),
            );
          },
        );
      },
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_outlined,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Завершених подорожей ще немає',
              key: const Key('gps_history_empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Завершені подорожі з’являться тут.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// `dd.MM.yyyy HH:mm` in the device's local time.
String formatGpsHistoryDate(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// One completed Journey. Identity, dates and sync status come from the
/// (reactive) route row; distance/duration/Moments come from the canonical
/// local Summary and simply stay absent while it loads or if it fails --
/// never a placeholder number.
class GpsJourneyHistoryCard extends ConsumerWidget {
  const GpsJourneyHistoryCard({
    super.key,
    required this.ownerId,
    required this.route,
    this.onTap,
  });

  final String ownerId;
  final LocalRecordedRoute route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref
        .watch(gpsJourneySummaryProvider((ownerId: ownerId, routeId: route.id)))
        .value;
    final title = (route.title != null && route.title!.trim().isNotEmpty)
        ? route.title!.trim()
        : 'Подорож';
    final ended = route.endedAt ?? route.startedAt;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Завершено: ${formatGpsHistoryDate(ended)}',
                key: const Key('gps_history_item_date'),
                style: theme.textTheme.bodySmall,
              ),
              if (summary != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _Metric(
                        icon: Icons.straighten,
                        text: formatGpsDistance(
                            summary.statistics.totalDistanceMeters)),
                    _Metric(
                        icon: Icons.timer_outlined,
                        text: formatGpsDuration(summary.statistics.elapsed)),
                    _Metric(
                        icon: Icons.place_outlined,
                        text: 'Точки: ${summary.momentCount}'),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: GpsSyncBadge(sync: mapGpsSyncUiState(route.syncStatus)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: Text(text)),
        ],
      );
}
