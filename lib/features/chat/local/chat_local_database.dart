import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'chat_local_database.g.dart';

/// Cached copy of one server message, scoped to the account that cached
/// it.
///
/// Primary key is (accountUserId, id) rather than just id: message ids
/// are globally unique on the server, but the same physical device can
/// legitimately be used by more than one account over time (e.g. two
/// friends who message each other both use the same shared/family
/// device). In that case the exact same server message id must be
/// cacheable independently under each account without one account's
/// upsert ever touching the other's row — a bare PRIMARY KEY(id) would
/// not guarantee that; PRIMARY KEY(accountUserId, id) does, structurally,
/// regardless of whether every call site remembers to add a WHERE
/// clause.
@TableIndex(
  name: 'local_messages_conversation_idx',
  columns: {#accountUserId, #conversationKey, #createdAt, #id},
)
class LocalMessages extends Table {
  TextColumn get id => text()();
  TextColumn get accountUserId => text()();
  TextColumn get conversationKey => text()();
  TextColumn get senderId => text()();
  TextColumn get receiverId => text()();
  TextColumn get body => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {accountUserId, id};
}

/// Per-account, per-conversation reconnect/catch-up cursor
/// (`travel_conversation_catchup`'s `(change_at, change_id)` keyset).
/// Both fields must be written together — see [ChatLocalDatabase.setSyncCursor].
class ChatSyncState extends Table {
  TextColumn get accountUserId => text()();
  TextColumn get conversationKey => text()();
  DateTimeColumn get lastChangeAt => dateTime().nullable()();
  TextColumn get lastChangeId => text().nullable()();

  @override
  Set<Column> get primaryKey => {accountUserId, conversationKey};
}

/// Result of [ChatLocalDatabase.getSyncCursor]. Either both fields are
/// null (no prior sync for this conversation) or both are non-null —
/// never a mix, enforced by [ChatLocalDatabase.setSyncCursor].
typedef ChatSyncCursor = ({DateTime? changeAt, String? changeId});

@DriftDatabase(tables: [LocalMessages, ChatSyncState])
class ChatLocalDatabase extends _$ChatLocalDatabase {
  ChatLocalDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  /// Test-only convenience constructor for an in-memory database. Not
  /// used by the app itself; the default constructor above (used in
  /// production, once Phase C wires it up) opens a real on-disk database
  /// via drift_flutter's platform-aware `driftDatabase()` helper, which
  /// already places it in the app's private storage directory — no
  /// manual path_provider wiring required here.
  ChatLocalDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'chat_local');
  }

  /// Drift/sqlite3 round-trips the correct instant for a DateTime column,
  /// but reads it back with `isUtc: false` (local) regardless of what was
  /// written — confirmed empirically, not assumed. Dart's `DateTime==`
  /// is sensitive to that flag even when the underlying instant is
  /// identical, and `.toIso8601String()` on a mislabeled-local value
  /// would serialize without a `Z`/offset — exactly the kind of bug that
  /// would silently corrupt a server cursor comparison in Phase C. Every
  /// DateTime this class returns is normalized back to UTC here, once,
  /// so callers never have to think about it.
  static DateTime _utc(DateTime value) => value.toUtc();
  static DateTime? _utcOrNull(DateTime? value) => value?.toUtc();

  LocalMessage _normalizeRow(LocalMessage row) => row.copyWith(
        createdAt: _utc(row.createdAt),
        updatedAt: _utc(row.updatedAt),
        deletedAt: Value(_utcOrNull(row.deletedAt)),
      );

  // ---------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------

  Future<void> upsertMessage(LocalMessagesCompanion entry) {
    return into(localMessages).insertOnConflictUpdate(entry);
  }

  Future<void> upsertMessages(List<LocalMessagesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) => b.insertAllOnConflictUpdate(localMessages, entries));
  }

  /// Most recent [limit] cached messages for a conversation, returned
  /// oldest-first (ready to feed directly into a top-to-bottom chat
  /// ListView). Internally queried newest-first (so the index/LIMIT
  /// combination stays efficient) and reversed before returning.
  Future<List<LocalMessage>> getRecentMessages({
    required String accountUserId,
    required String conversationKey,
    required int limit,
  }) async {
    final query = select(localMessages)
      ..where((t) =>
          t.accountUserId.equals(accountUserId) &
          t.conversationKey.equals(conversationKey))
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.reversed.map(_normalizeRow).toList(growable: false);
  }

  /// Keyset pagination for scrolling further back in history. `before`
  /// is the oldest row currently shown (its createdAt/id). Returned
  /// oldest-first, same convention as [getRecentMessages].
  Future<List<LocalMessage>> getOlderMessages({
    required String accountUserId,
    required String conversationKey,
    required DateTime beforeCreatedAt,
    required String beforeId,
    required int limit,
  }) async {
    final query = select(localMessages)
      ..where((t) =>
          t.accountUserId.equals(accountUserId) &
          t.conversationKey.equals(conversationKey) &
          (t.createdAt.isSmallerThanValue(beforeCreatedAt) |
              (t.createdAt.equals(beforeCreatedAt) &
                  t.id.isSmallerThanValue(beforeId))))
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.reversed.map(_normalizeRow).toList(growable: false);
  }

  /// Reactive version of [getRecentMessages]: emits the current window
  /// immediately on subscription (this is what makes "cache-first"
  /// possible with zero separate one-shot read), then re-emits whenever
  /// any write touches this account+conversation's rows — whether from
  /// history merge, catch-up, or realtime forwarding. UI can watch this
  /// directly as its sole source of truth for message content.
  Stream<List<LocalMessage>> watchRecentMessages({
    required String accountUserId,
    required String conversationKey,
    required int limit,
  }) {
    final query = select(localMessages)
      ..where((t) =>
          t.accountUserId.equals(accountUserId) &
          t.conversationKey.equals(conversationKey))
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    return query.watch().map(
        (rows) => rows.reversed.map(_normalizeRow).toList(growable: false));
  }

  Future<void> deleteMessage({
    required String accountUserId,
    required String messageId,
  }) {
    return (delete(localMessages)
          ..where((t) =>
              t.accountUserId.equals(accountUserId) & t.id.equals(messageId)))
        .go();
  }

  Future<void> deleteConversationCache({
    required String accountUserId,
    required String conversationKey,
  }) {
    return (delete(localMessages)
          ..where((t) =>
              t.accountUserId.equals(accountUserId) &
              t.conversationKey.equals(conversationKey)))
        .go();
  }

  /// Wipes every cached message and sync cursor belonging to one
  /// account. Not wired to the app's logout flow yet (Phase C) — exposed
  /// here so that wiring is a one-line call when that happens.
  Future<void> clearAccountCache(String accountUserId) async {
    await (delete(localMessages)
          ..where((t) => t.accountUserId.equals(accountUserId)))
        .go();
    await (delete(chatSyncState)
          ..where((t) => t.accountUserId.equals(accountUserId)))
        .go();
  }

  /// Keeps only the newest [maxMessages] cached rows for one
  /// account+conversation, ordered by (createdAt desc, id desc). Local
  /// cache only — never touches server data.
  Future<void> cleanupConversation({
    required String accountUserId,
    required String conversationKey,
    int maxMessages = 300,
  }) async {
    final keepIds = await (select(localMessages)
          ..where((t) =>
              t.accountUserId.equals(accountUserId) &
              t.conversationKey.equals(conversationKey))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(maxMessages))
        .map((row) => row.id)
        .get();
    if (keepIds.isEmpty) return;
    await (delete(localMessages)
          ..where((t) =>
              t.accountUserId.equals(accountUserId) &
              t.conversationKey.equals(conversationKey) &
              t.id.isNotIn(keepIds)))
        .go();
  }

  // ---------------------------------------------------------------------
  // Sync cursor
  // ---------------------------------------------------------------------

  Future<ChatSyncCursor> getSyncCursor({
    required String accountUserId,
    required String conversationKey,
  }) async {
    final row = await (select(chatSyncState)
          ..where((t) =>
              t.accountUserId.equals(accountUserId) &
              t.conversationKey.equals(conversationKey)))
        .getSingleOrNull();
    if (row == null) return (changeAt: null, changeId: null);
    return (changeAt: _utcOrNull(row.lastChangeAt), changeId: row.lastChangeId);
  }

  /// Writes the cursor atomically as a pair: both null (no known sync
  /// point) or both non-null. Never a mix — enforced here, not left to
  /// caller discipline.
  Future<void> setSyncCursor({
    required String accountUserId,
    required String conversationKey,
    required DateTime? changeAt,
    required String? changeId,
  }) {
    if ((changeAt == null) != (changeId == null)) {
      throw ArgumentError(
        'changeAt and changeId must both be null or both be non-null '
        '(got changeAt=$changeAt, changeId=$changeId)',
      );
    }
    return into(chatSyncState).insertOnConflictUpdate(
      ChatSyncStateCompanion.insert(
        accountUserId: accountUserId,
        conversationKey: conversationKey,
        lastChangeAt: Value(changeAt),
        lastChangeId: Value(changeId),
      ),
    );
  }
}
