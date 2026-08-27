import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/profile_controller.dart';
import '../../navigation/presentation/main_navigation_screen.dart';
import '../domain/user_profile.dart';
import '../providers/profile_provider.dart';
import 'profile_components.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(
          title: const Text('Профіль'),
          actions: [
            IconButton(
              tooltip: 'Оновити профіль',
              onPressed: () => ref.invalidate(currentProfileProvider),
              icon: const Icon(Icons.refresh),
            )
          ],
        ),
        body: ref.watch(currentProfileProvider).when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              data: (profile) => _ProfileContent(profile: profile),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                  child: FilledButton.icon(
                onPressed: () => ref.invalidate(currentProfileProvider),
                icon: const Icon(Icons.refresh),
                label: Text('Не вдалося завантажити: $error'),
              )),
            ),
      );
}

class _ProfileContent extends ConsumerStatefulWidget {
  const _ProfileContent({required this.profile});
  final UserProfile profile;
  @override
  ConsumerState<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends ConsumerState<_ProfileContent> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(currentProfileProvider);
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
    await _run(() => ref
        .read(profileRepositoryProvider)
        .uploadAvatar(bytes, extension: extension));
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
    await _run(
        () => ref.read(profileRepositoryProvider).updateDisplayName(name));
  }

  void _open(String destination) {
    if (destination == 'logout') {
      profileController.logout();
    } else {
      openSecondarySection(context, destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final nextXp = _nextXp(profile.xp);
    return AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          ProfileIdentityHeader(
            name: profile.name,
            subtitle: profile.email,
            avatarUrl: profile.avatarUrl,
            onAvatarTap: _changeAvatar,
            nameAction: IconButton(
              tooltip: 'Змінити ім’я',
              onPressed: _changeName,
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.workspace_premium,
                          color: Color(0xFFD4A017)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(profile.level,
                              style: Theme.of(context).textTheme.titleMedium)),
                      Text('${profile.xp} XP'),
                    ]),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: nextXp == null
                          ? 1
                          : (profile.xp / nextXp).clamp(0, 1),
                      minHeight: 7,
                    ),
                    if (nextXp != null) Text('${profile.xp} / $nextXp XP'),
                  ]),
            ),
          ),
          const SizedBox(height: 12),
          ProfileStats(items: [
            (label: 'Локації', value: '${profile.locationsCount}'),
            (label: 'XP', value: '${profile.xp}'),
          ]),
          const SizedBox(height: 18),
          _ProfileSection(
              title: 'SOCIAL',
              actions: const [
                _ProfileAction('friends', Icons.people_outline, 'Друзі'),
                _ProfileAction('chat', Icons.chat_bubble_outline, 'Чати'),
              ],
              onTap: _open),
          _ProfileSection(
              title: 'TRAVEL',
              actions: const [
                _ProfileAction('saved', Icons.bookmark_outline, 'Мої закладки'),
                _ProfileAction('routes', Icons.route_outlined, 'Мої маршрути'),
              ],
              onTap: _open),
          _ProfileSection(
              title: 'PROGRESSION',
              actions: const [
                _ProfileAction(
                    'achievements', Icons.emoji_events_outlined, 'Досягнення'),
                _ProfileAction('invites', Icons.person_add_alt, 'Інвайти'),
                _ProfileAction('top', Icons.leaderboard_outlined, 'Лідерборд'),
              ],
              onTap: _open),
          _ProfileSection(
              title: 'SYSTEM',
              actions: const [
                _ProfileAction(
                    'settings', Icons.settings_outlined, 'Налаштування'),
                _ProfileAction('logout', Icons.logout, 'Вийти',
                    destructive: true),
              ],
              onTap: _open),
        ],
      ),
    );
  }
}

class _ProfileAction {
  const _ProfileAction(this.destination, this.icon, this.title,
      {this.destructive = false});
  final String destination;
  final IconData icon;
  final String title;
  final bool destructive;
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection(
      {required this.title, required this.actions, required this.onTap});
  final String title;
  final List<_ProfileAction> actions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Text(title, style: Theme.of(context).textTheme.labelLarge),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
                children: actions
                    .map((action) => ListTile(
                          minTileHeight: 56,
                          leading: Icon(action.icon,
                              color:
                                  action.destructive ? Colors.redAccent : null),
                          title: Text(action.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: action.destructive
                              ? null
                              : const Icon(Icons.chevron_right),
                          onTap: () => onTap(action.destination),
                        ))
                    .toList(growable: false)),
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
