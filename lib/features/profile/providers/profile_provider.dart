import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/user_profile.dart';

part 'profile_provider.g.dart';

class ProfileRepository {
  const ProfileRepository(this._supabase);

  final SupabaseClient _supabase;

  User _requireUser() {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Користувач не авторизований.');
    return user;
  }

  Future<UserProfile> fetchCurrentProfile() async {
    final user = _requireUser();
    Map<String, dynamic>? profile;
    try {
      profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Could not load profile row: $error\n$stackTrace');
      }
    }

    var locationsCount = 0;
    try {
      final locations = await _supabase
          .from('locations')
          .select('id')
          .eq('owner_id', user.id)
          .count(CountOption.exact)
          .timeout(const Duration(seconds: 15));
      locationsCount = locations.count;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Could not load profile locations count: $error\n$stackTrace',
        );
      }
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final profileData = <String, dynamic>{
      'id': user.id,
      'username': metadata['username'],
      'display_name': metadata['display_name'],
      'name': metadata['name'],
      'avatar_url': metadata['avatar_url'],
      'xp': 0,
      ...?profile,
    };

    return UserProfile.fromMap(profileData,
        email: user.email ?? '', locationsCount: locationsCount);
  }

  Future<void> updateDisplayName(String value) async {
    final user = _requireUser();
    final name = value.trim();
    if (name.length < 2) {
      throw ArgumentError('Нікнейм має містити щонайменше 2 символи.');
    }
    await _supabase.from('profiles').update({
      'username': name,
      'display_name': name,
      'name': name,
    }).eq('id', user.id);
    await _supabase.auth.updateUser(
        UserAttributes(data: {'username': name, 'display_name': name}));
  }

  Future<String> uploadAvatar(Uint8List bytes,
      {String extension = 'jpg'}) async {
    final user = _requireUser();
    final ext = extension.toLowerCase().replaceAll('.', '');
    final safeExt =
        {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(ext) ? ext : 'jpg';
    final path =
        '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    await _supabase.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    final url = _supabase.storage.from('avatars').getPublicUrl(path);
    await _supabase.from('profiles').update({
      'avatar_url': url,
    }).eq('id', user.id);
    await _supabase.auth.updateUser(UserAttributes(data: {'avatar_url': url}));
    return url;
  }
}

Duration? _neverRetry(int retryCount, Object error) => null;

@riverpod
ProfileRepository profileRepository(Ref ref) =>
    ProfileRepository(Supabase.instance.client);

@Riverpod(keepAlive: true, retry: _neverRetry)
Future<UserProfile> currentProfile(Ref ref) =>
    ref.watch(profileRepositoryProvider).fetchCurrentProfile();
