import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/location_model.dart';
import 'category_marker_icons.dart';
import 'map_reference_icons.dart';

class ClusteredLocationMap extends StatefulWidget {
  const ClusteredLocationMap({
    required this.initialTarget,
    required this.userPosition,
    required this.locations,
    required this.polylines,
    required this.onLocationTap,
    required this.onLongPress,
    required this.onViewportChanged,
    this.overlays = const <Widget>[],
    this.additionalToolbarActions,
    this.beforeLocationToolbarAction,
    super.key,
  });

  final LatLng initialTarget;
  final LatLng? userPosition;
  final List<LocationModel> locations;
  final Set<Polyline> polylines;
  final ValueChanged<LocationModel> onLocationTap;
  final ValueChanged<LatLng> onLongPress;
  final ValueChanged<LatLngBounds> onViewportChanged;
  final List<Widget> overlays;
  final Widget? additionalToolbarActions;
  final Widget? beforeLocationToolbarAction;

  @override
  State<ClusteredLocationMap> createState() => _ClusteredLocationMapState();
}

class _ClusteredLocationMapState extends State<ClusteredLocationMap> {
  static const _clusterManagerId = ClusterManagerId('locations');
  // A city-scale overview around the actual GPS position, wherever the user is.
  static const _initialOverviewZoom = 10.5;

  GoogleMapController? _controller;
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
    rootBundle
        .loadString('assets/map_styles/travel_light_map.json')
        .then((style) {
      if (mounted) setState(() => _normalMapStyle = style);
    });
    CategoryMarkerIcons.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ClusteredLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userPosition != widget.userPosition) {
      _centerOnInitialGpsIfNeeded();
    }
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Set<Marker> get _markers {
    final markers = widget.locations.map((location) {
      return Marker(
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
      );
    }).toSet();
    final userIcon = CategoryMarkerIcons.userLocation;
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
                fillColor: const Color(0x22EC407A),
                strokeColor: const Color(0x66EC407A),
                strokeWidth: 1,
              ),
          },
          onMapCreated: (controller) {
            _controller = controller;
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
            _idleDebounce?.cancel();
            _idleDebounce =
                Timer(const Duration(milliseconds: 300), _reportViewport);
          },
          onLongPress: widget.onLongPress,
          myLocationEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          compassEnabled: false,
        ),
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
                          : const Color(0xFFD4A017)),
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
                  onPressed:
                      widget.userPosition == null ? null : _centerOnCurrentGps,
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
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Key? buttonKey;
  final bool highlighted;
  final Widget? artwork;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 46,
        child: IconButton(
          key: buttonKey,
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 46),
            maximumSize: const Size(44, 46),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlighted
                  ? const Color(0xFF9A731D)
                  : const Color(0xFF0A120F),
              border: Border.all(color: const Color(0xFF2B362E)),
            ),
            child: Center(
                child: artwork ??
                    Icon(icon,
                        size: 20,
                        color: highlighted
                            ? Colors.white
                            : const Color(0xFFD4A017))),
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
