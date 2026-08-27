import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/domain/location_model.dart';
import '../domain/public_profile.dart';

class SocialRepository {
  const SocialRepository(this._supabase);

  final SupabaseClient _supabase;

  String get _currentUserId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw StateError('Користувач не авторизований.');
    return id;
  }

  Future<PublicProfile> fetchPublicProfile(String userId) async {
    final profile = await _supabase
        .from('profiles')
        .select('id, username, display_name, avatar_url, xp, level')
        .eq('id', userId)
        .single();
    final followers = await _supabase
        .from('follows')
        .select('follower_id')
        .eq('following_id', userId)
        .limit(500);
    final following = await _supabase
        .from('follows')
        .select('following_id')
        .eq('follower_id', userId)
        .limit(500);
    final ownFollow = userId == _currentUserId
        ? const <Map<String, dynamic>>[]
        : await _supabase
            .from('follows')
            .select('following_id')
            .eq('follower_id', _currentUserId)
            .eq('following_id', userId);

    final locationRows = await _supabase
        .from('locations')
        .select()
        .eq('owner_id', userId)
        .eq('status', 'approved')
        .eq('visibility', 'public')
        .order('created_at', ascending: false)
        .limit(30);

    final displayName = profile['display_name'] as String?;
    final username = profile['username'] as String?;
    return PublicProfile(
      id: profile['id'] as String,
      name: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : username?.trim().isNotEmpty == true
              ? username!.trim()
              : 'Мандрівник',
      avatarUrl: profile['avatar_url'] as String?,
      xp: (profile['xp'] as num? ?? 0).toInt(),
      level: profile['level'] as String? ?? 'Новачок',
      followersCount: followers.length,
      followingCount: following.length,
      isFollowing: ownFollow.isNotEmpty,
      locations: locationRows
          .map((row) => LocationModel.fromMap(row))
          .toList(growable: false),
    );
  }

  Future<void> follow(String userId) async {
    if (userId == _currentUserId) {
      throw const FormatException('Не можна підписатися на себе.');
    }
    await _supabase.from('follows').insert({
      'following_id': userId,
    });
  }

  Future<void> unfollow(String userId) async {
    await _supabase
        .from('follows')
        .delete()
        .eq('follower_id', _currentUserId)
        .eq('following_id', userId);
  }
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return SocialRepository(Supabase.instance.client);
});

final publicProfileProvider =
    FutureProvider.autoDispose.family<PublicProfile, String>((ref, userId) {
  return ref.watch(socialRepositoryProvider).fetchPublicProfile(userId);
});

class FollowController {
  const FollowController(this._ref);

  final Ref _ref;

  Future<void> setFollowing(String userId, bool follow) async {
    final repository = _ref.read(socialRepositoryProvider);
    if (follow) {
      await repository.follow(userId);
    } else {
      await repository.unfollow(userId);
    }
    _ref.invalidate(publicProfileProvider(userId));
  }
}

final followControllerProvider = Provider<FollowController>(
  FollowController.new,
);

class SavedPublicLocationsNotifier extends AsyncNotifier<Set<String>> {
  late SharedPreferences _preferences;
  late String _key;

  @override
  Future<Set<String>> build() async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    _key = 'saved_public_locations_$userId';
    _preferences = await SharedPreferences.getInstance();
    return (_preferences.getStringList(_key) ?? const []).toSet();
  }

  Future<void> toggle(String locationId) async {
    final current = state.value ?? const <String>{};
    final updated = Set<String>.of(current);
    updated.contains(locationId)
        ? updated.remove(locationId)
        : updated.add(locationId);
    state = AsyncData(updated);
    await _preferences.setStringList(_key, updated.toList(growable: false));
  }
}

final savedPublicLocationsProvider =
    AsyncNotifierProvider<SavedPublicLocationsNotifier, Set<String>>(
  SavedPublicLocationsNotifier.new,
);
