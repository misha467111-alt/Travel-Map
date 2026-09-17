import '../../local/gps_local_database.dart';

/// Why a [GpsSyncException] happened, so [GpsSyncCoordinator] can decide
/// whether to retry automatically or stop trying.
///
/// Only [GpsSyncErrorKind.retryable] is retryable. Every other kind is
/// terminal: the same request would fail again for the same reason no
/// matter how many times it is retried, so retrying automatically would
/// only loop forever without local data ever leaving 'failed'.
enum GpsSyncErrorKind {
  /// Network unavailable, timeout, a transient server-side failure, or an
  /// expired/refreshed auth session — worth retrying on the next
  /// opportunistic pass without any special handling.
  retryable,

  /// The server rejected the request as not belonging to the
  /// authenticated caller (wrong owner, or the route doesn't exist from
  /// their point of view). Should not normally happen at all, since
  /// [GpsSyncCoordinator] verifies ownership itself before ever calling
  /// the repository — if it does happen, it means the local and server
  /// views of ownership have diverged, which retrying cannot fix.
  ownerMismatch,

  /// The server reports a batch conflict: a submitted row has the same
  /// identity (route+seq, or the same point/event otherwise) as an
  /// already-persisted row, but different data. Retrying the identical
  /// payload will never resolve this — it needs investigation, not a
  /// retry loop.
  integrityConflict,

  /// The server rejected the payload itself as structurally invalid
  /// (e.g. a contract violation the local data shouldn't be able to
  /// produce in the first place). Retrying an unchanged, still-invalid
  /// payload can never succeed.
  invalidPayload,
}

/// Thrown by a [GpsSyncRepository] implementation for every classified
/// failure. [GpsSyncCoordinator] never inspects a raw network/Postgrest
/// exception itself — translating one into this type, with the right
/// [kind], is entirely the repository's job, keeping the coordinator's
/// retry logic free of any Supabase-specific knowledge.
class GpsSyncException implements Exception {
  GpsSyncException(this.kind, this.message);
  final GpsSyncErrorKind kind;
  final String message;

  bool get isRetryable => kind == GpsSyncErrorKind.retryable;

  @override
  String toString() => 'GpsSyncException(${kind.name}): $message';
}

/// The server row returned by `finalize_recorded_route`, narrowed to
/// exactly what [GpsSyncCoordinator] needs to verify before it may ever
/// mark a route [RouteSyncStatus.synced].
class GpsFinalizeResponse {
  const GpsFinalizeResponse({required this.id, required this.status});
  final String id;
  final String status;
}

/// The network boundary the GPS sync coordinator drives. An
/// implementation talks to Supabase; tests use a hand-rolled fake
/// implementing this interface directly (matching this codebase's
/// established `CheckInRepository`/`_RecordingCheckInRepository`
/// convention — no mocking library is used anywhere in this project).
///
/// Every method operates on exactly one already-authenticated user's
/// data. Owner verification (local `route.ownerId` against the live
/// `auth.uid()`) is entirely [GpsSyncCoordinator]'s responsibility,
/// performed *before* any of these methods is ever called — a
/// repository implementation never needs to re-derive or question who
/// the caller is.
abstract interface class GpsSyncRepository {
  /// Ensures a server-side `recorded_routes` shell exists for
  /// [routeId] — the *same* id as the local route (no server-generated
  /// replacement, no id-mapping table). Idempotent: safe to call
  /// whether or not the shell already exists.
  ///
  /// Deliberately has no `status` or `endedAt` parameter at all: those
  /// are server-owned finalization results (`status='completed'` is
  /// reachable only through [finalizeRoute]), so there is no way to
  /// pass them through this method even by mistake — the interface
  /// itself makes that class of bug structurally impossible, not just
  /// discouraged by convention.
  Future<void> ensureRouteShell({
    required String routeId,
    String? tripId,
    String? title,
    required String transportMode,
    required String visibility,
    required DateTime startedAt,
  });

  /// Uploads one batch of points via the `sync_route_points` RPC.
  /// Returns the cursor value the server reports as safely synced —
  /// the caller (never this method) is responsible for verifying that
  /// value actually corresponds to the submitted batch before trusting
  /// it enough to advance a local cursor.
  Future<int> syncPoints({
    required String routeId,
    required List<LocalRoutePoint> points,
  });

  /// Same contract as [syncPoints], for `sync_route_events`.
  Future<int> syncEvents({
    required String routeId,
    required List<LocalRouteEvent> events,
  });

  /// Creates or updates one waypoint server-side, using the *same*
  /// local waypoint UUID as its server id (no id mapping). Safe to call
  /// for both a brand-new waypoint and a retry/re-sync of a
  /// previously-edited one — an implementation is responsible for
  /// falling back to an update of only the server-editable fields
  /// (`waypoint_type`/`title`/`note`/`photo_ref`) when the id already
  /// exists server-side.
  Future<void> upsertWaypoint(LocalWaypoint waypoint);

  /// Pushes a local deletion tombstone to the server. Must only be
  /// called by the coordinator once it is ready to purge the local
  /// tombstone immediately afterward on success — this method itself
  /// has no "soft delete"; a thrown [GpsSyncException] means nothing
  /// was deleted server-side and the local tombstone must be preserved.
  Future<void> deleteWaypoint(String waypointId);

  /// Calls `finalize_recorded_route`. Safe to call repeatedly — the
  /// server function is idempotent (Phase 3C proved a retry after the
  /// route is already 'completed' returns the same row unchanged). The
  /// caller must still verify the returned id/status before trusting
  /// the route as synced.
  Future<GpsFinalizeResponse> finalizeRoute(String routeId);
}
