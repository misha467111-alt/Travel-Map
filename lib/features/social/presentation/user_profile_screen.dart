import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/presentation/location_card.dart';
import '../../map/presentation/map_screen.dart';
import '../../profile/presentation/profile_components.dart';
import '../domain/public_profile.dart';
import '../providers/public_profile_provider.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({required this.userId, super.key});

  final String userId;

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
        data: (value) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(publicProfileProvider(widget.userId)),
          child: _ProfileContent(
            profile: value,
            changingFollow: _changingFollow,
            onFollowChanged: _setFollowing,
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
  });

  final PublicProfile profile;
  final bool changingFollow;
  final ValueChanged<bool> onFollowChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedState = ref.watch(savedPublicLocationsProvider);
    final saved = savedState.value ?? const {};
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        ProfileIdentityHeader(
          name: profile.name,
          subtitle: '${profile.level} · ${profile.xp} XP',
          avatarUrl: profile.avatarUrl,
        ),
        const SizedBox(height: 16),
        ProfileStats(
          items: [
            (label: 'Підписники', value: '${profile.followersCount}'),
            (label: 'Підписки', value: '${profile.followingCount}'),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: profile.isFollowing
              ? OutlinedButton.icon(
                  onPressed:
                      changingFollow ? null : () => onFollowChanged(false),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('Відписатися'),
                )
              : FilledButton.icon(
                  onPressed:
                      changingFollow ? null : () => onFollowChanged(true),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Підписатися'),
                ),
        ),
        const SizedBox(height: 28),
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
