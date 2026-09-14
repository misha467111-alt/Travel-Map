import '../location/location_permission_state.dart';
import 'gps_sample_validation.dart';

/// One clean status enum suitable for a future UI to switch on directly
/// (task 16). Kept flat, matching this codebase's established state-
/// model style (e.g. ChatConversationState) rather than a sealed-class
/// hierarchy.
enum GpsRecordingStatus {
  idle,
  preparing,
  recording,
  paused,

  /// Between the finish action being invoked and the local transaction
  /// completing — normally near-instant, exposed as its own status so a
  /// future UI can show a brief "finishing…" affordance rather than
  /// nothing happening.
  finishing,
  completed,

  /// An unfinished (recording/paused) route was found on this
  /// controller's construction (crash/app-restart recovery) and is
  /// waiting for the user to choose resume/finish/discard.
  recoverable,
  permissionError,
  serviceError,
  otherError,
}

class GpsRecordingState {
  const GpsRecordingState({
    required this.status,
    this.routeId,
    this.lastAccepted,
    this.pointCount = 0,
    this.startedAt,
    this.transportMode,
    this.readiness,
    this.errorMessage,
  });

  static const idle = GpsRecordingState(status: GpsRecordingStatus.idle);

  final GpsRecordingStatus status;
  final String? routeId;
  final ValidatedGpsSample? lastAccepted;
  final int pointCount;
  final DateTime? startedAt;
  final String? transportMode;

  /// Set only for [GpsRecordingStatus.permissionError]/[serviceError] —
  /// which specific [LocationReadiness] outcome caused the error, so a
  /// future UI can offer the right recovery action (open app settings
  /// vs. open location settings).
  final LocationReadiness? readiness;

  /// A short, non-sensitive message for [GpsRecordingStatus.otherError]
  /// (e.g. a stream failure) — never raw exception text containing
  /// anything privacy-sensitive, matching this project's established
  /// "debug-safe, no content" logging/error convention.
  final String? errorMessage;

  static const _unset = Object();

  GpsRecordingState copyWith({
    GpsRecordingStatus? status,
    Object? routeId = _unset,
    Object? lastAccepted = _unset,
    int? pointCount,
    Object? startedAt = _unset,
    Object? transportMode = _unset,
    Object? readiness = _unset,
    Object? errorMessage = _unset,
  }) {
    return GpsRecordingState(
      status: status ?? this.status,
      routeId: identical(routeId, _unset) ? this.routeId : routeId as String?,
      lastAccepted: identical(lastAccepted, _unset)
          ? this.lastAccepted
          : lastAccepted as ValidatedGpsSample?,
      pointCount: pointCount ?? this.pointCount,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      transportMode: identical(transportMode, _unset)
          ? this.transportMode
          : transportMode as String?,
      readiness: identical(readiness, _unset)
          ? this.readiness
          : readiness as LocationReadiness?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}
