import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gps_local_database.dart';

/// Provides the local GPS/recording database.
///
/// Deliberately a *separate* database from ChatLocalDatabase (own file,
/// own schema, own migration lifecycle) rather than added as more tables
/// on the chat database — reuses the same drift/drift_flutter
/// infrastructure and idioms without coupling GPS persistence to chat's.
///
/// Non-autoDispose, same reasoning as chatLocalDatabaseProvider: a GPS
/// recording must never have its underlying database closed mid-session
/// just because some other part of the widget tree happened to
/// temporarily stop watching a provider.
final gpsLocalDatabaseProvider = Provider<GpsLocalDatabase>((ref) {
  final db = GpsLocalDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Intentionally does NOT exist: a `clearGpsCacheOnLogout()`-style
/// destructive wipe, unlike chat's `clearChatCacheOnLogout`. See the
/// account-isolation design note in gps_local_database.dart's class docs
/// and the GPS-2 report — GPS recordings are not a re-fetchable cache
/// (they may be the only copy of unsynced data), so logout must never
/// delete them. Isolation between accounts on a shared device is
/// achieved purely by every query being scoped to the caller's own
/// ownerId, never by deletion.

/// The actual guard decision, kept separate from and independent of
/// Supabase/Riverpod so it can be unit-tested directly with a plain
/// in-memory [GpsLocalDatabase] and an explicit (possibly null) userId —
/// no live Supabase session required, mirroring how
/// ChatConversationController's Supabase-touching parts are kept thin so
/// the logic around them can be tested without one either.
///
/// Returns the id of that account's recording/paused local route if one
/// exists (logout must be blocked), or `null` if logout may proceed. A
/// null [userId] (no session) never blocks — there is nothing to guard.
Future<String?> blockingActiveRecordingIdFor(GpsLocalDatabase db, String? userId) async {
  if (userId == null) return null;
  final recording = await db.getRecoverableRecording(userId);
  return recording?.id;
}

/// The centralized logout guard: every real logout entry point in the
/// app must call this *before* clearing any cache or calling
/// `profileController.logout()`, and must not proceed if it returns
/// non-null. Never deletes, finishes, or discards anything itself — it
/// only reports whether an active recording exists, matching the
/// "never silently finish/discard it" requirement. This is the one
/// place the check lives; every UI logout call site calls this same
/// function rather than each re-implementing the query itself.
Future<String?> blockingActiveRecordingId(WidgetRef ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  return blockingActiveRecordingIdFor(ref.read(gpsLocalDatabaseProvider), userId);
}
