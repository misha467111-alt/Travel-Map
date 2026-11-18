import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gps/local/gps_local_database_provider.dart';
import '../../gps/recording/gps_journey_summary.dart';

/// Phase 3.1 -- what the profile shows about this owner's recorded Journeys.
///
/// [confirmedDistanceMeters] is the sum of the canonical, CONFIRMED-track
/// distance of every completed Journey (`gps_track_quality`), read from the
/// local Drift data only. It is never the server's `total_distance_m`.
class ProfileJourneyStats {
  const ProfileJourneyStats({
    required this.count,
    required this.confirmedDistanceMeters,
  });

  final int count;
  final double confirmedDistanceMeters;
}

/// Loaded once per profile visit (autoDispose, off the build path) by reusing
/// the same per-Journey summary loader the History screen uses; nothing is
/// recomputed in a widget `build`. A Journey whose summary cannot be read is
/// skipped, and a failure to open the local database surfaces as an error
/// state that the profile renders without blocking anything else.
final profileJourneyStatsProvider = FutureProvider.autoDispose
    .family<ProfileJourneyStats, String>((ref, ownerId) async {
  final db = ref.watch(gpsLocalDatabaseProvider);
  final routes = await db.getCompletedRoutes(ownerId);
  final now = DateTime.now().toUtc();
  var meters = 0.0;
  for (final route in routes) {
    try {
      final summary = await loadGpsJourneySummary(
          db: db, ownerId: ownerId, routeId: route.id, now: now);
      final distance = summary?.statistics.totalDistanceMeters;
      if (distance != null && distance.isFinite && distance > 0) {
        meters += distance;
      }
    } catch (_) {
      // One unreadable Journey must not hide the others.
    }
  }
  return ProfileJourneyStats(
      count: routes.length, confirmedDistanceMeters: meters);
});
