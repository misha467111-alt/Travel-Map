import 'dart:math' as math;

/// Adventure Transport & Time Discovery Phase 2: the one source of truth
/// for how far a user can plausibly travel in a given amount of time by a
/// given transport mode, used to bound the Adventure ("Пригода") discovery
/// radius. Ported from the proven legacy `_TransportMode`/`_travelRadiusKm`
/// calculation in `_LocationsListScreen` (now dead code, kept temporarily
/// for parity verification) -- the speeds below are unchanged from that
/// implementation.
enum AdventureTransportMode { walk, bike, car }

/// Approximate average speed (km/h) per transport mode, used only to
/// bound a discovery radius -- not turn-by-turn routing.
double adventureTransportSpeedKmH(AdventureTransportMode mode) =>
    switch (mode) {
      AdventureTransportMode.walk => 4.5,
      AdventureTransportMode.bike => 14.0,
      AdventureTransportMode.car => 45.0,
    };

/// The effective Adventure discovery radius: never farther than the
/// user's own chosen radius, and never farther than what's plausibly
/// reachable in [travelMinutes] at [transport]'s speed.
double adventureEffectiveRadiusKm({
  required double userRadiusKm,
  required AdventureTransportMode transport,
  required double travelMinutes,
}) {
  final transportRadiusKm =
      adventureTransportSpeedKmH(transport) * travelMinutes / 60;
  return math.min(userRadiusKm, transportRadiusKm);
}
