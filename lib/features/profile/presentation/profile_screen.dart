import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/profile_controller.dart';
import '../../achievements/providers/achievements_provider.dart';
import '../../navigation/presentation/main_navigation_screen.dart';
import '../../social/providers/public_profile_provider.dart';
import '../domain/user_profile.dart';
import '../providers/profile_provider.dart';
import 'profile_components.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: const Text('Профіль',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: ref.watch(currentProfileProvider).when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              data: (profile) => ProfileContent(profile: profile),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                  child: FilledButton.icon(
                onPressed: () => ref.invalidate(currentProfileProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Не вдалося завантажити профіль'),
              )),
            ),
      );
}

class ProfileContent extends ConsumerStatefulWidget {
  const ProfileContent({
    required this.profile,
    this.onDestination,
    this.onLogout,
    this.savedCountOverride,
    this.achievementProgressOverride,
    this.inviteBalanceOverride,
    super.key,
  });
  final UserProfile profile;
  final ValueChanged<String>? onDestination;
  final VoidCallback? onLogout;
  final int? savedCountOverride;
  final ({int unlocked, int total})? achievementProgressOverride;
  final int? inviteBalanceOverride;
  @override
  ConsumerState<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends ConsumerState<ProfileContent> {
  bool _busy = false;
  String? _avatarOverride;
  String? _nameOverride;

  Future<bool> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(currentProfileProvider);
      ref.invalidate(publicProfileProvider(widget.profile.id));
      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Profile update failed: $error\n$stackTrace');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не вдалося оновити профіль.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    final extension =
        image.name.contains('.') ? image.name.split('.').last : 'jpg';
    String? uploadedUrl;
    final updated = await _run(() async {
      uploadedUrl = await ref
          .read(profileRepositoryProvider)
          .uploadAvatar(bytes, extension: extension);
    });
    if (updated && mounted && uploadedUrl != null) {
      final previous = _avatarOverride ?? widget.profile.avatarUrl;
      if (previous?.isNotEmpty == true) {
        await NetworkImage(previous!).evict();
      }
      setState(() => _avatarOverride = uploadedUrl);
    }
  }

  Future<void> _changeName() async {
    final controller = TextEditingController(text: widget.profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Змінити ім’я'),
        content:
            TextField(controller: controller, autofocus: true, maxLength: 30),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Скасувати')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Зберегти')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (name == null || !mounted) return;
    final updated = await _run(
        () => ref.read(profileRepositoryProvider).updateDisplayName(name));
    if (updated && mounted) setState(() => _nameOverride = name.trim());
  }

  void _open(String destination) {
    if (destination == 'logout') {
      (widget.onLogout ?? profileController.logout).call();
    } else {
      if (widget.onDestination != null) {
        widget.onDestination!(destination);
      } else {
        openSecondarySection(context, destination);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final nextXp = _nextXp(profile.xp);
    final savedState = widget.savedCountOverride == null
        ? ref.watch(savedPublicLocationsProvider)
        : null;
    final achievementsState = widget.achievementProgressOverride == null
        ? ref.watch(achievementsProvider)
        : null;
    final savedCount = widget.savedCountOverride ?? savedState?.value?.length;
    final achievementProgress = widget.achievementProgressOverride ??
        (achievementsState?.value == null
            ? null
            : (
                unlocked: achievementsState!.value!
                    .where((achievement) => achievement.isUnlocked)
                    .length,
                total: achievementsState.value!.length,
              ));
    final inviteBalance =
        widget.inviteBalanceOverride ?? profileController.invitesLeft;
    final mediaQuery = MediaQuery.of(context);
    final effectiveScale =
        mediaQuery.textScaler.scale(1).clamp(1.0, 1.12).toDouble();
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          children: [
            ProfileIdentityHeader(
              name: _nameOverride ?? profile.name,
              subtitle: profile.email,
              avatarUrl: _avatarOverride ?? profile.avatarUrl,
              onAvatarTap: _changeAvatar,
              nameAction: IconButton(
                tooltip: 'Змінити ім’я',
                onPressed: _changeName,
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Container(
              key: const Key('profile_xp_progress'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF14231D),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.workspace_premium,
                          color: Color(0xFFD4A017), size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(profile.level,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600))),
                      Text('${profile.xp} XP'),
                    ]),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: nextXp == null
                          ? 1
                          : (profile.xp / nextXp).clamp(0, 1),
                      minHeight: 4,
                      color: const Color(0xFFD4A017),
                    ),
                    if (nextXp != null) ...[
                      const SizedBox(height: 3),
                      Text('${profile.xp} / $nextXp XP',
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ]),
            ),
            const SizedBox(height: 8),
            ProfileStats(items: [
              (label: 'Локації', value: '${profile.locationsCount}'),
              if (savedCount != null) (label: 'Закладки', value: '$savedCount'),
              if (achievementProgress != null)
                (label: 'Досягнення', value: '${achievementProgress.unlocked}'),
            ]),
            const SizedBox(height: 10),
            _ProfileSection(
                title: 'SOCIAL',
                actions: const [
                  ProfileAction('friends', Icons.people_outline, 'Друзі'),
                  ProfileAction('chat', Icons.chat_bubble_outline, 'Чати'),
                ],
                onTap: _open),
            _ProfileSection(
                title: 'TRAVEL',
                actions: const [
                  ProfileAction('saved', Icons.bookmark_outline, 'Закладки'),
                  ProfileAction('routes', Icons.route_outlined, 'Маршрути'),
                ],
                onTap: _open),
            _ProfileSection(
                title: 'PROGRESSION',
                actions: [
                  ProfileAction(
                    'achievements',
                    Icons.emoji_events_outlined,
                    'Досягнення',
                    subtitle: achievementProgress == null
                        ? null
                        : '${achievementProgress.unlocked} із ${achievementProgress.total}',
                  ),
                  ProfileAction('invites', Icons.person_add_alt, 'Інвайти',
                      subtitle: 'Доступно: $inviteBalance'),
                  const ProfileAction(
                      'top', Icons.leaderboard_outlined, 'Лідерборд'),
                ],
                onTap: _open),
            _ProfileSection(
                title: 'SYSTEM',
                actions: const [
                  ProfileAction(
                      'settings', Icons.settings_outlined, 'Налаштування'),
                  ProfileAction('logout', Icons.logout, 'Вийти',
                      destructive: true),
                ],
                onTap: _open),
          ],
        ),
      ),
    );
  }
}

class ProfileAction {
  const ProfileAction(this.destination, this.icon, this.title,
      {this.subtitle, this.destructive = false});
  final String destination;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection(
      {required this.title, required this.actions, required this.onTap});
  final String title;
  final List<ProfileAction> actions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(color: Colors.white10),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                  children: actions.indexed.map((entry) {
                final action = entry.$2;
                return Column(children: [
                  if (entry.$1 > 0) const Divider(indent: 38, height: 1),
                  ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -4),
                    key: Key('profile_action_${action.destination}'),
                    minTileHeight: 40,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    minLeadingWidth: 28,
                    leading: Icon(action.icon,
                        color: action.destructive ? Colors.redAccent : null),
                    title: Text(action.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: action.subtitle == null
                        ? null
                        : Text(action.subtitle!,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: action.destructive
                        ? null
                        : const Icon(Icons.chevron_right),
                    onTap: () => onTap(action.destination),
                  ),
                ]);
              }).toList(growable: false)),
            ),
          ),
        ]),
      );
}

int? _nextXp(int xp) {
  for (final threshold in const [200, 700, 1500, 3000]) {
    if (xp < threshold) return threshold;
  }
  return null;
}
