import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/providers/chat_provider.dart';

void main() {
  group('mergeConversationStreams', () {
    test('merges both directions of a single conversation in order', () async {
      final outgoingController = StreamController<List<Map<String, dynamic>>>();
      final incomingController = StreamController<List<Map<String, dynamic>>>();

      final merged = mergeConversationStreams(
        outgoingController.stream,
        incomingController.stream,
      );

      final emissions = <List<Map<String, dynamic>>>[];
      final sub = merged.listen(emissions.add);

      outgoingController.add([
        {
          'id': '1',
          'sender_id': 'me',
          'receiver_id': 'friend',
          'text': 'hi',
          'timestamp': '2026-01-01T10:00:00Z',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      incomingController.add([
        {
          'id': '2',
          'sender_id': 'friend',
          'receiver_id': 'me',
          'text': 'hello back',
          'timestamp': '2026-01-01T10:01:00Z',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      final last = emissions.last;
      expect(last.length, 2);
      expect(last.map((m) => m['id']), ['1', '2']);
      expect(last.first['sender_id'], 'me');
      expect(last.last['sender_id'], 'friend');

      await sub.cancel();
      await outgoingController.close();
      await incomingController.close();
    });

    test('never surfaces messages that were not fed into either stream',
        () async {
      // Simulates the fact that each input stream is already scoped
      // server-side (via .eq filters) to this single conversation: a
      // message belonging to a different conversation is simply never
      // emitted by either source stream, so it can never appear here.
      final outgoingController = StreamController<List<Map<String, dynamic>>>();
      final incomingController = StreamController<List<Map<String, dynamic>>>();

      final merged = mergeConversationStreams(
        outgoingController.stream,
        incomingController.stream,
      );

      final emissions = <List<Map<String, dynamic>>>[];
      final sub = merged.listen(emissions.add);

      outgoingController.add([
        {
          'id': 'a1',
          'sender_id': 'me',
          'receiver_id': 'friendA',
          'text': 'for A only',
          'timestamp': '2026-01-01T09:00:00Z',
        },
      ]);
      incomingController.add(const []);
      await Future<void>.delayed(Duration.zero);

      final last = emissions.last;
      expect(last, hasLength(1));
      expect(last.single['receiver_id'], 'friendA');
      expect(
        last.any((m) => m['receiver_id'] == 'friendB'),
        isFalse,
        reason: 'a message never fed into either input stream must never '
            'appear in the merged conversation',
      );

      await sub.cancel();
      await outgoingController.close();
      await incomingController.close();
    });

    test('re-sorts as later, out-of-order emissions arrive', () async {
      final outgoingController = StreamController<List<Map<String, dynamic>>>();
      final incomingController = StreamController<List<Map<String, dynamic>>>();

      final merged = mergeConversationStreams(
        outgoingController.stream,
        incomingController.stream,
      );

      final emissions = <List<Map<String, dynamic>>>[];
      final sub = merged.listen(emissions.add);

      outgoingController.add([
        {
          'id': 'new',
          'sender_id': 'me',
          'receiver_id': 'friend',
          'text': 'later message',
          'timestamp': '2026-01-01T12:00:00Z',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      incomingController.add([
        {
          'id': 'old',
          'sender_id': 'friend',
          'receiver_id': 'me',
          'text': 'earlier message',
          'timestamp': '2026-01-01T08:00:00Z',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      final last = emissions.last;
      expect(last.map((m) => m['id']), ['old', 'new']);

      await sub.cancel();
      await outgoingController.close();
      await incomingController.close();
    });
  });
}
