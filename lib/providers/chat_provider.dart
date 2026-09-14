import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Streams a single 1:1 conversation between the current user and
/// [friendId]. The underlying `supabase_flutter` `.stream()` API only
/// combines filters with AND (no `.or()`), so a single query cannot express
/// "sender = me AND receiver = friend" OR "sender = friend AND receiver =
/// me" directly. Instead this subscribes to the two direction-scoped
/// streams (each correctly filtered server-side via `.eq()`) and merges
/// them, rather than fetching the whole table and filtering client-side.
final chatStreamProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, friendId) {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return Stream.value(const []);

  final outgoing = client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('sender_id', userId)
      .eq('receiver_id', friendId)
      .order('timestamp', ascending: false)
      .limit(100);

  final incoming = client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('sender_id', friendId)
      .eq('receiver_id', userId)
      .order('timestamp', ascending: false)
      .limit(100);

  return mergeConversationStreams(outgoing, incoming);
});

/// Combines the two direction-scoped message streams of a single
/// conversation into one chronologically ordered stream. Each input is
/// expected to already be scoped to exactly one sender/receiver pair, so
/// this only merges and sorts the latest known state of both directions —
/// it does no additional filtering.
Stream<List<Map<String, dynamic>>> mergeConversationStreams(
  Stream<List<Map<String, dynamic>>> outgoing,
  Stream<List<Map<String, dynamic>>> incoming,
) {
  late final StreamController<List<Map<String, dynamic>>> controller;
  var latestOutgoing = const <Map<String, dynamic>>[];
  var latestIncoming = const <Map<String, dynamic>>[];
  StreamSubscription<List<Map<String, dynamic>>>? outgoingSub;
  StreamSubscription<List<Map<String, dynamic>>>? incomingSub;

  void emit() {
    final merged = [...latestOutgoing, ...latestIncoming]..sort((a, b) =>
        (a['timestamp'] ?? '')
            .toString()
            .compareTo((b['timestamp'] ?? '').toString()));
    controller.add(merged);
  }

  controller = StreamController<List<Map<String, dynamic>>>.broadcast(
    onListen: () {
      outgoingSub = outgoing.listen(
        (rows) {
          latestOutgoing = rows.map(Map<String, dynamic>.from).toList();
          emit();
        },
        onError: controller.addError,
      );
      incomingSub = incoming.listen(
        (rows) {
          latestIncoming = rows.map(Map<String, dynamic>.from).toList();
          emit();
        },
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await outgoingSub?.cancel();
      await incomingSub?.cancel();
    },
  );

  return controller.stream;
}

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

class ChatService {
  SupabaseClient get _client => Supabase.instance.client;

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
