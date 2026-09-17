import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/providers/network_provider.dart';
import '../local/gps_local_database.dart';
import '../local/gps_local_database_provider.dart';
import '../recording/gps_recording_controller.dart';
import '../recording/gps_recording_state.dart';
import 'data/supabase_gps_sync_repository.dart';
import 'domain/gps_sync_repository.dart';

/// Drives one account's local-Drift -> Supabase GPS sync: route shell,
/// point/event batches, waypoints, and finalization, entirely on top of
/// the already-existing GPS-2/GPS-3 local database and the Phase 3B/3D
/// production backend. Never touches the recording hot path
/// ([GpsRecordingController]/`appendRoutePoint`) directly — the two are
/// connected only by both reading/writing the same Drift database, plus
/// an optional external listen on the recording state stream to trigger
/// an opportunistic pass after a recording completes.
///
/// Deliberately free of any direct Riverpod dependency, mirroring
/// [GpsRecordingController]'s own "entirely free of any direct Supabase
/// dependency" design: every environmental input (connectivity, the
/// live authenticated user id, recording-completion notifications) is
/// injected as a plain seam (a callback or a `Stream`), so this class is
/// directly unit-testable with fakes and never needs a `ProviderContainer`
/// in a test. All Riverpod wiring lives in [gpsSyncCoordinatorProvider]
/// below, exactly as [gpsRecordingControllerProvider] wires
/// [GpsRecordingController] to [gpsLocalDatabaseProvider].
///
/// Mixes in [WidgetsBindingObserver] directly (same precedent as
/// [GpsRecordingController]) purely to trigger an opportunistic sync
/// pass on app foreground/resume — no background execution framework of
/// any kind is used or assumed.
class GpsSyncCoordinator with WidgetsBindingObserver {
  GpsSyncCoordinator({
    required String ownerId,
    required GpsLocalDatabase db,
    required GpsSyncRepository repository,
    String? Function()? currentUserId,
    Stream<NetworkStatus>? onlineStatusStream,
    Stream<GpsRecordingState>? recordingStateStream,
    int pointBatchSize = 500,
    int eventBatchSize = 500,
    bool autoSyncOnInit = true,
  })  : _ownerId = ownerId,
        _db = db,
        _repository = repository,
        _currentUserId = currentUserId ??
            (() => Supabase.instance.client.auth.currentUser?.id),
        _pointBatchSize = pointBatchSize,
        _eventBatchSize = eventBatchSize {
    WidgetsBinding.instance.addObserver(this);
    _onlineSub = onlineStatusStream?.listen(_onNetworkStatus);
    _recordingStateSub = recordingStateStream?.listen(_onRecordingState);
    // `autoSyncOnInit: false` exists purely so a test can control exactly
    // when the first pass runs (production/[gpsSyncCoordinatorProvider]
    // always uses the default `true`, satisfying the "coordinator/app
    // initialization" sync trigger).
    if (autoSyncOnInit) unawaited(syncNow());
  }

  final String _ownerId;
  final GpsLocalDatabase _db;
  final GpsSyncRepository _repository;
  final String? Function() _currentUserId;
  final int _pointBatchSize;
  final int _eventBatchSize;

  StreamSubscription<NetworkStatus>? _onlineSub;
  StreamSubscription<GpsRecordingState>? _recordingStateSub;
  NetworkStatus? _lastNetworkStatus;

  /// Serializes sync passes for this owner so `syncNow`/`retryRoute`
  /// triggered from several sources at once (init, foreground-resume,
  /// connectivity, recording completion, manual retry) never run
  /// concurrently against the same local rows.
  Future<void> _passLock = Future<void>.value();

  /// Resolves once every sync pass triggered so far (including the
  /// automatic construction-time one) has finished. Exists so a test can
  /// deterministically await the *same* pass the constructor already
  /// triggered instead of racing a second, redundant call against it.
  @visibleForTesting
  Future<void> get pendingSync => _passLock;

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_onlineSub?.cancel());
    unawaited(_recordingStateSub?.cancel());
  }

  void _onNetworkStatus(NetworkStatus status) {
    final previous = _lastNetworkStatus;
    _lastNetworkStatus = status;
    if (previous == NetworkStatus.offline && status == NetworkStatus.online) {
      unawaited(syncNow());
    }
  }

  void _onRecordingState(GpsRecordingState state) {
    if (state.status == GpsRecordingStatus.completed) {
      unawaited(syncNow());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow());
    }
  }

  /// Runs one opportunistic sync pass: normalizes any stale `syncing`
  /// state left over from a previous process, then attempts every
  /// locally-eligible route (see
  /// [GpsLocalDatabase.getRoutesNeedingAutoSync] — never a `failed`
  /// route; those require [retryRoute]).
  Future<void> syncNow() {
    return _serialized(() async {
      if (_disposed) return;
      await _db.normalizeStaleSyncingRoutes(ownerId: _ownerId);
      final routes = await _db.getRoutesNeedingAutoSync(ownerId: _ownerId);
      for (final route in routes) {
        if (_disposed) return;
        await _syncRoute(route);
      }
    });
  }

  /// Explicit, user-initiated retry of exactly one route, regardless of
  /// its current `syncStatus` (including `failed`) — the one path a
  /// previously-terminal route can be attempted again, matching "do not
  /// loop infinitely" for automatic passes while still allowing a real
  /// user retry action.
  Future<void> retryRoute(String routeId) {
    return _serialized(() async {
      if (_disposed) return;
      final route = await _db.getRecordedRoute(ownerId: _ownerId, id: routeId);
      if (route == null) return;
      await _syncRoute(route);
    });
  }

  Future<void> _serialized(Future<void> Function() action) {
    final next = _passLock.then((_) => action());
    // Swallow so one failed pass never poisons the lock chain for the
    // next caller — each pass already records its own outcome onto the
    // relevant route(s); there is nothing further to propagate here.
    _passLock = next.catchError((_) {});
    return next;
  }

  Future<void> _syncRoute(LocalRecordedRoute route) async {
    // --- Owner safety: re-verify against the LIVE session, never trust
    // a captured/cached value, immediately before any network call. ---
    final liveUserId = _currentUserId();
    if (liveUserId == null) {
      // Not signed in: leave the route exactly as it is. This is an
      // ordinary, expected state, never a failure.
      return;
    }
    if (liveUserId != route.ownerId) {
      // Refuse safely: never upload, never reassign owner, never touch
      // local ownerId, never touch syncStatus. User A's route must never
      // upload using User B's session.
      return;
    }

    if (route.status == RecordedRouteStatus.discarded) return;

    await _db.markRouteSyncing(ownerId: route.ownerId, routeId: route.id);

    try {
      await _repository.ensureRouteShell(
        routeId: route.id,
        tripId: route.tripId,
        title: route.title,
        transportMode: route.transportMode,
        visibility: route.visibility,
        startedAt: route.startedAt,
      );

      await _syncPoints(route);
      await _syncWaypoints(route);
      await _syncEvents(route);

      if (route.status == RecordedRouteStatus.completed) {
        final result = await _repository.finalizeRoute(route.id);
        if (result.id == route.id && result.status == 'completed') {
          await _db.recordRouteSyncOutcome(
            ownerId: route.ownerId,
            routeId: route.id,
            syncStatus: RouteSyncStatus.synced,
          );
        } else {
          await _db.recordRouteSyncOutcome(
            ownerId: route.ownerId,
            routeId: route.id,
            syncStatus: RouteSyncStatus.failed,
            lastSyncError:
                'finalize_recorded_route returned an unexpected route '
                '(id=${result.id}, status=${result.status})',
          );
        }
        return;
      }

      // Still recording/paused: everything currently available was
      // uploaded successfully, but more local GPS data can still be
      // appended, so this route may never be marked permanently synced
      // here — `notSynced` is the only correct non-terminal value.
      await _db.recordRouteSyncOutcome(
        ownerId: route.ownerId,
        routeId: route.id,
        syncStatus: RouteSyncStatus.notSynced,
      );
    } on GpsSyncException catch (error) {
      await _db.recordRouteSyncOutcome(
        ownerId: route.ownerId,
        routeId: route.id,
        syncStatus: error.isRetryable
            ? RouteSyncStatus.notSynced
            : RouteSyncStatus.failed,
        lastSyncError: error.message,
      );
    } catch (error) {
      // Unclassified error: default retryable. An unrecognized failure
      // must never permanently bury local data as 'failed'.
      await _db.recordRouteSyncOutcome(
        ownerId: route.ownerId,
        routeId: route.id,
        syncStatus: RouteSyncStatus.notSynced,
        lastSyncError: error.toString(),
      );
    }
  }

  /// Uploads unsynced points in cursor-bounded batches straight from
  /// [GpsLocalDatabase.getUnsyncedPointBatch] — never reordered, never
  /// reconstructed from anything other than that query's own output, so
  /// gap-protection is inherited entirely from the local DAO's own
  /// gapless, monotonic `seq` generation (see its class doc). The
  /// returned cursor is verified against the submitted batch's own max
  /// `seq` *before* ever advancing the local cursor — a mismatch is
  /// treated as an integrity failure, exactly like a server-reported
  /// conflict, never silently accepted.
  Future<void> _syncPoints(LocalRecordedRoute route) async {
    while (true) {
      final batch = await _db.getUnsyncedPointBatch(
        ownerId: route.ownerId,
        recordedRouteId: route.id,
        batchSize: _pointBatchSize,
      );
      if (batch.isEmpty) return;

      final expectedCursor = batch.last.seq;
      final returnedCursor =
          await _repository.syncPoints(routeId: route.id, points: batch);
      if (returnedCursor != expectedCursor) {
        throw GpsSyncException(
          GpsSyncErrorKind.integrityConflict,
          'sync_route_points returned cursor $returnedCursor but the '
          'submitted batch\'s max seq was $expectedCursor',
        );
      }
      await _db.advancePointSyncCursor(
        ownerId: route.ownerId,
        recordedRouteId: route.id,
        newLastSyncedSeq: returnedCursor,
      );
      if (batch.length < _pointBatchSize) return;
    }
  }

  /// Same contract as [_syncPoints], for events.
  Future<void> _syncEvents(LocalRecordedRoute route) async {
    while (true) {
      final batch = await _db.getUnsyncedEventBatch(
        ownerId: route.ownerId,
        recordedRouteId: route.id,
        batchSize: _eventBatchSize,
      );
      if (batch.isEmpty) return;

      final expectedCursor = batch.last.seq;
      final returnedCursor =
          await _repository.syncEvents(routeId: route.id, events: batch);
      if (returnedCursor != expectedCursor) {
        throw GpsSyncException(
          GpsSyncErrorKind.integrityConflict,
          'sync_route_events returned cursor $returnedCursor but the '
          'submitted batch\'s max seq was $expectedCursor',
        );
      }
      await _db.advanceEventSyncCursor(
        ownerId: route.ownerId,
        recordedRouteId: route.id,
        newLastSyncedSeq: returnedCursor,
      );
      if (batch.length < _eventBatchSize) return;
    }
  }

  /// Pushes pending create/update waypoints, then pending deletion
  /// tombstones. A tombstone is purged locally only immediately after
  /// [GpsSyncRepository.deleteWaypoint] succeeds — never before,
  /// matching "never purge a tombstone until server acknowledgement is
  /// proven".
  Future<void> _syncWaypoints(LocalRecordedRoute route) async {
    final pending = await _db.getUnsyncedWaypoints(
      ownerId: route.ownerId,
      recordedRouteId: route.id,
    );
    for (final waypoint in pending) {
      await _repository.upsertWaypoint(waypoint);
      await _db.markWaypointSynced(ownerId: route.ownerId, id: waypoint.id);
    }

    final tombstones = await _db.getTombstonedWaypoints(
      ownerId: route.ownerId,
      recordedRouteId: route.id,
    );
    for (final waypoint in tombstones) {
      await _repository.deleteWaypoint(waypoint.id);
      await _db.purgeAcknowledgedTombstone(
          ownerId: route.ownerId, id: waypoint.id);
    }
  }
}

final gpsSyncRepositoryProvider = Provider<GpsSyncRepository>((ref) {
  return SupabaseGpsSyncRepository(Supabase.instance.client);
});

/// Non-`autoDispose`, same reasoning as [gpsRecordingControllerProvider]:
/// a sync pass must be able to run to completion (and the coordinator's
/// connectivity/lifecycle/recording-state listeners must stay alive)
/// regardless of which screen is currently mounted.
final gpsSyncCoordinatorProvider =
    Provider.family<GpsSyncCoordinator, String>((ref, ownerId) {
  final db = ref.watch(gpsLocalDatabaseProvider);
  final repository = ref.watch(gpsSyncRepositoryProvider);

  // Riverpod's own AsyncValue-wrapped providers are converted to plain
  // Streams here, at the provider boundary, so GpsSyncCoordinator itself
  // never needs to know Riverpod exists (see its class doc).
  final onlineController = StreamController<NetworkStatus>.broadcast();
  ref.listen<AsyncValue<NetworkStatus>>(networkStatusProvider, (_, next) {
    final status = next.value;
    if (status != null) onlineController.add(status);
  });

  final recordingController = StreamController<GpsRecordingState>.broadcast();
  ref.listen<AsyncValue<GpsRecordingState>>(
    gpsRecordingStateProvider(ownerId),
    (_, next) {
      final state = next.value;
      if (state != null) recordingController.add(state);
    },
  );

  final coordinator = GpsSyncCoordinator(
    ownerId: ownerId,
    db: db,
    repository: repository,
    onlineStatusStream: onlineController.stream,
    recordingStateStream: recordingController.stream,
  );
  ref.onDispose(() {
    coordinator.dispose();
    onlineController.close();
    recordingController.close();
  });
  return coordinator;
});

/// UI-facing reactive view of one route's local sync state — reuses the
/// existing [GpsLocalDatabase.watchRecordedRoute] stream directly rather
/// than inventing a parallel state model; `syncStatus` is already a
/// field on the row it returns.
final gpsRouteSyncStateProvider = StreamProvider.autoDispose
    .family<LocalRecordedRoute?, ({String ownerId, String routeId})>(
        (ref, args) {
  final db = ref.watch(gpsLocalDatabaseProvider);
  return db.watchRecordedRoute(ownerId: args.ownerId, id: args.routeId);
});
