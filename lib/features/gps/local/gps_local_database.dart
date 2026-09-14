import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'gps_local_database.g.dart';

/// Status/event/sync-state string constants. Plain strings (not a DB-level
/// CHECK constraint, unlike the server schema) because local SQLite is
/// single-writer, app-controlled data — there is no adversarial client to
/// defend against here, only our own code, so a Dart-level allow-list
/// (enforced in [GpsLocalDatabase.updateRouteStatus]) is enough.
abstract class RecordedRouteStatus {
  static const recording = 'recording';
  static const paused = 'paused';
  static const completed = 'completed';
  static const discarded = 'discarded';
}

abstract class RouteEventType {
  static const start = 'start';
  static const pause = 'pause';
  static const resume = 'resume';
  static const finish = 'finish';
  static const discard = 'discard';
}

/// A waypoint's local sync/deletion state.
///
/// [pendingDelete] is a tombstone, not a real waypoint state on the
/// server — it exists so a local delete of a possibly-already-synced
/// waypoint can still be pushed to the server later instead of silently
/// leaving an orphaned row there forever. See
/// [GpsLocalDatabase.deleteWaypoint] for the full reasoning.
abstract class WaypointSyncStatus {
  static const pending = 'pending';
  static const synced = 'synced';
  static const failed = 'failed';
  static const pendingDelete = 'pendingDelete';
}

abstract class RouteSyncStatus {
  static const notSynced = 'not_synced';
  static const syncing = 'syncing';
  static const synced = 'synced';
  static const failed = 'failed';
}

/// Thrown by [GpsLocalDatabase.updateRouteStatus] when the requested
/// transition isn't one of the allowed direct-client transitions —
/// mirrors the server's protect_recorded_route_system_fields trigger
/// exactly (recording<->paused, {recording,paused}->discarded;
/// 'completed' is reachable only through [GpsLocalDatabase.finishRecordingLocally],
/// never through this generic setter, and 'discarded'/'completed' are
/// both terminal).
class InvalidRouteStatusTransition implements Exception {
  InvalidRouteStatusTransition(this.from, this.to);
  final String from;
  final String to;
  @override
  String toString() =>
      'InvalidRouteStatusTransition: $from -> $to is not an allowed direct transition';
}

/// Thrown by [GpsLocalDatabase.createLocalRecordedRoute] when the owner
/// already has a recording/paused route. Raised as a friendly, typed
/// exception before ever reaching the database — the partial unique
/// index on [LocalRecordedRoutes] (see its class doc) is the actual
/// enforcement; this is just a nicer failure mode than a raw SQLite
/// constraint-violation exception.
class WaypointTombstonedException implements Exception {
  WaypointTombstonedException(this.waypointId);
  final String waypointId;
  @override
  String toString() => 'WaypointTombstonedException: waypoint $waypointId is '
      'pending deletion and can no longer be edited';
}

class ActiveRecordingExistsException implements Exception {
  ActiveRecordingExistsException(this.existingRouteId);
  final String existingRouteId;
  @override
  String toString() =>
      'ActiveRecordingExistsException: route $existingRouteId is already recording/paused for this owner';
}

/// One local GPS recording session. Mirrors public.recorded_routes
/// (supabase/migrations/202609140002_trips_gps_core.sql) field-for-field
/// where a server counterpart exists, plus purely-local sync-bookkeeping
/// columns that have no server column at all.
///
/// `id` has no default: it is always client-generated (matching the
/// server's `recorded_routes.id uuid primary key` with no
/// `default gen_random_uuid()`) so an offline-created recording syncs
/// later by a plain idempotent upsert on the same id.
///
/// Unlike LocalMessages in the chat module, the primary key here is a
/// bare `id`, not `(ownerId, id)`. Chat's composite key exists because
/// the same *server-generated* message id can legitimately need to be
/// cached under two different local accounts on a shared device (two
/// friends messaging each other on the same phone). A recorded route has
/// exactly one owner by construction and is never shared between
/// accounts, so there is no scenario where the same id needs two
/// independent local rows — a plain `id` primary key plus an indexed,
/// always-filtered `ownerId` column is sufficient scoping without the
/// composite-key complexity chat needed for a different reason.
///
/// The partial unique index below is the actual enforcement for "no two
/// active recordings per account" (see [GpsLocalDatabase.createLocalRecordedRoute]) —
/// a real SQLite constraint, not just application-level discipline.
@TableIndex(name: 'local_recorded_routes_owner_idx', columns: {#ownerId})
@TableIndex.sql(
  'CREATE UNIQUE INDEX local_recorded_routes_one_active_per_owner '
  "ON local_recorded_routes (owner_id) WHERE status IN ('recording', 'paused')",
)
class LocalRecordedRoutes extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get tripId => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get transportMode =>
      text().withDefault(const Constant('walking'))();
  TextColumn get status =>
      text().withDefault(const Constant(RecordedRouteStatus.recording))();
  TextColumn get visibility => text().withDefault(const Constant('private'))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // --- Local-only sync bookkeeping; no server column counterpart. ---
  TextColumn get syncStatus =>
      text().withDefault(const Constant(RouteSyncStatus.notSynced))();
  IntColumn get lastSyncedPointSeq => integer().nullable()();
  IntColumn get lastSyncedEventSeq => integer().nullable()();
  DateTimeColumn get lastSyncAttemptAt => dateTime().nullable()();
  TextColumn get lastSyncError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Raw GPS samples. Mirrors public.route_points exactly in shape, minus
/// PostGIS: latitude/longitude are stored as plain REAL columns (Drift's
/// `real()`), not any geography type — there is no local PostGIS, and a
/// pair of doubles is all that's needed until these rows are synced and
/// the server builds the real `geography(Point,4326)` value from them.
///
/// Primary key (recordedRouteId, seq) matches the server table exactly.
/// No `synced` flag on this table — deliberately: route_points/
/// recorded_route_events are immutable and strictly append-only, so a
/// single monotonic `lastSyncedPointSeq` cursor on the parent route
/// (see [LocalRecordedRoutes]) is a complete description of remaining
/// sync work ("everything with seq greater than the cursor is
/// unsynced"). Adding a per-row flag here would be redundant metadata on
/// the highest-volume local table for no benefit — contrast with
/// [LocalWaypoints], which needs per-row state for a real reason (see
/// its class doc).
class LocalRoutePoints extends Table {
  TextColumn get recordedRouteId => text()();
  IntColumn get seq => integer()();
  TextColumn get ownerId => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitude => real().nullable()();
  RealColumn get horizontalAccuracy => real().nullable()();
  RealColumn get verticalAccuracy => real().nullable()();
  RealColumn get speed => real().nullable()();
  RealColumn get speedAccuracy => real().nullable()();
  RealColumn get heading => real().nullable()();
  RealColumn get headingAccuracy => real().nullable()();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get provider => text().nullable()();

  @override
  Set<Column> get primaryKey => {recordedRouteId, seq};
}

/// Typed points a user adds to a recording, independent of whether it is
/// currently recording or paused (see [GpsLocalDatabase.addWaypoint] —
/// deliberately has no status check at all).
///
/// `id` is client-generated (matching public.route_waypoints.id), unlike
/// route points/events which use a route-scoped integer seq — waypoints
/// are independent objects with no natural total order.
///
/// Per-row `syncStatus`, not a route-level cursor: unlike route_points/
/// recorded_route_events (immutable, append-only), waypoints can be
/// edited (title/note/type) and deleted after creation, matching the
/// server's route_waypoints design. A single monotonic cursor cannot
/// correctly represent "this waypoint was synced once but has since been
/// edited and needs re-syncing" — there is no total order to advance a
/// cursor along, and re-editing an already-synced waypoint must be able
/// to un-sync it. A per-row `syncStatus`, reset to `pending` on every
/// local edit, is the safer, correct design for this specific table.
@TableIndex(name: 'local_waypoints_route_idx', columns: {#recordedRouteId})
class LocalWaypoints extends Table {
  TextColumn get id => text()();
  TextColumn get recordedRouteId => text()();
  TextColumn get ownerId => text()();
  TextColumn get waypointType => text()();
  TextColumn get title => text().nullable()();
  TextColumn get note => text().nullable()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitude => real().nullable()();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get photoRef => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(WaypointSyncStatus.pending))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only lifecycle/pause log — mirrors public.recorded_route_events
/// exactly. No update/delete DAO method exists for individual events by
/// design (see [GpsLocalDatabase.appendRouteEvent]): the only supported
/// operation is appending a new one.
class LocalRouteEvents extends Table {
  TextColumn get recordedRouteId => text()();
  IntColumn get seq => integer()();
  TextColumn get ownerId => text()();
  TextColumn get eventType => text()();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column> get primaryKey => {recordedRouteId, seq};
}

@DriftDatabase(
  tables: [
    LocalRecordedRoutes,
    LocalRoutePoints,
    LocalWaypoints,
    LocalRouteEvents
  ],
)
class GpsLocalDatabase extends _$GpsLocalDatabase {
  GpsLocalDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  /// Test-only convenience constructor for an in-memory database — same
  /// pattern as ChatLocalDatabase.forTesting. The default constructor
  /// (production) opens a real on-disk database via drift_flutter's
  /// platform-aware `driftDatabase()` helper, which works identically on
  /// Android and iOS (no manual path_provider wiring, no Android-only
  /// filesystem assumption).
  GpsLocalDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'gps_local');
  }

  // Same empirically-confirmed sqlite3/Drift DateTime quirk documented in
  // ChatLocalDatabase: values round-trip the correct instant but come
  // back with isUtc: false regardless of what was written. Normalized
  // back to UTC here, once, on every read.
  static DateTime _utc(DateTime value) => value.toUtc();
  static DateTime? _utcOrNull(DateTime? value) => value?.toUtc();

  LocalRecordedRoute _normalizeRoute(LocalRecordedRoute row) => row.copyWith(
        startedAt: _utc(row.startedAt),
        endedAt: Value(_utcOrNull(row.endedAt)),
        createdAt: _utc(row.createdAt),
        updatedAt: _utc(row.updatedAt),
        lastSyncAttemptAt: Value(_utcOrNull(row.lastSyncAttemptAt)),
      );

  LocalRoutePoint _normalizePoint(LocalRoutePoint row) =>
      row.copyWith(recordedAt: _utc(row.recordedAt));

  LocalWaypoint _normalizeWaypoint(LocalWaypoint row) => row.copyWith(
        recordedAt: _utc(row.recordedAt),
        createdAt: _utc(row.createdAt),
        updatedAt: _utc(row.updatedAt),
      );

  LocalRouteEvent _normalizeEvent(LocalRouteEvent row) =>
      row.copyWith(occurredAt: _utc(row.occurredAt));

  // ---------------------------------------------------------------------
  // Recorded routes
  // ---------------------------------------------------------------------

  /// Atomically creates a new local recording and its 'start' event.
  /// `status` is always forced to [RecordedRouteStatus.recording] here,
  /// mirroring the server trigger's INSERT-time behavior — the caller
  /// cannot create a route in any other state.
  ///
  /// Throws [ActiveRecordingExistsException] if this owner already has a
  /// recording/paused route (checked up front for a clear error; the
  /// partial unique index on [LocalRecordedRoutes] is the actual,
  /// database-enforced guarantee even if this check is ever bypassed).
  Future<LocalRecordedRoute> createLocalRecordedRoute({
    required String id,
    required String ownerId,
    String? tripId,
    String? title,
    String transportMode = 'walking',
    String visibility = 'private',
    required DateTime startedAt,
  }) {
    return transaction(() async {
      final existing = await _activeRouteQuery(ownerId).getSingleOrNull();
      if (existing != null) {
        throw ActiveRecordingExistsException(existing.id);
      }

      final now = DateTime.now().toUtc();
      await into(localRecordedRoutes).insert(
        LocalRecordedRoutesCompanion.insert(
          id: id,
          ownerId: ownerId,
          tripId: Value(tripId),
          title: Value(title),
          transportMode: Value(transportMode),
          status: const Value(RecordedRouteStatus.recording),
          visibility: Value(visibility),
          startedAt: startedAt,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _appendEventUnguarded(
        recordedRouteId: id,
        ownerId: ownerId,
        eventType: RouteEventType.start,
        occurredAt: startedAt,
      );
      return _normalizeRoute(
        await (select(localRecordedRoutes)..where((t) => t.id.equals(id)))
            .getSingle(),
      );
    });
  }

  Future<LocalRecordedRoute?> getRecordedRoute({
    required String ownerId,
    required String id,
  }) async {
    final row = await (select(localRecordedRoutes)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _normalizeRoute(row);
  }

  Stream<LocalRecordedRoute?> watchRecordedRoute({
    required String ownerId,
    required String id,
  }) {
    final query = select(localRecordedRoutes)
      ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id));
    return query
        .watchSingleOrNull()
        .map((row) => row == null ? null : _normalizeRoute(row));
  }

  SimpleSelectStatement<$LocalRecordedRoutesTable, LocalRecordedRoute>
      _activeRouteQuery(
    String ownerId,
  ) {
    return select(localRecordedRoutes)
      ..where((t) =>
          t.ownerId.equals(ownerId) &
          t.status.isIn(
              [RecordedRouteStatus.recording, RecordedRouteStatus.paused]));
  }

  /// The one recording/paused route for this owner, if any — reactive.
  /// At most one row is possible by construction (see the partial unique
  /// index on [LocalRecordedRoutes]).
  Stream<LocalRecordedRoute?> watchActiveRecordedRoute(String ownerId) {
    return _activeRouteQuery(ownerId)
        .watchSingleOrNull()
        .map((row) => row == null ? null : _normalizeRoute(row));
  }

  /// One-shot version of [watchActiveRecordedRoute], for the "is there an
  /// unfinished recording to offer resuming?" check on app launch —
  /// crash/restart recovery. A 'completed' or 'discarded' route is never
  /// returned (only 'recording'/'paused' match the underlying query).
  Future<LocalRecordedRoute?> getRecoverableRecording(String ownerId) async {
    final row = await _activeRouteQuery(ownerId).getSingleOrNull();
    return row == null ? null : _normalizeRoute(row);
  }

  /// Generic, guarded status setter — enforces exactly the same
  /// allow-list the server's protect_recorded_route_system_fields
  /// trigger enforces. 'completed' is never a valid target here; only
  /// [finishRecordingLocally] can reach it. Does not touch the event
  /// log — callers needing an atomic status+event change should use one
  /// of the dedicated transactional methods below instead of composing
  /// this manually.
  Future<void> updateRouteStatus({
    required String ownerId,
    required String routeId,
    required String newStatus,
  }) async {
    final current = await getRecordedRoute(ownerId: ownerId, id: routeId);
    if (current == null) {
      throw StateError('recorded route $routeId not found for this owner');
    }
    if (current.status == newStatus) return;

    final allowed = switch (current.status) {
      RecordedRouteStatus.recording =>
        newStatus == RecordedRouteStatus.paused ||
            newStatus == RecordedRouteStatus.discarded,
      RecordedRouteStatus.paused =>
        newStatus == RecordedRouteStatus.recording ||
            newStatus == RecordedRouteStatus.discarded,
      _ => false,
    };
    if (!allowed) {
      throw InvalidRouteStatusTransition(current.status, newStatus);
    }

    await (update(localRecordedRoutes)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(routeId)))
        .write(LocalRecordedRoutesCompanion(
      status: Value(newStatus),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  /// Atomic: status -> paused, append a 'pause' event.
  Future<void> pauseRecording({
    required String ownerId,
    required String routeId,
    required DateTime occurredAt,
  }) {
    return transaction(() async {
      await updateRouteStatus(
        ownerId: ownerId,
        routeId: routeId,
        newStatus: RecordedRouteStatus.paused,
      );
      await _appendEventUnguarded(
        recordedRouteId: routeId,
        ownerId: ownerId,
        eventType: RouteEventType.pause,
        occurredAt: occurredAt,
      );
    });
  }

  /// Atomic: status -> recording, append a 'resume' event.
  Future<void> resumeRecording({
    required String ownerId,
    required String routeId,
    required DateTime occurredAt,
  }) {
    return transaction(() async {
      await updateRouteStatus(
        ownerId: ownerId,
        routeId: routeId,
        newStatus: RecordedRouteStatus.recording,
      );
      await _appendEventUnguarded(
        recordedRouteId: routeId,
        ownerId: ownerId,
        eventType: RouteEventType.resume,
        occurredAt: occurredAt,
      );
    });
  }

  /// Atomic: status -> discarded, append a 'discard' event. Terminal —
  /// mirrors the server: nothing may transition out of 'discarded'.
  Future<void> discardRecording({
    required String ownerId,
    required String routeId,
    required DateTime occurredAt,
  }) {
    return transaction(() async {
      await updateRouteStatus(
        ownerId: ownerId,
        routeId: routeId,
        newStatus: RecordedRouteStatus.discarded,
      );
      await _appendEventUnguarded(
        recordedRouteId: routeId,
        ownerId: ownerId,
        eventType: RouteEventType.discard,
        occurredAt: occurredAt,
      );
    });
  }

  /// Atomic: append a 'finish' event, set endedAt, and transition status
  /// straight to 'completed' locally — the one place 'completed' is
  /// reachable from. This is a *local* completion only, for immediate
  /// UI/statistics-preview purposes; authoritative statistics are still
  /// only ever produced by the server's finalize_recorded_route() once
  /// synced (GPS-5+), exactly matching the "client previews, server
  /// decides" principle already used for chat/moderation/XP.
  Future<void> finishRecordingLocally({
    required String ownerId,
    required String routeId,
    required DateTime occurredAt,
  }) {
    return transaction(() async {
      final current = await getRecordedRoute(ownerId: ownerId, id: routeId);
      if (current == null) {
        throw StateError('recorded route $routeId not found for this owner');
      }
      if (current.status != RecordedRouteStatus.recording &&
          current.status != RecordedRouteStatus.paused) {
        throw InvalidRouteStatusTransition(
            current.status, RecordedRouteStatus.completed);
      }

      await _appendEventUnguarded(
        recordedRouteId: routeId,
        ownerId: ownerId,
        eventType: RouteEventType.finish,
        occurredAt: occurredAt,
      );
      await (update(localRecordedRoutes)
            ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(routeId)))
          .write(LocalRecordedRoutesCompanion(
        status: const Value(RecordedRouteStatus.completed),
        endedAt: Value(occurredAt),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    });
  }

  // ---------------------------------------------------------------------
  // Route points
  // ---------------------------------------------------------------------

  /// Appends one GPS sample, computing the next `seq` for this route
  /// (current max + 1, or 1 for the first point) inside a transaction so
  /// two near-simultaneous calls can never race onto the same seq. Every
  /// sample must be persistable independently of network state — this
  /// method never touches the network or sync cursor.
  Future<void> appendRoutePoint({
    required String ownerId,
    required String recordedRouteId,
    required double latitude,
    required double longitude,
    double? altitude,
    double? horizontalAccuracy,
    double? verticalAccuracy,
    double? speed,
    double? speedAccuracy,
    double? heading,
    double? headingAccuracy,
    required DateTime recordedAt,
    String? provider,
  }) {
    return transaction(() async {
      final seq = await _nextSeq(localRoutePoints, recordedRouteId);
      await into(localRoutePoints).insert(
        LocalRoutePointsCompanion.insert(
          recordedRouteId: recordedRouteId,
          seq: seq,
          ownerId: ownerId,
          latitude: latitude,
          longitude: longitude,
          altitude: Value(altitude),
          horizontalAccuracy: Value(horizontalAccuracy),
          verticalAccuracy: Value(verticalAccuracy),
          speed: Value(speed),
          speedAccuracy: Value(speedAccuracy),
          heading: Value(heading),
          headingAccuracy: Value(headingAccuracy),
          recordedAt: recordedAt,
          provider: Value(provider),
        ),
      );
    });
  }

  /// Oldest-first, matching the same convention ChatLocalDatabase uses
  /// for message history.
  Future<List<LocalRoutePoint>> getRoutePoints({
    required String ownerId,
    required String recordedRouteId,
  }) async {
    final rows = await (select(localRoutePoints)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.recordedRouteId.equals(recordedRouteId))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
    return rows.map(_normalizePoint).toList(growable: false);
  }

  Stream<List<LocalRoutePoint>> watchRoutePoints({
    required String ownerId,
    required String recordedRouteId,
  }) {
    final query = select(localRoutePoints)
      ..where((t) =>
          t.ownerId.equals(ownerId) & t.recordedRouteId.equals(recordedRouteId))
      ..orderBy([(t) => OrderingTerm.asc(t.seq)]);
    return query
        .watch()
        .map((rows) => rows.map(_normalizePoint).toList(growable: false));
  }

  /// Points with seq greater than this route's current
  /// `lastSyncedPointSeq` (0 if never synced), oldest-first, capped at
  /// [batchSize] — ready to hand directly to a batch upload call. Never
  /// loads the whole track: only this bounded window.
  Future<List<LocalRoutePoint>> getUnsyncedPointBatch({
    required String ownerId,
    required String recordedRouteId,
    int batchSize = 500,
  }) async {
    final route = await getRecordedRoute(ownerId: ownerId, id: recordedRouteId);
    final since = route?.lastSyncedPointSeq ?? 0;
    final rows = await (select(localRoutePoints)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.recordedRouteId.equals(recordedRouteId) &
              t.seq.isBiggerThanValue(since))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)])
          ..limit(batchSize))
        .get();
    return rows.map(_normalizePoint).toList(growable: false);
  }

  /// Advances the point sync cursor. Monotonic-only: a call with a value
  /// smaller than the current cursor is a no-op, never regresses it.
  Future<void> advancePointSyncCursor({
    required String ownerId,
    required String recordedRouteId,
    required int newLastSyncedSeq,
  }) async {
    final route = await getRecordedRoute(ownerId: ownerId, id: recordedRouteId);
    if (route == null) return;
    if (route.lastSyncedPointSeq != null &&
        newLastSyncedSeq <= route.lastSyncedPointSeq!) {
      return;
    }
    await (update(localRecordedRoutes)
          ..where(
              (t) => t.ownerId.equals(ownerId) & t.id.equals(recordedRouteId)))
        .write(LocalRecordedRoutesCompanion(
      lastSyncedPointSeq: Value(newLastSyncedSeq),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  // ---------------------------------------------------------------------
  // Route events
  // ---------------------------------------------------------------------

  /// Direct append, no status guard — used internally by the atomic
  /// pause/resume/discard/finish methods above, which are the only
  /// intended callers for anything other than a plain 'start' at
  /// creation. Not exposed as public API by that name; see
  /// [appendRouteEvent] for the public, general-purpose entry point.
  Future<void> _appendEventUnguarded({
    required String recordedRouteId,
    required String ownerId,
    required String eventType,
    required DateTime occurredAt,
  }) async {
    final seq = await _nextSeq(localRouteEvents, recordedRouteId);
    await into(localRouteEvents).insert(
      LocalRouteEventsCompanion.insert(
        recordedRouteId: recordedRouteId,
        seq: seq,
        ownerId: ownerId,
        eventType: eventType,
        occurredAt: occurredAt,
      ),
    );
  }

  /// Public, general-purpose event append (e.g. for a future auto-pause
  /// event that isn't paired with a status change the way manual pause/
  /// resume are). No update/delete method exists for individual events —
  /// the log is append-only by design, matching the server table.
  Future<void> appendRouteEvent({
    required String ownerId,
    required String recordedRouteId,
    required String eventType,
    required DateTime occurredAt,
  }) {
    return _appendEventUnguarded(
      recordedRouteId: recordedRouteId,
      ownerId: ownerId,
      eventType: eventType,
      occurredAt: occurredAt,
    );
  }

  Future<List<LocalRouteEvent>> getRouteEvents({
    required String ownerId,
    required String recordedRouteId,
  }) async {
    final rows = await (select(localRouteEvents)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.recordedRouteId.equals(recordedRouteId))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
    return rows.map(_normalizeEvent).toList(growable: false);
  }

  Future<List<LocalRouteEvent>> getUnsyncedEventBatch({
    required String ownerId,
    required String recordedRouteId,
    int batchSize = 500,
  }) async {
    final route = await getRecordedRoute(ownerId: ownerId, id: recordedRouteId);
    final since = route?.lastSyncedEventSeq ?? 0;
    final rows = await (select(localRouteEvents)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.recordedRouteId.equals(recordedRouteId) &
              t.seq.isBiggerThanValue(since))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)])
          ..limit(batchSize))
        .get();
    return rows.map(_normalizeEvent).toList(growable: false);
  }

  Future<void> advanceEventSyncCursor({
    required String ownerId,
    required String recordedRouteId,
    required int newLastSyncedSeq,
  }) async {
    final route = await getRecordedRoute(ownerId: ownerId, id: recordedRouteId);
    if (route == null) return;
    if (route.lastSyncedEventSeq != null &&
        newLastSyncedSeq <= route.lastSyncedEventSeq!) {
      return;
    }
    await (update(localRecordedRoutes)
          ..where(
              (t) => t.ownerId.equals(ownerId) & t.id.equals(recordedRouteId)))
        .write(LocalRecordedRoutesCompanion(
      lastSyncedEventSeq: Value(newLastSyncedSeq),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<int> _nextSeq(TableInfo table, String recordedRouteId) async {
    if (identical(table, localRoutePoints)) {
      final maxSeq = await (selectOnly(localRoutePoints)
            ..addColumns([localRoutePoints.seq.max()])
            ..where(localRoutePoints.recordedRouteId.equals(recordedRouteId)))
          .map((row) => row.read(localRoutePoints.seq.max()))
          .getSingleOrNull();
      return (maxSeq ?? 0) + 1;
    }
    final maxSeq = await (selectOnly(localRouteEvents)
          ..addColumns([localRouteEvents.seq.max()])
          ..where(localRouteEvents.recordedRouteId.equals(recordedRouteId)))
        .map((row) => row.read(localRouteEvents.seq.max()))
        .getSingleOrNull();
    return (maxSeq ?? 0) + 1;
  }

  // ---------------------------------------------------------------------
  // Waypoints
  // ---------------------------------------------------------------------

  /// No status check: a waypoint may be added whether the parent route
  /// is 'recording' or 'paused' — this method doesn't even look at the
  /// route's status, by design (see [LocalWaypoints]'s class doc).
  Future<void> addWaypoint({
    required String id,
    required String ownerId,
    required String recordedRouteId,
    required String waypointType,
    String? title,
    String? note,
    required double latitude,
    required double longitude,
    double? altitude,
    required DateTime recordedAt,
    String? photoRef,
  }) async {
    final now = DateTime.now().toUtc();
    await into(localWaypoints).insert(
      LocalWaypointsCompanion.insert(
        id: id,
        recordedRouteId: recordedRouteId,
        ownerId: ownerId,
        waypointType: waypointType,
        title: Value(title),
        note: Value(note),
        latitude: latitude,
        longitude: longitude,
        altitude: Value(altitude),
        recordedAt: recordedAt,
        photoRef: Value(photoRef),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Editing title/note/type resets syncStatus back to 'pending' so a
  /// previously-synced waypoint is correctly re-queued — the whole
  /// reason this table uses per-row sync state instead of a cursor.
  ///
  /// Throws [WaypointTombstonedException] if the waypoint is currently a
  /// deletion tombstone ([WaypointSyncStatus.pendingDelete]) — a
  /// tombstone represents "this must be deleted," not a live waypoint,
  /// so editing it (which would silently resurrect it as a normal
  /// 'pending' waypoint) is rejected outright.
  Future<void> updateWaypointMetadata({
    required String ownerId,
    required String id,
    Value<String?> title = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<String> waypointType = const Value.absent(),
  }) async {
    final row = await (select(localWaypoints)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('waypoint $id not found for this owner');
    }
    if (row.syncStatus == WaypointSyncStatus.pendingDelete) {
      throw WaypointTombstonedException(id);
    }

    await (update(localWaypoints)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .write(LocalWaypointsCompanion(
      title: title,
      note: note,
      waypointType: waypointType,
      syncStatus: const Value(WaypointSyncStatus.pending),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  /// Sync-safe deletion.
  ///
  /// A waypoint that has never been confirmed synced
  /// ([WaypointSyncStatus.pending]) is physically removed: the server
  /// never had it, so there is nothing to reconcile.
  ///
  /// A waypoint that IS or MIGHT BE synced ([WaypointSyncStatus.synced]
  /// or [WaypointSyncStatus.failed] — 'failed' is treated as "may have
  /// reached the server even though we never got confirmation," the
  /// same idempotent-retry caution already applied to
  /// finalize_recorded_route in GPS-1) is instead turned into a
  /// tombstone: its syncStatus becomes [WaypointSyncStatus.pendingDelete]
  /// and the row is preserved, so a future sync engine can still push
  /// the deletion to the server.
  ///
  /// Normal reads ([getWaypoints]/[watchWaypoints]) never return a
  /// tombstoned row. Use [getTombstonedWaypoints] to find one, and
  /// [purgeAcknowledgedTombstone] to physically remove it once the
  /// server has confirmed the deletion — never call that from general
  /// app code before that confirmation exists.
  Future<void> deleteWaypoint(
      {required String ownerId, required String id}) async {
    final row = await (select(localWaypoints)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;

    if (row.syncStatus == WaypointSyncStatus.pending) {
      await (delete(localWaypoints)
            ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
          .go();
      return;
    }

    await (update(localWaypoints)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .write(LocalWaypointsCompanion(
      syncStatus: const Value(WaypointSyncStatus.pendingDelete),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  /// Waypoints visible to normal UI use — a tombstone
  /// ([WaypointSyncStatus.pendingDelete]) is never returned here.
  Future<List<LocalWaypoint>> getWaypoints({
    required String ownerId,
    required String recordedRouteId,
  }) async {
    final rows = await (select(localWaypoints)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.recordedRouteId.equals(recordedRouteId) &
              t.syncStatus.equals(WaypointSyncStatus.pendingDelete).not())
          ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
        .get();
    return rows.map(_normalizeWaypoint).toList(growable: false);
  }

  /// Reactive version of [getWaypoints] — same tombstone exclusion.
  Stream<List<LocalWaypoint>> watchWaypoints({
    required String ownerId,
    required String recordedRouteId,
  }) {
    final query = select(localWaypoints)
      ..where((t) =>
          t.ownerId.equals(ownerId) &
          t.recordedRouteId.equals(recordedRouteId) &
          t.syncStatus.equals(WaypointSyncStatus.pendingDelete).not())
      ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]);
    return query
        .watch()
        .map((rows) => rows.map(_normalizeWaypoint).toList(growable: false));
  }

  /// Waypoints needing a create/update push — a sync-oriented query;
  /// deliberately excludes tombstones (they need a *delete* push
  /// instead, see [getTombstonedWaypoints]).
  Future<List<LocalWaypoint>> getUnsyncedWaypoints({
    required String ownerId,
    required String recordedRouteId,
  }) async {
    final rows = await (select(localWaypoints)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.recordedRouteId.equals(recordedRouteId) &
              t.syncStatus.equals(WaypointSyncStatus.pending)))
        .get();
    return rows.map(_normalizeWaypoint).toList(growable: false);
  }

  /// Deletion tombstones needing a delete push to the server — the
  /// sync-oriented counterpart to [getWaypoints]/[watchWaypoints]
  /// deliberately hiding them from normal UI use.
  Future<List<LocalWaypoint>> getTombstonedWaypoints({
    required String ownerId,
    required String recordedRouteId,
  }) async {
    final rows = await (select(localWaypoints)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.recordedRouteId.equals(recordedRouteId) &
              t.syncStatus.equals(WaypointSyncStatus.pendingDelete)))
        .get();
    return rows.map(_normalizeWaypoint).toList(growable: false);
  }

  /// Marks a waypoint as successfully synced. Throws if called on a
  /// tombstone — a sync engine acknowledging a *deletion* must call
  /// [purgeAcknowledgedTombstone] instead, never this method, which
  /// would otherwise silently resurrect a pending-delete row as a live
  /// 'synced' waypoint.
  Future<void> markWaypointSynced(
      {required String ownerId, required String id}) async {
    final row = await (select(localWaypoints)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    if (row.syncStatus == WaypointSyncStatus.pendingDelete) {
      throw StateError(
          'markWaypointSynced called on tombstoned waypoint $id — use purgeAcknowledgedTombstone instead');
    }
    await (update(localWaypoints)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .write(const LocalWaypointsCompanion(
            syncStatus: Value(WaypointSyncStatus.synced)));
  }

  /// Physically removes a tombstoned waypoint row. Must only be called
  /// by a future sync engine after the server has confirmed the
  /// corresponding delete succeeded — never from general app code, and
  /// never as a substitute for [deleteWaypoint]. Throws if the row
  /// isn't actually a tombstone, to catch a caller bug rather than
  /// silently deleting a live waypoint.
  Future<void> purgeAcknowledgedTombstone(
      {required String ownerId, required String id}) async {
    final row = await (select(localWaypoints)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    if (row.syncStatus != WaypointSyncStatus.pendingDelete) {
      throw StateError(
          'purgeAcknowledgedTombstone called on a non-tombstoned waypoint $id (syncStatus=${row.syncStatus})');
    }
    await (delete(localWaypoints)
          ..where((t) => t.ownerId.equals(ownerId) & t.id.equals(id)))
        .go();
  }
}
