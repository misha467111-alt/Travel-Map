import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gps/local/gps_local_database.dart' show LocalRecordedRoute;
import '../../gps/local/gps_local_database_provider.dart';
import '../../gps/presentation/gps_journey_history_view.dart'
    show gpsJourneyHistoryProvider;
import 'profile_journey_data_provider.dart';

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

/// The totals of this owner's finished Journeys.
///
/// Loaded off the build path, and RE-computed whenever the SET of finished
/// Journeys changes (a new Journey was finished, one was removed): it watches
/// [gpsJourneyHistoryProvider] through the list of ids, so a token like a sync
/// status change does not trigger it. Every Journey's numbers come from the
/// shared per-Journey [profileJourneyDataProvider] -- the same canonical
/// statistics the Summary uses, read once and cached, so only a NEW Journey is
/// read again. A Journey whose data cannot be read is skipped for the distance
/// (it is still counted), and a failure to open the local database surfaces as
/// an error state that the profile renders without blocking anything else.
final profileJourneyStatsProvider = FutureProvider.autoDispose
    .family<ProfileJourneyStats, String>((ref, ownerId) async {
  ref.watch(gpsJourneyHistoryProvider(ownerId).select((history) => [
        for (final r in history.value ?? const <LocalRecordedRoute>[]) r.id
      ].join('|')));
  final db = ref.watch(gpsLocalDatabaseProvider);
  final routes = await db.getCompletedRoutes(ownerId);
  var meters = 0.0;
  for (final route in routes) {
    try {
      final data = await ref.watch(
          profileJourneyDataProvider((ownerId: ownerId, routeId: route.id))
              .future);
      final distance = data?.statistics.totalDistanceMeters;
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
