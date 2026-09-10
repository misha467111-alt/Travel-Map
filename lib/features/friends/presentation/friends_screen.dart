import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/providers/locations_provider.dart';
import '../domain/friend_models.dart';
import '../providers/friends_provider.dart';
import '../../social/presentation/user_profile_screen.dart';

class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: const Text('Друзі',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Мої друзі'),
              Tab(text: 'Запити'),
              Tab(text: 'Пошук'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _FriendsTab(),
            _RequestsTab(),
            _SearchTab(),
          ],
        ),
      ),
    );
  }
}

class _FriendsTab extends ConsumerWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(acceptedFriendsProvider);
    return _AsyncList<FriendProfile>(
      value: friends,
      emptyMessage: 'У вас ще немає друзів.',
      onRefresh: () => ref.invalidate(acceptedFriendsProvider),
      itemBuilder: (friend) => _ProfileTile(profile: friend),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    FriendRequest request,
  ) async {
    try {
      await ref.read(friendsRepositoryProvider).acceptRequest(request.id);
      ref.invalidate(pendingFriendRequestsProvider);
      ref.invalidate(acceptedFriendsProvider);
      ref.invalidate(fetchLocationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${request.sender.name} тепер у друзях.')),
        );
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(pendingFriendRequestsProvider);
    return _AsyncList<FriendRequest>(
      value: requests,
      emptyMessage: 'Нових запитів немає.',
      onRefresh: () => ref.invalidate(pendingFriendRequestsProvider),
      itemBuilder: (request) => _ProfileTile(
        profile: request.sender,
        trailing: FilledButton(
          onPressed: () => _accept(context, ref, request),
          child: const Text('Прийняти'),
        ),
      ),
    );
  }
}

class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab();

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  final _controller = TextEditingController();
  String _query = '';
  final Set<String> _sentRequests = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search() {
    FocusScope.of(context).unfocus();
    setState(() => _query = _controller.text.trim());
  }

  Future<void> _sendRequest(FriendProfile profile) async {
    try {
      await ref.read(friendsRepositoryProvider).sendRequest(profile.id);
      if (mounted) {
        setState(() => _sentRequests.add(profile.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Запит для ${profile.name} надіслано.')),
        );
      }
    } catch (error) {
      if (mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchFriendsProvider(_query));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Ім’я користувача',
              hintText: 'Введіть щонайменше 2 символи',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        Expanded(
          child: _query.length < 2
              ? const Center(child: Text('Введіть ім’я для пошуку.'))
              : _AsyncList<FriendProfile>(
                  value: results,
                  emptyMessage: 'Користувачів не знайдено.',
                  onRefresh: () =>
                      ref.invalidate(searchFriendsProvider(_query)),
                  itemBuilder: (profile) => _ProfileTile(
                    profile: profile,
                    trailing: FilledButton.tonal(
                      onPressed: _sentRequests.contains(profile.id)
                          ? null
                          : () => _sendRequest(profile),
                      child: Text(
                        _sentRequests.contains(profile.id)
                            ? 'Надіслано'
                            : 'Додати',
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.value,
    required this.emptyMessage,
    required this.onRefresh,
    required this.itemBuilder,
  });

  final AsyncValue<List<T>> value;
  final String emptyMessage;
  final VoidCallback onRefresh;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.people_outline,
                    size: 44, color: Color(0xFFD4A017)),
                const SizedBox(height: 12),
                Text(emptyMessage, textAlign: TextAlign.center),
              ]),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) => itemBuilder(items[index]),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не вдалося завантажити дані.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторити'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, this.trailing});

  final FriendProfile profile;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final avatar = profile.avatarUrl;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              avatar == null || avatar.isEmpty ? null : NetworkImage(avatar),
          child: avatar == null || avatar.isEmpty
              ? const Icon(Icons.person)
              : null,
        ),
        title: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('Профіль мандрівника',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        trailing: trailing,
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UserProfileScreen(userId: profile.id),
          ),
        ),
      ),
    );
  }
}

void _showError(BuildContext context, Object _) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Не вдалося виконати дію. Спробуйте ще раз.'),
      backgroundColor: Colors.red,
    ),
  );
}
