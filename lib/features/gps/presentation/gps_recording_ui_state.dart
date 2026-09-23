import '../location/location_permission_state.dart';
import '../recording/gps_recording_state.dart';

/// Phase 4B — pure presentation contract for the future recording UI
/// (4C/4D). Deliberately contains no `BuildContext`, widgets, navigation,
/// Supabase, Drift, or Google Maps — only plain immutable Dart values and
/// pure mapping functions over the *existing* engine state
/// ([GpsRecordingState]/[GpsRecordingStatus]).
///
/// This does NOT introduce a second recording state machine.
/// [GpsRecordingStatus] (from `gps_recording_state.dart`) remains the one
/// and only source of truth for "what is the recorder actually doing" —
/// every field below is a deterministic function of it (plus, for the
/// error/readiness case, the existing [LocationReadiness]). A future
/// widget can always fall back to switching on `state.status` directly;
/// this contract exists only to make the common cases (labels, which
/// buttons to show, error classification, cheap stats) trivial and
/// consistent to render without every screen re-deriving the same
/// switch statements.

/// A coarse, presentation-only classification of *why* recording is in
/// an error status — requested explicitly by the Phase 4B task ("at
/// minimum distinguish: permission problem, location service disabled,
/// other recording error"). This is a *view* of existing engine state
/// (`GpsRecordingStatus.permissionError`/`serviceError`/`otherError` +
/// [LocationReadiness]), never a new persisted/mutable state — it does
/// not compete with [GpsRecordingStatus].
enum GpsRecordingErrorKind {
  /// [GpsRecordingStatus.permissionError] — location permission was
  /// denied (or denied forever). Maps to [LocationReadiness.denied] or
  /// [LocationReadiness.deniedForever].
  permissionProblem,

  /// [GpsRecordingStatus.serviceError] — the OS-level location service
  /// itself is off. Maps to [LocationReadiness.serviceDisabled].
  locationServiceDisabled,

  /// [GpsRecordingStatus.otherError] — anything else (e.g. a location
  /// stream failure). See [GpsRecordingState.errorMessage] for the
  /// existing short, debug-safe detail string.
  otherError,
}

/// Cheap, already-available stats a future UI can render *without* any
/// additional Drift query or live distance calculation.
///
/// Deliberately does NOT expose a live distance field: [GpsRecordingState]
/// has no distance field today (distance is only ever computed
/// server-side, once, inside `finalize_recorded_route` — see GPS-1).
/// Computing it client-side during an active recording would require
/// either an expensive full-route Drift query per update or a bespoke
/// (and easily-wrong) incremental distance accumulator that doesn't
/// exist in the engine today. Phase 4B's instructions are explicit that
/// this must be documented as unavailable rather than invented — so it
/// is simply absent from this contract. A future phase may add a real,
/// cheap running-total field to [GpsRecordingState] itself if ever
/// needed; that is an engine change, not a presentation one, and is out
/// of scope here.
class GpsRecordingStatsUiState {
  const GpsRecordingStatsUiState({
    required this.pointCount,
    this.lastLatitude,
    this.lastLongitude,
    this.lastHorizontalAccuracyMeters,
    this.startedAt,
  });

  final int pointCount;
  final double? lastLatitude;
  final double? lastLongitude;

  /// Meters. `null` when the last accepted sample didn't carry a
  /// horizontal-accuracy measurement (see [ValidatedGpsSample]/
  /// `validateGpsSample`'s existing "finite non-zero or absent" rule).
  final double? lastHorizontalAccuracyMeters;

  /// When the *current* session started. A future UI wanting a live
  /// elapsed-time readout must compute `DateTime.now().difference(...)`
  /// itself on a ticker — that is a per-frame presentation concern, not
  /// something a static state snapshot can usefully capture, so it is
  /// intentionally left as a raw timestamp here rather than a
  /// pre-computed (and instantly stale) `Duration`.
  final DateTime? startedAt;
}

/// The full presentation contract for one recording session, derived
/// entirely from a [GpsRecordingState] snapshot.
class GpsRecordingUiState {
  const GpsRecordingUiState({
    required this.status,
    required this.statusLabel,
    required this.stats,
    required this.canPause,
    required this.canResume,
    required this.canFinish,
    required this.canDiscard,
    required this.canAddWaypoint,
    required this.discardRequiresConfirmation,
    required this.isActive,
    required this.isRecoverable,
    this.errorKind,
    this.errorDetail,
  });

  /// The authoritative engine status this whole state was derived from.
  /// Exposed as-is (not duplicated/renamed) so a future widget can
  /// always fall back to switching on it directly for anything this
  /// contract doesn't already cover.
  final GpsRecordingStatus status;

  /// Ukrainian, user-facing headline for the current [status]. No
  /// established equivalent existed for these specific session-status
  /// headlines prior to this phase (the existing debug screen only ever
  /// printed the raw `status.name`) — these are new copy, kept short and
  /// consistent in tone with the app's existing action-button labels
  /// (e.g. "Пауза", "Завершити") and empty-state copy (e.g. Routes tab's
  /// "Активного маршруту немає").
  final String statusLabel;

  final GpsRecordingStatsUiState stats;

  final bool canPause;
  final bool canResume;
  final bool canFinish;
  final bool canDiscard;
  final bool canAddWaypoint;

  /// Whenever [canDiscard] is true, discarding should be confirmed
  /// before acting on it (matches the Phase 4A product recommendation:
  /// discard is destructive-*feeling* even though the engine's
  /// `discard()` never actually deletes local data). Exposed as its own
  /// field rather than left implicit so a future widget doesn't have to
  /// re-derive this rule itself.
  final bool discardRequiresConfirmation;

  /// True for [GpsRecordingStatus.recording]/[GpsRecordingStatus.paused]
  /// — i.e. there is a live session right now (as opposed to idle,
  /// finished, errored, or merely recoverable).
  final bool isActive;

  /// True only for [GpsRecordingStatus.recoverable] — an unfinished
  /// recording was found on this controller's construction and is
  /// waiting for an explicit resume/finish/discard choice. A future
  /// widget uses this to decide whether to show a recovery
  /// prompt/banner; it does NOT implement that prompt here (Phase 4B is
  /// contract-only).
  final bool isRecoverable;

  /// Only set for [GpsRecordingStatus.permissionError]/[serviceError]/
  /// [otherError]; `null` otherwise.
  final GpsRecordingErrorKind? errorKind;

  /// A short, user-facing detail string for the current error, already
  /// safe to display (never raw exception text — matches this
  /// project's established "debug-safe, no content" convention). `null`
  /// when there is no error.
  final String? errorDetail;
}

/// The one place [GpsRecordingErrorKind]/[errorDetail] get derived from
/// [GpsRecordingStatus] + [LocationReadiness]. Reuses the existing,
/// already-shipped Ukrainian [LocationReadiness] labels verbatim (see
/// `gps_recording_debug_screen.dart`'s `_readinessLabel`) rather than
/// inventing new copy for an equivalent that already exists.
String _readinessLabel(LocationReadiness readiness) => switch (readiness) {
      LocationReadiness.serviceDisabled => 'служби геолокації вимкнені',
      LocationReadiness.denied => 'дозвіл відхилено',
      LocationReadiness.deniedForever => 'дозвіл заблоковано назавжди',
      LocationReadiness.granted => 'надано',
    };

({GpsRecordingErrorKind? kind, String? detail}) _mapError(
    GpsRecordingState state) {
  switch (state.status) {
    case GpsRecordingStatus.permissionError:
      return (
        kind: GpsRecordingErrorKind.permissionProblem,
        detail:
            state.readiness != null ? _readinessLabel(state.readiness!) : null,
      );
    case GpsRecordingStatus.serviceError:
      return (
        kind: GpsRecordingErrorKind.locationServiceDisabled,
        detail:
            state.readiness != null ? _readinessLabel(state.readiness!) : null,
      );
    case GpsRecordingStatus.otherError:
      return (
        kind: GpsRecordingErrorKind.otherError,
        detail: state.errorMessage,
      );
    default:
      return (kind: null, detail: null);
  }
}

String _statusLabel(GpsRecordingStatus status) => switch (status) {
      GpsRecordingStatus.idle => 'Готово до запису',
      GpsRecordingStatus.preparing => 'Підготовка…',
      GpsRecordingStatus.recording => 'Запис триває',
      GpsRecordingStatus.paused => 'Пауза',
      GpsRecordingStatus.finishing => 'Завершення запису…',
      GpsRecordingStatus.completed => 'Запис завершено',
      GpsRecordingStatus.recoverable => 'Знайдено незавершений запис',
      GpsRecordingStatus.permissionError => 'Немає дозволу на геолокацію',
      GpsRecordingStatus.serviceError => 'Службу геолокації вимкнено',
      GpsRecordingStatus.otherError => 'Помилка запису',
    };

/// The single mapping entry point: `GpsRecordingState` (engine, already
/// authoritative) -> `GpsRecordingUiState` (presentation, purely
/// derived). Every boolean below is taken directly from
/// `GpsRecordingController`'s own existing guard conditions
/// (`start`/`pause`/`resume`/`finish`/`discard`/`addWaypoint`/
/// `resumeRecoverableRecording`/`finishRecoverableRecording`/
/// `discardRecoverableRecording`) — never guessed.
GpsRecordingUiState mapGpsRecordingUiState(GpsRecordingState state) {
  final status = state.status;
  final isRecording = status == GpsRecordingStatus.recording;
  final isPaused = status == GpsRecordingStatus.paused;
  final isRecoverable = status == GpsRecordingStatus.recoverable;

  // pause(): guarded to status == recording.
  final canPause = isRecording;
  // resume()/resumeRecoverableRecording(): guarded to paused/recoverable
  // respectively -- both are "resume is available" from a UI
  // perspective; the caller picks the concrete controller method from
  // `status`.
  final canResume = isPaused || isRecoverable;
  // finish()/finishRecoverableRecording(): guarded to
  // recording/paused/recoverable.
  final canFinish = isRecording || isPaused || isRecoverable;
  // discard()/discardRecoverableRecording(): same guard set as finish.
  final canDiscard = isRecording || isPaused || isRecoverable;
  // addWaypoint(): guarded to recording/paused only (never recoverable
  // -- there is no live position to attach a waypoint to until the
  // session is actually resumed).
  final canAddWaypoint = isRecording || isPaused;

  final error = _mapError(state);

  return GpsRecordingUiState(
    status: status,
    statusLabel: _statusLabel(status),
    stats: GpsRecordingStatsUiState(
      pointCount: state.pointCount,
      lastLatitude: state.lastAccepted?.latitude,
      lastLongitude: state.lastAccepted?.longitude,
      lastHorizontalAccuracyMeters: state.lastAccepted?.horizontalAccuracy,
      startedAt: state.startedAt,
    ),
    canPause: canPause,
    canResume: canResume,
    canFinish: canFinish,
    canDiscard: canDiscard,
    canAddWaypoint: canAddWaypoint,
    discardRequiresConfirmation: canDiscard,
    isActive: isRecording || isPaused,
    isRecoverable: isRecoverable,
    errorKind: error.kind,
    errorDetail: error.detail,
  );
}
