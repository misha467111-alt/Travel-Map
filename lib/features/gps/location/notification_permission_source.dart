import 'package:permission_handler/permission_handler.dart';

/// Abstraction around the one `permission_handler` permission GPS-4B2.1
/// needs (`Permission.notification`, i.e. Android 13+'s `POST_NOTIFICATIONS`),
/// so production code never calls the static `Permission` API directly —
/// exists purely for testability, exactly mirroring why `LocationSource`
/// exists for `geolocator`. Deliberately not a generic multi-permission
/// framework: this app has exactly one non-location permission to manage,
/// and this interface is kept exactly that narrow.
abstract class NotificationPermissionSource {
  /// Requests the permission if not already decided, or returns the
  /// existing status if it has already been granted or permanently
  /// denied. Never throws; the caller must never block on the result
  /// (see `GpsRecordingController._ensureNotificationPermissionRequested`)
  /// — a location foreground service remains fully standards-compliant
  /// and functional regardless of this permission's outcome.
  Future<bool> request();
}

/// The real, production implementation — a thin pass-through to
/// `permission_handler`'s `Permission.notification`, confirmed to exist
/// in the exact installed version (permission_handler 13.0.2 /
/// permission_handler_android 14.1.0) before writing this class, not
/// assumed. `permission_handler_android`'s own native source was read
/// directly and confirmed to already gate all notification-permission
/// handling behind `Build.VERSION.SDK_INT >= TIRAMISU` (API 33) itself —
/// so this class does not need to duplicate that version check; on
/// pre-33 devices `request()` resolves to granted without ever touching
/// the OS permission system, exactly matching official Android behavior
/// (the permission does not exist there).
class PermissionHandlerNotificationSource
    implements NotificationPermissionSource {
  const PermissionHandlerNotificationSource();

  @override
  Future<bool> request() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }
}
