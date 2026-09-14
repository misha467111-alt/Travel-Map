import 'package:geolocator/geolocator.dart' show LocationPermission, Geolocator;

import 'location_permission_state.dart';
import 'location_source.dart';

/// The foreground location readiness flow (task 3): checks location
/// services + permission and returns one clear [LocationReadiness]
/// outcome. Mirrors the exact check/request sequence already
/// established and working in `map_provider.dart`'s `currentPosition`
/// provider (service enabled -> checkPermission -> requestPermission if
/// denied -> handle denied/deniedForever), but factored out behind
/// [LocationSource] so it's unit-testable without real GPS hardware or
/// real OS permission dialogs, and reused by the recording controller
/// instead of duplicating the sequence.
///
/// Never silently opens settings itself (task 3's explicit requirement)
/// — [openAppSettings]/[openLocationSettings] exist so a caller can
/// offer that as a deliberate, user-initiated action.
class LocationPermissionService {
  const LocationPermissionService(this._source);

  final LocationSource _source;

  /// Checks current state without prompting. Use [ensureReady] when you
  /// want the OS permission dialog to actually appear if needed.
  Future<LocationReadiness> checkReadiness() async {
    if (!await _source.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }
    return _fromPermission(await _source.checkPermission());
  }

  /// Checks current state and, if permission has never been asked
  /// (`denied`, not `deniedForever`), triggers the OS prompt once.
  /// Never prompts again if the user already permanently refused, and
  /// never touches location services (there is no "request" for that —
  /// only the user can enable it, via device settings).
  Future<LocationReadiness> ensureReady() async {
    if (!await _source.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }
    var permission = await _source.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _source.requestPermission();
    }
    return _fromPermission(permission);
  }

  LocationReadiness _fromPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.whileInUse ||
      LocationPermission.always =>
        LocationReadiness.granted,
      LocationPermission.deniedForever => LocationReadiness.deniedForever,
      LocationPermission.denied => LocationReadiness.denied,
      // unableToDetermine is web-only per the platform interface's own
      // doc; this app doesn't target web for GPS recording, but treat
      // it as the conservative "not usable" case rather than assume.
      LocationPermission.unableToDetermine => LocationReadiness.denied,
    };
  }

  /// Opens the app's own settings page (for a permanently-denied
  /// permission). A deliberate, caller-initiated action only — never
  /// called automatically by this class.
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the device's location-services settings page (for a
  /// disabled service). A deliberate, caller-initiated action only —
  /// never called automatically by this class.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
