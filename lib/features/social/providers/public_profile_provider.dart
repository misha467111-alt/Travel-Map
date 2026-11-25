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
      locationsCount: locationRows.length < 30
          ? locationRows.length
          : await _publicLocationsCount(userId),
      isSelf: userId == _currentUserId,
      followersCount: followers.length,
      followingCount: following.length,
      isFollowing: ownFollow.isNotEmpty,
      locations: locationRows
          .map((row) => LocationModel.fromMap(row))
          .toList(growable: false),
    );
  }

  Future<int?> _publicLocationsCount(String userId) async {
    try {
      final result = await _supabase
          .from('locations')
          .select('id')
          .eq('owner_id', userId)
          .eq('status', 'approved')
          .eq('visibility', 'public')
          .count(CountOption.exact);
      return result.count;
    } catch (_) {
      return null;
    }
  }

  /// Cheap follower/following totals (counts only, no rows).
  Future<FollowCounts> fetchFollowCounts(String userId) async {
    final followers = await _supabase
        .from('follows')
        .select('follower_id')
        .eq('following_id', userId)
        .count(CountOption.exact);
    final following = await _supabase
        .from('follows')
        .select('following_id')
        .eq('follower_id', userId)
        .count(CountOption.exact);
    return FollowCounts(followers: followers.count, following: following.count);
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

final followCountsProvider =
    FutureProvider.autoDispose.family<FollowCounts, String>((ref, userId) {
  return ref.watch(socialRepositoryProvider).fetchFollowCounts(userId);
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

/// The signed-in user's id (`null` when signed out), available synchronously
/// and updated on every sign-in / sign-out, so anything per-account can rebuild
/// when the account changes inside one app session. A token refresh keeps the
/// same id and notifies nobody.
class SignedInUserId extends Notifier<String?> {
  @override
  String? build() {
    final auth = Supabase.instance.client.auth;
    final sub = auth.onAuthStateChange.listen((event) {
      final id = event.session?.user.id;
      if (id != state) state = id;
    });
    ref.onDispose(sub.cancel);
    return auth.currentUser?.id;
  }
}

final signedInUserIdProvider =
    NotifierProvider<SignedInUserId, String?>(SignedInUserId.new);

/// The signed-in user's bookmarks, stored on this device under a PER-ACCOUNT
/// key (`saved_public_locations_<user_id>`). The notifier rebuilds whenever the
/// signed-in account changes, so after a logout / login as someone else it
/// never shows -- or writes to -- the previous account's bookmarks. Nothing is
/// deleted: each account's bookmarks stay under its own key. Signed out, the
/// list is empty and nothing is persisted.
class SavedPublicLocationsNotifier extends AsyncNotifier<Set<String>> {
  static String _keyFor(String userId) => 'saved_public_locations_$userId';

  @override
  Future<Set<String>> build() async {
    final userId = ref.watch(signedInUserIdProvider);
    final preferences = await SharedPreferences.getInstance();
    if (userId == null) return <String>{};
    return (preferences.getStringList(_keyFor(userId)) ?? const []).toSet();
  }

  /// Adds / removes a bookmark of the CURRENT account. The account is captured
  /// first and the bookmarks are awaited, so a toggle can never be applied to
  /// the previous account's set while a rebuild is still in flight; if the
  /// account changes while waiting, the toggle is dropped instead of being
  /// written under the wrong key.
  Future<void> toggle(String locationId) async {
    final userId = ref.read(signedInUserIdProvider);
    final current = await future;
    if (ref.read(signedInUserIdProvider) != userId) return;
    final updated = Set<String>.of(current);
    updated.contains(locationId)
        ? updated.remove(locationId)
        : updated.add(locationId);
    state = AsyncData(updated);
    if (userId == null) return; // signed out: nothing to persist
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
        _keyFor(userId), updated.toList(growable: false));
  }
}

final savedPublicLocationsProvider =
    AsyncNotifierProvider<SavedPublicLocationsNotifier, Set<String>>(
  SavedPublicLocationsNotifier.new,
);
