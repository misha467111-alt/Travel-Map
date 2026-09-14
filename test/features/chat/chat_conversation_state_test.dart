import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/conversation/chat_conversation_controller.dart';

void main() {
  group('ChatConversationState.initial', () {
    test('starts empty, with hasMore true and no error/offline flags', () {
      final state = ChatConversationState.initial();
      expect(state.messages, isEmpty);
      expect(state.isLoadingOlder, isFalse);
      expect(state.hasMore, isTrue);
      expect(state.isOffline, isFalse);
      expect(state.syncError, isNull);
    });
  });

  group('ChatConversationState.copyWith', () {
    test('omitted fields are preserved unchanged', () {
      final state = ChatConversationState.initial()
          .copyWith(isOffline: true, hasMore: false);
      final updated = state.copyWith(isLoadingOlder: true);

      expect(updated.isOffline, isTrue);
      expect(updated.hasMore, isFalse);
      expect(updated.isLoadingOlder, isTrue);
    });

    test(
        'an explicit null syncError clears a previously-set error, '
        'distinct from simply omitting the argument', () {
      final withError =
          ChatConversationState.initial().copyWith(syncError: 'oops');
      expect(withError.syncError, 'oops');

      final unchanged = withError.copyWith(isOffline: true);
      expect(
        unchanged.syncError,
        'oops',
        reason: 'omitting syncError must not clear it',
      );

      final cleared = withError.copyWith(syncError: null);
      expect(
        cleared.syncError,
        isNull,
        reason: 'passing syncError: null explicitly must clear it',
      );
    });
  });
}
