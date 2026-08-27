import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../controllers/profile_controller.dart';
import '../../../providers/chat_provider.dart';
import '../../achievements/presentation/achievements_tab.dart';
import '../../friends/domain/friend_models.dart';
import '../../friends/presentation/friends_screen.dart';
import '../../friends/providers/friends_provider.dart';
import '../../map/domain/location_model.dart';
import '../../map/domain/location_query.dart';
import '../../map/presentation/map_screen.dart';
import '../../map/presentation/location_card.dart';
import '../../map/providers/locations_provider.dart';
import '../../map/providers/map_provider.dart';
import '../../map/providers/route_provider.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../social/presentation/user_profile_screen.dart';
import '../../social/providers/public_profile_provider.dart';
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
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: 'Карта'),
            NavigationDestination(
                icon: Icon(Icons.dynamic_feed_outlined),
                selectedIcon: Icon(Icons.dynamic_feed),
                label: 'Відкривай'),
            NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
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
      );
}

enum _LocationListMode { feed, random, saved, nearby }

enum _TransportMode { walk, bike, car }

enum _TravelParty { solo, couple, friends }

class _LocationsListScreen extends ConsumerStatefulWidget {
  const _LocationsListScreen({required this.mode});
  final _LocationListMode mode;

  @override
  ConsumerState<_LocationsListScreen> createState() =>
      _LocationsListScreenState();
}

class _LocationsListScreenState extends ConsumerState<_LocationsListScreen> {
  double _radiusKm = 10;
  double _travelMinutes = 30;
  String _query = '';
  String _category = 'all';
  LocationModel? _random;
  _TransportMode _transport = _TransportMode.walk;
  _TravelParty _party = _TravelParty.solo;
  List<LocationModel> _discoverItems = const [];
  LocationCursor? _discoverCursor;
  bool _discoverHasMore = true;
  bool _discoverLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == _LocationListMode.feed) {
      Future.microtask(() => _loadDiscover(reset: true));
    }
  }

  Future<void> _loadDiscover({required bool reset}) async {
    if (_discoverLoading || (!reset && !_discoverHasMore)) return;
    setState(() {
      _discoverLoading = true;
      if (reset) {
        _discoverItems = const [];
        _discoverCursor = null;
        _discoverHasMore = true;
      }
    });
    try {
      final page =
          await ref.read(locationsRepositoryProvider).fetchDiscoverPage(
                cursor: reset ? null : _discoverCursor,
                category: _category == 'all' ? null : _category,
                search: _query,
              );
      if (!mounted) return;
      setState(() {
        _discoverItems = reset
            ? page.items.map((item) => item.location).toList(growable: false)
            : [..._discoverItems, ...page.items.map((item) => item.location)];
        _discoverCursor = page.nextCursor;
        _discoverHasMore = page.hasMore;
      });
    } catch (error) {
      // The reachable scalable screen reports page errors inline.
    } finally {
      if (mounted) setState(() => _discoverLoading = false);
    }
  }

  String get _title => switch (widget.mode) {
        _LocationListMode.feed => 'Відкривай нові місця',
        _LocationListMode.random => 'Пригода',
        _LocationListMode.saved => 'Збережені місця',
        _LocationListMode.nearby => 'Сфера поруч',
      };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fetchLocationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
              onPressed: () => ref.invalidate(fetchLocationsProvider),
              icon: const Icon(Icons.refresh),
              tooltip: 'Оновити'),
          const _MoreMenuButton(),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Не вдалося завантажити локації: $error')),
        data: (all) {
          if (widget.mode != _LocationListMode.random &&
              widget.mode != _LocationListMode.nearby) {
            return _buildList(all, null);
          }
          return ref.watch(currentPositionProvider).when(
                loading: () => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Визначаємо вашу позицію…'),
                    ],
                  ),
                ),
                error: (error, _) => _LocationError(
                  error: error,
                  onRetry: () => ref.invalidate(currentPositionProvider),
                ),
                data: (position) => _buildList(all, position),
              );
        },
      ),
    );
  }

  Widget _buildList(List<LocationModel> all, Position? position) {
    var candidates = all.where((item) {
      final search = _query.toLowerCase();
      return (_category == 'all' || item.category == _category) &&
          (search.isEmpty ||
              item.title.toLowerCase().contains(search) ||
              (item.description ?? '').toLowerCase().contains(search));
    }).toList();
    if (widget.mode == _LocationListMode.saved) {
      final saved =
          ref.watch(savedPublicLocationsProvider).value ?? const <String>{};
      candidates = candidates.where((item) => saved.contains(item.id)).toList();
    }
    if (position != null) {
      final effectiveRadiusKm = widget.mode == _LocationListMode.random
          ? math.min(_radiusKm, _travelRadiusKm)
          : _radiusKm;
      candidates = candidates
          .where((item) =>
              _distanceMeters(position, item) <= effectiveRadiusKm * 1000)
          .toList()
        ..sort((a, b) => _distanceMeters(position, a)
            .compareTo(_distanceMeters(position, b)));
    }
    final items = widget.mode == _LocationListMode.random
        ? (_random != null && candidates.any((item) => item.id == _random!.id)
            ? <LocationModel>[_random!]
            : <LocationModel>[])
        : candidates;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(fetchLocationsProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (widget.mode == _LocationListMode.feed) ...[
            Text('Швидкий пошук',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.radar, size: 18),
                  label: const Text('Поруч'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _LocationsListScreen(
                          mode: _LocationListMode.nearby),
                    ),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.bookmark_outline, size: 18),
                  label: const Text('Збережені'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _LocationsListScreen(
                          mode: _LocationListMode.saved),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Пошук місць',
                border: OutlineInputBorder()),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 8),
          Wrap(
              spacing: 6,
              children: [
                'all',
                'general',
                'cafe',
                'nature',
                'culture',
                'entertainment'
              ]
                  .map((category) => ChoiceChip(
                        label: Text(category == 'all' ? 'Усі' : category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ))
                  .toList()),
          if (widget.mode == _LocationListMode.random ||
              widget.mode == _LocationListMode.nearby) ...[
            Text('Радіус: ${_radiusKm.round()} км'),
            Slider(
                value: _radiusKm,
                min: 1,
                max: 50,
                divisions: 49,
                onChanged: (value) => setState(() => _radiusKm = value)),
          ],
          if (widget.mode == _LocationListMode.random) ...[
            Text('Час у дорозі: ${_travelMinutes.round()} хв'),
            Slider(
              value: _travelMinutes,
              min: 10,
              max: 180,
              divisions: 17,
              onChanged: (value) => setState(() => _travelMinutes = value),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<_TransportMode>(
                    initialValue: _transport,
                    decoration: const InputDecoration(labelText: 'Транспорт'),
                    items: _TransportMode.values
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_transportLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _transport = value ?? _transport),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<_TravelParty>(
                    initialValue: _party,
                    decoration: const InputDecoration(labelText: 'Компанія'),
                    items: _TravelParty.values
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(_partyLabel(value)),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _party = value ?? _party),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Доступна відстань за часом: ${_travelRadiusKm.toStringAsFixed(1)} км',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
          ],
          if (widget.mode == _LocationListMode.random)
            FilledButton.icon(
              onPressed: candidates.isEmpty
                  ? null
                  : () => setState(() => _random =
                      candidates[math.Random().nextInt(candidates.length)]),
              icon: const Icon(Icons.auto_awesome),
              label: Text('Surprise me · ${_partyLabel(_party).toLowerCase()}'),
            ),
          if (candidates.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('У вибраному радіусі локацій не знайдено'),
              ),
            )
          else if (items.isEmpty && widget.mode == _LocationListMode.random)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Натисніть кнопку для вибору місця')),
            ),
          ...items.map((location) => _LocationListCard(
                location: location,
                distanceMeters: position == null
                    ? null
                    : _distanceMeters(position, location),
              )),
        ],
      ),
    );
  }

  static double _distanceMeters(Position position, LocationModel location) =>
      Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        location.latitude,
        location.longitude,
      );

  double get _travelRadiusKm {
    final speedKmH = switch (_transport) {
      _TransportMode.walk => 4.5,
      _TransportMode.bike => 14.0,
      _TransportMode.car => 45.0,
    };
    return speedKmH * _travelMinutes / 60;
  }

  static String _transportLabel(_TransportMode value) => switch (value) {
        _TransportMode.walk => 'Пішки',
        _TransportMode.bike => 'Велосипед',
        _TransportMode.car => 'Авто',
      };

  static String _partyLabel(_TravelParty value) => switch (value) {
        _TravelParty.solo => 'Соло',
        _TravelParty.couple => 'Удвох',
        _TravelParty.friends => 'З друзями',
      };
}

class _LocationError extends StatelessWidget {
  const _LocationError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text('Не вдалося визначити геопозицію: $error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Спробувати ще раз'),
              ),
            ],
          ),
        ),
      );
}

class _LocationListCard extends ConsumerWidget {
  const _LocationListCard({required this.location, this.distanceMeters});
  final LocationModel location;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved =
        ref.watch(savedPublicLocationsProvider).value ?? const <String>{};
    final author = ref.watch(publicProfileProvider(location.userId));
    final profile = author.value;
    return LocationCard(
      location: location,
      distanceMeters: distanceMeters,
      isSaved: saved.contains(location.id),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LocationDetailsScreen(location: location))),
      onBookmarkTap: () =>
          ref.read(savedPublicLocationsProvider.notifier).toggle(location.id),
      authorName: profile?.name ?? (author.hasError ? 'Профіль автора' : null),
      authorAvatarUrl: profile?.avatarUrl,
      onAuthorTap: () => context.push('/users/${location.userId}'),
    );
  }
}

// ignore: unused_element
class _RoutesScreen extends ConsumerWidget {
  const _RoutesScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(routeProvider);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Маршрути'), actions: const [_MoreMenuButton()]),
      body: ref.watch(fetchLocationsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
                child: Text('Не вдалося завантажити точки маршрутів: $error')),
            data: (items) =>
                ListView(padding: const EdgeInsets.all(16), children: [
              if (route.status != RouteStatus.idle)
                Card(
                  child: ListTile(
                    leading: Icon(route.status == RouteStatus.success
                        ? Icons.route
                        : route.status == RouteStatus.failure
                            ? Icons.error_outline
                            : Icons.hourglass_top),
                    title: Text(route.status == RouteStatus.success
                        ? 'Активний маршрут'
                        : route.status == RouteStatus.failure
                            ? 'Маршрут не побудовано'
                            : 'Будуємо маршрут…'),
                    subtitle: Text(route.status == RouteStatus.success
                        ? '${LocationCard.formatDistance(route.distanceMeters ?? 0)} · ${((route.durationSeconds ?? 0) / 60).round()} хв'
                        : route.errorMessage ?? 'Зачекайте'),
                    trailing: IconButton(
                      tooltip: 'Скинути маршрут',
                      onPressed: () => ref.read(routeProvider.notifier).clear(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              const Card(
                  child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Побудова маршруту'),
                      subtitle: Text(
                          'Оберіть локацію та натисніть «Побудувати маршрут» у її деталях.'))),
              ...items.take(20).map((item) => ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(item.title),
                    subtitle: Text(item.category),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => LocationDetailsScreen(location: item),
                    )),
                  )),
            ]),
          ),
    );
  }
}

class _MoreMenuButton extends StatelessWidget {
  const _MoreMenuButton();
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Розділи',
        onSelected: (value) => openSecondarySection(context, value),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'friends', child: Text('Друзі та пошук людей')),
          PopupMenuItem(value: 'chat', child: Text('Чати')),
          PopupMenuItem(value: 'saved', child: Text('Збережені місця')),
          PopupMenuItem(value: 'nearby', child: Text('Сфера поруч')),
          PopupMenuItem(value: 'top', child: Text('Топ мандрівників')),
          PopupMenuItem(
              value: 'achievements', child: Text('Досягнення та квести')),
          PopupMenuItem(value: 'invites', child: Text('Запрошення')),
          PopupMenuItem(value: 'notifications', child: Text('Сповіщення')),
          PopupMenuItem(value: 'settings', child: Text('Налаштування')),
        ],
        icon: const Icon(Icons.more_vert),
      );
}

void openSecondarySection(BuildContext context, String value) {
  final Widget screen = switch (value) {
    'friends' => const FriendsScreen(),
    'chat' => const ChatsScreen(),
    'saved' =>
      const ScalableLocationsScreen(mode: ScalableLocationListMode.saved),
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
  Widget build(BuildContext context) => AppBar(title: Text(title));
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
            appBar: AppBar(title: const Text('Запрошення')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Доступно запрошень: ${profileController.invitesLeft}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                        onPressed: _busy || profileController.invitesLeft <= 0
                            ? null
                            : _create,
                        icon: const Icon(Icons.add_link),
                        label: const Text('Створити invite-код')),
                    if (_busy) const LinearProgressIndicator(),
                    if (_code != null)
                      SelectableText(_code!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium),
                  ]),
            )),
      );
}

// Legacy implementation retained for dependency safety; canonical entry uses SettingsScreen.
// ignore: unused_element
class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen();
  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Налаштування')),
      body: ListView(children: [
        SwitchListTile(
            value: profileController.isOfflineMode,
            onChanged: (value) =>
                setState(() => profileController.isOfflineMode = value),
            secondary: const Icon(Icons.offline_bolt_outlined),
            title: const Text('Офлайн-режим'),
            subtitle: const Text(
                'Кеш локацій використовується автоматично без мережі.')),
        ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Модерація'),
            subtitle: const Text(
                'Нові локації проходять production moderation workflow.')),
        ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Вийти'),
            onTap: profileController.logout),
      ]));
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
      appBar: AppBar(title: const Text('Топ мандрівників')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _load(),
          builder: (_, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                  child: Text(
                      'Не вдалося завантажити рейтинг: ${snapshot.error}'));
            }
            return ListView(children: [
              for (final (index, row)
                  in (snapshot.data ?? const <Map<String, dynamic>>[]).indexed)
                ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(
                        (row['display_name'] ?? row['username'] ?? 'Мандрівник')
                            .toString()),
                    trailing: Text('${row['xp'] ?? 0} XP'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => UserProfileScreen(
                                userId: row['id'] as String))))
            ]);
          }));
}

// Legacy implementation retained for dependency safety; canonical entry uses ChatsScreen.
// ignore: unused_element
class _ChatsScreen extends ConsumerWidget {
  const _ChatsScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(title: const Text('Чати')),
      body: ref.watch(acceptedFriendsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Не вдалося завантажити чати: $e')),
            data: (friends) => friends.isEmpty
                ? const Center(child: Text('Додайте друга, щоб почати чат'))
                : ListView(
                    children: friends
                        .map((friend) => ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(friend.name),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        _ChatScreen(friend: friend)))))
                        .toList()),
          ));
}

class _ChatScreen extends ConsumerStatefulWidget {
  const _ChatScreen({required this.friend});
  final FriendProfile friend;
  @override
  ConsumerState<_ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<_ChatScreen> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    _controller.clear();
    await ref.read(chatServiceProvider).sendMessage(widget.friend.id, text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.friend.name)),
      body: Column(children: [
        Expanded(
            child: ref.watch(chatStreamProvider(widget.friend.id)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (rows) => ListView(
                    padding: const EdgeInsets.all(12),
                    children: rows
                        .map((row) => Card(
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text((row['text'] ?? '').toString()))))
                        .toList()))),
        SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                              hintText: 'Повідомлення',
                              border: OutlineInputBorder()))),
                  IconButton(onPressed: _send, icon: const Icon(Icons.send))
                ]))),
      ]));
}
