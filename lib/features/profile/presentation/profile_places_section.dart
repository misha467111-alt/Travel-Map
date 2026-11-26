import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../../gps/local/gps_local_database.dart';
import '../../gps/presentation/gps_journey_history_view.dart'
    show gpsJourneyHistoryProvider;
import '../../gps/presentation/gps_journey_summary_view.dart'
    show formatGpsDistance, formatGpsDuration;
import '../providers/profile_journey_data_provider.dart';
import 'profile_premium_components.dart';
import 'profile_route_sketch.dart';

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

/// The three most recent finished Journeys of this owner (local data) as
/// horizontal cards: date, CONFIRMED distance and moving time, and an outline of
/// the confirmed track drawn from the local GPS points. Tap opens the existing
/// Journey details; "Усі →" opens the existing history.
class ProfileRecentJourneysCard extends ConsumerWidget {
  const ProfileRecentJourneysCard({
    required this.ownerId,
    required this.journeys,
    required this.onOpenJourney,
    this.onOpenAll,
    this.loadData = true,
    super.key,
  });

  final String ownerId;
  final AsyncValue<List<LocalRecordedRoute>> journeys;
  final ValueChanged<String> onOpenJourney;

  /// Whether the per-Journey data (statistics and outline) may be read now.
  /// The profile is a tab kept alive in an `IndexedStack`, so it passes
  /// `false` until the tab has been shown at least once: nothing is read from
  /// the GPS database for a tab nobody has opened.
  final bool loadData;

  /// Opens the full Journey history; the "Усі →" link is hidden when `null`.
  final VoidCallback? onOpenAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget panel(Widget child) => Container(
          width: double.infinity,
          decoration: premiumCardDecoration(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: child,
        );
    final body = journeys.when(
      loading: () => panel(const Center(
          child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  key: Key('profile_journeys_loading'),
                  strokeWidth: 2,
                  color: AppColors.accent)))),
      error: (_, __) => panel(Text('Не вдалося завантажити подорожі',
          key: const Key('profile_journeys_error'),
          style: theme.textTheme.bodySmall)),
      data: (routes) => routes.isEmpty
          ? panel(Text('Подорожей ще немає',
              key: const Key('profile_journeys_empty'),
              style: theme.textTheme.bodySmall))
          : LayoutBuilder(builder: (context, constraints) {
              final shown = routes.take(3).toList();
              // One card fills the width; several leave the next one peeking.
              final width = shown.length == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth * 0.86).clamp(260.0, 340.0);
              return SingleChildScrollView(
                key: const Key('profile_journeys_strip'),
                scrollDirection: Axis.horizontal,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.sm),
                        SizedBox(
                          width: width,
                          child: _RecentJourneyCard(
                            ownerId: ownerId,
                            route: shown[i],
                            loadData: loadData,
                            onTap: () => onOpenJourney(shown[i].id),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PremiumSectionHeader(
          title: 'Останні подорожі',
          onAll: onOpenAll,
          allKey: const Key('profile_journeys_all'),
        ),
        body,
      ],
    );
  }
}

String _dateTime(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

class _RecentJourneyCard extends ConsumerWidget {
  const _RecentJourneyCard({
    required this.ownerId,
    required this.route,
    required this.onTap,
    required this.loadData,
  });

  final String ownerId;
  final LocalRecordedRoute route;
  final VoidCallback onTap;
  final bool loadData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = (ownerId: ownerId, routeId: route.id);
    // One read of the Journey's points gives both the numbers and the outline.
    final dataState = loadData
        ? ref.watch(profileJourneyDataProvider(key))
        : const AsyncLoading<ProfileJourneyData?>();
    final data = dataState.value;
    final loading = dataState.isLoading && data == null;
    final title = (route.title != null && route.title!.trim().isNotEmpty)
        ? route.title!.trim()
        : 'Подорож';
    final when = _dateTime(route.endedAt ?? route.startedAt);

    Widget metric(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.accent),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
          ],
        );

    // While the numbers load their space is reserved (invisible text of the same
    // style with a quiet bar on top), so the card does not jump when they arrive.
    Widget metricSlot(IconData icon, String? text) => text != null
        ? metric(icon, text)
        : ExcludeSemantics(
            child: Stack(children: [
              Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: metric(icon, '0')),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    key: const Key('profile_journey_metric_placeholder'),
                    width: 72,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
              ),
            ]),
          );

    return Container(
      key: Key('profile_journey_${route.id}'),
      decoration: premiumCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 112, child: RouteSketchPanel(runs: data?.runs)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 20, color: AppColors.textSecondary),
                      ]),
                      const SizedBox(height: 2),
                      Text(when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                      // Only what is really available; the distance is the
                      // CONFIRMED track.
                      if (data != null || loading) ...[
                        const SizedBox(height: AppSpacing.sm),
                        metricSlot(
                            Icons.straighten,
                            data == null
                                ? null
                                : formatGpsDistance(
                                    data.statistics.totalDistanceMeters)),
                        const SizedBox(height: AppSpacing.xs),
                        metricSlot(
                            Icons.timer_outlined,
                            data == null
                                ? null
                                : formatGpsDuration(data.statistics.moving)),
                      ],
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The recent-Journeys stream for [ownerId] (local Drift data only).
AsyncValue<List<LocalRecordedRoute>> watchRecentJourneys(
        WidgetRef ref, String ownerId) =>
    ref.watch(gpsJourneyHistoryProvider(ownerId));
