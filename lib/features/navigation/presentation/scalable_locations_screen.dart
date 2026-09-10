import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/data/routes_repository.dart';
import '../../map/domain/location_model.dart';
import '../../map/domain/location_query.dart';
import '../../map/domain/route.dart';
import '../../map/providers/locations_provider.dart';
import '../../map/providers/map_provider.dart';
import '../../map/providers/route_provider.dart';
import '../../social/providers/public_profile_provider.dart';
import '../../map/presentation/location_card.dart';
import '../../map/presentation/map_screen.dart';
import '../../map/presentation/route_creation_screen.dart';
import '../../map/presentation/route_details_screen.dart';
import '../../map/presentation/routes_presentation.dart';

enum ScalableLocationListMode { discover, adventure, nearby, saved, routes }

class ScalableLocationsScreen extends ConsumerStatefulWidget {
  const ScalableLocationsScreen({required this.mode, super.key});

  final ScalableLocationListMode mode;

  @override
  ConsumerState<ScalableLocationsScreen> createState() =>
      _ScalableLocationsScreenState();
}

class _ScalableLocationsScreenState
    extends ConsumerState<ScalableLocationsScreen> {
  static const _pageSize = 30;
  final _items = <LocationModel>[];
  LocationCursor? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  String _category = 'all';
  String _search = '';
  double _radiusKm = 10;
  int _adventureGeneration = 1;
  LocationModel? _activeRouteDestination;

  static const _categoryPresentation = <String, (String, IconData)>{
    'all': ('Усі', Icons.auto_awesome),
    'general': ('Загальне', Icons.place_outlined),
    'cafe': ('Кафе', Icons.local_cafe),
    'nature': ('Природа', Icons.park),
    'culture': ('Культура', Icons.museum),
    'entertainment': ('Розваги', Icons.theater_comedy),
  };

  bool get _isDiscover =>
      widget.mode == ScalableLocationListMode.discover ||
      widget.mode == ScalableLocationListMode.routes;

  @override
  void initState() {
    super.initState();
    if (_isDiscover) Future.microtask(() => _loadPage(reset: true));
  }

  Future<void> _loadPage({required bool reset}) async {
    if (_loading || (!reset && !_hasMore)) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _cursor = null;
        _hasMore = true;
      }
    });
    try {
      final page =
          await ref.read(locationsRepositoryProvider).fetchDiscoverPage(
                cursor: reset ? null : _cursor,
                category: _category == 'all' ? null : _category,
                search: _search,
                limit: widget.mode == ScalableLocationListMode.routes
                    ? 20
                    : _pageSize,
              );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items.map((item) => item.location));
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: Text(
              switch (widget.mode) {
                ScalableLocationListMode.discover => 'Відкривай',
                ScalableLocationListMode.adventure => 'Пригода',
                ScalableLocationListMode.nearby => 'Сфера поруч',
                ScalableLocationListMode.saved => 'Збережені місця',
                ScalableLocationListMode.routes => 'Маршрути',
              },
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
          top: false,
          child: widget.mode == ScalableLocationListMode.routes
              ? _routesBody()
              : (_isDiscover ? _discoverBody() : _locationAwareBody()),
        ),
      );

  Future<void> _chooseRouteDestination() async {
    if (_items.isEmpty) return;
    final location = await showModalBottomSheet<LocationModel>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _RouteDestinationSheet(locations: _items),
    );
    if (location != null && mounted) {
      setState(() => _activeRouteDestination = location);
      try {
        ref.invalidate(currentPositionProvider);
        final position = await ref.read(currentPositionProvider.future);
        await ref.read(routeProvider.notifier).buildRoute(
              start: RoutePoint(
                latitude: position.latitude,
                longitude: position.longitude,
              ),
              end: RoutePoint(
                latitude: location.latitude,
                longitude: location.longitude,
              ),
            );
        if (mounted && ref.read(routeProvider).hasRoute) {
          await _openActiveRouteDetails();
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Не вдалося побудувати маршрут. Спробуйте ще раз.')),
          );
        }
      }
    }
  }

  Future<void> _openActiveRouteDetails() async {
    final destination = _activeRouteDestination;
    if (destination == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RouteDetailsScreen(destination: destination),
    ));
  }

  Future<void> _openSavedRoute(SavedRoute saved) async {
    if (saved.points.isEmpty || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RouteCreationScreen(
        firstWaypoint: saved.points.first,
        initialWaypoints: saved.points,
        initialTransportMode: saved.transportMode,
      ),
    ));
  }

  Widget _routesBody() {
    final route = ref.watch(routeProvider);
    final savedRoutes = ref.watch(savedRoutesProvider);
    return RoutesContent(
      route: route,
      destination: _activeRouteDestination,
      onCreateRoute: _items.isEmpty ? null : _chooseRouteDestination,
      onOpenDetails: route.hasRoute && _activeRouteDestination != null
          ? _openActiveRouteDetails
          : null,
      loadingDestinations: _loading,
      savedRoutes: savedRoutes,
      onOpenSavedRoute: _openSavedRoute,
    );
  }

  // ignore: unused_element
  Widget _legacyRoutesBody() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Активний маршрут',
              style: Theme.of(context).textTheme.titleLarge),
          Card(
              child: ListTile(
            leading: const Icon(Icons.navigation_outlined),
            title: const Text('Плануйте наступну подорож'),
            subtitle: const Text('Оберіть місце на карті та побудуйте маршрут'),
            trailing: FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Оберіть місце на карті, щоб створити маршрут')),
              ),
              child: const Text('Створити'),
            ),
          )),
          const SizedBox(height: 12),
          Text('Збережені маршрути',
              style: Theme.of(context).textTheme.titleLarge),
          const Card(
              child: ListTile(
            leading: Icon(Icons.bookmark_outline),
            title: Text('Поки немає збережених маршрутів'),
            subtitle: Text('Ваші маршрути з’являться тут'),
          )),
          const SizedBox(height: 12),
          Text('Останні напрямки',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          ..._items.map((location) => _BoundedLocationCard(location: location)),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _hasMore)
            FilledButton.tonal(
                onPressed: () => _loadPage(reset: false),
                child: const Text('Показати ще')),
        ],
      );

  Widget _discoverBody() => _list(
        _items,
        loading: _loading,
        error: _error,
        loadMore: _hasMore ? () => _loadPage(reset: false) : null,
      );

  Widget _locationAwareBody() {
    if (widget.mode == ScalableLocationListMode.saved) {
      final ids =
          ref.watch(savedPublicLocationsProvider).value ?? const <String>{};
      return ref.watch(savedLocationsProvider(ids)).when(
            data: (items) => items.isEmpty ? _emptySavedState() : _list(items),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => const Center(
              child: Text('Не вдалося завантажити збережені місця.'),
            ),
          );
    }
    return ref.watch(currentPositionProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => const Center(
            child: Text('Не вдалося визначити вашу позицію.'),
          ),
          data: (position) {
            final double radius =
                widget.mode == ScalableLocationListMode.adventure
                    ? math.min(_radiusKm, 15)
                    : _radiusKm;
            final query = (
              latitude: position.latitude,
              longitude: position.longitude,
              radiusMeters: radius * 1000,
              category: _category == 'all' ? null : _category,
            );
            return ref.watch(nearbyLocationsProvider(query)).when(
                  data: (items) {
                    final locations =
                        items.map((item) => item.location).toList();
                    if (widget.mode == ScalableLocationListMode.adventure &&
                        locations.length > 1) {
                      locations.shuffle(math.Random(_adventureGeneration));
                      locations.removeRange(1, locations.length);
                    }
                    return _list(locations);
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => const Center(
                    child: Text('Не вдалося завантажити місця поруч.'),
                  ),
                );
          },
        );
  }

  Widget _emptySavedState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.bookmark_border,
                    size: 56, color: Colors.amber),
                const SizedBox(height: 12),
                Text('Мої закладки',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                    'Зберігайте цікаві місця, щоб повернутися до них пізніше.',
                    textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      );

  Widget _list(
    List<LocationModel> items, {
    bool loading = false,
    Object? error,
    VoidCallback? loadMore,
  }) =>
      ListView(
        key: Key('locations_${widget.mode.name}_scroll'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: [
          if (widget.mode != ScalableLocationListMode.routes) ...[
            if (widget.mode == ScalableLocationListMode.adventure)
              Card(
                key: const Key('adventure_hero'),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.explore,
                            color: Color(0xFFD4A017), size: 28),
                        const SizedBox(height: 5),
                        Text('Куди вирушимо сьогодні?',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text(
                            'Оберіть настрій і відстань — ми запропонуємо реальне місце поруч.'),
                        const SizedBox(height: 9),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                setState(() => _adventureGeneration++),
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Здивуй мене'),
                          ),
                        ),
                      ]),
                ),
              ),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Пошук місць',
              ),
              onSubmitted: (value) {
                setState(() => _search = value.trim());
                if (_isDiscover) _loadPage(reset: true);
              },
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 0,
              children: [
                'all',
                'general',
                'cafe',
                'nature',
                'culture',
                'entertainment'
              ]
                  .map((category) => ChoiceChip(
                        visualDensity:
                            const VisualDensity(horizontal: -3, vertical: -3),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        avatar:
                            Icon(_categoryPresentation[category]!.$2, size: 15),
                        label: Text(_categoryPresentation[category]!.$1,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500)),
                        selected: _category == category,
                        onSelected: (_) {
                          setState(() => _category = category);
                          if (_isDiscover) _loadPage(reset: true);
                        },
                      ))
                  .toList(),
            ),
          ],
          if (widget.mode == ScalableLocationListMode.nearby ||
              widget.mode == ScalableLocationListMode.adventure)
            Slider(
              value: _radiusKm,
              min: 1,
              max: 50,
              divisions: 49,
              label: '${_radiusKm.round()} км',
              onChanged: (value) => setState(() => _radiusKm = value),
            ),
          for (final location in items)
            _BoundedLocationCard(
              location: location,
              compact: widget.mode == ScalableLocationListMode.discover ||
                  widget.mode == ScalableLocationListMode.adventure,
            ),
          if (error != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Не вдалося завантажити місця.'),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (loadMore != null)
            FilledButton.tonal(
              onPressed: loadMore,
              child: const Text('Завантажити ще'),
            ),
        ],
      );
}

class _BoundedLocationCard extends ConsumerWidget {
  const _BoundedLocationCard({required this.location, this.compact = false});

  final LocationModel location;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved =
        ref.watch(savedPublicLocationsProvider).value ?? const <String>{};
    return LocationCard(
      location: location,
      compact: compact,
      isSaved: saved.contains(location.id),
      onBookmarkTap: () =>
          ref.read(savedPublicLocationsProvider.notifier).toggle(location.id),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LocationDetailsScreen(location: location),
      )),
    );
  }
}

class _RouteDestinationSheet extends StatelessWidget {
  const _RouteDestinationSheet({required this.locations});
  final List<LocationModel> locations;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final effectiveScale =
        mediaQuery.textScaler.scale(1).clamp(1.0, 1.12).toDouble();
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: SafeArea(
        child: FractionallySizedBox(
          heightFactor: .72,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 6, 8),
              child: Row(children: [
                Expanded(
                  child: Text('Створити маршрут',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: 'Закрити',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Column(children: [
                _RouteEndpoint(
                  icon: Icons.my_location_rounded,
                  label: 'Звідки',
                  value: 'Моя позиція',
                ),
                Padding(
                  padding: EdgeInsets.only(left: 21),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 10,
                      child: VerticalDivider(width: 1),
                    ),
                  ),
                ),
                _RouteEndpoint(
                  icon: Icons.flag_rounded,
                  label: 'Куди',
                  value: 'Оберіть локацію нижче',
                ),
              ]),
            ),
            const SizedBox(height: 9),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
                itemCount: locations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final item = locations[index];
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(Icons.place_outlined,
                        color: Color(0xFFD4A017)),
                    title: Text(item.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_ScalableLocationsScreenState
                            ._categoryPresentation[item.category]?.$1 ??
                        'Локація'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RouteEndpoint extends StatelessWidget {
  const _RouteEndpoint({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF14231D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          Icon(icon, color: const Color(0xFFD4A017)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        ]),
      );
}
