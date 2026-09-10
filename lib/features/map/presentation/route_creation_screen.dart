import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/routes_repository.dart';
import '../domain/route.dart';
import '../providers/route_provider.dart';

class RouteCreationScreen extends ConsumerStatefulWidget {
  const RouteCreationScreen({
    required this.firstWaypoint,
    this.initialWaypoints,
    this.initialTransportMode,
    super.key,
  });

  final RoutePoint firstWaypoint;
  final List<RoutePoint>? initialWaypoints;
  final RouteTransportMode? initialTransportMode;

  @override
  ConsumerState<RouteCreationScreen> createState() =>
      _RouteCreationScreenState();
}

class _RouteCreationScreenState extends ConsumerState<RouteCreationScreen> {
  final Map<int, BitmapDescriptor> _markerIcons = {};
  bool _saving = false;

  RoutesRepository get _repository =>
      RoutesRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final waypoints = widget.initialWaypoints ?? [widget.firstWaypoint];
      ref.read(routeProvider.notifier).clear();
      ref.read(routeProvider.notifier).restoreWaypoints(
            waypoints,
            transportMode:
                widget.initialTransportMode ?? RouteTransportMode.driving,
          );
      _ensureMarkerIcons(waypoints.length);
    });
  }

  Future<void> _ensureMarkerIcons(int count) async {
    for (var number = 1; number <= count; number++) {
      _markerIcons[number] ??= await _createNumberedMarker(number);
    }
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _createNumberedMarker(int number) async {
    const size = 108.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = const Color(0xFFD4A017);
    canvas.drawCircle(const Offset(size / 2, size / 2), 44, paint);
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      44,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = const Color(0xFF071713),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color: Color(0xFF071713),
          fontSize: 46,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2),
    );
    final image =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
        width: 36, height: 36);
  }

  Future<void> _addWaypoint(LatLng point) async {
    final notifier = ref.read(routeProvider.notifier);
    final nextCount = ref.read(routeProvider).waypoints.length + 1;
    await _ensureMarkerIcons(nextCount);
    await notifier.addWaypoint(
      RoutePoint(latitude: point.latitude, longitude: point.longitude),
    );
  }

  Future<void> _save() async {
    final route = ref.read(routeProvider);
    if (route.waypoints.length < 2 || _saving) return;
    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(
            text: 'Маршрут ${DateTime.now().day}.${DateTime.now().month}');
        return AlertDialog(
          title: const Text('Зберегти маршрут'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Назва'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Скасувати'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Зберегти'),
            ),
          ],
        );
      },
    );
    if (title == null || title.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      await _repository.save(
        title: title,
        points: route.waypoints,
        transportMode: route.transportMode,
      );
      ref.invalidate(savedRoutesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Маршрут збережено.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося зберегти маршрут.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSavedRoutes() async {
    try {
      final routes = await _repository.fetchOwn();
      if (!mounted) return;
      final selected = await showModalBottomSheet<SavedRoute>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: routes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Збережених маршрутів ще немає.'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: routes
                      .map((route) => ListTile(
                            leading: const Icon(Icons.route),
                            title: Text(route.title),
                            subtitle: Text(
                              '${route.points.length} точки · '
                              '${route.transportMode == RouteTransportMode.walking ? 'Пішки' : 'Авто'}',
                            ),
                            onTap: () => Navigator.pop(context, route),
                          ))
                      .toList(growable: false),
                ),
        ),
      );
      if (selected != null) {
        await _ensureMarkerIcons(selected.points.length);
        ref.read(routeProvider.notifier).restoreWaypoints(
              selected.points,
              transportMode: selected.transportMode,
            );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося відкрити маршрути.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(routeProvider);
    final markers = <Marker>{
      for (var index = 0; index < route.waypoints.length; index++)
        Marker(
          markerId: MarkerId('waypoint_$index'),
          position: LatLng(
            route.waypoints[index].latitude,
            route.waypoints[index].longitude,
          ),
          icon: _markerIcons[index + 1] ?? BitmapDescriptor.defaultMarker,
          draggable: true,
          infoWindow: InfoWindow(title: 'Точка ${index + 1}'),
          onDragEnd: (point) => ref.read(routeProvider.notifier).moveWaypoint(
                index,
                RoutePoint(
                    latitude: point.latitude, longitude: point.longitude),
              ),
        ),
    };
    final polylines = <Polyline>{
      for (var index = 0; index < route.segments.length; index++)
        Polyline(
          polylineId: PolylineId('segment_$index'),
          points: route.segments[index].points
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList(growable: false),
          color: const Color(0xFFD4A017),
          width: 6,
          patterns: route.segments[index].isFallback ||
                  route.transportMode == RouteTransportMode.walking
              ? [PatternItem.dash(24), PatternItem.gap(14)]
              : const [],
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Новий маршрут',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Збережені маршрути',
            onPressed: _showSavedRoutes,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: 'Очисти',
            onPressed: route.waypoints.isEmpty
                ? null
                : () => ref.read(routeProvider.notifier).clear(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.firstWaypoint.latitude,
                  widget.firstWaypoint.longitude),
              zoom: 14,
            ),
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            markers: markers,
            polylines: polylines,
            onLongPress: _addWaypoint,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              color: const Color(0xEE102019),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<RouteTransportMode>(
                      segments: const [
                        ButtonSegment(
                            value: RouteTransportMode.driving,
                            icon: Icon(Icons.directions_car),
                            label: Text('Авто')),
                        ButtonSegment(
                            value: RouteTransportMode.walking,
                            icon: Icon(Icons.directions_walk),
                            label: Text('Пішки')),
                        ButtonSegment(
                            value: RouteTransportMode.cycling,
                            icon: Icon(Icons.directions_bike),
                            label: Text('Вело')),
                      ],
                      selected: {route.transportMode},
                      onSelectionChanged: (selection) => ref
                          .read(routeProvider.notifier)
                          .setTransportMode(selection.single),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      route.waypoints.length < 2
                          ? 'Точка 1 додана. Затисніть і утримуйте карту, щоб додати наступну.'
                          : '${route.waypoints.length} точок · '
                              '${((route.distanceMeters ?? 0) / 1000).toStringAsFixed(1)} км'
                              '${route.usesFallback ? ' · прямий fallback' : ''}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: const Color(0xF5102019),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 62,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: route.waypoints.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            avatar: CircleAvatar(child: Text('${index + 1}')),
                            label: Text('Точка ${index + 1}'),
                            onDeleted: () => ref
                                .read(routeProvider.notifier)
                                .removeWaypoint(index),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Скасувати'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: route.waypoints.length >= 2 && !_saving
                                ? _save
                                : null,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Зберегти'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (route.status == RouteStatus.loading)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    );
  }
}
