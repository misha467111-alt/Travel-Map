import 'package:url_launcher/url_launcher.dart';

/// Location Details External Maps Phase 3A -- matches `url_launcher`'s own
/// `launchUrl` signature closely enough for a test seam: see
/// [openExternalMap].
typedef ExternalMapLauncher = Future<bool> Function(Uri uri);

/// The single cross-platform Google Maps search URL for a coordinate (opens
/// the native app when installed, else a browser -- no `dart:io` platform
/// branching needed).
Uri externalMapUri(double latitude, double longitude) =>
    Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });

/// Whether a coordinate can be shown on a map: both parts present, finite and
/// within the valid ranges (latitude -90..90, longitude -180..180).
bool isValidMapCoordinate(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

/// Hands a coordinate off to an external maps-capable app. Returns whether it
/// was launched; a refusal ([launcher] returns `false`) and any thrown error
/// both yield `false`, never an exception -- the caller only decides how to
/// tell the user. Never mutates any app state.
///
/// A missing or invalid coordinate ([isValidMapCoordinate]) is never handed to
/// the launcher: the result is `false` at once.
///
/// [launcher] is the test seam; production uses `url_launcher.launchUrl` with
/// `LaunchMode.externalApplication`.
Future<bool> openExternalMap(
  double? latitude,
  double? longitude, {
  ExternalMapLauncher? launcher,
}) async {
  if (!isValidMapCoordinate(latitude, longitude)) return false;
  final launch = launcher ??
      (target) => launchUrl(target, mode: LaunchMode.externalApplication);
  try {
    return await launch(externalMapUri(latitude!, longitude!));
  } catch (_) {
    return false;
  }
}
