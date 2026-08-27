import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final friendsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];
  final rows = await client
      .from('friendships')
      .select('user_id, friend_id')
      .eq('status', 'accepted')
      .limit(100);
  final friendIds = (rows as List)
      .where((row) => row['user_id'] == userId || row['friend_id'] == userId)
      .map<String>((row) => row['user_id'] == userId
          ? row['friend_id'] as String
          : row['user_id'] as String)
      .toSet()
      .toList();
  if (friendIds.isEmpty) return [];
  final users = await client
      .from('users')
      .select('id, name, avatar_url')
      .inFilter('id', friendIds)
      .limit(100);
  return List<Map<String, dynamic>>.from(users);
});
