import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'clustered_location_map.dart';

/// Phase 2.2B: the only place a new public location's coordinates are
/// ever chosen. The product rule this exists to enforce: a public
/// location must never silently inherit the user's current GPS
/// coordinate -- GPS (via the existing "Моє місцезнаходження" toolbar
/// button, already wired into [ClusteredLocationMap] through
/// [userPosition]) only recenters the map here. The returned [LatLng] is
/// always either an explicit map tap the user made and then pressed
/// "Підтвердити місце" on, or `null` (cancelled/backed out, no location
/// is created).
class LocationPickScreen extends StatefulWidget {
  const LocationPickScreen({
    required this.initialTarget,
    this.initialPicked,
    this.userPosition,
    super.key,
  });

  /// Where the map camera starts. May come from GPS (to start centered
  /// near the user) or from a long-pressed point -- centering only, never
  /// itself a selection.
  final LatLng initialTarget;

  /// Pre-seeds the selection with an already-explicit point (the exact
  /// spot the user long-pressed to reach this screen). Still just a
  /// starting point: the user can tap elsewhere to change it, and it is
  /// never derived from GPS.
  final LatLng? initialPicked;

  final LatLng? userPosition;

  @override
  State<LocationPickScreen> createState() => _LocationPickScreenState();
}

class _LocationPickScreenState extends State<LocationPickScreen> {
  late LatLng? _picked = widget.initialPicked;

  void _select(LatLng point) => setState(() => _picked = point);

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return Scaffold(
      body: Stack(
        children: [
          ClusteredLocationMap(
            key: const Key('location_pick_map'),
            initialTarget: widget.initialTarget,
            userPosition: widget.userPosition,
            locations: const [],
            polylines: const {},
            onLocationTap: (_) {},
            onLongPress: _select,
            onTap: _select,
            pickedLocation: picked,
            onViewportChanged: (_) {},
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Material(
                    color: const Color(0xE6101915),
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: const Key('location_pick_back_button'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xE6101915),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Text(
                        'Оберіть місце на карті',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('location_pick_cancel_button'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Скасувати'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('location_pick_confirm_button'),
                      onPressed: picked == null
                          ? null
                          : () => Navigator.of(context).pop(picked),
                      child: const Text('Підтвердити місце'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
