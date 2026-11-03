import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../local/gps_local_database.dart';
import '../media/journey_media_storage.dart';
import 'domain/journey_media_sync_repository.dart';

/// How one media phase ended, so [GpsSyncCoordinator] can manage backoff.
enum JourneyMediaPhaseOutcome {
  /// Nothing ran: signed out, or a different account is signed in.
  notRun,

  /// Nothing (more) was started because this owner has an active
  /// (recording/paused) Journey -- at the phase start, before a new item, or
  /// right before an item's first remote request: GPS recording does not
  /// compete with NEW photo uploads. Not an error and never a reason to back
  /// off; unprocessed photos stay `pending`. A request that is already in
  /// flight is not cancelled and may still finish.
  deferredForActiveRecording,

  /// Every examined item reached a definitive outcome (or was skipped).
  clean,

  /// The first INDETERMINATE outcome stopped the phase; back off.
  indeterminate,

  /// Stopped after the current item because another sync pass is queued.
  yielded,

  /// Stopped at the per-pass item cap; the rest waits for the next trigger.
  capped,
}

/// The result of one media phase: how it ended and how many items it
/// definitively settled (acknowledged `synced`, or parked `failed`) itself.
class JourneyMediaPhaseResult {
  const JourneyMediaPhaseResult(this.outcome,
      {this.synced = 0, this.failed = 0});
  final JourneyMediaPhaseOutcome outcome;
  final int synced;
  final int failed;

  /// Items this phase moved out of `pending` by its own proven transition.
  int get settled => synced + failed;
}

/// Upper bounds for every remote media call (Journey Phase 1H-E2B). A
/// stalled request must never hold the coordinator's serialized pass -- and
/// with it every later route finalize -- open indefinitely. A timeout is
/// INDETERMINATE: nothing local changes, and a request that did commit
/// remotely is reconciled on a later attempt through the duplicate paths
/// (409 -> byte comparison, 23505 -> authenticated read-back).
class JourneyMediaTimeouts {
  const JourneyMediaTimeouts({
    this.upload = transfer,
    this.download = transfer,
    this.info = metadata,
    this.insert = metadata,
    this.select = metadata,
  });

  /// Object transfers (up to the 5 MiB bucket limit).
  static const transfer = Duration(seconds: 60);

  /// Small metadata requests.
  static const metadata = Duration(seconds: 20);

  final Duration upload;
  final Duration download;
  final Duration info;
  final Duration insert;
  final Duration select;
}

enum _ItemResult { synced, failed, skipped, indeterminate, deferred }

/// Journey Phase 1H-E2B -- uploads/reconciles Journey images for routes
/// that are locally completed AND remotely finalized (route
/// `syncStatus == synced`). Runs only inside [GpsSyncCoordinator]'s
/// serialized pass, one item at a time; no timer, no polling, no location
/// access, and never while the owner is recording a Journey.
///
/// Local Drift row + local canonical file are the source of truth; the
/// Storage object and the `route_media` row are replicas. An item becomes
/// `synced` only on positive proof of BOTH replicas in the same attempt
/// (see [_syncItem]). A Storage 404, an empty listing, a bare success, a
/// timeout, a 409 alone or a 23505 alone never prove anything. Remote
/// deletion is deferred (D-2): `pendingDelete` rows are never read here.
class JourneyMediaSync {
  JourneyMediaSync({
    required GpsLocalDatabase db,
    required JourneyMediaStorage storage,
    required JourneyMediaSyncRepository repository,
    int maxItemsPerPass = 50,
    JourneyMediaTimeouts timeouts = const JourneyMediaTimeouts(),
  })  : _db = db,
        _storage = storage,
        _repository = repository,
        _maxItemsPerPass = maxItemsPerPass,
        _timeouts = timeouts;

  final GpsLocalDatabase _db;
  final JourneyMediaStorage _storage;
  final JourneyMediaSyncRepository _repository;
  final int _maxItemsPerPass;
  final JourneyMediaTimeouts _timeouts;

  /// The bucket's own limit; checked locally before any upload.
  static const maxImageBytes = 5 * 1024 * 1024;

  /// Coordinate tolerance (degrees) when comparing a stored position.
  static const positionTolerance = 1e-9;

  static final _canonicalUuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  /// `<owner>/<route>/<media>.jpg` -- derived at call time, never persisted.
  static String objectPathFor({
    required String ownerId,
    required String recordedRouteId,
    required String mediaId,
  }) =>
      '$ownerId/$recordedRouteId/$mediaId.jpg';

  /// Runs one media phase for [ownerId]. [currentUserId] is the live-session
  /// seam (re-read before the first and after the last remote call of every
  /// item); [routeIds] limits the phase to those routes (explicit retry),
  /// otherwise the actionable query decides; [shouldYield] is checked before
  /// every item after the first, so a queued sync pass is never stuck behind
  /// uploads.
  Future<JourneyMediaPhaseResult> runPhase({
    required String ownerId,
    required String? Function() currentUserId,
    Iterable<String>? routeIds,
    bool Function()? shouldYield,
  }) async {
    if (currentUserId() != ownerId) {
      return const JourneyMediaPhaseResult(JourneyMediaPhaseOutcome.notRun);
    }
    // Do not START uploads while this owner records a Journey (any route):
    // GPS recording should not compete with photo uploads. Local-only, no
    // network (see [_recordingActive] for its cost). Re-checked before every
    // item and again right before an item's first remote request, because a
    // Journey can start while a photo is uploading. A request already in
    // flight is not cancelled -- there is no claim of absolute zero overlap.
    if (await _recordingActive(ownerId)) {
      return const JourneyMediaPhaseResult(
          JourneyMediaPhaseOutcome.deferredForActiveRecording);
    }

    final ids = routeIds?.toList(growable: false) ??
        await _db.getRouteIdsWithActionableMedia(ownerId: ownerId);
    var processed = 0;
    var synced = 0;
    var failed = 0;
    JourneyMediaPhaseResult finish(JourneyMediaPhaseOutcome outcome) =>
        JourneyMediaPhaseResult(outcome, synced: synced, failed: failed);

    for (final routeId in ids) {
      final route = await _db.getRecordedRoute(ownerId: ownerId, id: routeId);
      if (route == null ||
          route.status != RecordedRouteStatus.completed ||
          route.syncStatus != RouteSyncStatus.synced) {
        continue;
      }
      final items = await _db.getPendingJourneyMedia(
          ownerId: ownerId, recordedRouteId: routeId);
      if (items.isEmpty) continue;
      final waypoints = {
        for (final w in await _db.getWaypoints(
            ownerId: ownerId, recordedRouteId: routeId))
          w.id: w,
      };

      for (final item in items) {
        if (processed >= _maxItemsPerPass) {
          return finish(JourneyMediaPhaseOutcome.capped);
        }
        if (processed > 0 && (shouldYield?.call() ?? false)) {
          return finish(JourneyMediaPhaseOutcome.yielded);
        }
        // Moment dependency: the remote waypoint must already exist.
        final waypointId = item.waypointId;
        if (waypointId != null &&
            waypoints[waypointId]?.syncStatus != WaypointSyncStatus.synced) {
          continue;
        }
        // A Journey may have started since the phase began (e.g. while the
        // previous photo uploaded): never begin a new item then.
        if (await _recordingActive(ownerId)) {
          return finish(JourneyMediaPhaseOutcome.deferredForActiveRecording);
        }
        processed++;
        switch (await _syncItem(item, ownerId, currentUserId)) {
          case _ItemResult.synced:
            synced++;
          case _ItemResult.failed:
            failed++;
          case _ItemResult.skipped:
            break;
          case _ItemResult.deferred:
            return finish(JourneyMediaPhaseOutcome.deferredForActiveRecording);
          case _ItemResult.indeterminate:
            return finish(JourneyMediaPhaseOutcome.indeterminate);
        }
      }
    }
    return finish(JourneyMediaPhaseOutcome.clean);
  }

  Future<_ItemResult> _syncItem(
    LocalJourneyMediaItem item,
    String ownerId,
    String? Function() currentUserId,
  ) async {
    bool identityStable() => currentUserId() == ownerId;
    // Identity BEFORE the first remote call of this item (and after the
    // last, below): an account switch between items makes zero calls.
    if (!identityStable()) return _indeterminate('identity changed');
    try {
      // U0 -- preflight. Re-read: only a still-pending row is processed.
      final fresh = await _db.getJourneyMediaItem(
          ownerId: ownerId, recordedRouteId: item.recordedRouteId, id: item.id);
      if (fresh == null || fresh.syncStatus != JourneyMediaSyncStatus.pending) {
        return _ItemResult.skipped;
      }
      if (!_canonicalUuid.hasMatch(ownerId) ||
          !_canonicalUuid.hasMatch(fresh.recordedRouteId) ||
          !_canonicalUuid.hasMatch(fresh.id) ||
          fresh.mediaType != JourneyMediaType.image ||
          fresh.localRelativePath !=
              JourneyMediaStorage.relativePathFor(
                  recordedRouteId: fresh.recordedRouteId, mediaId: fresh.id)) {
        return await _fail(fresh, 'non-canonical identity', identityStable);
      }
      final objectPath = objectPathFor(
          ownerId: ownerId,
          recordedRouteId: fresh.recordedRouteId,
          mediaId: fresh.id);

      final file = await _storage.existingFile(fresh.localRelativePath);
      if (file == null) {
        return await _reconcileMissingFile(
            fresh, ownerId, objectPath, identityStable);
      }
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } on FileSystemException {
        return _indeterminate('local file unreadable');
      }
      if (!isPlausibleJpeg(bytes)) {
        return await _fail(
            fresh, 'local file failed JPEG/size checks', identityStable);
      }
      final blocked = await _beforeRemote(ownerId, identityStable);
      if (blocked != null) return blocked;

      // B -- Storage object.
      try {
        await bounded(
            _repository.uploadObject(objectPath: objectPath, bytes: bytes),
            _timeouts.upload,
            'upload');
      } on JourneyMediaSyncException catch (error) {
        if (error.kind != JourneyMediaRemoteFailureKind.duplicate) rethrow;
        if (!identityStable()) return _indeterminate('identity changed');
        // B2: a duplicate proves nothing until the bytes match exactly.
        final remote = await _read(() => bounded(
            _repository.downloadObject(objectPath),
            _timeouts.download,
            'download'));
        if (!identityStable()) return _indeterminate('identity changed');
        if (!listEquals(remote, bytes)) {
          return await _fail(
              fresh, 'remote object bytes differ', identityStable);
        }
      }
      if (!identityStable()) return _indeterminate('identity changed');

      // C -- route_media row.
      JourneyMediaRemoteRow? stored;
      try {
        stored = await bounded<JourneyMediaRemoteRow>(
            _repository.insertRow(JourneyMediaRowPayload(
              id: fresh.id,
              recordedRouteId: fresh.recordedRouteId,
              waypointId: fresh.waypointId,
              mediaType: fresh.mediaType,
              capturedAt: fresh.capturedAt,
              latitude: fresh.latitude,
              longitude: fresh.longitude,
            )),
            _timeouts.insert,
            'insert');
      } on JourneyMediaSyncException catch (error) {
        if (error.kind != JourneyMediaRemoteFailureKind.duplicate) rethrow;
        if (!identityStable()) return _indeterminate('identity changed');
        // C2: a duplicate proves nothing until the visible row matches.
        stored = await _read(() => bounded(
            _repository.selectRow(fresh.id), _timeouts.select, 'select'));
        if (stored == null) {
          return await _fail(
              fresh, 'duplicate row not visible', identityStable);
        }
      }
      if (!rowMatches(stored, fresh, ownerId)) {
        return await _fail(fresh, 'remote row differs', identityStable);
      }
      return await _acknowledge(fresh, identityStable);
    } on JourneyMediaSyncException catch (error) {
      if (error.kind == JourneyMediaRemoteFailureKind.permanent) {
        return await _fail(item, error.reason, identityStable);
      }
      return _indeterminate(error.reason);
    } catch (error) {
      // Unexpected (e.g. a local database error): no knowledge, no change.
      return _indeterminate('unexpected ${error.runtimeType}');
    }
  }

  /// P8-P11: no local bytes, so nothing is uploaded or inserted. Only a
  /// positively verified remote pair can complete the item.
  Future<_ItemResult> _reconcileMissingFile(
    LocalJourneyMediaItem item,
    String ownerId,
    String objectPath,
    bool Function() identityStable,
  ) async {
    final blocked = await _beforeRemote(ownerId, identityStable);
    if (blocked != null) return blocked;
    final row = await _read(() =>
        bounded(_repository.selectRow(item.id), _timeouts.select, 'select'));
    if (!identityStable()) return _indeterminate('identity changed');
    if (row == null) {
      return _fail(item, 'local file missing; no remote row', identityStable);
    }
    if (!rowMatches(row, item, ownerId)) {
      return _fail(
          item, 'local file missing; remote row differs', identityStable);
    }
    // B3: only a positive 2xx proves the object. A 404/NoSuchKey (or a
    // timeout) surfaces here as INDETERMINATE: the item stays pending (P11).
    await _read(() =>
        bounded(_repository.objectInfo(objectPath), _timeouts.info, 'info'));
    return _acknowledge(item, identityStable);
  }

  /// Whether this owner has a recording/paused Journey. Local-only.
  ///
  /// Cost, measured rather than assumed: [GpsLocalDatabase.getRecoverableRecording]
  /// binds the two statuses as parameters (`status IN (?, ?)`), so SQLite
  /// plans it with `local_recorded_routes_owner_idx (owner_id=?)` and filters
  /// the status. It is NOT served by the partial
  /// `local_recorded_routes_one_active_per_owner` index, which SQLite only
  /// uses when the statuses are literals. It is an owner-scoped read of that
  /// owner's route rows -- acceptable at this scale; no schema change.
  Future<bool> _recordingActive(String ownerId) async =>
      await _db.getRecoverableRecording(ownerId) != null;

  /// The last local checks before an item's FIRST remote request, run after
  /// all of its awaited local preflight (database row, file lookup/read).
  /// A Journey that started meanwhile defers the item without any backoff;
  /// the live identity is re-verified LAST, immediately before the request,
  /// so an account switch during the preflight makes zero remote calls.
  /// Returns `null` to proceed.
  Future<_ItemResult?> _beforeRemote(
      String ownerId, bool Function() identityStable) async {
    if (await _recordingActive(ownerId)) return _ItemResult.deferred;
    if (!identityStable()) return _indeterminate('identity changed');
    return null;
  }

  /// The conditional local `pending -> synced` transition. Reports `synced`
  /// ONLY if this call performed it; if the row changed meanwhile (another
  /// worker settled it, it was parked, or it became a tombstone) nothing is
  /// written and the item is reported as skipped.
  Future<_ItemResult> _acknowledge(
      LocalJourneyMediaItem item, bool Function() identityStable) async {
    if (!identityStable()) return _indeterminate('identity changed');
    final bool acknowledged;
    try {
      acknowledged = await _db.markJourneyMediaSynced(
          ownerId: item.ownerId,
          recordedRouteId: item.recordedRouteId,
          id: item.id);
    } on StateError {
      // Became a tombstone meanwhile: never acknowledge a deletion as an
      // upload. Nothing else to do here (remote deletion is deferred).
      debugPrint('gps media sync: not acknowledged (tombstoned meanwhile)');
      return _ItemResult.skipped;
    }
    if (!acknowledged) {
      debugPrint('gps media sync: not acknowledged (state changed meanwhile)');
      return _ItemResult.skipped;
    }
    return _ItemResult.synced;
  }

  Future<_ItemResult> _fail(LocalJourneyMediaItem item, String reason,
      bool Function() identityStable) async {
    if (!identityStable()) return _indeterminate('identity changed');
    final parked = await _db.markJourneyMediaFailed(
        ownerId: item.ownerId,
        recordedRouteId: item.recordedRouteId,
        id: item.id);
    if (!parked) return _ItemResult.skipped;
    debugPrint('gps media sync: item failed ($reason)');
    return _ItemResult.failed;
  }

  _ItemResult _indeterminate(String reason) {
    debugPrint('gps media sync: indeterminate ($reason); phase stopped');
    return _ItemResult.indeterminate;
  }

  /// Bounds one remote call. On expiry the call is abandoned (not
  /// cancelled -- if it still commits remotely, a later attempt reconciles
  /// it through the duplicate paths) and the outcome is INDETERMINATE.
  @visibleForTesting
  static Future<T> bounded<T>(
      Future<T> call, Duration limit, String operation) async {
    try {
      return await call.timeout(limit);
    } on TimeoutException {
      throw JourneyMediaSyncException(
          JourneyMediaRemoteFailureKind.indeterminate, '$operation timed out');
    }
  }

  /// Reads (download/info/select) can never permanently reject a valid,
  /// canonical request, so ANY failure of a read is INDETERMINATE.
  static Future<T> _read<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on JourneyMediaSyncException catch (error) {
      throw JourneyMediaSyncException(
          JourneyMediaRemoteFailureKind.indeterminate, error.reason);
    }
  }

  /// F5 client integrity checks (NOT a security boundary): size within the
  /// bucket limit, JPEG start-of-image and end-of-image markers.
  static bool isPlausibleJpeg(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes.length <= maxImageBytes &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF &&
      bytes[bytes.length - 2] == 0xFF &&
      bytes[bytes.length - 1] == 0xD9;

  /// Every accepted field must match the local item; `owner_id` must be the
  /// live owner (it is server-stamped, never sent).
  static bool rowMatches(
      JourneyMediaRemoteRow row, LocalJourneyMediaItem item, String ownerId) {
    if (row.id != item.id ||
        row.recordedRouteId != item.recordedRouteId ||
        row.ownerId != ownerId ||
        row.waypointId != item.waypointId ||
        row.mediaType != item.mediaType ||
        !row.capturedAt.isAtSameMomentAs(item.capturedAt)) {
      return false;
    }
    final localHasPosition = item.latitude != null && item.longitude != null;
    final remoteHasPosition = row.latitude != null && row.longitude != null;
    if (localHasPosition != remoteHasPosition) return false;
    if (!localHasPosition) return true;
    return (row.latitude! - item.latitude!).abs() <= positionTolerance &&
        (row.longitude! - item.longitude!).abs() <= positionTolerance;
  }
}
