import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/presentation/location_card.dart';
import '../../map/presentation/map_screen.dart';
import '../../../core/theme/app_design.dart';
import '../../profile/presentation/traveler_profile_header.dart';
import '../domain/public_profile.dart';
import '../../friends/domain/friend_models.dart';
import '../providers/public_profile_provider.dart';
import 'profile_social_actions.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({required this.userId, this.onOpenChat, super.key});

  final String userId;

  /// How to open the existing chat with a friend. Owned by the caller so this
  /// screen does not depend on the chat screens; without it no "Чат" button
  /// is shown.
  final void Function(BuildContext context, FriendProfile friend)? onOpenChat;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  bool _changingFollow = false;

  Future<void> _setFollowing(bool value) async {
    if (_changingFollow) return;
    setState(() => _changingFollow = true);
    try {
      await ref.read(followControllerProvider).setFollowing(
            widget.userId,
            value,
          );
      // The signed-in user's own "Стежу" counter changed too.
      ref.invalidate(followCountsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Не вдалося змінити підписку. Спробуйте ще раз.')),
        );
      }
    } finally {
      if (mounted) setState(() => _changingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(publicProfileProvider(widget.userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Профіль дослідника')),
      body: profile.when(
        skipLoadingOnReload: true,
        data: (value) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(publicProfileProvider(widget.userId)),
          child: _ProfileContent(
            profile: value,
            changingFollow: _changingFollow,
            onFollowChanged: _setFollowing,
            onOpenChat: widget.onOpenChat == null
                ? null
                : (friend) => widget.onOpenChat!(context, friend),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Не вдалося завантажити профіль.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(publicProfileProvider(widget.userId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Спробувати ще раз'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({
    required this.profile,
    required this.changingFollow,
    required this.onFollowChanged,
    this.onOpenChat,
  });

  final PublicProfile profile;
  final bool changingFollow;
  final ValueChanged<bool> onFollowChanged;
  final ValueChanged<FriendProfile>? onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedState = ref.watch(savedPublicLocationsProvider);
    final saved = savedState.value ?? const {};
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
      children: [
        TravelerProfileHeader(
          name: profile.name,
          level: profile.level,
          xp: profile.xp,
          avatarUrl: profile.avatarUrl,
          counters: [
            TravelerCounter(
                keyName: 'locations',
                label: 'Локації',
                value: profile.locationsCount),
            TravelerCounter(
                keyName: 'followers',
                label: 'Стежать',
                value: profile.followersCount),
            TravelerCounter(
                keyName: 'following',
                label: 'Стежу',
                value: profile.followingCount),
          ],
          // No social buttons on one's own profile.
          action: profile.isSelf
              ? null
              : ProfileSocialActions(
                  userId: profile.id,
                  name: profile.name,
                  avatarUrl: profile.avatarUrl,
                  isFollowing: profile.isFollowing,
                  followBusy: changingFollow,
                  onFollowChanged: onFollowChanged,
                  onOpenChat: onOpenChat,
                ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Публічні локації',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (profile.locations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Публічних локацій поки немає')),
          )
        else
          ...profile.locations.map(
            (location) => LocationCard(
              location: location,
              compact: true,
              isSaved: saved.contains(location.id),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LocationDetailsScreen(location: location),
                ),
              ),
              onBookmarkTap: savedState.hasValue
                  ? () => ref
                      .read(savedPublicLocationsProvider.notifier)
                      .toggle(location.id)
                  : null,
            ),
          ),
      ],
    );
  }
}
