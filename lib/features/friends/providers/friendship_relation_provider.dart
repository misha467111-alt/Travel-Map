import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/providers/locations_provider.dart';
import 'friends_provider.dart';

/// Phase 3.3-B -- the friendship between the signed-in user and ONE other
/// user, as the public profile needs it. Reads the existing `friendships`
/// table (RLS: a user sees only their own rows) and acts only through the
/// existing [FriendsRepository.sendRequest] / [FriendsRepository.acceptRequest];
/// no new server operation.
enum FriendshipState {
  /// No row: a request can be sent.
  none,

  /// I sent a pending request (`user_id_1` is me): nothing more to do.
  sentPending,

  /// The other user sent me a pending request (`user_id_2` is me): I can
  /// accept it.
  receivedPending,

  /// Accepted: friends; chat is allowed.
  friends,

  /// A row with a status this app does not recognise. Not the same as
  /// "no friendship": nothing may be sent or accepted until it is known.
  unknown,
}

class FriendshipRelation {
  const FriendshipRelation(this.state, {this.friendshipId});

  final FriendshipState state;

  /// The `friendships.id` of the row (needed to accept); `null` for [FriendshipState.none].
  final String? friendshipId;

  static const none = FriendshipRelation(FriendshipState.none);
}

/// Pure mapping of a `friendships` row to a [FriendshipRelation] from the point
/// of view of [me]. A missing row is [FriendshipState.none]; a row with an
/// unrecognised status is [FriendshipState.unknown] (never treated as "no
/// friendship", so no request can be sent on top of it).
FriendshipRelation friendshipRelationFromRow(
    Map<String, dynamic>? row, String me) {
  if (row == null) return FriendshipRelation.none;
  final id = row['id'] as String?;
  final status = row['status'];
  if (status == 'accepted') {
    return FriendshipRelation(FriendshipState.friends, friendshipId: id);
  }
  if (status == 'pending') {
    return FriendshipRelation(
      row['user_id_1'] == me
          ? FriendshipState.sentPending
          : FriendshipState.receivedPending,
      friendshipId: id,
    );
  }
  return FriendshipRelation(FriendshipState.unknown, friendshipId: id);
}

class FriendshipRelationRepository {
  const FriendshipRelationRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<FriendshipRelation> fetch(String otherUserId) async {
    final me = _supabase.auth.currentUser?.id;
    if (me == null) throw StateError('Користувач не авторизований.');
    final rows = await _supabase
        .from('friendships')
        .select('id, user_id_1, user_id_2, status')
        .or('and(user_id_1.eq.$me,user_id_2.eq.$otherUserId),'
            'and(user_id_1.eq.$otherUserId,user_id_2.eq.$me)')
        .limit(1);
    return friendshipRelationFromRow(rows.isEmpty ? null : rows.first, me);
  }
}

final friendshipRelationRepositoryProvider =
    Provider<FriendshipRelationRepository>(
  (ref) => FriendshipRelationRepository(Supabase.instance.client),
);

final friendshipRelationProvider = FutureProvider.autoDispose
    .family<FriendshipRelation, String>((ref, otherUserId) {
  return ref.watch(friendshipRelationRepositoryProvider).fetch(otherUserId);
});

/// Friend actions of the public profile. Both re-read the relation first, so a
/// stale screen can never send a duplicate request or accept something that is
/// no longer pending; the database also has a unique index on the pair.
class FriendshipActions {
  const FriendshipActions(this._ref);

  final Ref _ref;

  void _refresh(String otherUserId) {
    _ref.invalidate(friendshipRelationProvider(otherUserId));
    _ref.invalidate(pendingFriendRequestsProvider);
    _ref.invalidate(acceptedFriendsProvider);
  }

  Future<void> sendRequest(String otherUserId) async {
    final current = await _ref
        .read(friendshipRelationRepositoryProvider)
        .fetch(otherUserId);
    if (current.state == FriendshipState.none) {
      await _ref.read(friendsRepositoryProvider).sendRequest(otherUserId);
    }
    _refresh(otherUserId);
  }

  Future<void> acceptRequest(String otherUserId) async {
    final current = await _ref
        .read(friendshipRelationRepositoryProvider)
        .fetch(otherUserId);
    final id = current.friendshipId;
    if (current.state == FriendshipState.receivedPending && id != null) {
      await _ref.read(friendsRepositoryProvider).acceptRequest(id);
      _ref.invalidate(fetchLocationsProvider);
    }
    _refresh(otherUserId);
  }
}

final friendshipActionsProvider =
    Provider<FriendshipActions>(FriendshipActions.new);
