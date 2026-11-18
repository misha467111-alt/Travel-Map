import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/location_model.dart';
import 'category_marker_icons.dart';
import 'map_reference_icons.dart';
import 'map_route_fit.dart';
import '../../../core/theme/app_design.dart';

class ClusteredLocationMap extends StatefulWidget {
  const ClusteredLocationMap({
    required this.initialTarget,
    required this.userPosition,
    required this.locations,
    required this.polylines,
    required this.onLocationTap,
    required this.onLongPress,
    required this.onViewportChanged,
    this.additionalMarkers = const <Marker>{},
    this.overlays = const <Widget>[],
    this.additionalToolbarActions,
    this.compactToolbar = false,
    this.toolbarBottomInset = 16,
    this.bottomMapPadding = 0,
    this.topMapPadding = 0,
    this.fitRequest,
    this.userLocationIcon,
    this.userLocationColor,
    this.beforeLocationToolbarAction,
    this.onTap,
    this.pickedLocation,
    super.key,
  });

  final LatLng initialTarget;
  final LatLng? userPosition;
  final List<LocationModel> locations;
  final Set<Polyline> polylines;
  final ValueChanged<LocationModel> onLocationTap;
  final ValueChanged<LatLng> onLongPress;
  final ValueChanged<LatLngBounds> onViewportChanged;

  /// Non-POI markers supplied by a hosting map mode (for example live
  /// Journey Moments). They are deliberately not assigned to the location
  /// cluster manager and therefore remain visually/semantically independent
  /// from normal map locations.
  final Set<Marker> additionalMarkers;
  final List<Widget> overlays;
  final Widget? additionalToolbarActions;

  /// Main-map presentation: only layers and current location stay as small
  /// neutral buttons; [additionalToolbarActions] becomes the single primary
  /// action below them and [beforeLocationToolbarAction] is not shown (the
  /// host moves it into its own menu). Off by default, so every other host
  /// (recording, Details, location picking) is unchanged.
  final bool compactToolbar;

  /// Distance of the compact toolbar from the bottom edge (a host that shows
  /// its own bottom strip raises the buttons above it).
  final double toolbarBottomInset;

  /// Official `GoogleMap.padding` at the bottom: keeps the Google logo and
  /// attribution above a host strip (the carousel) instead of beneath it.
  final double bottomMapPadding;

  /// Official `GoogleMap.padding` at the top (a floating header): the map's
  /// visible area, and therefore any camera fit, starts below it.
  final double topMapPadding;

  /// Ask the map to frame a set of points (a route). Each request id runs
  /// once; rebuilds with the same id never move the camera, and manual
  /// gestures are never undone. `null` cancels a pending request.
  final MapFitRequest? fitRequest;

  /// Optional personalization of the user-location marker (bitmap and the
  /// accent of the accuracy halo). `null` keeps the default pink dot, so
  /// every other host is unchanged.
  final BitmapDescriptor? userLocationIcon;
  final Color? userLocationColor;
  final Widget? beforeLocationToolbarAction;

  /// Phase 2.2B (LocationPickMode): a single regular tap on the map.
  /// `null` everywhere else this widget is used (ExploreMode has no use
  /// for a plain-tap callback -- POI taps go through [onLocationTap] and
  /// point selection isn't a concept outside location picking).
  final ValueChanged<LatLng>? onTap;

  /// Phase 2.2B (LocationPickMode): the user's currently, explicitly
  /// selected create-location point, if any. Rendered as a marker
  /// visually distinct from both POI markers and the user's own GPS
  /// marker -- never auto-set from [userPosition].
  final LatLng? pickedLocation;

  @override
  State<ClusteredLocationMap> createState() => _ClusteredLocationMapState();
}

class _ClusteredLocationMapState extends State<ClusteredLocationMap> {
  static const _clusterManagerId = ClusterManagerId('locations');
  // A city-scale overview around the actual GPS position, wherever the user is.
  static const _initialOverviewZoom = 10.5;

  GoogleMapController? _controller;
  final MapFitCoordinator _fit = MapFitCoordinator();
  String? _normalMapStyle;
  Timer? _idleDebounce;
  MapType _mapType = MapType.normal;
  final InitialGpsCameraPolicy _gpsCameraPolicy = InitialGpsCameraPolicy();
  late final ClusterManager _clusterManager = ClusterManager(
    clusterManagerId: _clusterManagerId,
    onClusterTap: _zoomIntoCluster,
  );

  @override
  void initState() {
    super.initState();
    _fit.request(widget.fitRequest);
    rootBundle.loadString(AppMapStyle.assetPath).then((style) {
      if (mounted) setState(() => _normalMapStyle = style);
    });
    CategoryMarkerIcons.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ClusteredLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fitRequest?.id != widget.fitRequest?.id) {
      _fit.request(widget.fitRequest);
    }
    if (oldWidget.userPosition != widget.userPosition) {
      _centerOnInitialGpsIfNeeded();
    }
  }

  @override
  void dispose() {
    _fit.detach();
    _idleDebounce?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // POI markers are rebuilt only when the location list instance changes (or
  // the category bitmaps become ready); a rebuild caused by anything else
  // (user position, camera, toolbar) reuses the very same Marker objects, so
  // the map plugin's diff sees identical markers and skips them.
  List<LocationModel>? _poiSource;
  bool _poiIconsReady = false;
  List<Marker> _poiMarkers = const [];

  List<Marker> _buildPoiMarkers() {
    final ready = CategoryMarkerIcons.isReady;
    if (!identical(_poiSource, widget.locations) || _poiIconsReady != ready) {
      _poiSource = widget.locations;
      _poiIconsReady = ready;
      _poiMarkers = [
        for (final location in widget.locations)
          Marker(
            markerId: MarkerId(location.id),
            clusterManagerId: _clusterManagerId,
            visible: true,
            zIndexInt: 10,
            position: LatLng(location.latitude, location.longitude),
            infoWindow: InfoWindow(
              title: location.title,
              snippet: location.description,
            ),
            icon: CategoryMarkerIcons.forCategory(location.category),
            onTap: () => widget.onLocationTap(location),
          ),
      ];
    }
    return _poiMarkers;
  }

  Set<Marker> get _markers {
    final markers = <Marker>{...widget.additionalMarkers};
    markers.addAll(_buildPoiMarkers());
    final userIcon =
        widget.userLocationIcon ?? CategoryMarkerIcons.userLocation;
    final userPosition = widget.userPosition;
    if (userIcon != null && userPosition != null) {
      markers.add(Marker(
        markerId: const MarkerId('current_user_location'),
        position: userPosition,
        icon: userIcon,
        anchor: const Offset(.5, .5),
        zIndexInt: 1000,
      ));
    }
    final picked = widget.pickedLocation;
    if (picked != null) {
      markers.add(Marker(
        markerId: const MarkerId('picked_location'),
        position: picked,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
        anchor: const Offset(.5, 1),
        zIndexInt: 2000,
      ));
    }
    return markers;
  }

  Future<void> _centerOnInitialGpsIfNeeded() async {
    final controller = _controller;
    final position = widget.userPosition;
    if (controller == null || position == null) return;
    if (!_gpsCameraPolicy.claimInitialRecenter()) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(position, _initialOverviewZoom),
    );
  }

  Future<void> _centerOnCurrentGps() async {
    final controller = _controller;
    final position = widget.userPosition;
    if (controller == null || position == null) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(position, _initialOverviewZoom),
    );
  }

  Future<void> _zoomIntoCluster(Cluster cluster) async {
    final controller = _controller;
    if (controller == null) return;
    final zoom = await controller.getZoomLevel();
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(
        cluster.position,
        (zoom + 2).clamp(0, 20),
      ),
    );
  }

  Future<void> _reportViewport() async {
    final controller = _controller;
    if (controller == null) return;
    final region = await controller.getVisibleRegion();
    assert(() {
      controller.getZoomLevel().then((zoom) => debugPrint(
          '[MAP_DEBUG] zoom=$zoom southwest=${region.southwest.latitude},${region.southwest.longitude} northeast=${region.northeast.latitude},${region.northeast.longitude}'));
      return true;
    }());
    widget.onViewportChanged(region);
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      debugPrint('[MARKER_DEBUG] inputLocations=${widget.locations.length} '
          'googleMapMarkerCount=${_markers.length} controllerReady=${_controller != null}');
      return true;
    }());
    return Stack(
      children: [
        GoogleMap(
          padding: EdgeInsets.only(
              top: widget.topMapPadding, bottom: widget.bottomMapPadding),
          initialCameraPosition: CameraPosition(
            target: widget.initialTarget,
            zoom: _initialOverviewZoom,
          ),
          mapType: _mapType,
          style: _mapType == MapType.normal ? _normalMapStyle : null,
          clusterManagers: {_clusterManager},
          markers: _markers,
          polylines: widget.polylines,
          circles: {
            if (widget.userPosition != null)
              Circle(
                circleId: const CircleId('user_position'),
                center: widget.userPosition!,
                radius: 90,
                fillColor: (widget.userLocationColor ?? const Color(0xFFEC407A))
                    .withValues(alpha: 0.13),
                strokeColor:
                    (widget.userLocationColor ?? const Color(0xFFEC407A))
                        .withValues(alpha: 0.4),
                strokeWidth: 1,
              ),
          },
          onMapCreated: (controller) {
            _controller = controller;
            _fit.attach(_ControllerPort(controller));
            _centerOnInitialGpsIfNeeded();
            assert(() {
              debugPrint('[GPS_DEBUG] positionAvailable=true '
                  'lat=${widget.userPosition?.latitude} '
                  'lng=${widget.userPosition?.longitude} '
                  'markerCreated=${widget.userPosition != null && CategoryMarkerIcons.userLocation != null} '
                  'haloCreated=${widget.userPosition != null}');
              return true;
            }());
            _reportViewport();
          },
          onCameraIdle: () {
            _fit.onCameraIdle();
            _idleDebounce?.cancel();
            _idleDebounce =
                Timer(const Duration(milliseconds: 300), _reportViewport);
          },
          onLongPress: widget.onLongPress,
          onTap: widget.onTap,
          myLocationEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          compassEnabled: false,
        ),
        if (widget.compactToolbar)
          Positioned(
            bottom: widget.toolbarBottomInset,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MapToolbarButton(
                  buttonKey: const Key('map_layers_button'),
                  tooltip: _mapType == MapType.normal
                      ? 'Звичайна карта'
                      : 'Супутникова + рельєф',
                  icon: Icons.layers_outlined,
                  iconColor: AppColors.textPrimary,
                  floating: true,
                  highlighted: _mapType == MapType.hybrid,
                  onPressed: () => setState(() {
                    _mapType = _mapType == MapType.normal
                        ? MapType.hybrid
                        : MapType.normal;
                  }),
                ),
                const SizedBox(height: 8),
                MapToolbarButton(
                  buttonKey: const Key('map_my_location_button'),
                  tooltip: 'Моє місцезнаходження',
                  icon: Icons.my_location,
                  iconColor: AppColors.textPrimary,
                  floating: true,
                  onPressed:
                      widget.userPosition == null ? null : _centerOnCurrentGps,
                ),
                if (widget.additionalToolbarActions != null) ...[
                  const SizedBox(height: 12),
                  widget.additionalToolbarActions!,
                ],
              ],
            ),
          )
        else
          Positioned(
            bottom: 24,
            right: 8,
            child: Material(
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              color: const Color(0xFF17221D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MapToolbarButton(
                    tooltip: _mapType == MapType.normal
                        ? 'Звичайна карта'
                        : 'Супутникова + рельєф',
                    icon: Icons.layers_outlined,
                    artwork: MapReferenceIcon(MapReferenceGlyph.layers,
                        size: 20,
                        color: _mapType == MapType.hybrid
                            ? Colors.white
                            : AppColors.accent),
                    highlighted: _mapType == MapType.hybrid,
                    onPressed: () => setState(() {
                      _mapType = _mapType == MapType.normal
                          ? MapType.hybrid
                          : MapType.normal;
                    }),
                  ),
                  if (widget.beforeLocationToolbarAction != null)
                    widget.beforeLocationToolbarAction!,
                  MapToolbarButton(
                    buttonKey: const Key('map_my_location_button'),
                    tooltip: 'Моє місцезнаходження',
                    icon: Icons.my_location,
                    onPressed: widget.userPosition == null
                        ? null
                        : _centerOnCurrentGps,
                  ),
                  if (widget.additionalToolbarActions != null)
                    widget.additionalToolbarActions!,
                ],
              ),
            ),
          ),
        ...widget.overlays,
      ],
    );
  }
}

class MapToolbarButton extends StatelessWidget {
  const MapToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.buttonKey,
    this.highlighted = false,
    this.artwork,
    this.iconColor = AppColors.accent,
    this.floating = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? buttonKey;
  final bool highlighted;
  final Widget? artwork;

  /// Colour of the plain [icon] (the gold default is the classic look).
  final Color iconColor;

  /// The restrained main-map look: a 40 dp translucent circle, no border;
  /// highlighted uses the accent tint instead of a solid fill.
  final bool floating;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: floating ? 48 : 44,
        height: floating ? 48 : 46,
        child: IconButton(
          key: buttonKey,
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            minimumSize: floating ? const Size(48, 48) : const Size(44, 46),
            maximumSize: floating ? const Size(48, 48) : const Size(44, 46),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: Container(
            width: floating ? 40 : 34,
            height: floating ? 40 : 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: floating
                  ? (highlighted
                      ? AppColors.accent
                      : AppColors.background.withValues(alpha: 0.82))
                  : highlighted
                      ? const Color(0xFF9A731D)
                      : AppColors.background,
              border:
                  floating ? null : Border.all(color: const Color(0xFF2B362E)),
            ),
            child: Center(
                child: artwork ??
                    Icon(icon,
                        size: 20,
                        color: floating
                            ? (highlighted ? AppColors.onAccent : iconColor)
                            : highlighted
                                ? Colors.white
                                : iconColor)),
          ),
        ),
      );
}

/// Owns the one-shot part of GPS camera behavior independently of GPS updates.
class InitialGpsCameraPolicy {
  bool _didRecenter = false;

  bool claimInitialRecenter() {
    if (_didRecenter) return false;
    _didRecenter = true;
    return true;
  }
}

/// Frames a [MapFitPlan] with the real controller: an animated camera move.
/// The route card and the header are excluded from the map area by
/// `GoogleMap.padding`, so [padding] is only the comfort margin.
class _ControllerPort implements MapCameraPort {
  _ControllerPort(this._controller);
  final GoogleMapController _controller;

  @override
  Future<void> fit(MapFitPlan plan, double padding) {
    final update = plan.isPoint
        ? CameraUpdate.newLatLngZoom(plan.center!, plan.zoom!)
        : CameraUpdate.newLatLngBounds(plan.bounds!, padding);
    return _controller.animateCamera(update);
  }
}
