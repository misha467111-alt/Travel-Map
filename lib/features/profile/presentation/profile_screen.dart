import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/profile_controller.dart';
import '../../achievements/providers/achievements_provider.dart';
import '../../chat/local/chat_local_database_provider.dart';
import '../../gps/local/gps_local_database_provider.dart';
import '../../navigation/presentation/main_navigation_screen.dart';
import '../../social/providers/public_profile_provider.dart';
import '../domain/user_profile.dart';
import '../providers/profile_provider.dart';
import '../../achievements/domain/achievement_model.dart';
import '../../gps/presentation/gps_journey_summary_view.dart'
    show formatGpsDistance;
import '../providers/profile_journey_stats_provider.dart';
import 'profile_premium_components.dart';
import '../../../core/theme/app_design.dart';

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
    this.unlockedAchievementsOverride,
    this.journeyStatsOverride,
    super.key,
  });
  final UserProfile profile;
  final ValueChanged<String>? onDestination;
  final VoidCallback? onLogout;
  final int? savedCountOverride;
  final ({int unlocked, int total})? achievementProgressOverride;
  final int? inviteBalanceOverride;

  /// Test seam: the achievements list (real data) and the Journey stats.
  final List<AchievementModel>? unlockedAchievementsOverride;
  final AsyncValue<ProfileJourneyStats>? journeyStatsOverride;
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
      if (widget.onLogout != null) {
        widget.onLogout!();
      } else {
        unawaited(_logout());
      }
    } else {
      if (widget.onDestination != null) {
        widget.onDestination!(destination);
      } else {
        openSecondarySection(context, destination);
      }
    }
  }

  Future<void> _logout() async {
    final blockingRouteId = await blockingActiveRecordingId(ref);
    if (blockingRouteId != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'Завершіть або скасуйте активний GPS-запис перед виходом з акаунту.',
          ),
        ));
      }
      return;
    }
    await clearChatCacheOnLogout(ref);
    await profileController.logout();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final savedState = widget.savedCountOverride == null
        ? ref.watch(savedPublicLocationsProvider)
        : null;
    final achievementsState = widget.achievementProgressOverride == null &&
            widget.unlockedAchievementsOverride == null
        ? ref.watch(achievementsProvider)
        : null;
    final savedCount = widget.savedCountOverride ?? savedState?.value?.length;
    final achievementList =
        widget.unlockedAchievementsOverride ?? achievementsState?.value;
    final achievementProgress = widget.achievementProgressOverride ??
        (achievementList == null
            ? null
            : (
                unlocked: achievementList.where((a) => a.isUnlocked).length,
                total: achievementList.length,
              ));
    // Real, unlocked awards only, newest first; null while the list is not
    // known (loading / error / counters-only) so nothing is invented.
    final unlockedMedals = achievementList == null
        ? null
        : (achievementList.where((a) => a.isUnlocked).toList()
          ..sort((a, b) => (b.unlockedAt ?? DateTime(0))
              .compareTo(a.unlockedAt ?? DateTime(0))));
    final AsyncValue<ProfileJourneyStats> journeyState =
        widget.journeyStatsOverride ??
            ref.watch(profileJourneyStatsProvider(profile.id));
    final journeyTile = journeyTileText(journeyState, formatGpsDistance);
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
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
          children: [
            PremiumTravelerHero(
              name: _nameOverride ?? profile.name,
              email: profile.email,
              level: profile.level,
              xp: profile.xp,
              avatarUrl: _avatarOverride ?? profile.avatarUrl,
              onAvatarTap: _changeAvatar,
              nameAction: IconButton(
                tooltip: 'Змінити ім’я',
                onPressed: _changeName,
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            PremiumStatsGrid(tiles: [
              PremiumStatTile(
                  icon: Icons.place_outlined,
                  label: 'Локації',
                  value: '${profile.locationsCount}'),
              PremiumStatTile(
                  icon: Icons.bookmark_outline,
                  label: 'Закладки',
                  value: savedCount == null ? '—' : '$savedCount'),
              PremiumStatTile(
                  icon: Icons.emoji_events_outlined,
                  label: 'Досягнення',
                  value: achievementProgress == null
                      ? '—'
                      : '${achievementProgress.unlocked}'),
              PremiumStatTile(
                  key: const Key('profile_stat_journeys'),
                  icon: Icons.route_outlined,
                  label: 'Подорожі',
                  value: journeyTile.value,
                  caption: journeyTile.caption,
                  loading: journeyTile.loading),
            ]),
            const SizedBox(height: AppSpacing.sm),
            PremiumAchievementsStrip(
              progress: achievementProgress,
              unlocked: unlockedMedals,
              loading: achievementsState?.isLoading == true &&
                  achievementList == null,
              failed: achievementsState?.hasError == true &&
                  achievementList == null,
              onOpenAll: () => _open('achievements'),
            ),
            PremiumActionCard(title: 'Спільнота', rows: [
              PremiumActionRow(
                  destination: 'friends',
                  icon: Icons.people_outline,
                  title: 'Друзі',
                  onTap: _open),
              PremiumActionRow(
                  destination: 'chat',
                  icon: Icons.chat_bubble_outline,
                  title: 'Чати',
                  onTap: _open),
              PremiumActionRow(
                  destination: 'invites',
                  icon: Icons.person_add_alt,
                  title: 'Інвайти',
                  subtitle: 'Доступно: $inviteBalance',
                  onTap: _open),
              PremiumActionRow(
                  destination: 'top',
                  icon: Icons.leaderboard_outlined,
                  title: 'Лідерборд',
                  onTap: _open),
            ]),
            PremiumActionCard(title: 'Мої подорожі', rows: [
              PremiumActionRow(
                  destination: 'saved',
                  icon: Icons.bookmark_outline,
                  title: 'Закладки',
                  onTap: _open),
              PremiumActionRow(
                  destination: 'routes',
                  icon: Icons.route_outlined,
                  title: 'Маршрути',
                  onTap: _open),
              PremiumActionRow(
                  destination: 'journeys',
                  icon: Icons.history,
                  title: 'Історія подорожей',
                  onTap: _open),
            ]),
            PremiumActionCard(title: 'Система', rows: [
              PremiumActionRow(
                  destination: 'personalization',
                  icon: Icons.palette_outlined,
                  title: 'Персоналізація',
                  onTap: _open),
              PremiumActionRow(
                  destination: 'settings',
                  icon: Icons.settings_outlined,
                  title: 'Налаштування',
                  onTap: _open),
              PremiumActionRow(
                  destination: 'logout',
                  icon: Icons.logout,
                  title: 'Вийти',
                  destructive: true,
                  onTap: _open),
            ]),
          ],
        ),
      ),
    );
  }
}
