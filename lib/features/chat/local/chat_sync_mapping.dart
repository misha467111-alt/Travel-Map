import 'package:drift/drift.dart';

import 'chat_local_database.dart';

/// Mirrors one row returned by the server's `travel_conversation_messages`
/// or `travel_conversation_catchup` RPCs. Deliberately plain data — no
/// Supabase types — so the mapping logic below can be unit-tested without
/// a network call.
class ChatServerMessageRow {
  const ChatServerMessageRow({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.hiddenForMe,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String? body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final bool hiddenForMe;
}

/// What a server row implies for the local cache.
sealed class ChatCacheAction {
  const ChatCacheAction();
}

class ChatCacheUpsert extends ChatCacheAction {
  const ChatCacheUpsert(this.companion);
  final LocalMessagesCompanion companion;
}

class ChatCacheRemove extends ChatCacheAction {
  const ChatCacheRemove(this.messageId);
  final String messageId;
}

/// Pure mapping from one server row to the local cache action it implies:
///
/// - `hiddenForMe == true` → remove locally. Hidden-for-me rows are never
///   stored as messages, and their `body` (already null from the server)
///   must never be treated as content.
/// - `deletedAt != null` → remove locally. Phase B intentionally does not
///   keep a "message deleted" tombstone placeholder in the cache — the
///   conversation's next full history fetch (which already excludes
///   deleted rows server-side) is the source of truth for what exists.
/// - otherwise → upsert.
ChatCacheAction mapServerRowToCacheAction({
  required ChatServerMessageRow row,
  required String accountUserId,
  required String conversationKey,
}) {
  if (row.hiddenForMe || row.deletedAt != null) {
    return ChatCacheRemove(row.id);
  }
  return ChatCacheUpsert(
    LocalMessagesCompanion.insert(
      id: row.id,
      accountUserId: accountUserId,
      conversationKey: conversationKey,
      senderId: row.senderId,
      receiverId: row.receiverId,
      body: Value(row.body),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    ),
  );
}

/// Applies [mapServerRowToCacheAction]'s decision to the local database.
/// Still no Supabase call here — the caller (Phase C) is responsible for
/// fetching rows; this only ever touches the local cache.
Future<void> applyServerRowToCache({
  required ChatLocalDatabase db,
  required ChatServerMessageRow row,
  required String accountUserId,
  required String conversationKey,
}) {
  final action = mapServerRowToCacheAction(
    row: row,
    accountUserId: accountUserId,
    conversationKey: conversationKey,
  );
  return switch (action) {
    ChatCacheUpsert(:final companion) => db.upsertMessage(companion),
    ChatCacheRemove(:final messageId) =>
      db.deleteMessage(accountUserId: accountUserId, messageId: messageId),
  };
}
