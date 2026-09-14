import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../providers/chat_provider.dart';
import '../../chat/conversation/chat_conversation_controller.dart';
import '../../chat/local/chat_local_database.dart';
import '../../friends/domain/friend_models.dart';
import '../../friends/providers/friends_provider.dart';
import '../../social/presentation/user_profile_screen.dart';

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: const Text('Чати',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: ref.watch(acceptedFriendsProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: const Text('Не вдалося завантажити чати.'),
                ),
              ),
              data: (friends) => friends.isEmpty
                  ? const _EmptyChats()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: friends.length,
                      itemBuilder: (_, index) =>
                          _ConversationCard(friend: friends[index]),
                    ),
            ),
      );
}

class _ConversationCard extends ConsumerWidget {
  const _ConversationCard({required this.friend});
  final FriendProfile friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatStreamProvider(friend.id)).value;
    final last = messages?.isNotEmpty == true ? messages!.last : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        leading: _Avatar(friend: friend),
        title: Text(friend.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          last == null ? 'Почніть розмову' : (last['text'] ?? '').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: last == null
            ? const Icon(Icons.chevron_right)
            : Text(_messageTime(last),
                style: Theme.of(context).textTheme.labelSmall),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ChatScreen(friend: friend),
        )),
      ),
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({required this.friend, super.key});
  final FriendProfile friend;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  double? _extentBeforeLoadOlder;
  String? _lastFirstMessageId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 200) {
      _extentBeforeLoadOlder ??= _scrollController.position.maxScrollExtent;
      ref.read(chatConversationProvider(widget.friend.id)).loadOlder();
    }
  }

  /// If the oldest-known message changed (older messages were prepended
  /// by [ChatConversationController.loadOlder]), keep the user's current
  /// viewport anchored to the same content instead of letting the list
  /// visually jump.
  void _maybeRestoreScrollAfterPrepend(List<LocalMessage> messages) {
    if (messages.isEmpty) {
      _lastFirstMessageId = null;
      return;
    }
    final firstId = messages.first.id;
    final prepended =
        _lastFirstMessageId != null && firstId != _lastFirstMessageId;
    _lastFirstMessageId = firstId;
    final before = _extentBeforeLoadOlder;
    if (prepended && before != null) {
      _extentBeforeLoadOlder = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final delta = _scrollController.position.maxScrollExtent - before;
        if (delta > 0) {
          _scrollController.jumpTo(_scrollController.position.pixels + delta);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(chatServiceProvider).sendMessage(widget.friend.id, text);
      if (mounted) _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Не вдалося надіслати повідомлення. Спробуйте ще раз.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          titleSpacing: 0,
          title: Row(children: [
            _Avatar(friend: widget.friend, radius: 16),
            const SizedBox(width: 8),
            Expanded(
                child:
                    Text(widget.friend.name, overflow: TextOverflow.ellipsis)),
          ]),
          actions: [
            IconButton(
              tooltip: 'Відкрити профіль',
              icon: const Icon(Icons.person_outline),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => UserProfileScreen(userId: widget.friend.id),
              )),
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: ref
                .watch(chatConversationStateProvider(widget.friend.id))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => const Center(
                    child: Text('Не вдалося завантажити повідомлення.'),
                  ),
                  data: (state) {
                    _maybeRestoreScrollAfterPrepend(state.messages);
                    if (state.messages.isEmpty) {
                      if (state.syncError != null) {
                        return _ChatRetryState(
                          message: state.syncError!,
                          onRetry: () => ref
                              .read(chatConversationProvider(widget.friend.id))
                              .retry(),
                        );
                      }
                      return const Center(
                          child: Text('Напишіть перше повідомлення'));
                    }
                    return Column(children: [
                      if (state.isOffline)
                        const _ChatStatusBanner(
                          text: 'Немає з’єднання. Показано збережені '
                              'повідомлення.',
                        ),
                      if (!state.isOffline && state.syncError != null)
                        _ChatStatusBanner(text: state.syncError!),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                          itemCount: state.messages.length +
                              (state.isLoadingOlder ? 1 : 0),
                          itemBuilder: (_, index) {
                            if (state.isLoadingOlder && index == 0) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              );
                            }
                            final msgIndex =
                                state.isLoadingOlder ? index - 1 : index;
                            return _MessageBubble(
                                message: state.messages[msgIndex]);
                          },
                        ),
                      ),
                    ]);
                  },
                ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                8 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Повідомлення',
                      prefixIcon: Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Надіслати',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ]),
      );
}

class _ChatStatusBanner extends StatelessWidget {
  const _ChatStatusBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      );
}

class _ChatRetryState extends StatelessWidget {
  const _ChatRetryState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Спробувати ще раз'),
            ),
          ]),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final LocalMessage message;

  @override
  Widget build(BuildContext context) {
    final mine =
        message.senderId == Supabase.instance.client.auth.currentUser?.id;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF7A5910) : const Color(0xFF14231D),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(11),
            topRight: const Radius.circular(11),
            bottomLeft: Radius.circular(mine ? 11 : 4),
            bottomRight: Radius.circular(mine ? 4 : 11),
          ),
          border: Border.all(
            color: mine ? const Color(0x66D4A017) : Colors.white10,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(message.body ?? ''),
          const SizedBox(height: 3),
          Text(_localMessageTime(message),
              style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.friend, this.radius = 22});
  final FriendProfile friend;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundImage: friend.avatarUrl?.isNotEmpty == true
            ? NetworkImage(friend.avatarUrl!)
            : null,
        child: friend.avatarUrl?.isNotEmpty == true
            ? null
            : const Icon(Icons.person_outline),
      );
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();
  @override
  Widget build(BuildContext context) => Center(
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.forum_outlined, size: 36, color: Color(0xFFD4A017)),
            SizedBox(height: 8),
            Text('Ваші чати з’являться тут'),
            SizedBox(height: 4),
            Text('Додайте друга, щоб почати розмову.',
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

String _messageTime(Map<String, dynamic> row) {
  final raw = row['timestamp'] ?? row['created_at'];
  final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  if (value == null) return '';
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _localMessageTime(LocalMessage message) {
  final value = message.createdAt.toLocal();
  return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
