import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_model.dart';
import '../providers/route_provider.dart';
import 'map_screen.dart';
import 'routes_presentation.dart';

class RouteDetailsScreen extends ConsumerWidget {
  const RouteDetailsScreen({required this.destination, super.key});
  final LocationModel destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text(
          'Деталі маршруту',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: RouteDetailsContent(
        route: route,
        destination: destination,
        onStart: route.hasRoute
            ? () => Navigator.of(context).popUntil((route) => route.isFirst)
            : null,
        onDestinationTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LocationDetailsScreen(location: destination),
          ),
        ),
      ),
    );
  }
}

class RouteDetailsContent extends StatelessWidget {
  const RouteDetailsContent({
    required this.route,
    required this.destination,
    required this.onStart,
    this.onDestinationTap,
    super.key,
  });

  final RouteState route;
  final LocationModel destination;
  final VoidCallback? onStart;
  final VoidCallback? onDestinationTap;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final effectiveScale =
        mediaQuery.textScaler.scale(1).clamp(1.0, 1.12).toDouble();
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            key: const Key('route_details_scroll'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            children: [
              RouteHero(
                destination: destination,
                height: constraints.maxWidth < 350 ? 118 : 132,
              ),
              const SizedBox(height: 10),
              Text(
                'Маршрут до ${destination.title}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      height: 1.08,
                    ),
              ),
              if (route.distanceMeters != null ||
                  route.durationSeconds != null) ...[
                const SizedBox(height: 9),
                RouteStatsCard(route: route, stopCount: 2),
              ],
              const SizedBox(height: 16),
              const RouteSectionLabel('МАРШРУТ'),
              const SizedBox(height: 7),
              OrderedRouteStops(
                stops: [
                  const RouteStopPresentation(
                    title: 'Моя позиція',
                    icon: Icons.my_location_rounded,
                  ),
                  RouteStopPresentation(
                    title: destination.title,
                    icon: Icons.flag_rounded,
                    onTap: onDestinationTap,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('start_route_cta'),
                onPressed: onStart,
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Почати маршрут'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RouteHero extends StatelessWidget {
  const RouteHero({
    required this.destination,
    this.height = 190,
    super.key,
  });
  final LocationModel destination;
  final double height;

  @override
  Widget build(BuildContext context) {
    final image = destination.imageUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        key: const Key('route_details_hero'),
        height: height,
        child: image?.isNotEmpty == true
            ? Image.network(
                image!,
                key: const Key('route_real_image'),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const RoutePlaceholder(),
              )
            : const RoutePlaceholder(),
      ),
    );
  }
}

class RoutePlaceholder extends StatelessWidget {
  const RoutePlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('route_hero_placeholder'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1C382D), Color(0xFF10221B)],
          ),
        ),
        alignment: Alignment.center,
        child:
            const Icon(Icons.route_rounded, size: 42, color: Color(0xFFD4A017)),
      );
}

class RouteStatsCard extends StatelessWidget {
  const RouteStatsCard({
    required this.route,
    required this.stopCount,
    super.key,
  });
  final RouteState route;
  final int stopCount;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('route_stats'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF14231D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          runAlignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            if (route.distanceMeters != null)
              _LabeledStat(
                label: 'Відстань',
                value: formatRouteDistance(route.distanceMeters!),
              ),
            if (route.durationSeconds != null)
              _LabeledStat(
                label: 'Час',
                value: formatRouteDuration(route.durationSeconds!),
              ),
            _LabeledStat(label: 'Зупинки', value: '$stopCount точки'),
          ],
        ),
      );
}

class _LabeledStat extends StatelessWidget {
  const _LabeledStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 72),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(value,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFD4A017),
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.white60)),
        ]),
      );
}

class RouteStopPresentation {
  const RouteStopPresentation({
    required this.title,
    required this.icon,
    this.onTap,
  });
  final String title;
  final IconData icon;
  final VoidCallback? onTap;
}

class OrderedRouteStops extends StatelessWidget {
  const OrderedRouteStops({required this.stops, super.key});
  final List<RouteStopPresentation> stops;

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('ordered_route_stops'),
        children: List.generate(stops.length, (index) {
          final stop = stops[index];
          final isLast = index == stops.length - 1;
          return IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 34,
                child: Column(children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Text('${index + 1}',
                        key: Key('route_stop_number_${index + 1}'),
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w800)),
                  ),
                  if (!isLast)
                    const Expanded(
                      child: VerticalDivider(
                        color: Color(0x66D4A017),
                        thickness: 2,
                        width: 2,
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Card(
                  margin: EdgeInsets.only(bottom: isLast ? 0 : 7),
                  child: ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -2),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    leading: Icon(stop.icon, color: const Color(0xFFD4A017)),
                    title: Text(stop.title,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    trailing: stop.onTap == null
                        ? null
                        : const Icon(Icons.chevron_right),
                    onTap: stop.onTap,
                  ),
                ),
              ),
            ]),
          );
        }),
      );
}
