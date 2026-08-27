import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/location_model.dart';
import 'category_marker_icons.dart';

class ClusteredLocationMap extends StatefulWidget {
  const ClusteredLocationMap({
    required this.initialTarget,
    required this.locations,
    required this.polylines,
    required this.onLocationTap,
    required this.onLongPress,
    required this.onViewportChanged,
    super.key,
  });

  final LatLng initialTarget;
  final List<LocationModel> locations;
  final Set<Polyline> polylines;
  final ValueChanged<LocationModel> onLocationTap;
  final ValueChanged<LatLng> onLongPress;
  final ValueChanged<LatLngBounds> onViewportChanged;

  @override
  State<ClusteredLocationMap> createState() => _ClusteredLocationMapState();
}

class _ClusteredLocationMapState extends State<ClusteredLocationMap> {
  static const _clusterManagerId = ClusterManagerId('locations');

  GoogleMapController? _controller;
  Timer? _idleDebounce;
  MapType _mapType = MapType.normal;
  late final ClusterManager _clusterManager = ClusterManager(
    clusterManagerId: _clusterManagerId,
    onClusterTap: _zoomIntoCluster,
  );

  @override
  void initState() {
    super.initState();
    CategoryMarkerIcons.initialize().then((_) {
      if (mounted) setState(() {});
    });
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
    if (userIcon != null) {
      markers.add(Marker(
        markerId: const MarkerId('current_user_location'),
        position: widget.initialTarget,
        icon: userIcon,
        anchor: const Offset(.5, .5),
        zIndexInt: 1000,
      ));
    }
    return markers;
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
            // Start wide enough to reveal the bounded starter dataset around Kyiv.
            // Subsequent camera-idle events narrow the RPC bbox as the user zooms in.
            zoom: 8.5,
          ),
          mapType: _mapType,
          clusterManagers: {_clusterManager},
          markers: _markers,
          polylines: widget.polylines,
          circles: {
            Circle(
              circleId: const CircleId('user_position'),
              center: widget.initialTarget,
              radius: 90,
              fillColor: const Color(0x22EC407A),
              strokeColor: const Color(0x66EC407A),
              strokeWidth: 1,
            ),
          },
          onMapCreated: (controller) {
            _controller = controller;
            assert(() {
              debugPrint('[GPS_DEBUG] positionAvailable=true '
                  'lat=${widget.initialTarget.latitude} '
                  'lng=${widget.initialTarget.longitude} '
                  'markerCreated=${CategoryMarkerIcons.userLocation != null} '
                  'haloCreated=true');
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
          zoomControlsEnabled: false,
          myLocationButtonEnabled: true,
          compassEnabled: true,
        ),
        Positioned(
          top: 72,
          right: 12,
          child: Material(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            color: _mapType == MapType.hybrid
                ? const Color(0xFFD4A017)
                : const Color(0xFF14231D),
            shape: CircleBorder(
              side: BorderSide(
                color: _mapType == MapType.hybrid
                    ? const Color(0xFFD4A017)
                    : Colors.white24,
              ),
            ),
            child: IconButton(
              tooltip: _mapType == MapType.normal
                  ? 'Звичайна карта'
                  : 'Супутникова + рельєф',
              onPressed: () => setState(() {
                _mapType = _mapType == MapType.normal
                    ? MapType.hybrid
                    : MapType.normal;
              }),
              icon: Icon(
                Icons.terrain_rounded,
                color: _mapType == MapType.hybrid
                    ? Colors.black
                    : const Color(0xFFD4A017),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
