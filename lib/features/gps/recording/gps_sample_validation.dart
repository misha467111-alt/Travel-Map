import 'package:geolocator/geolocator.dart' show Position;

/// A validated, plain (non-Geolocator-typed) representation of one
/// accepted GPS sample, ready to hand to
/// `GpsLocalDatabase.appendRoutePoint`. Kept separate from `Position`
/// so the recording controller and its tests never depend on the raw
/// plugin type beyond this one conversion point.
class ValidatedGpsSample {
  const ValidatedGpsSample({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.altitude,
    this.horizontalAccuracy,
    this.verticalAccuracy,
    this.speed,
    this.speedAccuracy,
    this.heading,
    this.headingAccuracy,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final double? altitude;
  final double? horizontalAccuracy;
  final double? verticalAccuracy;
  final double? speed;
  final double? speedAccuracy;
  final double? heading;
  final double? headingAccuracy;
}

/// Deliberately conservative, minimal validation (task 7): rejects only
/// samples that are structurally nonsensical, never legitimate but
/// unusual movement. GPS-1's server-side finalize_recorded_route()
/// already has its own 70 m/s distance-jump safeguard applied at
/// finalize time over the *stored* (and therefore necessarily already
/// locally-valid) points — this function's job is only to keep obviously
/// broken data (NaN/Infinity, out-of-range coordinates) out of local
/// storage in the first place, not to second-guess real movement. No
/// speed-based or distance-based rejection happens here at all.
///
/// Returns `null` (rejected) or a [ValidatedGpsSample] (accepted) —
/// never throws, so a bad sample from a flaky GPS chipset never crashes
/// the recording loop.
ValidatedGpsSample? validateGpsSample(Position position) {
  final lat = position.latitude;
  final lng = position.longitude;

  if (!lat.isFinite || !lng.isFinite) return null;
  if (lat < -90 || lat > 90) return null;
  if (lng < -180 || lng > 180) return null;

  // accuracy/altitude/speed/heading are all optional/nullable inputs
  // downstream -- only pass through a value when the plugin actually
  // reports one (via has*) AND it is finite. A non-finite optional
  // field is simply omitted, not a reason to reject the whole sample:
  // the position itself is still valid data worth keeping.
  double? finiteOrNull(bool has, double value) =>
      (has && value.isFinite) ? value : null;

  return ValidatedGpsSample(
    latitude: lat,
    longitude: lng,
    recordedAt: position.timestamp.toUtc(),
    altitude: finiteOrNull(position.hasAltitude, position.altitude),
    horizontalAccuracy: finiteOrNull(position.hasAccuracy, position.accuracy),
    verticalAccuracy:
        finiteOrNull(position.hasAltitudeAccuracy, position.altitudeAccuracy),
    speed: finiteOrNull(position.hasSpeed, position.speed),
    speedAccuracy:
        finiteOrNull(position.hasSpeedAccuracy, position.speedAccuracy),
    heading: finiteOrNull(position.hasHeading, position.heading),
    headingAccuracy:
        finiteOrNull(position.hasHeadingAccuracy, position.headingAccuracy),
  );
}
