import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_model.dart';
import '../providers/route_provider.dart';

class RouteDetailsScreen extends ConsumerWidget {
  const RouteDetailsScreen({required this.destination, super.key});
  final LocationModel destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Деталі маршруту'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _RouteHero(destination: destination),
          const SizedBox(height: 16),
          Text(destination.title,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _RouteStats(route: route),
          if (destination.description?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Text(destination.description!),
          ],
          const SizedBox(height: 22),
          Text('Зупинки', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const _StopTile(number: 1, title: 'Ваша поточна локація'),
          _StopTile(number: 2, title: destination.title),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: route.hasRoute
                ? () => Navigator.of(context).popUntil((route) => route.isFirst)
                : null,
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Почати маршрут'),
          ),
        ],
      ),
    );
  }
}

class _RouteHero extends StatelessWidget {
  const _RouteHero({required this.destination});
  final LocationModel destination;

  @override
  Widget build(BuildContext context) {
    final image = destination.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: image?.isNotEmpty == true
          ? CachedNetworkImage(
              imageUrl: image!,
              height: 190,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const _RoutePlaceholder(),
            )
          : const _RoutePlaceholder(),
    );
  }
}

class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        height: 190,
        color: const Color(0xFF142A21),
        alignment: Alignment.center,
        child: const Icon(Icons.route, size: 64, color: Color(0xFFD4A017)),
      );
}

class _RouteStats extends StatelessWidget {
  const _RouteStats({required this.route});
  final RouteState route;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            _Stat(
                icon: Icons.straighten, label: _distance(route.distanceMeters)),
            _Stat(
                icon: Icons.schedule, label: _duration(route.durationSeconds)),
            const _Stat(icon: Icons.pin_drop_outlined, label: '2 зупинки'),
          ]),
        ),
      );

  static String _distance(double? meters) => meters == null
      ? '—'
      : meters < 1000
          ? '${meters.round()} м'
          : '${(meters / 1000).toStringAsFixed(1)} км';

  static String _duration(double? seconds) =>
      seconds == null ? '—' : '${(seconds / 60).ceil()} хв';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Icon(icon, color: const Color(0xFFD4A017)),
          const SizedBox(height: 5),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.number, required this.title});
  final int number;
  final String title;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFD4A017),
            foregroundColor: Colors.black,
            child: Text('$number'),
          ),
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      );
}
