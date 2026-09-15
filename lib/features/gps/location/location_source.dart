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

/// GPS's centralized sampling configuration — exactly the fields
/// confirmed to exist on AndroidSettings/AppleSettings/
/// ForegroundNotificationConfig in the installed geolocator version,
/// nothing invented.
///
/// Kept as one place so a later phase can tune per transport mode
/// without hunting through the recording controller for scattered
/// magic numbers.
///
/// Platform background behavior (GPS-4B2, Android only):
///   - Android: [_androidRecordingNotification] is always attached.
///     Setting `AndroidSettings.foregroundNotificationConfig` is what
///     starts the position stream as an Android foreground service
///     (confirmed by reading geolocator_android 4.6.2's own native
///     source: a non-null config makes `StreamHandlerImpl.onListen`
///     call `GeolocatorLocationService.enableBackgroundMode`, which
///     calls the real `startForeground()` — not just a priority hint).
///     `forCurrentPlatform()` is only ever called by
///     `GpsRecordingController` for an actual, explicitly-started
///     recording session (see its class doc), so there is no other
///     caller that would need a non-backgrounded variant — this is
///     deliberately unconditional, not a parameter, per the "one
///     recording engine" rule (GPS-4A/GPS-4B1): foreground and
///     background are two OS-level execution states of the exact same
///     subscription, not two configurations an app-level caller picks
///     between.
///   - iOS: unchanged from GPS-3/GPS-4B1 and **must stay that way**
///     until GPS-4B4 — `allowBackgroundLocationUpdates` is explicitly
///     `false` (its own default in AppleSettings is actually `true` —
///     confirmed by reading the geolocator_apple source, not assumed —
///     so leaving it unset here would have been a real foreground-only
///     violation). `Info.plist` still has no `UIBackgroundModes` entry
///     (GPS-4B2 does not touch it), so this would likely no-op at the
///     OS level regardless, but this phase does not rely on that as
///     its safety net.
class GpsSamplingSettings {
  const GpsSamplingSettings._();

  static const LocationAccuracy accuracy = LocationAccuracy.best;

  /// Matches the "small distance filter, ~3-5 m" MVP direction from the
  /// design review — fine enough detail for a future route replay
  /// without a sample on every meter of a stationary GPS-noise jitter.
  static const int distanceFilterMeters = 4;

  static const Duration intervalDuration = Duration(seconds: 3);

  /// The persistent notification shown for the entire duration of an
  /// active recording — required by Android for a location-type
  /// foreground service, and by GPS-4B2's own privacy requirement that
  /// background location is always honestly, visibly disclosed while
  /// it runs (never hidden). `notificationIcon` is left at its default
  /// (`@mipmap/ic_launcher`), which already exists as this app's launcher
  /// icon, so no new drawable resource is required.
  ///
  /// `enableWakeLock: true` is a deliberate choice, not the plugin's
  /// default (`false`): `ForegroundNotificationConfig.enableWakeLock`'s
  /// own doc states that without it "the system can still sleep and all
  /// location events will be received at once when the system wakes up
  /// again" — i.e. omitting it risks exactly the batched/delayed
  /// delivery GPS-4B2's product requirement ("route continues
  /// recording... points continue being written to Drift" while the
  /// screen is locked) explicitly rules out. `enableWifiLock` is left at
  /// its default `false` — GPS sampling has no need to keep Wi-Fi radio
  /// awake, and the task explicitly calls out not enabling unnecessary
  /// Wi-Fi locks.
  static const ForegroundNotificationConfig _androidRecordingNotification =
      ForegroundNotificationConfig(
    notificationTitle: 'Travel Map',
    notificationText: 'Записується ваш маршрут',
    notificationChannelName: 'Запис маршруту',
    setOngoing: true,
    enableWakeLock: true,
  );

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
          foregroundNotificationConfig: _androidRecordingNotification,
        );
    }
  }
}
