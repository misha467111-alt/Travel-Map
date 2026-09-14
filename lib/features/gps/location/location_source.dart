import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:geolocator/geolocator.dart';

/// Abstraction around the parts of `geolocator` GPS-3 needs, so
/// production code depends on this interface rather than the static
/// `Geolocator` class directly. Exists entirely for testability (task
/// 20): a test can inject a fake implementation that never touches real
/// GPS hardware, real OS permission dialogs, or real location services —
/// none of which are available in a `flutter test` run. Keep this
/// interface exactly as thin as what GPS-3 actually calls; do not grow
/// it speculatively.
abstract class LocationSource {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();

  /// A continuous stream of position updates using [settings]. Callers
  /// own subscription lifecycle (cancel to stop receiving updates) —
  /// this method itself does not start or stop anything persistent.
  Stream<Position> getPositionStream({required LocationSettings settings});

  /// Fires when the OS-level location service is toggled on/off (e.g.
  /// the user disables GPS entirely from quick settings mid-recording).
  Stream<ServiceStatus> getServiceStatusStream();
}

/// The real, production implementation — a thin pass-through to the
/// static `Geolocator` API confirmed to exist in the exact installed
/// version (geolocator 10.1.1 / geolocator_platform_interface 4.3.0)
/// before writing this class, not assumed.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Stream<Position> getPositionStream({required LocationSettings settings}) =>
      Geolocator.getPositionStream(locationSettings: settings);

  @override
  Stream<ServiceStatus> getServiceStatusStream() =>
      Geolocator.getServiceStatusStream();
}

/// GPS-3's centralized, foreground-only sampling configuration —
/// exactly the fields confirmed to exist on AndroidSettings/AppleSettings
/// in the installed geolocator version, nothing invented.
///
/// Kept as one place so a later phase can tune per transport mode
/// without hunting through the recording controller for scattered
/// magic numbers.
///
/// Deliberately foreground-only, explicitly documented at each point
/// that could silently turn this into a background configuration:
///   - Android: `foregroundNotificationConfig` is left null. Setting it
///     is what turns this into a foreground *service* with a
///     persistent notification (GPS-4 territory) — omitting it keeps
///     sampling tied to the normal activity lifecycle only.
///   - iOS: `allowBackgroundLocationUpdates` is explicitly set to
///     `false` (its own default in AppleSettings is actually `true` —
///     confirmed by reading the geolocator_apple source, not assumed —
///     so leaving it unset here would have been a real foreground-only
///     violation). `Info.plist` also has no `UIBackgroundModes` entry,
///     so this would likely no-op at the OS level regardless, but this
///     phase does not rely on that as its safety net.
class GpsSamplingSettings {
  const GpsSamplingSettings._();

  static const LocationAccuracy accuracy = LocationAccuracy.best;

  /// Matches the "small distance filter, ~3-5 m" MVP direction from the
  /// design review — fine enough detail for a future route replay
  /// without a sample on every meter of a stationary GPS-noise jitter.
  static const int distanceFilterMeters = 4;

  static const Duration intervalDuration = Duration(seconds: 3);

  /// Picks the platform-specific settings subclass geolocator expects —
  /// matches the pattern geolocator's own documentation/examples use
  /// (construct AndroidSettings vs AppleSettings by platform, since only
  /// the matching subclass's extra fields are actually read by each
  /// platform's plugin implementation).
  static LocationSettings forCurrentPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilterMeters,
          allowBackgroundLocationUpdates: false,
          showBackgroundLocationIndicator: false,
          pauseLocationUpdatesAutomatically: false,
        );
      case TargetPlatform.android:
      default:
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilterMeters,
          intervalDuration: intervalDuration,
          // Explicitly omitted: foregroundNotificationConfig. Setting
          // this is what starts an Android foreground service — GPS-4,
          // not now.
        );
    }
  }
}
