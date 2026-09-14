import '../local/chat_sync_mapping.dart';

/// Single trusted place that turns a raw Supabase row (however it
/// arrived — an RPC result or a realtime table row) into the plain
/// [ChatServerMessageRow] the local cache layer understands. Every server
/// timestamp is parsed and normalized to UTC here, once, so nothing
/// downstream has to re-derive or guess a timezone.
class ChatServerMessageMapper {
  const ChatServerMessageMapper._();

  /// `travel_conversation_messages` / `travel_conversation_catchup` RPC
  /// rows: carry `body` and `hidden_for_me` directly.
  static ChatServerMessageRow fromRpcRow(Map<String, dynamic> json) {
    return ChatServerMessageRow(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      body: json['body'] as String?,
      createdAt: _parseUtc(json['created_at'] as String),
      updatedAt: _parseUtc(json['updated_at'] as String),
      deletedAt: _parseUtcOrNull(json['deleted_at'] as String?),
      hiddenForMe: json['hidden_for_me'] as bool? ?? false,
    );
  }

  /// Raw `public.messages` realtime row (from the existing two scoped
  /// `.stream()` subscriptions): the column is `text`, not `body`, and
  /// there is no `hidden_for_me` concept at the raw-table level at all —
  /// delete-for-me propagation deliberately does not flow through
  /// realtime (see catch-up), so this is always `false` here.
  static ChatServerMessageRow fromRealtimeRow(Map<String, dynamic> row) {
    return ChatServerMessageRow(
      id: row['id'] as String,
      senderId: row['sender_id'] as String,
      receiverId: row['receiver_id'] as String,
      body: row['text'] as String?,
      createdAt: _parseUtc(row['timestamp'] as String),
      updatedAt: _parseUtc(row['updated_at'] as String),
      deletedAt: _parseUtcOrNull(row['deleted_at'] as String?),
      hiddenForMe: false,
    );
  }

  /// Only `travel_conversation_catchup` rows carry `change_at` — the
  /// cursor field, kept separate from [ChatServerMessageRow] since that
  /// type is shared with the history RPC, which has no such column.
  static DateTime parseChangeAt(Map<String, dynamic> json) =>
      _parseUtc(json['change_at'] as String);

  static DateTime _parseUtc(String value) => DateTime.parse(value).toUtc();

  static DateTime? _parseUtcOrNull(String? value) =>
      value == null ? null : DateTime.parse(value).toUtc();
}
