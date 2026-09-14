import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_local_database.dart';

/// Provides the local chat cache database.
final chatLocalDatabaseProvider = Provider<ChatLocalDatabase>((ref) {
  final db = ChatLocalDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Wipes the current account's cached chat messages/sync cursors, so a
/// different account signing in on the same device never sees a leftover
/// cache. Every logout entry point in the app should call this before
/// (or alongside) the actual sign-out, not just one of them — otherwise
/// some paths would leak cache and others wouldn't, depending only on
/// which button the user happened to tap. Reads the user id first since
/// signOut() clears it; a failed cache wipe must never block sign-out.
Future<void> clearChatCacheOnLogout(WidgetRef ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;
  try {
    await ref.read(chatLocalDatabaseProvider).clearAccountCache(userId);
  } catch (_) {}
}
