import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/friend_models.dart';

part 'friends_provider.g.dart';

class FriendsRepository {
  const FriendsRepository(this._supabase);

  final SupabaseClient _supabase;

  String get _currentUserId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw StateError('Користувач не авторизований.');
    return id;
  }

  Future<List<FriendProfile>> searchUsers(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];

    final rows = await _supabase
        .from('profiles')
        .select()
        .ilike('username', '%$normalized%')
        .neq('id', _currentUserId)
        .limit(20);
    return _profilesFrom(rows);
  }

  Future<void> sendRequest(String targetUserId) async {
    await _supabase.from('friendships').insert({
      'user_id_1': _currentUserId,
      'user_id_2': targetUserId,
      'status': 'pending',
    });
  }

  Future<void> acceptRequest(String friendshipId) async {
    await _supabase
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('id', friendshipId)
        .eq('user_id_2', _currentUserId);
  }

  Future<List<FriendProfile>> getFriends() async {
    final userId = _currentUserId;
    final rows = await _supabase
        .from('friendships')
        .select('user_id_1, user_id_2')
        .eq('status', 'accepted')
        .or('user_id_1.eq.$userId,user_id_2.eq.$userId')
        .limit(100);

    final ids = rows
        .map<String>(
          (row) => row['user_id_1'] == userId
              ? row['user_id_2'] as String
              : row['user_id_1'] as String,
        )
        .toSet()
        .toList();
    if (ids.isEmpty) return const [];

    final profiles =
        await _supabase.from('profiles').select().inFilter('id', ids);
    return _profilesFrom(profiles);
  }

  Future<List<FriendRequest>> getPendingRequests() async {
    final rows = await _supabase
        .from('friendships')
        .select('id, user_id_1, created_at')
        .eq('user_id_2', _currentUserId)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(100);
    if (rows.isEmpty) return const [];

    final senderIds =
        rows.map<String>((row) => row['user_id_1'] as String).toSet().toList();
    final profileRows =
        await _supabase.from('profiles').select().inFilter('id', senderIds);
    final profiles = {
      for (final profile in _profilesFrom(profileRows)) profile.id: profile,
    };

    return rows
        .where((row) => profiles.containsKey(row['user_id_1']))
        .map(
          (row) => FriendRequest(
            id: row['id'] as String,
            sender: profiles[row['user_id_1']]!,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  List<FriendProfile> _profilesFrom(List<Map<String, dynamic>> rows) {
    return rows.map(FriendProfile.fromMap).toList(growable: false);
  }
}

@riverpod
FriendsRepository friendsRepository(Ref ref) {
  return FriendsRepository(Supabase.instance.client);
}

@riverpod
Future<List<FriendProfile>> acceptedFriends(Ref ref) {
  return ref.watch(friendsRepositoryProvider).getFriends();
}

@riverpod
Future<List<FriendRequest>> pendingFriendRequests(Ref ref) {
  return ref.watch(friendsRepositoryProvider).getPendingRequests();
}

@riverpod
Future<List<FriendProfile>> searchFriends(Ref ref, String query) {
  return ref.watch(friendsRepositoryProvider).searchUsers(query);
}
