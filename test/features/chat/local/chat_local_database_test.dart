import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/local/chat_local_database.dart';

ChatLocalDatabase newTestDatabase() =>
    ChatLocalDatabase.forTesting(NativeDatabase.memory());

LocalMessagesCompanion message({
  required String id,
  required String accountUserId,
  required String conversationKey,
  required String senderId,
  required String receiverId,
  String? body,
  required DateTime createdAt,
  DateTime? updatedAt,
}) {
  return LocalMessagesCompanion.insert(
    id: id,
    accountUserId: accountUserId,
    conversationKey: conversationKey,
    senderId: senderId,
    receiverId: receiverId,
    body: Value(body ?? 'text $id'),
    createdAt: createdAt,
    updatedAt: updatedAt ?? createdAt,
  );
}

void main() {
  const accountA = 'account-a';
  const accountB = 'account-b';
  const convo = 'account-a:friend';
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

  late ChatLocalDatabase db;

  setUp(() {
    db = newTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('1. insert/upsert normal message is stored', () async {
    await db.upsertMessage(message(
      id: 'm1',
      accountUserId: accountA,
      conversationKey: convo,
      senderId: accountA,
      receiverId: 'friend',
      createdAt: t0,
    ));

    final rows = await db.getRecentMessages(
      accountUserId: accountA,
      conversationKey: convo,
      limit: 10,
    );
    expect(rows, hasLength(1));
    expect(rows.single.id, 'm1');
  });

  test('2. repeated upsert of the same message does not duplicate', () async {
    for (var i = 0; i < 3; i++) {
      await db.upsertMessage(message(
        id: 'm1',
        accountUserId: accountA,
        conversationKey: convo,
        senderId: accountA,
        receiverId: 'friend',
        body: 'attempt $i',
        createdAt: t0,
      ));
    }

    final rows = await db.getRecentMessages(
      accountUserId: accountA,
      conversationKey: convo,
      limit: 10,
    );
    expect(rows, hasLength(1));
    expect(rows.single.body, 'attempt 2');
  });

  test('4. account A cache is invisible to account B', () async {
    await db.upsertMessage(message(
      id: 'shared-id',
      accountUserId: accountA,
      conversationKey: convo,
      senderId: accountA,
      receiverId: 'friend',
      body: 'only A should see this',
      createdAt: t0,
    ));

    final bRows = await db.getRecentMessages(
      accountUserId: accountB,
      conversationKey: convo,
      limit: 10,
    );
    expect(bRows, isEmpty);

    // Same server message id cached independently for B (e.g. shared
    // device scenario) must not disturb A's row.
    await db.upsertMessage(message(
      id: 'shared-id',
      accountUserId: accountB,
      conversationKey: convo,
      senderId: accountA,
      receiverId: 'friend',
      body: 'B copy',
      createdAt: t0,
    ));

    final aRows = await db.getRecentMessages(
      accountUserId: accountA,
      conversationKey: convo,
      limit: 10,
    );
    expect(aRows, hasLength(1));
    expect(aRows.single.body, 'only A should see this');
  });

  test('6. recent messages are returned oldest to newest', () async {
    await db.upsertMessages([
      message(
          id: 'm1',
          accountUserId: accountA,
          conversationKey: convo,
          senderId: accountA,
          receiverId: 'friend',
          createdAt: t0),
      message(
          id: 'm2',
          accountUserId: accountA,
          conversationKey: convo,
          senderId: accountA,
          receiverId: 'friend',
          createdAt: t0.add(const Duration(minutes: 1))),
      message(
          id: 'm3',
          accountUserId: accountA,
          conversationKey: convo,
          senderId: accountA,
          receiverId: 'friend',
          createdAt: t0.add(const Duration(minutes: 2))),
    ]);

    final rows = await db.getRecentMessages(
      accountUserId: accountA,
      conversationKey: convo,
      limit: 10,
    );
    expect(rows.map((r) => r.id).toList(), ['m1', 'm2', 'm3']);
  });

  test('7. local keyset pagination returns the correct older page', () async {
    final entries = List.generate(
      5,
      (i) => message(
        id: 'm$i',
        accountUserId: accountA,
        conversationKey: convo,
        senderId: accountA,
        receiverId: 'friend',
        createdAt: t0.add(Duration(minutes: i)),
      ),
    );
    await db.upsertMessages(entries);

    // Newest page first (last 2): m3, m4.
    final recent = await db.getRecentMessages(
      accountUserId: accountA,
      conversationKey: convo,
      limit: 2,
    );
    expect(recent.map((r) => r.id).toList(), ['m3', 'm4']);

    // Older page before m3: should be m1, m2 (not m0 skipped, not m3
    // repeated).
    final older = await db.getOlderMessages(
      accountUserId: accountA,
      conversationKey: convo,
      beforeCreatedAt: recent.first.createdAt,
      beforeId: recent.first.id,
      limit: 2,
    );
    expect(older.map((r) => r.id).toList(), ['m1', 'm2']);
  });

  test('8. cleanup keeps only the newest maxMessages', () async {
    final entries = List.generate(
      10,
      (i) => message(
        id: 'm$i',
        accountUserId: accountA,
        conversationKey: convo,
        senderId: accountA,
        receiverId: 'friend',
        createdAt: t0.add(Duration(minutes: i)),
      ),
    );
    await db.upsertMessages(entries);

    await db.cleanupConversation(
      accountUserId: accountA,
      conversationKey: convo,
      maxMessages: 4,
    );

    final rows = await db.getRecentMessages(
      accountUserId: accountA,
      conversationKey: convo,
      limit: 100,
    );
    expect(rows.map((r) => r.id).toList(), ['m6', 'm7', 'm8', 'm9']);
  });

  test('9. cleanup of one conversation does not touch another', () async {
    const convoOther = 'account-a:other-friend';
    await db.upsertMessages(List.generate(
      5,
      (i) => message(
        id: 'a$i',
        accountUserId: accountA,
        conversationKey: convo,
        senderId: accountA,
        receiverId: 'friend',
        createdAt: t0.add(Duration(minutes: i)),
      ),
    ));
    await db.upsertMessages(List.generate(
      3,
      (i) => message(
        id: 'b$i',
        accountUserId: accountA,
        conversationKey: convoOther,
        senderId: accountA,
        receiverId: 'other-friend',
        createdAt: t0.add(Duration(minutes: i)),
      ),
    ));

    await db.cleanupConversation(
      accountUserId: accountA,
      conversationKey: convo,
      maxMessages: 1,
    );

    final untouched = await db.getRecentMessages(
      accountUserId: accountA,
      conversationKey: convoOther,
      limit: 100,
    );
    expect(untouched, hasLength(3));
  });

  test('10. clearAccountCache for A does not touch account B', () async {
    await db.upsertMessage(message(
        id: 'a1',
        accountUserId: accountA,
        conversationKey: convo,
        senderId: accountA,
        receiverId: 'friend',
        createdAt: t0));
    await db.upsertMessage(message(
        id: 'b1',
        accountUserId: accountB,
        conversationKey: convo,
        senderId: accountB,
        receiverId: 'friend',
        createdAt: t0));

    await db.clearAccountCache(accountA);

    final aRows = await db.getRecentMessages(
        accountUserId: accountA, conversationKey: convo, limit: 10);
    final bRows = await db.getRecentMessages(
        accountUserId: accountB, conversationKey: convo, limit: 10);
    expect(aRows, isEmpty);
    expect(bRows, hasLength(1));
  });

  test('14 & 15. sync cursor stores and reads back the exact pair', () async {
    final changeAt = DateTime.utc(2026, 2, 1, 10, 30);
    await db.setSyncCursor(
      accountUserId: accountA,
      conversationKey: convo,
      changeAt: changeAt,
      changeId: 'msg-42',
    );

    final cursor = await db.getSyncCursor(
      accountUserId: accountA,
      conversationKey: convo,
    );
    expect(cursor.changeAt, changeAt);
    expect(cursor.changeId, 'msg-42');
  });

  test('16. cursor null state works and rejects a mixed null/non-null pair',
      () async {
    final empty = await db.getSyncCursor(
      accountUserId: accountA,
      conversationKey: convo,
    );
    expect(empty.changeAt, isNull);
    expect(empty.changeId, isNull);

    expect(
      () => db.setSyncCursor(
        accountUserId: accountA,
        conversationKey: convo,
        changeAt: DateTime.utc(2026),
        changeId: null,
      ),
      throwsArgumentError,
    );
  });

  test('17. sync cursor is isolated per account', () async {
    await db.setSyncCursor(
      accountUserId: accountA,
      conversationKey: convo,
      changeAt: DateTime.utc(2026, 3, 1),
      changeId: 'a-cursor',
    );

    final bCursor = await db.getSyncCursor(
      accountUserId: accountB,
      conversationKey: convo,
    );
    expect(bCursor.changeAt, isNull);
    expect(bCursor.changeId, isNull);
  });
}
