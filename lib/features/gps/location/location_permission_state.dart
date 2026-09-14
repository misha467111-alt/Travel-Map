/// The outcome of a foreground location readiness check, exposed
/// explicitly enough that a future UI can present each case clearly
/// (task 3: "expose states that future UI can present clearly").
enum LocationReadiness {
  /// The OS-level location service is off entirely (e.g. GPS toggled
  /// off in quick settings). No permission prompt can fix this — the
  /// user must enable location services themselves. This library never
  /// opens settings automatically; callers decide whether/when to offer
  /// [LocationPermissionService.openLocationSettings].
  serviceDisabled,

  /// Permission was asked and refused, but may still be asked again
  /// (matches `LocationPermission.denied`).
  denied,

  /// Permission was permanently refused ("don't ask again" / iOS
  /// equivalent) — the OS will not show a prompt again. Only the app's
  /// own system settings page can change this; callers decide whether
  /// to offer [LocationPermissionService.openAppSettings].
  deniedForever,

  /// Foreground location is fully usable right now.
  granted,
}
