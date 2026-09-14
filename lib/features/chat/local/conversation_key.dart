/// Deterministic, order-independent identifier for a 1:1 conversation
/// between two participant ids.
///
/// There is no server-side conversation/thread entity in the schema —
/// messages only carry sender_id/receiver_id — so the local cache needs
/// its own stable way to group a conversation regardless of which side
/// sent a given message. Always use this instead of raw sender/receiver
/// ordering to identify a conversation locally.
String conversationKeyFor(String userIdA, String userIdB) {
  return userIdA.compareTo(userIdB) <= 0
      ? '$userIdA:$userIdB'
      : '$userIdB:$userIdA';
}
