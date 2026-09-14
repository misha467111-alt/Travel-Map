import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/chat/conversation/chat_conversation_controller.dart';
import 'package:flutter_application_1/features/friends/domain/friend_models.dart';
import 'package:flutter_application_1/features/navigation/presentation/chats_screen.dart';
import 'package:flutter_application_1/providers/chat_provider.dart';

class _FakeChatService extends ChatService {
  _FakeChatService({this.shouldFail = false});

  final bool shouldFail;
  final List<String> sentTexts = [];

  @override
  Future<void> sendMessage(String receiverId, String text) async {
    if (shouldFail) {
      throw Exception('simulated send failure');
    }
    sentTexts.add(text);
  }
}

void main() {
  const friend = FriendProfile(id: 'friend-1', name: 'Друг');

  Widget shell(ChatService service) => ProviderScope(
        overrides: [
          chatServiceProvider.overrideWithValue(service),
          chatStreamProvider('friend-1').overrideWith(
            (ref) => Stream.value(const <Map<String, dynamic>>[]),
          ),
          // Bypasses the real cache/sync controller entirely for these
          // send-flow-only tests — matches the existing chatStreamProvider
          // override above, and keeps the test hermetic (no real on-disk
          // Drift database, no Supabase RPC calls).
          chatConversationStateProvider('friend-1').overrideWith(
            (ref) => Stream.value(ChatConversationState.initial()),
          ),
        ],
        child: const MaterialApp(home: ChatScreen(friend: friend)),
      );

  testWidgets('successful send clears the input and reaches the service',
      (tester) async {
    final service = _FakeChatService();
    await tester.pumpWidget(shell(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Привіт!');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(service.sentTexts, ['Привіт!']);
    expect(find.text('Привіт!'), findsNothing);
  });

  testWidgets('failed send keeps the message text and shows an error snackbar',
      (tester) async {
    final service = _FakeChatService(shouldFail: true);
    await tester.pumpWidget(shell(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Це не надішлеться');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(service.sentTexts, isEmpty);
    expect(find.text('Це не надішлеться'), findsOneWidget);
    expect(
      find.text('Не вдалося надіслати повідомлення. Спробуйте ще раз.'),
      findsOneWidget,
    );
  });
}
