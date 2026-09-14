import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/local/chat_local_database.dart';
import 'package:flutter_application_1/features/chat/local/chat_sync_mapping.dart';

void main() {
  const accountA = 'account-a';
  const convo = 'account-a:friend';
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

  ChatServerMessageRow normalRow({String id = 'm1'}) => ChatServerMessageRow(
        id: id,
        senderId: accountA,
        receiverId: 'friend',
        body: 'hello',
        createdAt: t0,
        updatedAt: t0,
        deletedAt: null,
        hiddenForMe: false,
      );

  test('13. a normal server row maps to an upsert action', () {
    final action = mapServerRowToCacheAction(
      row: normalRow(),
      accountUserId: accountA,
      conversationKey: convo,
    );
    expect(action, isA<ChatCacheUpsert>());
    final upsert = action as ChatCacheUpsert;
    expect(upsert.companion.id.value, 'm1');
  });

  test('11. a deleted-for-everyone row maps to a remove action', () {
    final action = mapServerRowToCacheAction(
      row: ChatServerMessageRow(
        id: 'm2',
        senderId: accountA,
        receiverId: 'friend',
        body: null,
        createdAt: t0,
        updatedAt: t0.add(const Duration(minutes: 5)),
        deletedAt: t0.add(const Duration(minutes: 5)),
        hiddenForMe: false,
      ),
      accountUserId: accountA,
      conversationKey: convo,
    );
    expect(action, isA<ChatCacheRemove>());
    expect((action as ChatCacheRemove).messageId, 'm2');
  });

  test('12. a hidden-for-me row maps to a remove action', () {
    final action = mapServerRowToCacheAction(
      row: ChatServerMessageRow(
        id: 'm3',
        senderId: accountA,
        receiverId: 'friend',
        body: null,
        createdAt: t0,
        updatedAt: t0,
        deletedAt: null,
        hiddenForMe: true,
      ),
      accountUserId: accountA,
      conversationKey: convo,
    );
    expect(action, isA<ChatCacheRemove>());
    expect((action as ChatCacheRemove).messageId, 'm3');
  });

  group('applyServerRowToCache (integration with the local DB)', () {
    late ChatLocalDatabase db;

    setUp(() {
      db = ChatLocalDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('normal row is actually upserted into the cache', () async {
      await applyServerRowToCache(
        db: db,
        row: normalRow(),
        accountUserId: accountA,
        conversationKey: convo,
      );
      final rows = await db.getRecentMessages(
        accountUserId: accountA,
        conversationKey: convo,
        limit: 10,
      );
      expect(rows, hasLength(1));
      expect(rows.single.id, 'm1');
    });

    test('deleted-for-everyone row removes an already-cached message',
        () async {
      await applyServerRowToCache(
        db: db,
        row: normalRow(),
        accountUserId: accountA,
        conversationKey: convo,
      );
      await applyServerRowToCache(
        db: db,
        row: ChatServerMessageRow(
          id: 'm1',
          senderId: accountA,
          receiverId: 'friend',
          body: null,
          createdAt: t0,
          updatedAt: t0.add(const Duration(minutes: 1)),
          deletedAt: t0.add(const Duration(minutes: 1)),
          hiddenForMe: false,
        ),
        accountUserId: accountA,
        conversationKey: convo,
      );

      final rows = await db.getRecentMessages(
        accountUserId: accountA,
        conversationKey: convo,
        limit: 10,
      );
      expect(rows, isEmpty);
    });

    test('hidden-for-me row removes an already-cached message', () async {
      await applyServerRowToCache(
        db: db,
        row: normalRow(),
        accountUserId: accountA,
        conversationKey: convo,
      );
      await applyServerRowToCache(
        db: db,
        row: ChatServerMessageRow(
          id: 'm1',
          senderId: accountA,
          receiverId: 'friend',
          body: null,
          createdAt: t0,
          updatedAt: t0,
          deletedAt: null,
          hiddenForMe: true,
        ),
        accountUserId: accountA,
        conversationKey: convo,
      );

      final rows = await db.getRecentMessages(
        accountUserId: accountA,
        conversationKey: convo,
        limit: 10,
      );
      expect(rows, isEmpty);
    });
  });
}
