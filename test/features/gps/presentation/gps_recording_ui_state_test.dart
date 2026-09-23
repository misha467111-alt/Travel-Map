import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/location/location_permission_state.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_recording_ui_state.dart';
import 'package:flutter_application_1/features/gps/recording/gps_recording_state.dart';
import 'package:flutter_application_1/features/gps/recording/gps_sample_validation.dart';

void main() {
  GpsRecordingUiState map(GpsRecordingStatus status,
          {LocationReadiness? readiness, String? errorMessage}) =>
      mapGpsRecordingUiState(GpsRecordingState(
        status: status,
        readiness: readiness,
        errorMessage: errorMessage,
      ));

  test('U01 idle: no active-session controls', () {
    final ui = map(GpsRecordingStatus.idle);
    expect(ui.canPause, isFalse);
    expect(ui.canResume, isFalse);
    expect(ui.canFinish, isFalse);
    expect(ui.canDiscard, isFalse);
    expect(ui.canAddWaypoint, isFalse);
    expect(ui.isActive, isFalse);
    expect(ui.isRecoverable, isFalse);
    expect(ui.errorKind, isNull);
    expect(ui.statusLabel, isNotEmpty);
  });

  test('U02 preparing: no active-session controls yet (not recording/paused)',
      () {
    final ui = map(GpsRecordingStatus.preparing);
    expect(ui.canPause, isFalse);
    expect(ui.canResume, isFalse);
    expect(ui.canFinish, isFalse);
    expect(ui.canDiscard, isFalse);
    expect(ui.canAddWaypoint, isFalse);
    expect(ui.isActive, isFalse);
    expect(ui.isRecoverable, isFalse);
  });

  test('U03 recording: pause/finish/discard available, resume is not', () {
    final ui = map(GpsRecordingStatus.recording);
    expect(ui.canPause, isTrue);
    expect(ui.canFinish, isTrue);
    expect(ui.canDiscard, isTrue);
    expect(ui.canAddWaypoint, isTrue);
    expect(ui.canResume, isFalse);
    expect(ui.discardRequiresConfirmation, isTrue);
    expect(ui.isActive, isTrue);
    expect(ui.isRecoverable, isFalse);
  });

  test('U04 paused: resume/finish/discard available, pause is not', () {
    final ui = map(GpsRecordingStatus.paused);
    expect(ui.canResume, isTrue);
    expect(ui.canFinish, isTrue);
    expect(ui.canDiscard, isTrue);
    expect(ui.canAddWaypoint, isTrue);
    expect(ui.canPause, isFalse);
    expect(ui.discardRequiresConfirmation, isTrue);
    expect(ui.isActive, isTrue);
    expect(ui.isRecoverable, isFalse);
  });

  test('U05 finishing: no duplicate/destructive actions available', () {
    final ui = map(GpsRecordingStatus.finishing);
    expect(ui.canPause, isFalse);
    expect(ui.canResume, isFalse);
    expect(ui.canFinish, isFalse);
    expect(ui.canDiscard, isFalse);
    expect(ui.canAddWaypoint, isFalse);
    expect(ui.isActive, isFalse);
  });

  test('U06 recoverable: recovery actions available, not "active"', () {
    final ui = map(GpsRecordingStatus.recoverable);
    expect(ui.isRecoverable, isTrue);
    expect(ui.canResume, isTrue);
    expect(ui.canFinish, isTrue);
    expect(ui.canDiscard, isTrue);
    expect(ui.discardRequiresConfirmation, isTrue);
    // No live position exists yet for a merely-recoverable session.
    expect(ui.canAddWaypoint, isFalse);
    // Recoverable is a distinct concept from "actively recording right now".
    expect(ui.isActive, isFalse);
  });

  test(
      'U07 permissionError: classified as permissionProblem, detail from readiness',
      () {
    final ui = map(GpsRecordingStatus.permissionError,
        readiness: LocationReadiness.deniedForever);
    expect(ui.errorKind, GpsRecordingErrorKind.permissionProblem);
    expect(ui.errorDetail, contains('назавжди'));
    expect(ui.canPause, isFalse);
    expect(ui.canResume, isFalse);
    expect(ui.canFinish, isFalse);
    expect(ui.canDiscard, isFalse);
    expect(ui.isActive, isFalse);
  });

  test('U08 serviceError: classified as locationServiceDisabled', () {
    final ui = map(GpsRecordingStatus.serviceError,
        readiness: LocationReadiness.serviceDisabled);
    expect(ui.errorKind, GpsRecordingErrorKind.locationServiceDisabled);
    expect(ui.errorDetail, isNotNull);
    expect(ui.isActive, isFalse);
  });

  test('U09 otherError: classified as otherError, detail from errorMessage',
      () {
    final ui = map(GpsRecordingStatus.otherError,
        errorMessage: 'location stream error');
    expect(ui.errorKind, GpsRecordingErrorKind.otherError);
    expect(ui.errorDetail, 'location stream error');
    expect(ui.isActive, isFalse);
  });

  test('completed: session-level terminal status, no active-session controls',
      () {
    final ui = map(GpsRecordingStatus.completed);
    expect(ui.canPause, isFalse);
    expect(ui.canResume, isFalse);
    expect(ui.canFinish, isFalse);
    expect(ui.canDiscard, isFalse);
    expect(ui.isActive, isFalse);
    expect(ui.isRecoverable, isFalse);
    expect(ui.errorKind, isNull);
  });

  test('non-error statuses never carry an errorKind/errorDetail', () {
    for (final status in [
      GpsRecordingStatus.idle,
      GpsRecordingStatus.preparing,
      GpsRecordingStatus.recording,
      GpsRecordingStatus.paused,
      GpsRecordingStatus.finishing,
      GpsRecordingStatus.completed,
      GpsRecordingStatus.recoverable,
    ]) {
      final ui = map(status);
      expect(ui.errorKind, isNull, reason: 'status=$status');
      expect(ui.errorDetail, isNull, reason: 'status=$status');
    }
  });

  test('stats: cheap fields pass through from GpsRecordingState unchanged', () {
    final startedAt = DateTime.utc(2026, 1, 1, 10);
    final sample = ValidatedGpsSample(
      latitude: 50.45,
      longitude: 30.52,
      recordedAt: startedAt,
      horizontalAccuracy: 12.5,
    );
    final ui = mapGpsRecordingUiState(GpsRecordingState(
      status: GpsRecordingStatus.recording,
      pointCount: 42,
      lastAccepted: sample,
      startedAt: startedAt,
    ));
    expect(ui.stats.pointCount, 42);
    expect(ui.stats.lastLatitude, 50.45);
    expect(ui.stats.lastLongitude, 30.52);
    expect(ui.stats.lastHorizontalAccuracyMeters, 12.5);
    expect(ui.stats.startedAt, startedAt);
  });

  test('stats: absent sample -> null coordinate/accuracy fields, zero points',
      () {
    final ui = map(GpsRecordingStatus.idle);
    expect(ui.stats.pointCount, 0);
    expect(ui.stats.lastLatitude, isNull);
    expect(ui.stats.lastLongitude, isNull);
    expect(ui.stats.lastHorizontalAccuracyMeters, isNull);
  });

  test('status is exposed unchanged -- no shadow/competing status value', () {
    for (final status in GpsRecordingStatus.values) {
      expect(map(status).status, status);
    }
  });
}
