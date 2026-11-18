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
          // Compact, solid bottom action bar: readable on top of any map,
          // SafeArea-aware, one-line labels that fit 320 dp.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              key: const Key('location_pick_action_bar'),
              color: const Color(0xFA0D1C17),
              elevation: 8,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          key: const Key('location_pick_cancel_button'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const _OneLine('Скасувати'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: FilledButton(
                          key: const Key('location_pick_confirm_button'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            disabledBackgroundColor: Colors.white12,
                            disabledForegroundColor: Colors.white60,
                          ),
                          onPressed: picked == null
                              ? null
                              : () => Navigator.of(context).pop(picked),
                          child: const _OneLine('Підтвердити місце'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single-line button label that shrinks instead of clipping or wrapping.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, softWrap: false),
      );
}
