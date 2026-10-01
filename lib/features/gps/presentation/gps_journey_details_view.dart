import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_design.dart';
import '../../map/presentation/clustered_location_map.dart';
import '../local/gps_local_database.dart';
import '../local/gps_local_database_provider.dart';
import '../recording/gps_journey_details.dart';
import '../recording/gps_journey_statistics.dart';
import 'gps_journey_history_view.dart' show formatGpsHistoryDate;
import 'gps_journey_summary_view.dart';
import 'gps_live_moments.dart';
import 'gps_sync_badge.dart';
import 'gps_sync_ui_state.dart';

/// Journey Phase 1G -- the immutable part of one completed Journey (route,
/// points, Moments, statistics, Timeline), loaded once from Drift. Completed
/// geometry/telemetry never changes after Finish, so a one-shot load is the
/// right model; `.autoDispose` so it is released when Details closes.
final gpsJourneyDetailsProvider = FutureProvider.autoDispose
    .family<GpsJourneyDetails?, ({String ownerId, String routeId})>(
        (ref, args) {
  final db = ref.watch(gpsLocalDatabaseProvider);
  return loadGpsJourneyDetails(
    db: db,
    ownerId: args.ownerId,
    routeId: args.routeId,
    now: DateTime.now().toUtc(),
  );
});

/// The one reactive part of Details: the route row, because its sync status
/// can still change after completion (background sync).
final gpsJourneyDetailsRouteProvider = StreamProvider.autoDispose
    .family<LocalRecordedRoute?, ({String ownerId, String routeId})>(
        (ref, args) {
  final db = ref.watch(gpsLocalDatabaseProvider);
  return db.watchRecordedRoute(ownerId: args.ownerId, id: args.routeId);
});

/// Read-only Details for one completed Journey. Local-only: its sole data
/// dependency is [GpsLocalDatabase].
class GpsJourneyDetailsBody extends ConsumerWidget {
  const GpsJourneyDetailsBody({
    super.key,
    required this.ownerId,
    required this.routeId,
  });

  final String ownerId;
  final String routeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (ownerId: ownerId, routeId: routeId);
    return ref.watch(gpsJourneyDetailsProvider(args)).when(
          loading: () => const Center(
            child: CircularProgressIndicator(key: Key('gps_details_loading')),
          ),
          error: (_, __) => const _Message(
            messageKey: Key('gps_details_error'),
            text: 'Не вдалося завантажити подорож.',
          ),
          data: (details) {
            if (details == null) {
              return const _Message(
                messageKey: Key('gps_details_unavailable'),
                text: 'Подорож недоступна.',
              );
            }
            final liveRoute =
                ref.watch(gpsJourneyDetailsRouteProvider(args)).value;
            return _DetailsContent(
              details: details,
              syncStatus: (liveRoute ?? details.route).syncStatus,
            );
          },
        );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.messageKey, required this.text});
  final Key messageKey;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(text, key: messageKey, textAlign: TextAlign.center),
        ),
      );
}

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({required this.details, required this.syncStatus});

  final GpsJourneyDetails details;
  final String syncStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = details.route;
    final title = (route.title != null && route.title!.trim().isNotEmpty)
        ? route.title!.trim()
        : 'Подорож';
    final ended = route.endedAt ?? route.startedAt;
    final timeline = details.timeline;

    return CustomScrollView(
      key: const Key('gps_details_scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    key: const Key('gps_details_title'),
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${formatGpsHistoryDate(route.startedAt)} — '
                  '${formatGpsHistoryDate(ended)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                GpsSyncBadge(sync: mapGpsSyncUiState(syncStatus)),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: GpsJourneyDetailsMap(
              points: details.points,
              moments: details.moments,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: _StatsCard(
              stats: details.statistics,
              momentCount: details.moments.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: Text('Хронологія',
                key: const Key('gps_details_timeline_title'),
                style: theme.textTheme.titleMedium),
          ),
        ),
        SliverList.builder(
          itemCount: timeline.length,
          itemBuilder: (context, index) => _TimelineRow(
            key: ValueKey('gps_timeline_${timeline[index].id}'),
            entry: timeline[index],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
  }
}

/// Read-only map of the persisted route. Reuses [ClusteredLocationMap]
/// exactly as the recording screen does: no POIs, no tap handlers, no GPS
/// subscription and no user position -- it can neither start recording nor
/// mutate anything. With no points and no Moments there is nothing to draw,
/// so a plain note replaces the map instead of an arbitrary location.
///
/// The camera is centred on the route's bounding-box centre; fitting the
/// bounds is deferred (the shared map widget exposes no fit API).
class GpsJourneyDetailsMap extends StatelessWidget {
  const GpsJourneyDetailsMap({
    super.key,
    required this.points,
    required this.moments,
  });

  final List<LocalRoutePoint> points;
  final List<LocalWaypoint> moments;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty && moments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text('У цій подорожі немає збережених точок маршруту.',
              key: const Key('gps_details_no_geometry'),
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }

    final latLngs = [for (final p in points) LatLng(p.latitude, p.longitude)];
    final reference = latLngs.isNotEmpty
        ? latLngs
        : [for (final m in moments) LatLng(m.latitude, m.longitude)];
    var minLat = reference.first.latitude, maxLat = minLat;
    var minLng = reference.first.longitude, maxLng = minLng;
    for (final p in reference) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: SizedBox(
        height: 260,
        child: ClusteredLocationMap(
          key: const Key('gps_details_map'),
          initialTarget: LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
          userPosition: null,
          locations: const [],
          polylines: latLngs.length < 2
              ? const {}
              : {
                  Polyline(
                    polylineId: const PolylineId('gps_journey_route'),
                    points: latLngs,
                    color: Theme.of(context).colorScheme.primary,
                    width: 6,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                  ),
                },
          additionalMarkers: buildGpsMomentMarkers(moments),
          onLocationTap: (_) {},
          onLongPress: (_) {},
          onViewportChanged: (_) {},
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.momentCount});

  final GpsJourneyStatistics stats;
  final int momentCount;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Відстань', formatGpsDistance(stats.totalDistanceMeters)),
      ('Загальний час', formatGpsDuration(stats.elapsed)),
      ('Час у русі', formatGpsDuration(stats.moving)),
      ('Час на паузі', formatGpsDuration(stats.paused)),
      ('Середня швидкість', formatGpsSpeed(stats.averageSpeedMps)),
      ('Макс. швидкість', formatGpsSpeed(stats.maxSpeedMps)),
      ('Набір висоти', formatGpsElevation(stats.elevationGainMeters)),
      ('Спуск', formatGpsElevation(stats.elevationLossMeters)),
      ('Темп', formatGpsPace(stats.paceSecondsPerKilometer)),
      ('Точки подорожі', '$momentCount'),
    ];
    final theme = Theme.of(context);
    return Card(
      key: const Key('gps_details_stats'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Text(label, style: theme.textTheme.bodyMedium)),
                    const SizedBox(width: AppSpacing.md),
                    Flexible(
                      child: Text(value,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.titleSmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({super.key, required this.entry});

  final GpsTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moment = entry.moment;
    final presentation =
        moment == null ? null : gpsMomentPresentation(moment.waypointType);

    final (IconData icon, String label) = switch (entry.kind) {
      GpsTimelineEntryKind.started => (
          Icons.flag_outlined,
          'Подорож розпочато'
        ),
      GpsTimelineEntryKind.paused => (Icons.pause_circle_outline, 'Пауза'),
      GpsTimelineEntryKind.resumed => (
          Icons.play_circle_outline,
          'Продовження'
        ),
      GpsTimelineEntryKind.moment => (
          presentation!.icon,
          (moment!.title != null && moment.title!.trim().isNotEmpty)
              ? moment.title!.trim()
              : presentation.label,
        ),
      GpsTimelineEntryKind.finished => (
          Icons.check_circle_outline,
          'Подорож завершено'
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                Text(formatGpsHistoryDate(entry.timestamp),
                    style: theme.textTheme.bodySmall),
                if (moment != null && presentation != null) ...[
                  if (moment.title != null && moment.title!.trim().isNotEmpty)
                    Text(presentation.label, style: theme.textTheme.bodySmall),
                  if (moment.note != null && moment.note!.trim().isNotEmpty)
                    Text(moment.note!.trim(),
                        key: const Key('gps_timeline_moment_note'),
                        style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
