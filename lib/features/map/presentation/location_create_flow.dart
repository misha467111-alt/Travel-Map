import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../providers/network_provider.dart';
import 'create_location_screen.dart';
import 'location_pick_screen.dart';

/// Shown after a successful [LocationsRepository.createLocation] call.
/// Deliberately does not claim the location is already public: every new
/// location is inserted with `status = 'draft'` and only becomes visible
/// to map queries once the moderation pipeline (`moderate-content`
/// Edge Function -> `record_location_moderation_result`) approves it --
/// see `create_location_with_xp` / `travel_locations_in_bounds_v2`.
/// `@visibleForTesting` only so a test can assert the UI actually shows
/// this exact text.
@visibleForTesting
const locationPendingReviewMessage =
    'Локацію створено та відправлено на перевірку';

const _needsInternetMessage = 'Для цієї дії потрібен інтернет';

/// Phase 2.2B: the only flow that leads to creating a public location, shared
/// by every entry point (the map, "Мої місця"). [initialTarget] only centers
/// [LocationPickScreen]'s camera (GPS position, or a long-pressed point as a
/// convenience); [initialPicked] pre-seeds an already-explicit selection (the
/// exact long-pressed point) but is never GPS-derived; [userPosition] only
/// enables the "my location" button there. Either way, the point actually
/// submitted is whatever the user explicitly confirmed on the pick screen.
///
/// Returns `true` only after a location was created (the form popped with
/// `true`); `false` when offline, cancelled, or the context is gone.
Future<bool> pickLocationThenCreate(
  BuildContext context,
  WidgetRef ref, {
  required LatLng initialTarget,
  LatLng? initialPicked,
  LatLng? userPosition,
}) async {
  if (!ref.read(isOnlineProvider)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(_needsInternetMessage)),
    );
    return false;
  }
  final picked = await Navigator.of(context).push<LatLng>(
    MaterialPageRoute<LatLng>(
      fullscreenDialog: true,
      builder: (_) => LocationPickScreen(
        initialTarget: initialTarget,
        initialPicked: initialPicked,
        userPosition: userPosition,
      ),
    ),
  );
  if (picked == null || !context.mounted) return false;
  return addLocationAtPoint(context, ref, picked);
}

/// Opens [CreateLocationScreen] for an already confirmed [point]. Returns
/// `true` after a successful create.
///
/// [CreateLocationScreen] owns the actual `createLocation()` call and the
/// `viewportLocationsProvider` invalidation itself (so it can show its own
/// submitting/loading state); it only pops with `true` once both have already
/// completed successfully. The pending-review message is shown from here, on
/// the caller's own `Scaffold`, because a SnackBar shown from the screen we
/// just popped would be torn down before it could ever be read.
Future<bool> addLocationAtPoint(
  BuildContext context,
  WidgetRef ref,
  LatLng point,
) async {
  if (!ref.read(isOnlineProvider)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(_needsInternetMessage)),
    );
    return false;
  }
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
  return created == true;
}
