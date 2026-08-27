import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final chatStreamProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, friendId) {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return Stream.value([]);
  return client
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('timestamp', ascending: false)
      .limit(100)
      .map((rows) {
        final messages = rows
            .where((row) =>
                (row['sender_id'] == userId &&
                    row['receiver_id'] == friendId) ||
                (row['sender_id'] == friendId && row['receiver_id'] == userId))
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        messages.sort((a, b) => (a['created_at'] ?? a['timestamp'] ?? '')
            .toString()
            .compareTo((b['created_at'] ?? b['timestamp'] ?? '').toString()));
        return messages;
      });
});

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

class ChatService {
  final SupabaseClient _client = Supabase.instance.client;
  Future<void> sendMessage(String receiverId, String text) async {
    final senderId = _client.auth.currentUser?.id;
    if (senderId == null || text.trim().isEmpty) return;
    await _client.from('messages').insert({
      'sender_id': senderId,
      'receiver_id': receiverId,
      'text': text.trim(),
      'timestamp': DateTime.now().toUtc().toIso8601String()
    });
  }
}
