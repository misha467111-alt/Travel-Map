import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/presentation/gps_sync_ui_state.dart';

void main() {
  group('mapGpsSyncUiState', () {
    test('U10 notSynced: locally safe, retry available, not syncing', () {
      final ui = mapGpsSyncUiState(RouteSyncStatus.notSynced);
      expect(ui.syncStatus, RouteSyncStatus.notSynced);
      expect(ui.label, isNotEmpty);
      expect(ui.isSyncing, isFalse);
      expect(ui.canRetry, isTrue);
    });

    test('U11 syncing: in progress, retry not offered', () {
      final ui = mapGpsSyncUiState(RouteSyncStatus.syncing);
      expect(ui.isSyncing, isTrue);
      expect(ui.canRetry, isFalse);
    });

    test('U12 synced: complete, no retry needed', () {
      final ui = mapGpsSyncUiState(RouteSyncStatus.synced);
      expect(ui.isSyncing, isFalse);
      expect(ui.canRetry, isFalse);
    });

    test('U13 failed: retry explicitly offered', () {
      final ui = mapGpsSyncUiState(RouteSyncStatus.failed);
      expect(ui.isSyncing, isFalse);
      expect(ui.canRetry, isTrue);
    });

    test('labels are distinct for every known status', () {
      final labels = {
        RouteSyncStatus.notSynced,
        RouteSyncStatus.syncing,
        RouteSyncStatus.synced,
        RouteSyncStatus.failed,
      }.map((s) => mapGpsSyncUiState(s).label).toSet();
      expect(labels, hasLength(4));
    });
  });

  group('orthogonality: recording status never influences sync mapping', () {
    test('U14 completed + notSynced', () {
      final ui = mapGpsRecordedRouteUiState(
        recordedRouteStatus: RecordedRouteStatus.completed,
        syncStatus: RouteSyncStatus.notSynced,
      );
      expect(ui.recordedRouteStatus, RecordedRouteStatus.completed);
      expect(ui.sync.syncStatus, RouteSyncStatus.notSynced);
      expect(ui.sync.canRetry, isTrue);
      expect(ui.sync.isSyncing, isFalse);
    });

    test('U15 completed + syncing', () {
      final ui = mapGpsRecordedRouteUiState(
        recordedRouteStatus: RecordedRouteStatus.completed,
        syncStatus: RouteSyncStatus.syncing,
      );
      expect(ui.recordedRouteStatus, RecordedRouteStatus.completed);
      expect(ui.sync.syncStatus, RouteSyncStatus.syncing);
      expect(ui.sync.isSyncing, isTrue);
      expect(ui.sync.canRetry, isFalse);
    });

    test('U16 completed + synced', () {
      final ui = mapGpsRecordedRouteUiState(
        recordedRouteStatus: RecordedRouteStatus.completed,
        syncStatus: RouteSyncStatus.synced,
      );
      expect(ui.recordedRouteStatus, RecordedRouteStatus.completed);
      expect(ui.sync.syncStatus, RouteSyncStatus.synced);
      expect(ui.sync.canRetry, isFalse);
    });

    test('U17 completed + failed', () {
      final ui = mapGpsRecordedRouteUiState(
        recordedRouteStatus: RecordedRouteStatus.completed,
        syncStatus: RouteSyncStatus.failed,
      );
      expect(ui.recordedRouteStatus, RecordedRouteStatus.completed);
      expect(ui.sync.syncStatus, RouteSyncStatus.failed);
      expect(ui.sync.canRetry, isTrue);
    });

    test(
        'the same syncStatus produces an identical GpsSyncUiState regardless '
        'of recordedRouteStatus -- proves sync mapping never reads recording '
        'status', () {
      for (final syncStatus in [
        RouteSyncStatus.notSynced,
        RouteSyncStatus.syncing,
        RouteSyncStatus.synced,
        RouteSyncStatus.failed,
      ]) {
        final fromCompleted = mapGpsRecordedRouteUiState(
          recordedRouteStatus: RecordedRouteStatus.completed,
          syncStatus: syncStatus,
        ).sync;
        final fromDiscarded = mapGpsRecordedRouteUiState(
          recordedRouteStatus: RecordedRouteStatus.discarded,
          syncStatus: syncStatus,
        ).sync;
        final fromRecording = mapGpsRecordedRouteUiState(
          recordedRouteStatus: RecordedRouteStatus.recording,
          syncStatus: syncStatus,
        ).sync;

        expect(fromCompleted.label, fromDiscarded.label);
        expect(fromCompleted.label, fromRecording.label);
        expect(fromCompleted.canRetry, fromDiscarded.canRetry);
        expect(fromCompleted.canRetry, fromRecording.canRetry);
        expect(fromCompleted.isSyncing, fromDiscarded.isSyncing);
        expect(fromCompleted.isSyncing, fromRecording.isSyncing);
      }
    });

    test('recordedRouteStatus label is independent of sync status', () {
      final synced = mapGpsRecordedRouteUiState(
        recordedRouteStatus: RecordedRouteStatus.completed,
        syncStatus: RouteSyncStatus.synced,
      );
      final failed = mapGpsRecordedRouteUiState(
        recordedRouteStatus: RecordedRouteStatus.completed,
        syncStatus: RouteSyncStatus.failed,
      );
      expect(synced.statusLabel, failed.statusLabel);
    });
  });
}
