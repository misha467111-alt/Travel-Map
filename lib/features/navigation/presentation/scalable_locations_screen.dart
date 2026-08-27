import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/domain/location_model.dart';
import '../../map/domain/location_query.dart';
import '../../map/providers/locations_provider.dart';
import '../../map/providers/map_provider.dart';
import '../../map/providers/route_provider.dart';
import '../../social/providers/public_profile_provider.dart';
import '../../map/presentation/location_card.dart';
import '../../map/presentation/map_screen.dart';

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
          title: Text(switch (widget.mode) {
            ScalableLocationListMode.discover => 'Відкривай',
            ScalableLocationListMode.adventure => 'Пригода',
            ScalableLocationListMode.nearby => 'Сфера поруч',
            ScalableLocationListMode.saved => 'Збережені місця',
            ScalableLocationListMode.routes => 'Маршрути',
          }),
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: widget.mode == ScalableLocationListMode.routes
            ? _routesBody()
            : (_isDiscover ? _discoverBody() : _locationAwareBody()),
      );

  Future<void> _chooseRouteDestination() async {
    if (_items.isEmpty) return;
    final location = await showModalBottomSheet<LocationModel>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Оберіть напрямок',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            ..._items.take(12).map((item) => ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(item.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      _categoryPresentation[item.category]?.$1 ?? 'Локація'),
                  onTap: () => Navigator.pop(context, item),
                )),
          ],
        ),
      ),
    );
    if (location != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LocationDetailsScreen(location: location),
      ));
    }
  }

  Widget _routesBody() {
    final route = ref.watch(routeProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (route.hasRoute)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading:
                  const CircleAvatar(child: Icon(Icons.navigation_rounded)),
              title: const Text('Активний маршрут'),
              subtitle: Text(
                '${((route.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} км • '
                '${((route.durationSeconds ?? 0) / 60).ceil()} хв',
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          )
        else
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.route_outlined, color: Color(0xFFD4A017), size: 30),
                SizedBox(width: 12),
                Expanded(child: Text('Створіть маршрут до наступної локації')),
              ]),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _items.isEmpty ? null : _chooseRouteDestination,
            icon: const Icon(Icons.add_road),
            label: const Text('Створити маршрут'),
          ),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Популярні напрямки',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ..._items
              .take(8)
              .map((location) => _BoundedLocationCard(location: location)),
        ] else if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
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

  Future<void> _refresh() async {
    if (_isDiscover) return _loadPage(reset: true);
    ref.invalidate(currentPositionProvider);
  }

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
            error: (error, _) => Center(child: Text('$error')),
          );
    }
    return ref.watch(currentPositionProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
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
                  error: (error, _) => Center(child: Text('$error')),
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
        padding: const EdgeInsets.all(12),
        children: [
          if (widget.mode != ScalableLocationListMode.routes) ...[
            if (widget.mode == ScalableLocationListMode.adventure)
              Card(
                margin: const EdgeInsets.only(bottom: 14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.explore,
                            color: Color(0xFFD4A017), size: 34),
                        const SizedBox(height: 8),
                        Text('Куди вирушимо сьогодні?',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        const Text(
                            'Оберіть настрій і відстань — ми запропонуємо реальне місце поруч.'),
                        const SizedBox(height: 12),
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
            Wrap(
              spacing: 6,
              children: [
                'all',
                'general',
                'cafe',
                'nature',
                'culture',
                'entertainment'
              ]
                  .map((category) => ChoiceChip(
                        avatar:
                            Icon(_categoryPresentation[category]!.$2, size: 17),
                        label: Text(_categoryPresentation[category]!.$1),
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
            _BoundedLocationCard(location: location),
          if (error != null) Text('Не вдалося завантажити: $error'),
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
  const _BoundedLocationCard({required this.location});

  final LocationModel location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved =
        ref.watch(savedPublicLocationsProvider).value ?? const <String>{};
    return LocationCard(
      location: location,
      isSaved: saved.contains(location.id),
      onBookmarkTap: () =>
          ref.read(savedPublicLocationsProvider.notifier).toggle(location.id),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LocationDetailsScreen(location: location),
      )),
    );
  }
}
