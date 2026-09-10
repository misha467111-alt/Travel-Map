import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/routes_repository.dart';
import '../domain/location_model.dart';
import '../domain/route.dart';
import '../providers/route_provider.dart';

class RoutesContent extends StatelessWidget {
  const RoutesContent({
    required this.route,
    required this.destination,
    required this.onCreateRoute,
    this.onOpenDetails,
    this.loadingDestinations = false,
    this.savedRoutes,
    this.onOpenSavedRoute,
    super.key,
  });

  final RouteState route;
  final LocationModel? destination;
  final VoidCallback? onCreateRoute;
  final VoidCallback? onOpenDetails;
  final bool loadingDestinations;
  final AsyncValue<List<SavedRoute>>? savedRoutes;
  final ValueChanged<SavedRoute>? onOpenSavedRoute;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final effectiveScale =
        mediaQuery.textScaler.scale(1).clamp(1.0, 1.12).toDouble();
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: ListView(
        key: const Key('routes_main_scroll'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        children: [
          const RouteSectionLabel('АКТИВНИЙ МАРШРУТ'),
          const SizedBox(height: 5),
          if (route.hasRoute)
            TravelRouteCard(
              title: destination == null
                  ? 'Активний маршрут'
                  : 'Маршрут до ${destination!.title}',
              destination: destination?.title,
              distanceMeters: route.distanceMeters,
              durationSeconds: route.durationSeconds,
              stopCount: 2,
              onTap: onOpenDetails,
              footer: onOpenDetails == null
                  ? null
                  : Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: onOpenDetails,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: const Text('Деталі'),
                      ),
                    ),
            )
          else
            const _ActiveRouteEmpty(),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('create_route_cta'),
              onPressed: onCreateRoute,
              icon: loadingDestinations
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_road_rounded),
              label: const Text('Створити маршрут'),
            ),
          ),
          const SizedBox(height: 14),
          const RouteSectionLabel('ЗБЕРЕЖЕНІ МАРШРУТИ'),
          const SizedBox(height: 5),
          ..._savedRoutesChildren(),
        ],
      ),
    );
  }

  List<Widget> _savedRoutesChildren() {
    final value = savedRoutes;
    if (value == null) return const [RoutesEmptyState()];
    return value.when(
      loading: () => const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
      error: (error, stack) => const [
        Text('Не вдалося завантажити збережені маршрути.'),
      ],
      data: (routes) {
        if (routes.isEmpty) return const [RoutesEmptyState()];
        return [
          for (final saved in routes) ...[
            TravelRouteCard(
              key: ValueKey('saved_route_${saved.id}'),
              title: saved.title,
              stopCount: saved.points.length,
              modeLabel: saved.transportMode == RouteTransportMode.walking
                  ? 'Пішки'
                  : 'Авто',
              modeIcon: saved.transportMode == RouteTransportMode.walking
                  ? Icons.directions_walk
                  : Icons.directions_car,
              onTap: onOpenSavedRoute == null
                  ? null
                  : () => onOpenSavedRoute!(saved),
            ),
            const SizedBox(height: 8),
          ],
        ];
      },
    );
  }
}

class TravelRouteCard extends StatelessWidget {
  const TravelRouteCard({
    required this.title,
    this.destination,
    this.distanceMeters,
    this.durationSeconds,
    this.stopCount,
    this.modeLabel,
    this.modeIcon,
    this.onTap,
    this.footer,
    super.key,
  });

  final String title;
  final String? destination;
  final double? distanceMeters;
  final double? durationSeconds;
  final int? stopCount;
  final String? modeLabel;
  final IconData? modeIcon;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('travel_route_card'),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white12),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017).withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.route_rounded,
                        color: Color(0xFFD4A017)),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        if (destination != null) ...[
                          const SizedBox(height: 4),
                          Text(destination!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                ]),
                if (distanceMeters != null ||
                    durationSeconds != null ||
                    stopCount != null ||
                    modeLabel != null) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      if (modeLabel != null)
                        RouteMetric(
                          icon: modeIcon ?? Icons.directions_car,
                          label: modeLabel!,
                        ),
                      if (distanceMeters != null)
                        RouteMetric(
                          icon: Icons.straighten_rounded,
                          label: formatRouteDistance(distanceMeters!),
                        ),
                      if (durationSeconds != null)
                        RouteMetric(
                          icon: Icons.schedule_rounded,
                          label: formatRouteDuration(durationSeconds!),
                        ),
                      if (stopCount != null)
                        RouteMetric(
                          icon: Icons.pin_drop_outlined,
                          label: '$stopCount точки',
                        ),
                    ],
                  ),
                ],
                if (footer != null) footer!,
              ],
            ),
          ),
        ),
      );
}

class RouteMetric extends StatelessWidget {
  const RouteMetric({required this.icon, required this.label, super.key});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17, color: const Color(0xFFD4A017)),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ]);
}

class RouteSectionLabel extends StatelessWidget {
  const RouteSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white60,
              fontWeight: FontWeight.w600,
              letterSpacing: .7,
              fontSize: 12,
            ),
      );
}

class RoutesEmptyState extends StatelessWidget {
  const RoutesEmptyState({super.key});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('saved_routes_empty'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF14231D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(children: [
          Icon(Icons.bookmark_border_rounded,
              color: Color(0xFFD4A017), size: 22),
          SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('У вас ще немає маршрутів'),
              SizedBox(height: 3),
              Text('Збережені маршрути з’являться тут.',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ),
        ]),
      );
}

class _ActiveRouteEmpty extends StatelessWidget {
  const _ActiveRouteEmpty();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('active_route_empty'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF14231D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.route_outlined, color: Color(0xFFD4A017), size: 23),
          const SizedBox(height: 5),
          Text('Активного маршруту немає',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          const Text('Оберіть напрямок і побудуйте маршрут.'),
        ]),
      );
}

String formatRouteDistance(double meters) => meters < 1000
    ? '${meters.round()} м'
    : '${(meters / 1000).toStringAsFixed(1)} км';

String formatRouteDuration(double seconds) {
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return '$minutes хв';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours год' : '$hours год $rest хв';
}
