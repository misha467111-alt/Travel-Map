import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/local/conversation_key.dart';

void main() {
  group('conversationKeyFor', () {
    test('is deterministic for a given pair', () {
      final key = conversationKeyFor('user-a', 'user-b');
      expect(key, 'user-a:user-b');
    });

    test('produces the same key regardless of argument order', () {
      final ab = conversationKeyFor('user-a', 'user-b');
      final ba = conversationKeyFor('user-b', 'user-a');
      expect(ab, ba);
    });

    test('same participants always produce the same key reversed', () {
      const a = 'ede85904-cfc8-4f5e-844a-6b9018ff747e';
      const b = 'ada8d90e-6b28-4124-bc15-6a274de9002c';
      expect(conversationKeyFor(a, b), conversationKeyFor(b, a));
    });
  });
}
