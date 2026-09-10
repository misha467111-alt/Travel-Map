import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../controllers/profile_controller.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../social/providers/public_profile_provider.dart';
import '../../check_in/data/supabase_check_in_repository.dart';
import '../domain/location_model.dart';
import '../domain/location_query.dart';
import '../domain/location_categories.dart';
import '../domain/comment_model.dart';
import '../domain/route.dart';
import '../providers/comments_provider.dart';
import '../providers/locations_provider.dart';
import '../providers/map_provider.dart';
import '../providers/map_filter_provider.dart';
import '../providers/network_provider.dart';
import '../providers/route_provider.dart';
import 'clustered_location_map.dart';
import 'map_reference_icons.dart';
import 'location_card.dart';
import 'route_details_screen.dart';
import 'route_creation_screen.dart';
import 'review_screen.dart';
import 'map_filters_sheet.dart';
import 'map_categories_sheet.dart';
import '../../navigation/presentation/scalable_locations_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapViewportBounds? _viewport;
  List<LocationModel> _lastLocations = const [];
  double? _lastUserLatitude;
  double? _lastUserLongitude;

  Future<void> _handleMapLongPress(
      BuildContext context, WidgetRef ref, LatLng point) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Що створити?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: const Text('Створити локацію'),
              onTap: () => Navigator.pop(context, 'location'),
            ),
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: const Text('Створити маршрут'),
              onTap: () => Navigator.pop(context, 'route'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Скасувати'),
            ),
          ]),
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'location') {
      await _addLocation(context, ref, point);
    } else if (action == 'route') {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => RouteCreationScreen(
          firstWaypoint: RoutePoint(
            latitude: point.latitude,
            longitude: point.longitude,
          ),
        ),
      ));
    }
  }

  @override
  void initState() {
    super.initState();
    assert(() {
      _logGpsState();
      return true;
    }());
  }

  Future<void> _logGpsState() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    debugPrint('[GPS_DEBUG] permission=$permission '
        'serviceEnabled=$serviceEnabled');
  }

  void _showMapFilters(BuildContext context, WidgetRef ref) {
    final bounds = _viewport ??
        (_lastUserLatitude == null
            ? null
            : MapViewportBounds(
                minLatitude: _lastUserLatitude! - .1,
                minLongitude: _lastUserLongitude! - .1,
                maxLatitude: _lastUserLatitude! + .1,
                maxLongitude: _lastUserLongitude! + .1,
              ));
    final effectiveBounds = bounds ??
        const MapViewportBounds(
          minLatitude: 50.35,
          minLongitude: 30.42,
          maxLatitude: 50.55,
          maxLongitude: 30.62,
        );
    final filters = ref.read(mapFilterProvider);
    ref.read(mapFilterProvider.notifier).updatePending(filters.applied);
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => MapFiltersSheet(
        bounds: effectiveBounds,
        userLatitude: _lastUserLatitude,
        userLongitude: _lastUserLongitude,
      ),
    ));
  }

  Future<void> _addLocation(
    BuildContext context,
    WidgetRef ref,
    LatLng point,
  ) async {
    if (!ref.read(isOnlineProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для цієї дії потрібен інтернет')),
      );
      return;
    }
    final input = await showDialog<_NewLocationInput>(
      context: context,
      builder: (context) => const _AddLocationDialog(),
    );
    if (input == null || !context.mounted) return;

    final requestId = const Uuid().v4();
    try {
      await ref.read(locationsRepositoryProvider).createLocation(
            title: input.title,
            description: input.description,
            latitude: point.latitude,
            longitude: point.longitude,
            category: input.category,
            imageBytes: input.imageBytes,
            imageName: input.imageName,
            requestId: requestId,
          );
      ref.invalidate(viewportLocationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Локацію успішно додано.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('Не вдалося зберегти локацію. Спробуйте ще раз.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLocationDetails(
    BuildContext context,
    WidgetRef ref,
    LocationModel location,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => MapLocationPreview(
        location: location,
        onBuildRoute: () {
          Navigator.of(sheetContext).pop();
          _buildRoute(context, ref, location);
        },
        onOpenDetails: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => LocationDetailsScreen(location: location),
          ));
        },
      ),
    );
  }

  Future<void> _buildRoute(
    BuildContext context,
    WidgetRef ref,
    LocationModel location,
  ) async {
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
      if (context.mounted && ref.read(routeProvider).hasRoute) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RouteDetailsScreen(destination: location),
        ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося отримати геопозицію.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(currentPositionProvider);
    final route = ref.watch(routeProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 12,
        title: const Text(
          'Travel Map',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        actionsIconTheme: const IconThemeData(size: 18),
        actions: [
          const _NotificationsButton(),
          IconButton(
            tooltip: 'Фільтри',
            onPressed: () => _showMapFilters(context, ref),
            style: _mapAppBarActionStyle,
            icon:
                const Icon(Icons.filter_alt_outlined, color: Color(0xFFD4A017)),
          ),
        ],
      ),
      body: position.when(
        data: (currentPosition) {
          _lastUserLatitude = currentPosition.latitude;
          _lastUserLongitude = currentPosition.longitude;
          final bounds = _viewport ??
              MapViewportBounds(
                minLatitude: currentPosition.latitude - 0.1,
                minLongitude: currentPosition.longitude - 0.1,
                maxLatitude: currentPosition.latitude + 0.1,
                maxLongitude: currentPosition.longitude + 0.1,
              );
          final filters = ref.watch(mapFilterProvider).applied;
          final query = MapViewportQuery(
            bounds: bounds,
            category: filters.category == 'all' ? null : filters.category,
            userLatitude: currentPosition.latitude,
            userLongitude: currentPosition.longitude,
            maximumDistanceMeters: filters.maximumDistanceMeters,
            minimumRating: filters.minimumRating,
            openNow: filters.openNow,
            familyOnly: filters.familyOnly,
            sort: filters.rpcSort,
          );
          final locations = ref.watch(viewportLocationsProvider(query));
          final freshLocations = locations.asData?.value.items;
          if (freshLocations != null) _lastLocations = freshLocations;
          final visibleLocations = freshLocations ?? _lastLocations;
          assert(() {
            if (freshLocations != null) {
              debugPrint('[MAP_DEBUG] rows=${freshLocations.length} '
                  'bbox=${bounds.minLatitude},${bounds.minLongitude},'
                  '${bounds.maxLatitude},${bounds.maxLongitude} '
                  'category=${query.category ?? "NULL"}');
            }
            return true;
          }());
          return Stack(
            children: [
              ClusteredLocationMap(
                key: const Key('stable_viewport_map'),
                initialTarget: LatLng(
                  currentPosition.latitude,
                  currentPosition.longitude,
                ),
                userPosition: LatLng(
                  currentPosition.latitude,
                  currentPosition.longitude,
                ),
                locations: visibleLocations,
                polylines: route.hasRoute
                    ? {
                        Polyline(
                          polylineId: const PolylineId('active_route'),
                          points: route.points
                              .map((point) => LatLng(
                                    point.latitude,
                                    point.longitude,
                                  ))
                              .toList(growable: false),
                          color: Theme.of(context).colorScheme.primary,
                          width: 6,
                          startCap: Cap.roundCap,
                          endCap: Cap.roundCap,
                        ),
                      }
                    : const <Polyline>{},
                onLocationTap: (location) =>
                    _showLocationDetails(context, ref, location),
                onLongPress: (point) =>
                    _handleMapLongPress(context, ref, point),
                onViewportChanged: (visible) {
                  final next = MapViewportBounds(
                    minLatitude: visible.southwest.latitude,
                    minLongitude: visible.southwest.longitude,
                    maxLatitude: visible.northeast.latitude,
                    maxLongitude: visible.northeast.longitude,
                  );
                  if (_viewport == null ||
                      next.materiallyDiffersFrom(_viewport!)) {
                    setState(() => _viewport = next);
                  }
                },
                beforeLocationToolbarAction: MapToolbarButton(
                  tooltip: 'Випадкова локація',
                  icon: Icons.casino_outlined,
                  artwork: const MapReferenceIcon(MapReferenceGlyph.dice,
                      size: 20, color: Color(0xFFD4A017)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const ScalableLocationsScreen(
                            mode: ScalableLocationListMode.adventure)),
                  ),
                ),
                additionalToolbarActions: _MapQuickActions(
                  onAdd: () => _addLocation(
                    context,
                    ref,
                    LatLng(currentPosition.latitude, currentPosition.longitude),
                  ),
                ),
                overlays: [
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _CategoryFilterBar(),
                  ),
                ],
              ),
              if (route.status != RouteStatus.idle)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: _RouteCard(route: route),
                ),
              if (locations.isLoading && visibleLocations.isEmpty)
                const Positioned(
                  top: 56,
                  left: 16,
                  right: 16,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (locations.hasError && visibleLocations.isEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _InlineMapError(
                    onRetry: () =>
                        ref.invalidate(viewportLocationsProvider(query)),
                  ),
                ),
              if (!isOnline)
                const Positioned(
                  top: 64,
                  left: 16,
                  right: 16,
                  child: _OfflineBanner(),
                ),
            ],
          );
        },
        loading: () => ClusteredLocationMap(
          initialTarget: const LatLng(50.4501, 30.5234),
          userPosition: null,
          locations: const [],
          polylines: const {},
          onLocationTap: (_) {},
          onLongPress: (point) => _handleMapLongPress(context, ref, point),
          onViewportChanged: (_) {},
        ),
        error: (error, stackTrace) => Stack(
          children: [
            ClusteredLocationMap(
              initialTarget: const LatLng(50.4501, 30.5234),
              userPosition: null,
              locations: const [],
              polylines: const {},
              onLocationTap: (_) {},
              onLongPress: (point) => _handleMapLongPress(context, ref, point),
              onViewportChanged: (_) {},
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: ListTile(
                  leading: const Icon(Icons.location_off_outlined),
                  title: const Text('Геолокація недоступна'),
                  subtitle: const Text(
                    'Перевірте дозвіл або служби геолокації.',
                    maxLines: 2,
                  ),
                  trailing: IconButton(
                    tooltip: 'Спробувати ще раз',
                    onPressed: () => ref.invalidate(currentPositionProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsButton extends ConsumerWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    return IconButton(
      style: _mapAppBarActionStyle,
      tooltip: 'Сповіщення',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const NotificationsScreen(),
        ),
      ),
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class _MapQuickActions extends StatelessWidget {
  const _MapQuickActions({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _action(
              context,
              'Поруч',
              Icons.near_me_outlined,
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ScalableLocationsScreen(
                      mode: ScalableLocationListMode.nearby)))),
          _action(context, 'Додати місце', Icons.add, onAdd),
        ],
      );

  Widget _action(BuildContext context, String label, IconData icon,
          VoidCallback onPressed) =>
      MapToolbarButton(
        tooltip: label,
        icon: icon,
        onPressed: onPressed,
        highlighted: icon == Icons.add,
      );
}

class MapLocationPreview extends StatelessWidget {
  const MapLocationPreview({
    required this.location,
    required this.onBuildRoute,
    required this.onOpenDetails,
    super.key,
  });

  final LocationModel location;
  final VoidCallback onBuildRoute;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final category = locationCategoryPresentation(location.category);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A017).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(category.icon, color: const Color(0xFFD4A017)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(location.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text('${category.emoji} ${category.label}',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFFD4A017),
                                )),
                  ],
                ),
              ),
            ]),
            if (location.description?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(location.description!,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const Key('preview_open_details'),
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Детальніше'),
                ),
                OutlinedButton.icon(
                  key: const Key('preview_route'),
                  onPressed: onBuildRoute,
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Маршрут'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LocationDetailsScreen extends ConsumerWidget {
  const LocationDetailsScreen({required this.location, super.key});

  final LocationModel location;

  Future<void> _buildRoute(BuildContext context, WidgetRef ref) async {
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
      if (context.mounted && ref.read(routeProvider).hasRoute) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RouteDetailsScreen(destination: location),
        ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося побудувати маршрут.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedLocations = ref.watch(savedPublicLocationsProvider);
    final isSaved =
        (savedLocations.value ?? const <String>{}).contains(location.id);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: const Text(
          'Локація',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            key: const Key('details_saved_action'),
            tooltip: isSaved ? 'Прибрати зі збережених' : 'Зберегти локацію',
            onPressed: savedLocations.hasValue
                ? () => ref
                    .read(savedPublicLocationsProvider.notifier)
                    .toggle(location.id)
                : null,
            icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
          ),
        ],
      ),
      body: LocationDetailsContent(
        location: location,
        onBuildRoute: () => _buildRoute(context, ref),
        showRouteStatus: true,
      ),
    );
  }
}

class LocationDetailsContent extends ConsumerStatefulWidget {
  const LocationDetailsContent(
      {required this.location,
      required this.onBuildRoute,
      this.showRouteStatus = false,
      super.key});

  final LocationModel location;
  final VoidCallback onBuildRoute;
  final bool showRouteStatus;

  @override
  ConsumerState<LocationDetailsContent> createState() =>
      _LocationDetailsContentState();
}

class _LocationDetailsContentState
    extends ConsumerState<LocationDetailsContent> {
  bool _checkingIn = false;
  bool _descriptionExpanded = false;

  Future<void> _checkIn() async {
    if (_checkingIn || !ref.read(isOnlineProvider)) return;
    setState(() => _checkingIn = true);
    try {
      final position = await Geolocator.getCurrentPosition();
      final result =
          await SupabaseCheckInRepository(Supabase.instance.client).checkIn(
        locationId: widget.location.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
      await profileController.refreshServerProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-in успішний: +${result.xpAwarded} XP')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося зробити check-in.')),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  Future<void> _delete(String id) async {
    if (!ref.read(isOnlineProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для цієї дії потрібен інтернет')),
      );
      return;
    }
    try {
      await ref.read(commentsControllerProvider).deleteOwnComment(
            locationId: widget.location.id,
            commentId: id,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося видалити коментар.')),
        );
      }
    }
  }

  Future<void> _editLocation() async {
    final input = await showDialog<_LocationEditInput>(
      context: context,
      builder: (_) => _EditLocationDialog(location: widget.location),
    );
    if (input == null || !mounted) return;
    try {
      await ref.read(locationsRepositoryProvider).updateLocation(
            locationId: widget.location.id,
            title: input.title,
            description: input.description,
            category: input.category,
          );
      ref.invalidate(viewportLocationsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося оновити локацію.')),
        );
      }
    }
  }

  Future<void> _deleteLocation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити локацію?'),
        content: const Text('Цю дію неможливо скасувати.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(locationsRepositoryProvider)
          .deleteLocation(widget.location.id);
      ref.invalidate(viewportLocationsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося видалити локацію.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(locationDetailsProvider(widget.location.id));
    final location = details.value?.location ?? widget.location;
    final tags = details.value?.tags ?? const <String>[];
    final photos = details.value?.photoUrls ?? const <String>[];
    final comments = ref.watch(commentsProvider(location.id));
    final author = ref.watch(publicProfileProvider(location.userId));
    final position = ref.watch(currentPositionProvider).value;
    final distance = position == null
        ? null
        : Geolocator.distanceBetween(position.latitude, position.longitude,
            location.latitude, location.longitude);
    final heroUrl = photos.isNotEmpty ? photos.first : location.imageUrl;
    final amenities = location.presentedAmenities;

    final mediaQuery = MediaQuery.of(context);
    final detailsScale = mediaQuery.textScaler.scale(1).clamp(1.0, 1.15);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(detailsScale.toDouble()),
      ),
      child: Material(
        color: const Color(0xFF101A16),
        child: CustomScrollView(
          key: const Key('location_details_scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                key: const Key('location_details_hero'),
                height: 120,
                child: Stack(fit: StackFit.expand, children: [
                  if (heroUrl?.trim().isNotEmpty == true)
                    Image.network(heroUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            LocationImage(location: location))
                  else
                    LocationImage(
                        location: location, borderRadius: BorderRadius.zero),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xE6101A16)],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.list(children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _LocationCategoryBadge(category: location.category),
                ),
                const SizedBox(height: 6),
                Text(location.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.08,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                _DetailsFactsRow(location: location, distanceMeters: distance),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: tags
                          .map((tag) => Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(tag)))
                          .toList(growable: false)),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('details_route_action'),
                      onPressed: widget.onBuildRoute,
                      icon: const Icon(Icons.directions),
                      label: const Text('Маршрут'),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFD6A928),
                          foregroundColor: const Color(0xFF142019),
                          minimumSize: const Size.fromHeight(42)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                      tooltip: 'Зробити check-in',
                      onPressed: _checkingIn ? null : _checkIn,
                      icon: const Icon(Icons.how_to_reg_outlined)),
                ]),
                if (location.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 20),
                  const _DetailsHeading('Про локацію'),
                  const SizedBox(height: 6),
                  Text(location.description!.trim(),
                      maxLines: _descriptionExpanded ? null : 3,
                      overflow: _descriptionExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFD6DED9), fontSize: 14, height: 1.4)),
                  TextButton(
                    onPressed: () => setState(
                        () => _descriptionExpanded = !_descriptionExpanded),
                    child:
                        Text(_descriptionExpanded ? 'Згорнути' : 'Докладніше'),
                  ),
                ],
                if (amenities != null) ...[
                  const SizedBox(height: 26),
                  const _DetailsHeading('Зручності'),
                  const SizedBox(height: 12),
                  if (amenities.isEmpty)
                    const Text('Зручності не зазначені',
                        style: TextStyle(color: Color(0xFF9EAAA4)))
                  else
                    _AmenitiesGrid(keys: amenities),
                ],
                if (location.openingHours != null) ...[
                  const SizedBox(height: 26),
                  const _DetailsHeading('Години роботи'),
                  const SizedBox(height: 10),
                  _OpeningHours(schedule: location.openingHours!),
                ],
                if (location.address != null) ...[
                  const SizedBox(height: 26),
                  const _DetailsHeading('Адреса'),
                  const SizedBox(height: 9),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on_outlined,
                        color: Color(0xFFD6A928)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(location.address!,
                            style: const TextStyle(color: Colors.white))),
                  ]),
                ],
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    key: const Key('details_mini_map'),
                    height: 170,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                          target: LatLng(location.latitude, location.longitude),
                          zoom: 15),
                      liteModeEnabled: true,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      myLocationButtonEnabled: false,
                      markers: {
                        Marker(
                            markerId: MarkerId(location.id),
                            position:
                                LatLng(location.latitude, location.longitude)),
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                author.when(
                  data: (profile) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundImage: profile.avatarUrl?.isNotEmpty == true
                          ? NetworkImage(profile.avatarUrl!)
                          : null,
                      child: profile.avatarUrl?.isNotEmpty == true
                          ? null
                          : const Icon(Icons.person),
                    ),
                    title: Text(profile.name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: const Text('Автор локації'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/users/${location.userId}'),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 18),
                comments.when(
                  data: (items) =>
                      _CommentsContent(comments: items, onDelete: _delete),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Text(
                      'Не вдалося завантажити відгуки.',
                      style: TextStyle(color: Color(0xFF9EAAA4))),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  key: const Key('details_review_action'),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => ReviewScreen(location: location))),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text('Написати відгук'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // Kept temporarily to preserve owner/edit behavior while the reference
  // details composition above replaces the old visual layout.
  // ignore: unused_element
  Widget _buildLegacy(BuildContext context) {
    final comments = ref.watch(commentsProvider(widget.location.id));
    final isOnline = ref.watch(isOnlineProvider);
    final author = ref.watch(publicProfileProvider(widget.location.userId));
    final route = ref.watch(routeProvider);
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const Key('location_details_scroll'),
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                key: const Key('location_details_hero'),
                height: constraints.maxWidth < 350 ? 148 : 160,
                width: double.infinity,
                child: LocationImage(location: widget.location),
              ),
              const SizedBox(height: 10),
              _LocationCategoryBadge(category: widget.location.category),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.location.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            height: 1.12,
                          ),
                    ),
                  ),
                  if (widget.location.userId ==
                      Supabase.instance.client.auth.currentUser?.id)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _editLocation();
                        if (value == 'delete') _deleteLocation();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Редагувати')),
                        PopupMenuItem(value: 'delete', child: Text('Видалити')),
                      ],
                    ),
                ],
              ),
              if (widget.location.description?.isNotEmpty ?? false) ...[
                const SizedBox(height: 12),
                Text('Про локацію',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        )),
                const SizedBox(height: 4),
                Text(widget.location.description!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 13, height: 1.35)),
              ],
              const SizedBox(height: 8),
              author.when(
                data: (profile) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -3),
                  leading: CircleAvatar(
                    radius: 17,
                    backgroundImage: profile.avatarUrl?.isNotEmpty == true
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: profile.avatarUrl?.isNotEmpty == true
                        ? null
                        : const Icon(Icons.person),
                  ),
                  title: Text(profile.name),
                  subtitle: const Text('Автор локації'),
                  onTap: () => context.push('/users/${widget.location.userId}'),
                ),
                loading: () => const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(Icons.person)),
                  title: Text('Завантаження автора…'),
                ),
                error: (_, __) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: const Text('Профіль автора'),
                  onTap: () => context.push('/users/${widget.location.userId}'),
                ),
              ),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.onBuildRoute,
                  icon: const Icon(Icons.directions),
                  label: const Text('Побудувати маршрут'),
                ),
              ),
              if (widget.showRouteStatus &&
                  route.status != RouteStatus.idle) ...[
                const SizedBox(height: 12),
                _RouteCard(route: route),
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _checkingIn || !isOnline ? null : _checkIn,
                  icon: _checkingIn
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.how_to_reg),
                  label: const Text('Зробити check-in'),
                ),
              ),
              const SizedBox(height: 18),
              comments.when(
                data: (items) =>
                    _CommentsContent(comments: items, onDelete: _delete),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Row(
                  children: [
                    const Expanded(
                        child: Text('Не вдалося завантажити відгуки.')),
                    IconButton(
                      onPressed: () => ref.invalidate(
                        commentsProvider(widget.location.id),
                      ),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: !isOnline
                      ? null
                      : () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) =>
                                ReviewScreen(location: widget.location),
                          )),
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text(
                    'Написати відгук',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationCategoryBadge extends StatelessWidget {
  const _LocationCategoryBadge({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    final presentation = locationCategoryPresentation(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFD4A017).withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: const Color(0xFFD4A017).withValues(alpha: .35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(presentation.icon, size: 14, color: const Color(0xFFD4A017)),
        const SizedBox(width: 4),
        Text(presentation.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFD4A017),
                  fontWeight: FontWeight.w700,
                )),
      ]),
    );
  }
}

class _DetailsHeading extends StatelessWidget {
  const _DetailsHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800));
}

class _DetailsFactsRow extends StatelessWidget {
  const _DetailsFactsRow({required this.location, this.distanceMeters});
  final LocationModel location;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final facts = <Widget>[];
    if ((location.ratingsCount ?? 0) > 0 && location.rating != null) {
      facts.add(_fact(Icons.star_rounded,
          '${location.rating!.toStringAsFixed(1)} (${location.ratingsCount})'));
    }
    if (distanceMeters != null) {
      facts.add(_fact(Icons.near_me_outlined,
          '${LocationCard.formatDistance(distanceMeters!)} від вас'));
    }
    if (location.isFamilyFriendly != null) {
      facts.add(_fact(Icons.family_restroom,
          location.isFamilyFriendly! ? 'Для родини' : 'Не для дітей'));
    }
    return Wrap(spacing: 15, runSpacing: 8, children: facts);
  }

  Widget _fact(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFD6A928), size: 18),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Color(0xFFD6DED9))),
        ],
      );
}

class _AmenitiesGrid extends StatelessWidget {
  const _AmenitiesGrid({required this.keys});
  final List<String> keys;

  static const values = <String, (IconData, String)>{
    'parking': (Icons.local_parking, 'Паркінг'),
    'wifi': (Icons.wifi, 'Wi-Fi'),
    'toilet': (Icons.wc, 'Туалет'),
    'accessibility': (Icons.accessible, 'Доступність'),
    'pets': (Icons.pets, 'З тваринами'),
    'food': (Icons.restaurant, 'Їжа'),
  };

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: keys.where(values.containsKey).map((key) {
          final value = values[key]!;
          return Container(
            width: 98,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2A23),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF30443B)),
            ),
            child: Column(children: [
              Icon(value.$1, color: const Color(0xFFD6A928)),
              const SizedBox(height: 6),
              Text(value.$2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          );
        }).toList(growable: false),
      );
}

class _OpeningHours extends StatelessWidget {
  const _OpeningHours({required this.schedule});
  final Map<String, dynamic> schedule;

  static const labels = <String, String>{
    'mon': 'Пн',
    'tue': 'Вт',
    'wed': 'Ср',
    'thu': 'Чт',
    'fri': 'Пт',
    'sat': 'Сб',
    'sun': 'Нд',
  };

  @override
  Widget build(BuildContext context) => Column(
        children: labels.entries.map((entry) {
          final intervals = schedule[entry.key] as List? ?? const [];
          final text = intervals.isEmpty
              ? 'Зачинено'
              : intervals.map((value) {
                  final interval = value as Map;
                  return '${interval['open']}–${interval['close']}';
                }).join(', ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                  width: 34,
                  child: Text(entry.value,
                      style: const TextStyle(color: Color(0xFF9EAAA4)))),
              Text(text, style: const TextStyle(color: Colors.white)),
            ]),
          );
        }).toList(growable: false),
      );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined),
            SizedBox(width: 8),
            Text('Офлайн — показано збережені локації'),
          ],
        ),
      ),
    );
  }
}

class _InlineMapError extends StatelessWidget {
  const _InlineMapError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xEE14231D),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.cloud_off_outlined),
          title: const Text('Не вдалося оновити локації'),
          trailing: IconButton(
            tooltip: 'Спробувати ще раз',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
}

class _CommentsContent extends StatelessWidget {
  const _CommentsContent({required this.comments, required this.onDelete});

  final List<CommentModel> comments;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final ratings =
        comments.map((item) => item.rating).whereType<int>().toList();
    final average = ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Відгуки',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            if (average != null) ...[
              Icon(Icons.star, color: Colors.amber.shade700),
              const SizedBox(width: 4),
              Text('${average.toStringAsFixed(1)} (${ratings.length})'),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (comments.isEmpty)
          const Text(
            'Ще немає відгуків. Будьте першим!',
            style: TextStyle(fontSize: 13),
          )
        else
          ...comments.map(
            (comment) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Expanded(child: Text(comment.userName)),
                  if (comment.rating != null) ...[
                    Icon(Icons.star, size: 18, color: Colors.amber.shade700),
                    Text('${comment.rating}'),
                  ],
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(comment.text),
              ),
              trailing: comment.userId == currentUserId
                  ? IconButton(
                      tooltip: 'Видалити коментар',
                      onPressed: () => onDelete(comment.id),
                      icon: const Icon(Icons.delete_outline),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _NewLocationInput {
  const _NewLocationInput({
    required this.title,
    required this.description,
    required this.category,
    this.imageBytes,
    this.imageName,
  });

  final String title;
  final String description;
  final String category;
  final Uint8List? imageBytes;
  final String? imageName;
}

class _LocationEditInput {
  const _LocationEditInput({
    required this.title,
    required this.description,
    required this.category,
  });

  final String title;
  final String description;
  final String category;
}

class _EditLocationDialog extends StatefulWidget {
  const _EditLocationDialog({required this.location});

  final LocationModel location;

  @override
  State<_EditLocationDialog> createState() => _EditLocationDialogState();
}

class _EditLocationDialogState extends State<_EditLocationDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _category;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.location.title);
    _descriptionController =
        TextEditingController(text: widget.location.description);
    _category = widget.location.category;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редагувати локацію'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Назва'),
            ),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Опис'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: const InputDecoration(labelText: 'Категорія'),
              items: editableLocationCategories
                  .map((value) => DropdownMenuItem(
                        value: value.key,
                        child: Text(
                          value.label.replaceAll('\n', ' '),
                          softWrap: true,
                        ),
                      ))
                  .toList(growable: false),
              onChanged: (value) => _category = value ?? 'general',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              _LocationEditInput(
                title: title,
                description: _descriptionController.text.trim(),
                category: _category,
              ),
            );
          },
          child: const Text('Зберегти'),
        ),
      ],
    );
  }
}

class MapFilterCategoryGrid extends StatelessWidget {
  const MapFilterCategoryGrid({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 6.0;
          final columns = constraints.maxWidth < 344 ? 3 : 4;
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final tileExtent = textScale > 1.35 ? 76.0 : 64.0;
          return GridView.builder(
            key: const Key('map_filter_category_grid'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              mainAxisExtent: tileExtent,
            ),
            itemCount: referenceLocationCategories.length,
            itemBuilder: (context, index) {
              final entry = referenceLocationCategories[index];
              final active = selected == entry.key;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(entry.key),
                child: Container(
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFD4A017)
                        : const Color(0xFF14231D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: active ? const Color(0xFFD4A017) : Colors.white10,
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        entry.icon,
                        size: 23,
                        color: active ? Colors.black : entry.referenceColor,
                      ),
                      const SizedBox(height: 3),
                      Flexible(
                        child: Text(
                          entry.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? Colors.black : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
}

class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(mapFilterProvider).applied.category;
    return ColoredBox(
      color: Colors.transparent,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF09120F),
          border: Border.all(color: const Color(0x33294037)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          // Display order only; the canonical registry and filter state are shared.
          children: [
            'all',
            'nature',
            'culture',
            'entertainment',
            'active_outdoors',
            'viewpoints',
            'historic',
            'cafe',
            'events',
            'romance',
            'shopping',
            'kids',
          ].map((key) {
            final entry = locationCategoryDefinition(key);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Tooltip(
                message: entry.label,
                child: Semantics(
                  button: true,
                  selected: selected == entry.key,
                  label: entry.label,
                  child: Material(
                    clipBehavior: Clip.antiAlias,
                    color: selected == entry.key
                        ? entry.referenceColor.withValues(alpha: .25)
                        : const Color(0xFF0B1512),
                    shape: CircleBorder(
                      side: BorderSide(
                        color: selected == entry.key
                            ? entry.referenceColor.withValues(alpha: .7)
                            : const Color(0xFF23332D),
                      ),
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: entry.key == 'all'
                          ? () => showMapCategoriesSheet(context: context)
                          : () => ref
                              .read(mapFilterProvider.notifier)
                              .selectCategory(entry.key),
                      child: SizedBox.square(
                        dimension: 34,
                        child: Center(
                          child: MapCategoryArtwork(
                            category: entry.key,
                            icon: entry.icon,
                            color: entry.referenceColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

final ButtonStyle _mapAppBarActionStyle = IconButton.styleFrom(
  minimumSize: const Size.square(32),
  maximumSize: const Size.square(32),
  iconSize: 18,
  padding: const EdgeInsets.all(6),
  backgroundColor: Colors.transparent,
  side: const BorderSide(color: Colors.white24),
  shape: const CircleBorder(),
);

class _RouteCard extends ConsumerWidget {
  const _RouteCard({required this.route});

  final RouteState route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (route.status) {
          RouteStatus.loading => const Row(
              children: [
                SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Будуємо маршрут…')),
              ],
            ),
          RouteStatus.failure => Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    route.errorMessage ?? 'Не вдалося побудувати маршрут.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Скинути маршрут',
                  onPressed: () => ref.read(routeProvider.notifier).clear(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          RouteStatus.success => Row(
              children: [
                const Icon(Icons.route),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDistance(route.distanceMeters!),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                          'Орієнтовно ${_formatDuration(route.durationSeconds!)}'),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => ref.read(routeProvider.notifier).clear(),
                  icon: const Icon(Icons.close),
                  label: const Text('Скинути'),
                ),
              ],
            ),
          RouteStatus.idle => const SizedBox.shrink(),
        },
      ),
    );
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} м';
    final kilometers = meters / 1000;
    return '${kilometers.toStringAsFixed(kilometers < 10 ? 1 : 0)} км';
  }

  static String _formatDuration(double seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes хв';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes == 0
        ? '$hours год'
        : '$hours год $remainingMinutes хв';
  }
}

class _AddLocationDialog extends StatefulWidget {
  const _AddLocationDialog();

  @override
  State<_AddLocationDialog> createState() => _AddLocationDialogState();
}

class _AddLocationDialogState extends State<_AddLocationDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imagePicker = ImagePicker();

  String? _titleError;
  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageError;
  bool _isPickingImage = false;
  String _category = 'general';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingImage) return;
    setState(() {
      _isPickingImage = true;
      _imageError = null;
    });

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = image.name;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _imageError = 'Не вдалося вибрати фото.');
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Введіть назву місця.');
      return;
    }

    Navigator.of(context).pop(
      _NewLocationInput(
        title: title,
        description: _descriptionController.text.trim(),
        category: _category,
        imageBytes: _imageBytes,
        imageName: _imageName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Нова локація'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Назва',
                errorText: _titleError,
              ),
              onChanged: (_) {
                if (_titleError != null) {
                  setState(() => _titleError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Опис'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: const InputDecoration(labelText: 'Категорія'),
              selectedItemBuilder: (context) => editableLocationCategories
                  .map((value) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value.label.replaceAll('\n', ' '),
                          maxLines: 2,
                          softWrap: true,
                        ),
                      ))
                  .toList(growable: false),
              items: editableLocationCategories
                  .map((value) => DropdownMenuItem(
                        value: value.key,
                        child: Text(
                          value.label.replaceAll('\n', ' '),
                          softWrap: true,
                        ),
                      ))
                  .toList(growable: false),
              onChanged: _isPickingImage
                  ? null
                  : (value) => setState(() => _category = value ?? 'general'),
            ),
            const SizedBox(height: 16),
            if (_imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isPickingImage
                      ? null
                      : () => setState(() {
                            _imageBytes = null;
                            _imageName = null;
                          }),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Видалити фото'),
                ),
              ),
            ],
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isPickingImage
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Галерея'),
                ),
                OutlinedButton.icon(
                  onPressed: _isPickingImage
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Камера'),
                ),
              ],
            ),
            if (_isPickingImage) const LinearProgressIndicator(),
            if (_imageError != null) ...[
              const SizedBox(height: 8),
              Text(
                _imageError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isPickingImage ? null : () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: _isPickingImage ? null : _save,
          child: const Text('Зберегти'),
        ),
      ],
    );
  }
}
