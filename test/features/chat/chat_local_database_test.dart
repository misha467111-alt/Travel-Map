import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/local/chat_local_database.dart';

LocalMessagesCompanion _msg({
  required String id,
  String accountUserId = 'me',
  String conversationKey = 'k',
  String senderId = 'me',
  String receiverId = 'friend',
  String? body,
  required DateTime createdAt,
}) {
  return LocalMessagesCompanion.insert(
    id: id,
    accountUserId: accountUserId,
    conversationKey: conversationKey,
    senderId: senderId,
    receiverId: receiverId,
    body: Value(body ?? 'text-$id'),
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

void main() {
  late ChatLocalDatabase db;

  setUp(() {
    db = ChatLocalDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('getRecentMessages', () {
    test('returns messages oldest-first regardless of insert order', () async {
      await db.upsertMessages([
        _msg(id: 'm2', createdAt: DateTime.utc(2026, 1, 1, 10, 1)),
        _msg(id: 'm1', createdAt: DateTime.utc(2026, 1, 1, 10, 0)),
        _msg(id: 'm3', createdAt: DateTime.utc(2026, 1, 1, 10, 2)),
      ]);

      final rows = await db.getRecentMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        limit: 10,
      );
      expect(rows.map((r) => r.id), ['m1', 'm2', 'm3']);
    });
  });

  group('watchRecentMessages (cache-first reactivity)', () {
    test('emits the current cache state immediately on subscription', () async {
      await db.upsertMessage(
        _msg(id: 'm1', createdAt: DateTime.utc(2026, 1, 1, 10)),
      );

      final first = await db
          .watchRecentMessages(
              accountUserId: 'me', conversationKey: 'k', limit: 10)
          .first;
      expect(first.map((r) => r.id), ['m1']);
    });

    test('re-emits when a later write touches the same conversation', () async {
      final emissions = <int>[];
      final sub = db
          .watchRecentMessages(
              accountUserId: 'me', conversationKey: 'k', limit: 10)
          .listen((rows) => emissions.add(rows.length));

      await pumpEventQueue();
      await db.upsertMessage(
        _msg(id: 'm1', createdAt: DateTime.utc(2026, 1, 1, 10)),
      );
      await pumpEventQueue();

      expect(emissions, [0, 1]);
      await sub.cancel();
    });
  });

  group('getOlderMessages (keyset pagination)', () {
    test(
        'paging with the same cursor twice returns the same page, so a '
        'caller merging pages by upsert never duplicates rows', () async {
      await db.upsertMessages([
        for (var i = 1; i <= 5; i++)
          _msg(id: 'm$i', createdAt: DateTime.utc(2026, 1, 1, 10, i)),
      ]);

      final page1 = await db.getOlderMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        beforeCreatedAt: DateTime.utc(2026, 1, 1, 10, 4),
        beforeId: 'm4',
        limit: 10,
      );
      final page2 = await db.getOlderMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        beforeCreatedAt: DateTime.utc(2026, 1, 1, 10, 4),
        beforeId: 'm4',
        limit: 10,
      );

      expect(page1.map((r) => r.id), page2.map((r) => r.id));
      expect(page1.map((r) => r.id), ['m1', 'm2', 'm3']);
    });
  });

  group('account isolation', () {
    test(
        'the same message id cached under two different accounts never '
        'collides or leaks across accounts', () async {
      await db.upsertMessage(_msg(
        id: 'shared-id',
        accountUserId: 'accountA',
        body: 'A copy',
        createdAt: DateTime.utc(2026, 1, 1),
      ));
      await db.upsertMessage(_msg(
        id: 'shared-id',
        accountUserId: 'accountB',
        body: 'B copy',
        createdAt: DateTime.utc(2026, 1, 1),
      ));

      final aRows = await db.getRecentMessages(
        accountUserId: 'accountA',
        conversationKey: 'k',
        limit: 10,
      );
      final bRows = await db.getRecentMessages(
        accountUserId: 'accountB',
        conversationKey: 'k',
        limit: 10,
      );

      expect(aRows.single.body, 'A copy');
      expect(bRows.single.body, 'B copy');
    });
  });

  group('cleanupConversation', () {
    test('trims cached rows to maxMessages, keeping the newest', () async {
      await db.upsertMessages([
        for (var i = 1; i <= 5; i++)
          _msg(id: 'm$i', createdAt: DateTime.utc(2026, 1, 1, 10, i)),
      ]);

      await db.cleanupConversation(
        accountUserId: 'me',
        conversationKey: 'k',
        maxMessages: 3,
      );

      final rows = await db.getRecentMessages(
        accountUserId: 'me',
        conversationKey: 'k',
        limit: 10,
      );
      expect(rows.map((r) => r.id), ['m3', 'm4', 'm5']);
    });
  });

  group('clearAccountCache (logout)', () {
    test(
        'wipes messages and sync cursor for one account without touching '
        'another account cached on the same device', () async {
      await db.upsertMessage(_msg(
        id: 'm1',
        accountUserId: 'accountA',
        createdAt: DateTime.utc(2026, 1, 1),
      ));
      await db.upsertMessage(_msg(
        id: 'm1',
        accountUserId: 'accountB',
        createdAt: DateTime.utc(2026, 1, 1),
      ));
      await db.setSyncCursor(
        accountUserId: 'accountA',
        conversationKey: 'k',
        changeAt: DateTime.utc(2026, 1, 1),
        changeId: 'm1',
      );
      await db.setSyncCursor(
        accountUserId: 'accountB',
        conversationKey: 'k',
        changeAt: DateTime.utc(2026, 1, 1),
        changeId: 'm1',
      );

      await db.clearAccountCache('accountA');

      final aRows = await db.getRecentMessages(
        accountUserId: 'accountA',
        conversationKey: 'k',
        limit: 10,
      );
      final bRows = await db.getRecentMessages(
        accountUserId: 'accountB',
        conversationKey: 'k',
        limit: 10,
      );
      final aCursor = await db.getSyncCursor(
        accountUserId: 'accountA',
        conversationKey: 'k',
      );
      final bCursor = await db.getSyncCursor(
        accountUserId: 'accountB',
        conversationKey: 'k',
      );

      expect(aRows, isEmpty);
      expect(bRows, hasLength(1));
      expect(aCursor.changeAt, isNull);
      expect(bCursor.changeAt, isNotNull);
    });
  });

  group('sync cursor', () {
    test('round-trips changeAt/changeId and normalizes back to UTC', () async {
      await db.setSyncCursor(
        accountUserId: 'me',
        conversationKey: 'k',
        changeAt: DateTime.utc(2026, 1, 1, 10),
        changeId: 'm1',
      );

      final cursor =
          await db.getSyncCursor(accountUserId: 'me', conversationKey: 'k');
      expect(cursor.changeAt, DateTime.utc(2026, 1, 1, 10));
      expect(cursor.changeAt!.isUtc, isTrue);
      expect(cursor.changeId, 'm1');
    });

    test('a later setSyncCursor call advances the stored cursor', () async {
      await db.setSyncCursor(
        accountUserId: 'me',
        conversationKey: 'k',
        changeAt: DateTime.utc(2026, 1, 1, 10),
        changeId: 'm1',
      );
      await db.setSyncCursor(
        accountUserId: 'me',
        conversationKey: 'k',
        changeAt: DateTime.utc(2026, 1, 1, 11),
        changeId: 'm2',
      );

      final cursor =
          await db.getSyncCursor(accountUserId: 'me', conversationKey: 'k');
      expect(cursor.changeAt, DateTime.utc(2026, 1, 1, 11));
      expect(cursor.changeId, 'm2');
    });

    test('rejects a mixed null/non-null cursor pair', () async {
      expect(
        () => db.setSyncCursor(
          accountUserId: 'me',
          conversationKey: 'k',
          changeAt: DateTime.utc(2026, 1, 1),
          changeId: null,
        ),
        throwsArgumentError,
      );
    });

    test('no prior sync returns a fully-null cursor', () async {
      final cursor = await db.getSyncCursor(
        accountUserId: 'me',
        conversationKey: 'never-synced',
      );
      expect(cursor.changeAt, isNull);
      expect(cursor.changeId, isNull);
    });
  });
}
