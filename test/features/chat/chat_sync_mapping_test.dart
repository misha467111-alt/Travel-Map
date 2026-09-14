import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/local/chat_local_database.dart';
import 'package:flutter_application_1/features/chat/local/chat_sync_mapping.dart';

ChatServerMessageRow _row({
  String id = 'm1',
  String senderId = 'me',
  String receiverId = 'friend',
  String? body = 'hello',
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
  bool hiddenForMe = false,
}) {
  return ChatServerMessageRow(
    id: id,
    senderId: senderId,
    receiverId: receiverId,
    body: body,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1, 10),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1, 10),
    deletedAt: deletedAt,
    hiddenForMe: hiddenForMe,
  );
}

void main() {
  group('mapServerRowToCacheAction (pure)', () {
    test('hidden-for-me row maps to a remove action', () {
      final action = mapServerRowToCacheAction(
        row: _row(hiddenForMe: true, body: null),
        accountUserId: 'me',
        conversationKey: 'k',
      );
      expect(action, isA<ChatCacheRemove>());
      expect((action as ChatCacheRemove).messageId, 'm1');
    });

    test('deleted-for-everyone row maps to a remove action', () {
      final action = mapServerRowToCacheAction(
        row: _row(deletedAt: DateTime.utc(2026, 1, 1, 11), body: null),
        accountUserId: 'me',
        conversationKey: 'k',
      );
      expect(action, isA<ChatCacheRemove>());
    });

    test('a normal row maps to an upsert action carrying the right fields', () {
      final action = mapServerRowToCacheAction(
        row: _row(),
        accountUserId: 'me',
        conversationKey: 'k',
      );
      expect(action, isA<ChatCacheUpsert>());
      final companion = (action as ChatCacheUpsert).companion;
      expect(companion.id.value, 'm1');
      expect(companion.accountUserId.value, 'me');
      expect(companion.conversationKey.value, 'k');
      expect(companion.body.value, 'hello');
    });
  });

  group('applyServerRowToCache (against a real in-memory database)', () {
    late ChatLocalDatabase db;

    setUp(() {
      db = ChatLocalDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('a normal row is upserted into the cache', () async {
      await applyServerRowToCache(
        db: db,
        row: _row(),
        accountUserId: 'me',
        conversationKey: 'k',
      );

      final rows = await db.getRecentMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        limit: 10,
      );
      expect(rows, hasLength(1));
      expect(rows.single.body, 'hello');
    });

    test('a hidden-for-me row removes a previously cached message', () async {
      await applyServerRowToCache(
        db: db,
        row: _row(),
        accountUserId: 'me',
        conversationKey: 'k',
      );

      await applyServerRowToCache(
        db: db,
        row: _row(hiddenForMe: true, body: null),
        accountUserId: 'me',
        conversationKey: 'k',
      );

      final rows = await db.getRecentMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        limit: 10,
      );
      expect(rows, isEmpty);
    });

    test(
        'a deleted-for-everyone row (realtime UPDATE tombstone) removes '
        'the cached message', () async {
      await applyServerRowToCache(
        db: db,
        row: _row(),
        accountUserId: 'me',
        conversationKey: 'k',
      );

      await applyServerRowToCache(
        db: db,
        row: _row(
          deletedAt: DateTime.utc(2026, 1, 1, 12),
          updatedAt: DateTime.utc(2026, 1, 1, 12),
          body: null,
        ),
        accountUserId: 'me',
        conversationKey: 'k',
      );

      final rows = await db.getRecentMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        limit: 10,
      );
      expect(rows, isEmpty);
    });

    test(
        'applying the exact same server row twice does not duplicate the '
        'cached message (upsert is idempotent)', () async {
      final row = _row();
      await applyServerRowToCache(
        db: db,
        row: row,
        accountUserId: 'me',
        conversationKey: 'k',
      );
      await applyServerRowToCache(
        db: db,
        row: row,
        accountUserId: 'me',
        conversationKey: 'k',
      );

      final rows = await db.getRecentMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        limit: 10,
      );
      expect(rows, hasLength(1));
    });

    test(
        'a realtime UPDATE with the same id refreshes the existing row '
        'in place instead of adding a second one', () async {
      await applyServerRowToCache(
        db: db,
        row: _row(body: 'original'),
        accountUserId: 'me',
        conversationKey: 'k',
      );
      await applyServerRowToCache(
        db: db,
        row: _row(
          body: 'edited',
          updatedAt: DateTime.utc(2026, 1, 1, 10, 1),
        ),
        accountUserId: 'me',
        conversationKey: 'k',
      );

      final rows = await db.getRecentMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        limit: 10,
      );
      expect(rows, hasLength(1));
      expect(rows.single.body, 'edited');
    });
  });
}
