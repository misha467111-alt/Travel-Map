import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../../friends/domain/friend_models.dart';
import '../../friends/providers/friendship_relation_provider.dart';

/// Phase 3.3-B -- the social buttons of ANOTHER user's public profile:
/// follow ("Стежити" / "Стежу"), friendship ("Додати в друзі" / "Запит
/// надіслано" / "Прийняти" / "У друзях") and, for confirmed friends only,
/// "Чат". Follows and friendships are independent systems. Never built for the
/// signed-in user's own profile.
class ProfileSocialActions extends ConsumerStatefulWidget {
  const ProfileSocialActions({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.isFollowing,
    required this.followBusy,
    required this.onFollowChanged,
    this.onOpenChat,
    super.key,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final bool isFollowing;
  final bool followBusy;
  final ValueChanged<bool> onFollowChanged;

  /// Opens the existing chat with this user. Supplied by the parent screen
  /// (which owns navigation); the "Чат" button is shown only for confirmed
  /// friends AND when this is provided.
  final ValueChanged<FriendProfile>? onOpenChat;

  @override
  ConsumerState<ProfileSocialActions> createState() =>
      _ProfileSocialActionsState();
}

class _ProfileSocialActionsState extends ConsumerState<ProfileSocialActions> {
  bool _friendBusy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_friendBusy) return; // double-tap guard
    setState(() => _friendBusy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ref.invalidate(friendshipRelationProvider(widget.userId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Не вдалося виконати дію. Спробуйте ще раз.')),
        );
      }
    } finally {
      if (mounted) setState(() => _friendBusy = false);
    }
  }

  ButtonStyle get _style => ButtonStyle(
        minimumSize:
            const WidgetStatePropertyAll(Size(0, AppSizes.buttonHeight)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.sm)),
      );

  Widget _label(String text) =>
      Text(text, maxLines: 2, textAlign: TextAlign.center);

  Widget _followButton() {
    final busy = widget.followBusy;
    return widget.isFollowing
        ? OutlinedButton.icon(
            key: const Key('profile_unfollow_button'),
            style: _style,
            onPressed: busy ? null : () => widget.onFollowChanged(false),
            icon: const Icon(Icons.check),
            label: _label('Стежу'),
          )
        : FilledButton.icon(
            key: const Key('profile_follow_button'),
            style: _style,
            onPressed: busy ? null : () => widget.onFollowChanged(true),
            icon: const Icon(Icons.person_add_outlined),
            label: _label('Стежити'),
          );
  }

  Widget _friendButton(AsyncValue<FriendshipRelation> relation) {
    final actions = ref.read(friendshipActionsProvider);
    // Keep the last known state while a refresh is running.
    final value = relation.value;
    if (value == null) {
      return relation.hasError
          ? OutlinedButton.icon(
              key: const Key('friend_error_button'),
              style: _style,
              onPressed: () =>
                  ref.invalidate(friendshipRelationProvider(widget.userId)),
              icon: const Icon(Icons.refresh),
              label: _label('Повторити'),
            )
          : OutlinedButton(
              key: const Key('friend_loading_button'),
              style: _style,
              onPressed: null,
              child: const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            );
    }
    final disabledAccent = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, AppSizes.buttonHeight)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.sm)),
      foregroundColor: const WidgetStatePropertyAll(AppColors.accent),
    );
    switch (value.state) {
      case FriendshipState.none:
        return FilledButton.tonalIcon(
          key: const Key('friend_add_button'),
          style: _style,
          onPressed: _friendBusy
              ? null
              : () => _run(() => actions.sendRequest(widget.userId)),
          icon: const Icon(Icons.group_add_outlined),
          label: _label('Додати в друзі'),
        );
      case FriendshipState.sentPending:
        return OutlinedButton.icon(
          key: const Key('friend_sent_button'),
          style: _style,
          onPressed: null,
          icon: const Icon(Icons.hourglass_top),
          label: _label('Запит надіслано'),
        );
      case FriendshipState.receivedPending:
        return FilledButton.icon(
          key: const Key('friend_accept_button'),
          style: _style,
          onPressed: _friendBusy
              ? null
              : () => _run(() => actions.acceptRequest(widget.userId)),
          icon: const Icon(Icons.how_to_reg_outlined),
          label: _label('Прийняти'),
        );
      case FriendshipState.unknown:
        return OutlinedButton.icon(
          key: const Key('friend_unknown_button'),
          style: _style,
          onPressed: () =>
              ref.invalidate(friendshipRelationProvider(widget.userId)),
          icon: const Icon(Icons.refresh),
          label: _label('Статус недоступний'),
        );
      case FriendshipState.friends:
        return OutlinedButton.icon(
          key: const Key('friend_friends_button'),
          style: disabledAccent,
          onPressed: null,
          icon: const Icon(Icons.group),
          label: _label('У друзях'),
        );
    }
  }

  void _openChat() => widget.onOpenChat?.call(FriendProfile(
        id: widget.userId,
        name: widget.name,
        avatarUrl: widget.avatarUrl,
      ));

  @override
  Widget build(BuildContext context) {
    final relation = ref.watch(friendshipRelationProvider(widget.userId));
    final isFriend = relation.value?.state == FriendshipState.friends &&
        widget.onOpenChat != null;
    return Column(
      key: const Key('profile_social_actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _followButton()),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _friendButton(relation)),
          ]),
        ),
        if (isFriend) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('profile_chat_button'),
              style: _style,
              onPressed: _openChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: _label('Чат'),
            ),
          ),
        ],
      ],
    );
  }
}
