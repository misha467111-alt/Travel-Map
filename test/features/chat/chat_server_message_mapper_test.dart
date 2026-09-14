import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/conversation/chat_server_message_mapper.dart';

void main() {
  group('ChatServerMessageMapper.fromRpcRow', () {
    test('parses all fields and normalizes timestamps to UTC', () {
      final row = ChatServerMessageMapper.fromRpcRow({
        'id': 'm1',
        'sender_id': 'me',
        'receiver_id': 'friend',
        'body': 'hello',
        'created_at': '2026-01-01T10:00:00+00:00',
        'updated_at': '2026-01-01T10:00:00+00:00',
        'deleted_at': null,
        'hidden_for_me': false,
      });

      expect(row.id, 'm1');
      expect(row.body, 'hello');
      expect(row.createdAt.isUtc, isTrue);
      expect(row.updatedAt.isUtc, isTrue);
      expect(row.deletedAt, isNull);
      expect(row.hiddenForMe, isFalse);
    });

    test('missing hidden_for_me defaults to false', () {
      final row = ChatServerMessageMapper.fromRpcRow({
        'id': 'm1',
        'sender_id': 'me',
        'receiver_id': 'friend',
        'body': 'hello',
        'created_at': '2026-01-01T10:00:00+00:00',
        'updated_at': '2026-01-01T10:00:00+00:00',
        'deleted_at': null,
      });

      expect(row.hiddenForMe, isFalse);
    });

    test('a non-null deleted_at is parsed and normalized to UTC', () {
      final row = ChatServerMessageMapper.fromRpcRow({
        'id': 'm1',
        'sender_id': 'me',
        'receiver_id': 'friend',
        'body': null,
        'created_at': '2026-01-01T10:00:00+00:00',
        'updated_at': '2026-01-01T10:05:00+00:00',
        'deleted_at': '2026-01-01T10:05:00+00:00',
        'hidden_for_me': false,
      });

      expect(row.deletedAt, isNotNull);
      expect(row.deletedAt!.isUtc, isTrue);
      expect(row.body, isNull);
    });
  });

  group('ChatServerMessageMapper.fromRealtimeRow', () {
    test('maps the raw messages table shape (text/timestamp columns)', () {
      final row = ChatServerMessageMapper.fromRealtimeRow({
        'id': 'm2',
        'sender_id': 'me',
        'receiver_id': 'friend',
        'text': 'raw table body',
        'timestamp': '2026-01-01T11:00:00+00:00',
        'updated_at': '2026-01-01T11:00:00+00:00',
        'deleted_at': null,
      });

      expect(row.body, 'raw table body');
      expect(row.createdAt.isUtc, isTrue);
      expect(
        row.hiddenForMe,
        isFalse,
        reason: 'the raw table has no hidden_for_me concept — realtime '
            'never carries delete-for-me propagation',
      );
    });
  });

  group('ChatServerMessageMapper.parseChangeAt', () {
    test('normalizes the catch-up cursor timestamp to UTC', () {
      final changeAt = ChatServerMessageMapper.parseChangeAt({
        'change_at': '2026-01-01T12:30:00+00:00',
      });

      expect(changeAt.isUtc, isTrue);
      expect(changeAt, DateTime.utc(2026, 1, 1, 12, 30));
    });
  });
}
