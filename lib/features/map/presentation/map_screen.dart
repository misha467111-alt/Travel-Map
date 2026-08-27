import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
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
import '../domain/comment_model.dart';
import '../domain/route.dart';
import '../providers/comments_provider.dart';
import '../providers/locations_provider.dart';
import '../providers/map_provider.dart';
import '../providers/map_filter_provider.dart';
import '../providers/network_provider.dart';
import '../providers/route_provider.dart';
import 'clustered_location_map.dart';
import 'route_details_screen.dart';
import 'review_screen.dart';
import '../../navigation/presentation/scalable_locations_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapViewportBounds? _viewport;
  List<LocationModel> _lastLocations = const [];

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
    var selected = ref.read(mapFilterProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                      child: Text('Фільтри',
                          style: Theme.of(context).textTheme.headlineSmall)),
                  IconButton(
                    tooltip: 'Закрити',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ]),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Категорії',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount:
                      MediaQuery.sizeOf(context).width < 350 ? 3 : 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: .95,
                  children: _CategoryFilterBar._labels.entries.map((entry) {
                    final active = selected == entry.key;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setSheetState(() => selected = entry.key),
                      child: Container(
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFFD4A017)
                              : const Color(0xFF14231D),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: active
                                  ? const Color(0xFFD4A017)
                                  : Colors.white10),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_CategoryFilterBar._icons[entry.key],
                                  color: active ? Colors.black : Colors.white),
                              const SizedBox(height: 6),
                              Text(entry.value,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color:
                                          active ? Colors.black : Colors.white,
                                      fontSize: 11)),
                            ]),
                      ),
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      ref.read(mapFilterProvider.notifier).select(selected);
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Показати локації'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
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
            content: Text('Не вдалося зберегти локацію: $error'),
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
      builder: (sheetContext) => LocationDetailsContent(
        location: location,
        onBuildRoute: () {
          Navigator.of(sheetContext).pop();
          _buildRoute(context, ref, location);
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
          SnackBar(content: Text('Не вдалося отримати геопозицію: $error')),
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
        title: const Text('Travel Map'),
        actions: [
          const _NotificationsButton(),
          IconButton(
            tooltip: 'Пошук',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const ScalableLocationsScreen(
                mode: ScalableLocationListMode.discover,
              ),
            )),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Фільтри',
            onPressed: () => _showMapFilters(context, ref),
            icon: const Icon(Icons.tune),
          ),
          /*
          IconButton(
            tooltip: 'Друзі',
            onPressed: () => ref.invalidate(viewportLocationsProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Профіль',
            onPressed: () => ref.invalidate(viewportLocationsProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Оновити локації',
            onPressed: () => ref.invalidate(viewportLocationsProvider),
            icon: const Icon(Icons.refresh),
          ),
          */
        ],
      ),
      body: position.when(
        data: (currentPosition) {
          final bounds = _viewport ??
              MapViewportBounds(
                minLatitude: currentPosition.latitude - 0.1,
                minLongitude: currentPosition.longitude - 0.1,
                maxLatitude: currentPosition.latitude + 0.1,
                maxLongitude: currentPosition.longitude + 0.1,
              );
          final category = ref.watch(mapFilterProvider);
          final query = MapViewportQuery(
            bounds: bounds,
            category: category == 'all' ? null : category,
          );
          final locations = ref.watch(viewportLocationsProvider(query));
          return locations.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            skipError: true,
            data: (items) {
              _lastLocations = items;
              assert(() {
                debugPrint(
                    '[MAP_DEBUG] rows=${items.length} mapped=${items.length} '
                    'bbox=${bounds.minLatitude},${bounds.minLongitude},'
                    '${bounds.maxLatitude},${bounds.maxLongitude} '
                    'category=${query.category ?? "NULL"} markers=${items.length}');
                return true;
              }());
              return Stack(
                children: [
                  ClusteredLocationMap(
                    initialTarget: LatLng(
                      currentPosition.latitude,
                      currentPosition.longitude,
                    ),
                    locations: items,
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
                    onLongPress: (point) => _addLocation(context, ref, point),
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
                  ),
                  if (route.status != RouteStatus.idle)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: _RouteCard(route: route),
                    ),
                  const Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: _CategoryFilterBar(),
                  ),
                  Positioned(
                    top: 142,
                    right: 10,
                    child: _MapQuickActions(
                      onAdd: () => _addLocation(
                          context,
                          ref,
                          LatLng(currentPosition.latitude,
                              currentPosition.longitude)),
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
            loading: () => _lastLocations.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      ClusteredLocationMap(
                        initialTarget: LatLng(currentPosition.latitude,
                            currentPosition.longitude),
                        locations: _lastLocations,
                        polylines: route.hasRoute
                            ? {
                                Polyline(
                                  polylineId: const PolylineId('active_route'),
                                  points: route.points
                                      .map((p) =>
                                          LatLng(p.latitude, p.longitude))
                                      .toList(growable: false),
                                ),
                              }
                            : const <Polyline>{},
                        onLocationTap: (location) =>
                            _showLocationDetails(context, ref, location),
                        onLongPress: (point) =>
                            _addLocation(context, ref, point),
                        onViewportChanged: (_) {},
                      ),
                      const Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: _CategoryFilterBar(),
                      ),
                    ],
                  ),
            error: (error, stackTrace) => _ErrorView(
              message: 'Не вдалося завантажити локації: $error',
              onRetry: () => ref.invalidate(viewportLocationsProvider(query)),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorView(
          message: 'Помилка геолокації: $error',
          onRetry: () => ref.invalidate(currentPositionProvider),
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
              'Випадкова локація',
              Icons.casino_outlined,
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ScalableLocationsScreen(
                      mode: ScalableLocationListMode.adventure)))),
          _action(
              context,
              'Куди сьогодні?',
              Icons.explore_outlined,
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ScalableLocationsScreen(
                      mode: ScalableLocationListMode.adventure)))),
          _action(
              context,
              'Поруч',
              Icons.radar,
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const ScalableLocationsScreen(
                      mode: ScalableLocationListMode.nearby)))),
          _action(
              context, 'Додати місце', Icons.add_location_alt_outlined, onAdd),
        ],
      );

  Widget _action(BuildContext context, String label, IconData icon,
          VoidCallback onPressed) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Tooltip(
          message: label,
          child: Material(
            color: const Color(0xFF142416),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(icon, color: Colors.amber),
              tooltip: label,
            ),
          ),
        ),
      );
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
          SnackBar(content: Text('Не вдалося побудувати маршрут: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(location.title)),
        body: LocationDetailsContent(
          location: location,
          onBuildRoute: () => _buildRoute(context, ref),
          showRouteStatus: true,
        ),
      );
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
  final _controller = TextEditingController();
  int? _rating;
  bool _submitting = false;
  bool _checkingIn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!ref.read(isOnlineProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для цієї дії потрібен інтернет')),
      );
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref.read(commentsControllerProvider).addComment(
            locationId: widget.location.id,
            text: text,
            rating: _rating,
          );
      if (!mounted) return;
      _controller.clear();
      setState(() => _rating = null);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не вдалося додати коментар: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

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
          SnackBar(content: Text('Не вдалося зробити check-in: $error')),
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
          SnackBar(content: Text('Не вдалося видалити коментар: $error')),
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
          SnackBar(content: Text('Не вдалося оновити локацію: $error')),
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
          SnackBar(content: Text('Не вдалося видалити локацію: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(commentsProvider(widget.location.id));
    final isOnline = ref.watch(isOnlineProvider);
    final author = ref.watch(publicProfileProvider(widget.location.userId));
    final savedLocations = ref.watch(savedPublicLocationsProvider);
    final route = ref.watch(routeProvider);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.location.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: widget.location.imageUrl!,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox(
                      height: 220,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.location.title,
                      style: Theme.of(context).textTheme.headlineSmall,
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
                const SizedBox(height: 8),
                Text(widget.location.description!),
              ],
              const SizedBox(height: 12),
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
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: savedLocations.hasValue
                      ? () => ref
                          .read(savedPublicLocationsProvider.notifier)
                          .toggle(widget.location.id)
                      : null,
                  icon: Icon(
                    (savedLocations.value ?? const <String>{})
                            .contains(widget.location.id)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  ),
                  label: Text(
                    (savedLocations.value ?? const <String>{})
                            .contains(widget.location.id)
                        ? 'Прибрати зі збережених'
                        : 'Зберегти локацію',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
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
              const SizedBox(height: 28),
              comments.when(
                data: (items) =>
                    _CommentsContent(comments: items, onDelete: _delete),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Row(
                  children: [
                    Expanded(
                        child: Text('Не вдалося завантажити відгуки: $error')),
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
                  label: const Text('Написати відгук'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                minLines: 2,
                maxLines: 4,
                maxLength: 2000,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Ваш коментар',
                  border: OutlineInputBorder(),
                ),
              ),
              Row(
                children: [
                  const Text('Оцінка: '),
                  ...List.generate(5, (index) {
                    final value = index + 1;
                    return IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '$value з 5',
                      onPressed: _submitting
                          ? null
                          : () => setState(
                                () => _rating = _rating == value ? null : value,
                              ),
                      icon: Icon(
                        value <= (_rating ?? 0)
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber.shade700,
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting || !isOnline ? null : _submit,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Опублікувати відгук'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            Text('Відгуки', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            if (average != null) ...[
              Icon(Icons.star, color: Colors.amber.shade700),
              const SizedBox(width: 4),
              Text('${average.toStringAsFixed(1)} (${ratings.length})'),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (comments.isEmpty)
          const Text('Ще немає відгуків. Будьте першим!')
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
              decoration: const InputDecoration(labelText: 'Категорія'),
              items: const [
                DropdownMenuItem(value: 'general', child: Text('Загальне')),
                DropdownMenuItem(value: 'cafe', child: Text('Кафе')),
                DropdownMenuItem(value: 'nature', child: Text('Природа')),
                DropdownMenuItem(value: 'culture', child: Text('Культура')),
                DropdownMenuItem(
                  value: 'entertainment',
                  child: Text('Розваги'),
                ),
              ],
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

class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar();

  static const _labels = <String, String>{
    'all': 'Усі',
    'cafe': 'Кафе',
    'nature': 'Природа',
    'culture': 'Культура',
    'entertainment': 'Розваги',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(mapFilterProvider);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _labels.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Icon(_icons[entry.key], size: 18),
              tooltip: entry.value,
              selected: selected == entry.key,
              onSelected: (_) =>
                  ref.read(mapFilterProvider.notifier).select(entry.key),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  static const _icons = <String, IconData>{
    'all': Icons.auto_awesome,
    'cafe': Icons.local_cafe,
    'nature': Icons.park,
    'culture': Icons.museum,
    'entertainment': Icons.theater_comedy,
  };
}

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
        setState(() => _imageError = 'Не вдалося вибрати фото: $error');
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
              decoration: const InputDecoration(labelText: 'Категорія'),
              items: const [
                DropdownMenuItem(value: 'general', child: Text('Загальне')),
                DropdownMenuItem(value: 'cafe', child: Text('Кафе')),
                DropdownMenuItem(value: 'nature', child: Text('Природа')),
                DropdownMenuItem(value: 'culture', child: Text('Культура')),
                DropdownMenuItem(
                  value: 'entertainment',
                  child: Text('Розваги'),
                ),
              ],
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Спробувати ще раз'),
            ),
          ],
        ),
      ),
    );
  }
}
