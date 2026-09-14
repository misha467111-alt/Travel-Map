import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// ownerId, never by deletion. [GpsLocalDatabase.getRecoverableRecording]
/// is the hook a future logout guard should use to detect and block an
/// in-progress recording before allowing sign-out.
