import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../../gps/local/gps_local_database.dart';
import '../../gps/presentation/gps_journey_history_view.dart'
    show gpsJourneyHistoryProvider;
import '../../gps/presentation/gps_journey_summary_view.dart'
    show formatGpsDistance, formatGpsDuration, gpsJourneySummaryProvider;
import 'profile_premium_components.dart';

/// Phase 3.3-D -- own-profile sections for places and recent Journeys. Both are
/// private to the signed-in user and are never built on a public profile.

/// "Мої місця": created / saved / visited, each with a real count (or an
/// honest loading / unavailable state) that opens [MyPlacesScreen] on that tab.
class ProfilePlacesCard extends StatelessWidget {
  const ProfilePlacesCard({
    required this.created,
    required this.saved,
    required this.visited,
    required this.onTap,
    this.visitedIsExact = true,
    super.key,
  });

  /// The exact number of created places (a count query).
  final AsyncValue<int> created;
  final int? saved;

  /// The number of UNIQUE visited places.
  final AsyncValue<int> visited;

  /// False when not all check-ins could be read: shown as "N+".
  final bool visitedIsExact;
  final ValueChanged<String> onTap;

  static String countText(AsyncValue<int> v, {int cap = 0}) => v.when(
        loading: () => 'Завантаження…',
        error: (_, __) => 'Недоступно',
        data: (n) => cap > 0 && n >= cap ? '$cap+' : '$n',
      );

  static String _visitedText(AsyncValue<int> v, bool exact) => exact
      ? countText(v)
      : v.when(
          loading: () => 'Завантаження…',
          error: (_, __) => 'Недоступно',
          data: (n) => '$n+',
        );

  @override
  Widget build(BuildContext context) => PremiumActionCard(
        title: 'Мої місця',
        rows: [
          PremiumActionRow(
            destination: 'places_created',
            icon: Icons.add_location_alt_outlined,
            title: 'Створені',
            subtitle: countText(created),
            onTap: onTap,
          ),
          PremiumActionRow(
            destination: 'places_saved',
            icon: Icons.bookmark_outline,
            title: 'Збережені',
            subtitle: saved == null ? 'Недоступно' : '$saved',
            onTap: onTap,
          ),
          PremiumActionRow(
            destination: 'places_visited',
            icon: Icons.flag_outlined,
            title: 'Відвідані',
            subtitle: _visitedText(visited, visitedIsExact),
            onTap: onTap,
          ),
        ],
      );
}

/// The three most recent finished Journeys of this owner (local data): date or
/// title, CONFIRMED distance and moving time, tap to open the existing details.
class ProfileRecentJourneysCard extends ConsumerWidget {
  const ProfileRecentJourneysCard({
    required this.ownerId,
    required this.journeys,
    required this.onOpenJourney,
    super.key,
  });

  final String ownerId;
  final AsyncValue<List<LocalRecordedRoute>> journeys;
  final ValueChanged<String> onOpenJourney;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget message(String key, String text) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(text, key: Key(key), style: theme.textTheme.bodySmall),
        );
    final rows = journeys.when(
      loading: () => <Widget>[
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(
              child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      key: Key('profile_journeys_loading'),
                      strokeWidth: 2,
                      color: AppColors.accent))),
        ),
      ],
      error: (_, __) => <Widget>[
        message('profile_journeys_error', 'Не вдалося завантажити подорожі'),
      ],
      data: (routes) => routes.isEmpty
          ? <Widget>[message('profile_journeys_empty', 'Подорожей ще немає')]
          : <Widget>[
              for (final route in routes.take(3))
                _RecentJourneyRow(
                  ownerId: ownerId,
                  route: route,
                  onTap: () => onOpenJourney(route.id),
                ),
            ],
    );
    return PremiumActionCard(title: 'Останні подорожі', rows: rows);
  }
}

String _dateTime(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

class _RecentJourneyRow extends ConsumerWidget {
  const _RecentJourneyRow({
    required this.ownerId,
    required this.route,
    required this.onTap,
  });

  final String ownerId;
  final LocalRecordedRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref
        .watch(gpsJourneySummaryProvider((ownerId: ownerId, routeId: route.id)))
        .value;
    final title = (route.title != null && route.title!.trim().isNotEmpty)
        ? route.title!.trim()
        : 'Подорож';
    final when = _dateTime(route.endedAt ?? route.startedAt);
    // Only what is really available; the distance is the CONFIRMED track.
    final subtitle = summary == null
        ? when
        : '$when · ${formatGpsDistance(summary.statistics.totalDistanceMeters)}'
            ' · ${formatGpsDuration(summary.statistics.moving)}';
    return ListTile(
      key: Key('profile_journey_${route.id}'),
      minTileHeight: AppSizes.touchTarget,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: const Icon(Icons.route_outlined, color: AppColors.accent),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}

/// The recent-Journeys stream for [ownerId] (local Drift data only).
AsyncValue<List<LocalRecordedRoute>> watchRecentJourneys(
        WidgetRef ref, String ownerId) =>
    ref.watch(gpsJourneyHistoryProvider(ownerId));
