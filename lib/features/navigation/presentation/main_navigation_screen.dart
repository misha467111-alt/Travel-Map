import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../controllers/profile_controller.dart';
import '../../achievements/presentation/achievements_tab.dart';
import '../../friends/presentation/friends_screen.dart';
import '../../gps/presentation/gps_active_recording_banner.dart';
import '../../map/presentation/map_screen.dart';
import '../../map/presentation/map_reference_icons.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../profile/presentation/saved_screen.dart';
import '../../social/presentation/user_profile_screen.dart';
import 'scalable_locations_screen.dart';
import 'chats_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _index = 0;

  static const _pages = <Widget>[
    MapScreen(),
    ScalableLocationsScreen(mode: ScalableLocationListMode.discover),
    ScalableLocationsScreen(mode: ScalableLocationListMode.adventure),
    ScalableLocationsScreen(mode: ScalableLocationListMode.routes),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final effectiveScale =
        mediaQuery.textScaler.scale(1).clamp(1.0, 1.12).toDouble();
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        // The active-recording banner lives outside the tab IndexedStack,
        // above the existing 5-tab bar -- it is not a sixth tab, and it
        // stays visible/consistent no matter which tab is selected.
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GpsActiveRecordingBanner(),
            _index == 0
                ? _MapBottomNavigation(
                    onSelected: (value) => setState(() => _index = value),
                  )
                : NavigationBar(
                    height: _index == 0 ? 60 : 72,
                    indicatorColor: Colors.transparent,
                    selectedIndex: _index,
                    onDestinationSelected: (value) =>
                        setState(() => _index = value),
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.map_outlined),
                          selectedIcon: Icon(Icons.map),
                          label: 'Карта'),
                      NavigationDestination(
                          icon: Icon(Icons.explore_outlined),
                          selectedIcon: Icon(Icons.explore),
                          label: 'Відкривай'),
                      NavigationDestination(
                          icon: Icon(Icons.person_pin_circle_outlined),
                          selectedIcon: Icon(Icons.person_pin_circle),
                          label: 'Пригода'),
                      NavigationDestination(
                          icon: Icon(Icons.route_outlined),
                          selectedIcon: Icon(Icons.route),
                          label: 'Маршрути'),
                      NavigationDestination(
                          icon: Icon(Icons.person_outline),
                          selectedIcon: Icon(Icons.person),
                          label: 'Профіль'),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

/// Compact map presentation; tab indices and the existing IndexedStack are shared.
class _MapBottomNavigation extends StatelessWidget {
  const _MapBottomNavigation({required this.onSelected});
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF09120F),
        child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(children: [
                for (final (index, item) in const [
                  (MapReferenceGlyph.map, 'Карта'),
                  (MapReferenceGlyph.compass, 'Відкривай'),
                  (MapReferenceGlyph.adventure, 'Пригода'),
                  (MapReferenceGlyph.route, 'Маршрути'),
                  (MapReferenceGlyph.profile, 'Профіль'),
                ].indexed)
                  Expanded(
                      child: Semantics(
                    selected: index == 0,
                    button: true,
                    child: InkWell(
                      onTap: () => onSelected(index),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MapReferenceIcon(item.$1,
                                size: 22,
                                color: index == 0
                                    ? const Color(0xFFD4A017)
                                    : const Color(0xFFA3AAA3)),
                            const SizedBox(height: 5),
                            Text(item.$2,
                                style: TextStyle(
                                    fontSize: 10,
                                    height: 1,
                                    fontWeight: FontWeight.w400,
                                    color: index == 0
                                        ? const Color(0xFFD4A017)
                                        : const Color(0xFFA3AAA3))),
                          ]),
                    ),
                  )),
              ]),
            )),
      );
}

void openSecondarySection(BuildContext context, String value) {
  final Widget screen = switch (value) {
    'friends' => const FriendsScreen(),
    'chat' => const ChatsScreen(),
    'saved' => const SavedScreen(),
    'routes' =>
      const ScalableLocationsScreen(mode: ScalableLocationListMode.routes),
    'random' =>
      const ScalableLocationsScreen(mode: ScalableLocationListMode.adventure),
    'nearby' =>
      const ScalableLocationsScreen(mode: ScalableLocationListMode.nearby),
    'top' => const _TopTravelersScreen(),
    'achievements' => const Scaffold(
        appBar: _SimpleAppBar(title: 'Досягнення та квести'),
        body: AchievementsTab()),
    'invites' => const _InvitesScreen(),
    'notifications' => const NotificationsScreen(),
    'settings' => const SettingsScreen(),
    _ => const SettingsScreen(),
  };
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class _SimpleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SimpleAppBar({required this.title});
  final String title;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(
        toolbarHeight: 52,
        title: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      );
}

class _InvitesScreen extends StatefulWidget {
  const _InvitesScreen();
  @override
  State<_InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<_InvitesScreen> {
  bool _busy = false;
  String? _code;
  Future<void> _create() async {
    setState(() => _busy = true);
    final code = await profileController.generateNewInviteCode();
    if (mounted) {
      setState(() {
        _busy = false;
        _code = code;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: profileController,
        builder: (_, __) => Scaffold(
            appBar: AppBar(
              toolbarHeight: 52,
              title: const Text('Запрошення',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14231D),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.person_add_alt_rounded,
                          size: 26, color: Color(0xFFD4A017)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${profileController.invitesLeft}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontSize: 20,
                                      color: const Color(0xFFD4A017),
                                      fontWeight: FontWeight.w600,
                                    )),
                            const Text('Доступно запрошень',
                                style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      onPressed: _busy || profileController.invitesLeft <= 0
                          ? null
                          : _create,
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Створити invite-код',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600))),
                  if (_busy) const LinearProgressIndicator(),
                  if (_code != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1C17),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: const Color(0x66D4A017)),
                      ),
                      child: SelectableText(_code!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(letterSpacing: 3)),
                    ),
                  ],
                ],
              ),
            )),
      );
}

class _TopTravelersScreen extends StatelessWidget {
  const _TopTravelersScreen();
  Future<List<Map<String, dynamic>>> _load() async => Supabase.instance.client
      .from('profiles')
      .select('id,display_name,username,avatar_url,xp')
      .order('xp', ascending: false)
      .limit(50);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text('Топ мандрівників',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _load(),
          builder: (_, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                  child: Text('Не вдалося завантажити рейтинг.'));
            }
            final rows = snapshot.data ?? const <Map<String, dynamic>>[];
            if (rows.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.leaderboard_outlined,
                        size: 46, color: Color(0xFFD4A017)),
                    SizedBox(height: 12),
                    Text('Рейтинг поки порожній'),
                  ]),
                ),
              );
            }
            final currentUserId = Supabase.instance.client.auth.currentUser?.id;
            return ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                children: [
                  for (final (index, row) in rows.indexed)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                      color: row['id'] == currentUserId
                          ? const Color(0xFF203426)
                          : null,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: index < 3
                                ? const Color(0xFFD4A017)
                                : const Color(0xFF20362C),
                            foregroundColor:
                                index < 3 ? Colors.black : Colors.white,
                            child: Text('${index + 1}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          title: Text(
                              (row['display_name'] ??
                                      row['username'] ??
                                      'Мандрівник')
                                  .toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: Text('${row['xp'] ?? 0} XP',
                              style: const TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontWeight: FontWeight.w600)),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => UserProfileScreen(
                                      userId: row['id'] as String)))),
                    ),
                ]);
          }));
}
