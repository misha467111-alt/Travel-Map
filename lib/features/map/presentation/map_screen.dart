import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
import 'create_location_screen.dart';
import 'location_pick_screen.dart';
import 'search_screen.dart';
import '../../gps/presentation/gps_recording_map_screen.dart';

/// Shown after a successful [LocationsRepository.createLocation] call.
/// Deliberately does not claim the location is already public: every new
/// location is inserted with `status = 'draft'` and only becomes visible
/// to map queries once the moderation pipeline (`moderate-content`
/// Edge Function -> `record_location_moderation_result`) approves it --
/// see `create_location_with_xp` / `travel_locations_in_bounds_v2`.
/// `@visibleForTesting` only so a test can assert the UI actually shows
/// this exact text, without needing to drive the private
/// `_AddLocationDialog`/`_addLocation` flow through a full `GoogleMap`
/// widget test harness.
@visibleForTesting
const locationPendingReviewMessage =
    'Локацію створено та відправлено на перевірку';

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
      await _pickLocationThenCreate(
        context,
        ref,
        initialTarget: point,
        initialPicked: point,
      );
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

  /// Phase 2.2B: the only entry point that leads to creating a public
  /// location. [initialTarget] only centers [LocationPickScreen]'s
  /// camera (GPS position, or the long-pressed point as a convenience);
  /// [initialPicked] pre-seeds an already-explicit selection (the exact
  /// long-pressed point) but is never GPS-derived. Either way, the point
  /// actually submitted is whatever the user explicitly confirmed there.
  Future<void> _pickLocationThenCreate(
    BuildContext context,
    WidgetRef ref, {
    required LatLng initialTarget,
    LatLng? initialPicked,
  }) async {
    if (!ref.read(isOnlineProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для цієї дії потрібен інтернет')),
      );
      return;
    }
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        fullscreenDialog: true,
        builder: (_) => LocationPickScreen(
          initialTarget: initialTarget,
          initialPicked: initialPicked,
          userPosition: _lastUserLatitude == null
              ? null
              : LatLng(_lastUserLatitude!, _lastUserLongitude!),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await _addLocation(context, ref, picked);
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
    // CreateLocationScreen owns the actual createLocation() call and the
    // viewportLocationsProvider invalidation itself (so it can show its
    // own submitting/loading state); it only pops with `true` once both
    // have already completed successfully. The pending-review message is
    // shown from here, on the map's own Scaffold, because a SnackBar
    // shown from the screen we just popped would be torn down before it
    // could ever be read.
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => CreateLocationScreen(point: point),
      ),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(locationPendingReviewMessage)),
      );
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
          MapSearchAction(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LocationSearchScreen(),
              ),
            ),
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
                additionalToolbarActions: MapQuickActions(
                  onAdd: () => _pickLocationThenCreate(
                    context,
                    ref,
                    initialTarget: LatLng(
                      currentPosition.latitude,
                      currentPosition.longitude,
                    ),
                  ),
                  onRecordRoute: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => const GpsRecordingMapScreen(),
                    ),
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

/// The Map's Search entry point (Search Phase 2A). Public (not
/// underscore-private) -- same rationale as [MapQuickActions] below: a
/// widget test can prove the button exists and invokes the given
/// [onPressed] exactly once without mounting the full [MapScreen] and
/// its provider graph. `MapScreen`'s own wiring of [onPressed] (pushing
/// [LocationSearchScreen]) is verified by direct code inspection, the
/// same split already established for [MapQuickActions.onRecordRoute].
@visibleForTesting
class MapSearchAction extends StatelessWidget {
  const MapSearchAction({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const Key('map_search_action'),
        tooltip: 'Пошук',
        onPressed: onPressed,
        style: _mapAppBarActionStyle,
        icon: const Icon(Icons.search, color: Color(0xFFD4A017)),
      );
}

/// The Map's [additionalToolbarActions] slot. Public (not
/// underscore-private) -- unlike this file's other private helpers --
/// specifically so a widget test can pump it in isolation without
/// mounting the full [MapScreen] and its provider graph (same rationale
/// as [locationPendingReviewMessage] above and the public
/// `LocationDetailsContent`/`MapLocationPreview` in this same file).
@visibleForTesting
class MapQuickActions extends StatelessWidget {
  const MapQuickActions({
    super.key,
    required this.onAdd,
    required this.onRecordRoute,
  });

  final VoidCallback onAdd;

  /// Phase 4D: opens the dedicated GPS recording mode
  /// ([GpsRecordingMapScreen]) -- the only Map entry point into GPS
  /// recording. Never gated on connectivity: recording works fully
  /// offline.
  final VoidCallback onRecordRoute;

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
          _action(context, 'Записати маршрут', Icons.fiber_manual_record,
              onRecordRoute,
              buttonKey: const Key('gps_record_route_action')),
        ],
      );

  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed, {
    Key? buttonKey,
  }) =>
      MapToolbarButton(
        buttonKey: buttonKey,
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

/// Matches `LocationsRepository.updateLocation`'s exact signature -- see
/// [LocationDetailsContent.updateLocationOverride].
typedef UpdateLocationCall = Future<void> Function({
  required String locationId,
  required String title,
  required String description,
  required String category,
});

/// Matches `LocationsRepository.deleteLocation`'s exact signature -- see
/// [LocationDetailsContent.deleteLocationOverride].
typedef DeleteLocationCall = Future<void> Function(String locationId);

/// Owner Location Management Phase 1: an owner may manage their own
/// location only while the backend itself would actually allow it --
/// `locations_update`/`locations_delete` RLS and `update_own_location`
/// all restrict edit/delete to `owner_id = auth.uid() AND status IN
/// ('draft', 'rejected')` (confirmed by the read-only backend audit this
/// phase followed). This UI gate is UX only, never a substitute for that
/// backend enforcement -- an approved/pending location remains
/// unmodifiable server-side even if this function were bypassed.
///
/// Public and pure so it can be unit-tested directly instead of faking a
/// live Supabase session inside a widget test, matching this codebase's
/// existing precedent for `Supabase.instance.client.auth.currentUser`
/// -coupled logic (see `blockingActiveRecordingIdFor` /
/// `gps_logout_guard_test.dart`).
@visibleForTesting
bool canManageLocationOwnership({
  required String? currentUserId,
  required LocationModel location,
}) {
  if (currentUserId == null || currentUserId != location.userId) return false;
  return location.status == 'draft' || location.status == 'rejected';
}

class LocationDetailsContent extends ConsumerStatefulWidget {
  const LocationDetailsContent({
    required this.location,
    required this.onBuildRoute,
    this.showRouteStatus = false,
    @visibleForTesting this.updateLocationOverride,
    @visibleForTesting this.deleteLocationOverride,
    @visibleForTesting this.currentUserIdOverride,
    super.key,
  });

  final LocationModel location;
  final VoidCallback onBuildRoute;
  final bool showRouteStatus;

  /// Test-only seam: when set, replaces the real
  /// `LocationsRepository.updateLocation` call, matching the
  /// `CreateLocationScreen.createLocationOverride` pattern so a widget
  /// test can control success/failure/timing without constructing a real
  /// `SupabaseClient`. Production code never sets this; see the default
  /// in `_editLocation()`.
  @visibleForTesting
  final UpdateLocationCall? updateLocationOverride;

  /// Test-only seam: replaces the real `LocationsRepository.deleteLocation`
  /// call. Production code never sets this; see the default in
  /// `_confirmDeleteLocation()`.
  @visibleForTesting
  final DeleteLocationCall? deleteLocationOverride;

  /// Test-only seam: when set, replaces
  /// `Supabase.instance.client.auth.currentUser?.id` as the source of the
  /// current user id used by [canManageLocationOwnership]. A real
  /// `SupabaseClient` session cannot be faked in a widget test (see
  /// `gps_logout_guard_test.dart`'s own comment on the same limitation),
  /// so this is the same kind of test-only seam as
  /// [updateLocationOverride]/[deleteLocationOverride] -- the function
  /// itself may still return `null` to simulate a signed-out user.
  /// Production code never sets this.
  @visibleForTesting
  final String? Function()? currentUserIdOverride;

  @override
  ConsumerState<LocationDetailsContent> createState() =>
      _LocationDetailsContentState();
}

class _LocationDetailsContentState
    extends ConsumerState<LocationDetailsContent> {
  bool _checkingIn = false;
  bool _descriptionExpanded = false;
  bool _deletingLocation = false;

  Future<void> _checkIn() async {
    if (_checkingIn || !ref.read(isOnlineProvider)) return;
    setState(() => _checkingIn = true);
    // Generated once per button press (one logical check-in attempt), not
    // once per network call -- there is no automatic retry loop here today,
    // so this single call is the entire attempt. See create_check_in's own
    // p_request_id contract for what reusing vs. regenerating this means.
    final requestId = const Uuid().v4();
    try {
      final position = await Geolocator.getCurrentPosition();
      final result =
          await SupabaseCheckInRepository(Supabase.instance.client).checkIn(
        locationId: widget.location.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        requestId: requestId,
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

  /// Owner Location Management Phase 1. Opens the (adapted, previously
  /// dead) [_EditLocationDialog], which performs the save itself via
  /// [onSave] so a failed save shows an inline error instead of popping
  /// as if it had succeeded. Only reachable when
  /// [canManageLocationOwnership] already gated the entry point that
  /// calls this.
  Future<void> _editLocation(LocationModel location) async {
    if (!ref.read(isOnlineProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для цієї дії потрібен інтернет')),
      );
      return;
    }
    final override = widget.updateLocationOverride;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditLocationDialog(
        location: location,
        onSave: (input) => override != null
            ? override(
                locationId: location.id,
                title: input.title,
                description: input.description,
                category: input.category,
              )
            : ref.read(locationsRepositoryProvider).updateLocation(
                  locationId: location.id,
                  title: input.title,
                  description: input.description,
                  category: input.category,
                ),
      ),
    );
    if (saved == true) {
      // Same invalidation mechanism CreateLocationScreen already uses --
      // no second refresh system.
      ref.invalidate(locationDetailsProvider(location.id));
      ref.invalidate(viewportLocationsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Зміни збережено')),
        );
      }
    }
  }

  /// Owner Location Management Phase 1. Uses the existing
  /// `LocationsRepository.deleteLocation` (Storage cleanup already
  /// happens inside it) -- no second delete path. On success, dismisses
  /// the details screen so a deleted location's details are never left
  /// visible; the map refreshes via the same `viewportLocationsProvider`
  /// invalidation every other write path here already uses.
  Future<void> _confirmDeleteLocation(LocationModel location) async {
    if (!ref.read(isOnlineProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для цієї дії потрібен інтернет')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Видалити локацію?'),
        content: const Text('Цю дію неможливо скасувати.'),
        actions: [
          TextButton(
            key: const Key('location_delete_cancel_button'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            key: const Key('location_delete_confirm_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (confirmed != true || _deletingLocation) return;
    setState(() => _deletingLocation = true);
    try {
      final delete = widget.deleteLocationOverride ??
          ref.read(locationsRepositoryProvider).deleteLocation;
      await delete(location.id);
      ref.invalidate(viewportLocationsProvider);
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) {
        setState(() => _deletingLocation = false);
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
    final currentUserId = widget.currentUserIdOverride != null
        ? widget.currentUserIdOverride!()
        : Supabase.instance.client.auth.currentUser?.id;
    final canManage = canManageLocationOwnership(
      currentUserId: currentUserId,
      location: location,
    );

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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Larger decode target than a list/card thumbnail
                        // -- this box is the full hero width, not a
                        // 78x92 tile -- computed the same way (bounded
                        // by the actual rendered box, scaled for device
                        // pixel ratio, capped at the stored image's own
                        // max size) via the shared helper.
                        final decodeSize = locationImageDecodeSize(
                          constraints: constraints,
                          devicePixelRatio:
                              MediaQuery.devicePixelRatioOf(context),
                        );
                        return Image.network(heroUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: decodeSize.width,
                            cacheHeight: decodeSize.height,
                            errorBuilder: (_, __, ___) =>
                                LocationImage(location: location));
                      },
                    )
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child:
                            _LocationCategoryBadge(category: location.category),
                      ),
                    ),
                    if (canManage)
                      _OwnerActionsRow(
                        deleting: _deletingLocation,
                        onEdit: () => _editLocation(location),
                        onDelete: () => _confirmDeleteLocation(location),
                      ),
                  ],
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

/// Owner Location Management Phase 1: compact Edit/Delete affordance,
/// shown only when [canManageLocationOwnership] already gated it. Icon +
/// tooltip + distinct color for delete, never color alone.
class _OwnerActionsRow extends StatelessWidget {
  const _OwnerActionsRow({
    required this.onEdit,
    required this.onDelete,
    required this.deleting,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('location_details_edit_action'),
            tooltip: 'Редагувати локацію',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, color: Color(0xFFD6A928)),
          ),
          IconButton(
            key: const Key('location_details_delete_action'),
            tooltip: 'Видалити локацію',
            onPressed: deleting ? null : onDelete,
            icon: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
          ),
        ],
      );
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

/// Owner Location Management Phase 1: adapted from the pre-existing
/// (previously unreferenced -- see the completed read-only audit) edit
/// dialog. Now performs the save itself via [onSave] so a failed save
/// shows an inline error and stays open, instead of popping as if it had
/// succeeded.
class _EditLocationDialog extends StatefulWidget {
  const _EditLocationDialog({required this.location, required this.onSave});

  final LocationModel location;
  final Future<void> Function(_LocationEditInput input) onSave;

  @override
  State<_EditLocationDialog> createState() => _EditLocationDialogState();
}

class _EditLocationDialogState extends State<_EditLocationDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _category;
  bool _saving = false;
  String? _error;

  // 'general' is the legacy backend fallback and is deliberately never
  // offered here -- the same canonical exclusion
  // CreateLocationScreen._realCategories applies (Phase 2.2B), so Edit
  // and Create can never disagree about which categories are real.
  static List<LocationCategoryDefinition> get _editableCategories =>
      referenceLocationCategories.where((c) => c.key != 'all').toList();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.location.title);
    _descriptionController =
        TextEditingController(text: widget.location.description);
    final categories = _editableCategories;
    final currentCategory = widget.location.category;
    _category = categories.any((c) => c.key == currentCategory)
        ? currentCategory
        : categories.first.key;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_LocationEditInput(
        title: title,
        description: _descriptionController.text.trim(),
        category: _category,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Не вдалося зберегти зміни.';
        });
      }
    }
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
              key: const Key('location_edit_title_field'),
              controller: _titleController,
              enabled: !_saving,
              maxLength: locationTitleMaxLength,
              decoration: const InputDecoration(labelText: 'Назва'),
            ),
            TextField(
              key: const Key('location_edit_description_field'),
              controller: _descriptionController,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              maxLength: locationDescriptionMaxLength,
              decoration: const InputDecoration(labelText: 'Опис'),
            ),
            DropdownButtonFormField<String>(
              key: const Key('location_edit_category_field'),
              initialValue: _category,
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: const InputDecoration(labelText: 'Категорія'),
              items: _editableCategories
                  .map((value) => DropdownMenuItem(
                        value: value.key,
                        child: Text(
                          value.label.replaceAll('\n', ' '),
                          softWrap: true,
                        ),
                      ))
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (value) => setState(
                      () => _category = value ?? _editableCategories.first.key),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('location_edit_cancel_button'),
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          key: const Key('location_edit_save_button'),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Зберегти'),
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
