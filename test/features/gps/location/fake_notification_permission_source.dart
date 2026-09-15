import 'package:flutter_application_1/features/gps/location/notification_permission_source.dart';

/// A fully in-memory [NotificationPermissionSource] for tests — never
/// touches the real `permission_handler` platform channel, which has no
/// mock registered in a plain `flutter test` run (and `defaultTargetPlatform`
/// defaults to `TargetPlatform.android` there, so the real
/// [PermissionHandlerNotificationSource] would otherwise be reached by
/// every existing `start()`/`resume()` test).
class FakeNotificationPermissionSource implements NotificationPermissionSource {
  /// What `request()` resolves to. Defaults to granted — most tests don't
  /// care about this permission's outcome, only that requesting it never
  /// blocks or corrupts a recording either way.
  bool granted = true;

  /// Incremented on every `request()` call — lets a test assert exactly
  /// how many times (if at all) the permission was actually requested.
  int requestCallCount = 0;

  @override
  Future<bool> request() async {
    requestCallCount++;
    return granted;
  }
}
