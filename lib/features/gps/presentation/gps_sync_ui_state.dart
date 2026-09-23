import '../local/gps_local_database.dart'
    show RecordedRouteStatus, RouteSyncStatus;

/// Phase 4B — pure presentation contract for the future "sync state" and
/// "completed recorded route" UI (4C/4E/4J's "Записані маршрути" list).
/// Deliberately contains no `BuildContext`, widgets, navigation,
/// Supabase, Drift, or Google Maps — only plain immutable Dart values and
/// pure mapping functions.
///
/// [RecordedRouteStatus] and [RouteSyncStatus] (both plain `String`
/// constants, not Dart enums — see `gps_local_database.dart`) remain the
/// only source of truth. This file adds no new persisted/mutable state;
/// it only classifies those existing string values into presentation-
/// ready labels/flags.
///
/// CRITICAL: recording state and sync state are and must remain
/// orthogonal (Phase 3E's own design principle). [GpsSyncUiState] is
/// derived from a sync status alone and never looks at a route's
/// recording status — a route can legitimately be
/// `RecordedRouteStatus.completed` and, independently,
/// `RouteSyncStatus.notSynced`/`syncing`/`synced`/`failed`. See
/// [GpsRecordedRouteUiState] below for how a future widget combines the
/// two *without* collapsing them into one type.

/// A future-proof mapping over [RouteSyncStatus]'s four values. Reuses
/// the exact, already-shipped, already-physically-QA'd Ukrainian labels
/// from `gps_recording_debug_screen.dart`'s `_SyncStatusRow` verbatim
/// (Phase 3F confirmed these render correctly on a real device) rather
/// than inventing new copy — the only exception is `failed`, where this
/// codebase's own established label ("Помилка синхронізації") is kept
/// in preference to the phase-task's merely suggested alternative
/// ("Не вдалося синхронізувати"), per the instruction to prefer an
/// existing established equivalent when one already exists.
class GpsSyncUiState {
  const GpsSyncUiState({
    required this.syncStatus,
    required this.label,
    required this.isSyncing,
    required this.canRetry,
  });

  /// The raw, authoritative [RouteSyncStatus] value this was derived
  /// from — kept for reference/debugging and so a future widget can
  /// always fall back to it directly.
  final String syncStatus;

  final String label;

  /// True only for [RouteSyncStatus.syncing] — a future UI might use
  /// this to show a progress indicator instead of/alongside [label].
  final bool isSyncing;

  /// True for [RouteSyncStatus.notSynced] and [RouteSyncStatus.failed]
  /// — matches the exact rule already established (and physically
  /// proven) in `gps_recording_debug_screen.dart`'s `_SyncStatusRow`:
  /// `syncing` has nothing useful for a user to press, and `synced`
  /// needs no action at all.
  final bool canRetry;
}

GpsSyncUiState mapGpsSyncUiState(String syncStatus) {
  final label = switch (syncStatus) {
    RouteSyncStatus.notSynced => 'Збережено на пристрої',
    RouteSyncStatus.syncing => 'Синхронізація…',
    RouteSyncStatus.synced => 'Синхронізовано',
    RouteSyncStatus.failed => 'Помилка синхронізації',
    _ => syncStatus,
  };
  return GpsSyncUiState(
    syncStatus: syncStatus,
    label: label,
    isSyncing: syncStatus == RouteSyncStatus.syncing,
    canRetry: syncStatus == RouteSyncStatus.notSynced ||
        syncStatus == RouteSyncStatus.failed,
  );
}

/// Ukrainian label for a recorded route's own (recording-side) status —
/// distinct from, and independent of, its [GpsSyncUiState]. No
/// established equivalent existed for these specific labels prior to
/// this phase; kept short and consistent with [GpsRecordingUiState]'s
/// session-status headlines in `gps_recording_ui_state.dart`.
String _recordedRouteStatusLabel(String recordedRouteStatus) =>
    switch (recordedRouteStatus) {
      RecordedRouteStatus.recording => 'Запис триває',
      RecordedRouteStatus.paused => 'Пауза',
      RecordedRouteStatus.completed => 'Завершено',
      RecordedRouteStatus.discarded => 'Скасовано',
      _ => recordedRouteStatus,
    };

/// A ready-made view model for one row of a future "Записані маршрути"
/// list (Phase 4J+) or a `RecordedRouteDetails` screen (Phase 4E+):
/// combines a route's [RecordedRouteStatus] label with its independent
/// [GpsSyncUiState] — two fields, never merged into one enum. This is
/// exactly the shape the Phase 4B orthogonality tests
/// (`completed + notSynced`, `completed + syncing`, `completed +
/// synced`, `completed + failed`) exercise.
class GpsRecordedRouteUiState {
  const GpsRecordedRouteUiState({
    required this.recordedRouteStatus,
    required this.statusLabel,
    required this.sync,
  });

  final String recordedRouteStatus;
  final String statusLabel;
  final GpsSyncUiState sync;
}

GpsRecordedRouteUiState mapGpsRecordedRouteUiState({
  required String recordedRouteStatus,
  required String syncStatus,
}) {
  return GpsRecordedRouteUiState(
    recordedRouteStatus: recordedRouteStatus,
    statusLabel: _recordedRouteStatusLabel(recordedRouteStatus),
    sync: mapGpsSyncUiState(syncStatus),
  );
}
