import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/friends/domain/friend_models.dart';
import 'package:flutter_application_1/features/friends/providers/friends_provider.dart';
import 'package:flutter_application_1/features/friends/providers/friendship_relation_provider.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';
import 'package:flutter_application_1/features/social/presentation/user_profile_screen.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';

class _FakeSaved extends SavedPublicLocationsNotifier {
  @override
  Future<Set<String>> build() async => <String>{};
}

class _FakeFollow extends FollowController {
  _FakeFollow(super.ref, this.calls, {this.gate});
  final List<(String, bool)> calls;
  final Completer<void>? gate;

  @override
  Future<void> setFollowing(String userId, bool follow) async {
    calls.add((userId, follow));
    await gate?.future;
  }
}

class _FakeActions extends FriendshipActions {
  _FakeActions(super.ref, this.log, {this.gate, this.fail = false});
  final List<String> log;
  final Completer<void>? gate;
  final bool fail;

  @override
  Future<void> sendRequest(String otherUserId) async {
    log.add('send:$otherUserId');
    await gate?.future;
    if (fail) throw StateError('server said no');
  }

  @override
  Future<void> acceptRequest(String otherUserId) async {
    log.add('accept:$otherUserId');
    await gate?.future;
    if (fail) throw StateError('server said no');
  }
}

class _SpyFriends implements FriendsRepository {
  final List<String> log = [];

  @override
  Future<void> sendRequest(String targetUserId) async =>
      log.add('send:$targetUserId');

  @override
  Future<void> acceptRequest(String friendshipId) async =>
      log.add('accept:$friendshipId');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FixedRelationRepo implements FriendshipRelationRepository {
  _FixedRelationRepo(this.relation);
  final FriendshipRelation relation;

  @override
  Future<FriendshipRelation> fetch(String otherUserId) async => relation;
}

/// Phase 3.3-B -- follow, friendship and chat on another user's public profile.
void main() {
  PublicProfile profile({bool isFollowing = false, bool isSelf = false}) =>
      PublicProfile(
        id: 'u2',
        name: 'Олена Мандрівниця',
        xp: 120,
        level: 'Дослідник',
        followersCount: 5,
        followingCount: 7,
        isFollowing: isFollowing,
        locations: const [],
        locationsCount: 0,
        isSelf: isSelf,
      );

  final followCalls = <(String, bool)>[];
  final friendLog = <String>[];
  final chatOpened = <FriendProfile>[];

  Widget screen({
    FriendshipRelation relation = FriendshipRelation.none,
    AsyncValue<FriendshipRelation>? relationState,
    PublicProfile? data,
    Completer<void>? followGate,
    Completer<void>? friendGate,
    bool friendFails = false,
    bool withChatCallback = true,
    double width = 400,
    double scale = 1,
  }) {
    followCalls.clear();
    friendLog.clear();
    chatOpened.clear();
    return ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        publicProfileProvider('u2').overrideWith((ref) => data ?? profile()),
        friendshipRelationProvider('u2').overrideWith((ref) {
          final s = relationState;
          if (s is AsyncError<FriendshipRelation>) throw s.error;
          if (s is AsyncLoading<FriendshipRelation>) {
            return Completer<FriendshipRelation>().future;
          }
          return relation;
        }),
        friendshipActionsProvider.overrideWith((ref) =>
            _FakeActions(ref, friendLog, gate: friendGate, fail: friendFails)),
        followControllerProvider.overrideWith(
            (ref) => _FakeFollow(ref, followCalls, gate: followGate)),
        savedPublicLocationsProvider.overrideWith(_FakeSaved.new),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: UserProfileScreen(
            userId: 'u2',
            onOpenChat: withChatCallback
                ? (context, friend) => chatOpened.add(friend)
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump();
  }

  group('friendship state matrix (pure mapping)', () {
    test('no row → none', () {
      expect(friendshipRelationFromRow(null, 'me').state, FriendshipState.none);
    });
    test('pending I sent (user_id_1 = me) → sentPending', () {
      final r = friendshipRelationFromRow({
        'id': 'f',
        'user_id_1': 'me',
        'user_id_2': 'u2',
        'status': 'pending'
      }, 'me');
      expect(r.state, FriendshipState.sentPending);
      expect(r.friendshipId, 'f');
    });
    test('pending sent to me (user_id_2 = me) → receivedPending', () {
      final r = friendshipRelationFromRow({
        'id': 'f',
        'user_id_1': 'u2',
        'user_id_2': 'me',
        'status': 'pending'
      }, 'me');
      expect(r.state, FriendshipState.receivedPending);
      expect(r.friendshipId, 'f');
    });
    test('accepted, either direction → friends', () {
      for (final row in [
        {'id': 'f', 'user_id_1': 'me', 'user_id_2': 'u2', 'status': 'accepted'},
        {'id': 'f', 'user_id_1': 'u2', 'user_id_2': 'me', 'status': 'accepted'},
      ]) {
        expect(friendshipRelationFromRow(row, 'me').state,
            FriendshipState.friends);
      }
    });
    test('an unrecognised status is UNKNOWN, not "no friendship"', () {
      final r = friendshipRelationFromRow({'id': 'f', 'status': 'weird'}, 'me');
      expect(r.state, FriendshipState.unknown);
      expect(r.state, isNot(FriendshipState.none));
      expect(r.friendshipId, 'f');
    });
  });

  group('friend button states', () {
    testWidgets('none → "Додати в друзі" sends exactly one request',
        (tester) async {
      await tester.pumpWidget(screen());
      await settle(tester);
      expect(find.text('Додати в друзі'), findsOneWidget);
      expect(find.byKey(const Key('profile_chat_button')), findsNothing);
      await tester.tap(find.byKey(const Key('friend_add_button')));
      await tester.pump();
      expect(friendLog, ['send:u2']);
    });

    testWidgets('sent → "Запит надіслано", inactive, no chat', (tester) async {
      await tester.pumpWidget(screen(
          relation: const FriendshipRelation(FriendshipState.sentPending,
              friendshipId: 'f')));
      await settle(tester);
      expect(find.text('Запит надіслано'), findsOneWidget);
      final b = tester
          .widget<OutlinedButton>(find.byKey(const Key('friend_sent_button')));
      expect(b.onPressed, isNull);
      expect(find.byKey(const Key('profile_chat_button')), findsNothing);
    });

    testWidgets('received → "Прийняти" accepts', (tester) async {
      await tester.pumpWidget(screen(
          relation: const FriendshipRelation(FriendshipState.receivedPending,
              friendshipId: 'f')));
      await settle(tester);
      expect(find.text('Прийняти'), findsOneWidget);
      expect(find.byKey(const Key('profile_chat_button')), findsNothing);
      await tester.tap(find.byKey(const Key('friend_accept_button')));
      await tester.pump();
      expect(friendLog, ['accept:u2']);
    });

    testWidgets('friends → "У друзях" (inactive) and the "Чат" button',
        (tester) async {
      await tester.pumpWidget(screen(
          relation: const FriendshipRelation(FriendshipState.friends,
              friendshipId: 'f')));
      await settle(tester);
      expect(find.text('У друзях'), findsOneWidget);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.byKey(const Key('friend_friends_button')))
              .onPressed,
          isNull);
      expect(find.text('Чат'), findsOneWidget);
    });

    testWidgets('the "Чат" button hands the friend to the parent callback',
        (tester) async {
      await tester.pumpWidget(screen(
          relation: const FriendshipRelation(FriendshipState.friends,
              friendshipId: 'f')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('profile_chat_button')));
      await tester.pump();
      expect(chatOpened, hasLength(1));
      expect(chatOpened.single.id, 'u2');
      expect(chatOpened.single.name, 'Олена Мандрівниця');
    });

    testWidgets('without a chat callback there is no "Чат" button',
        (tester) async {
      await tester.pumpWidget(screen(
          withChatCallback: false,
          relation: const FriendshipRelation(FriendshipState.friends,
              friendshipId: 'f')));
      await settle(tester);
      expect(find.text('У друзях'), findsOneWidget);
      expect(find.byKey(const Key('profile_chat_button')), findsNothing);
    });

    testWidgets(
        'unknown status → "Статус недоступний": no add, no accept, no chat; '
        'tap reloads', (tester) async {
      await tester.pumpWidget(screen(
          relation: const FriendshipRelation(FriendshipState.unknown,
              friendshipId: 'f')));
      await settle(tester);
      expect(find.text('Статус недоступний'), findsOneWidget);
      expect(find.byKey(const Key('friend_add_button')), findsNothing);
      expect(find.byKey(const Key('friend_accept_button')), findsNothing);
      expect(find.byKey(const Key('profile_chat_button')), findsNothing);
      await tester.tap(find.byKey(const Key('friend_unknown_button')));
      await settle(tester);
      expect(friendLog, isEmpty, reason: 'retry only reloads the state');
      // follow is independent of the friend state
      expect(find.byKey(const Key('profile_follow_button')), findsOneWidget);
    });

    testWidgets('loading → disabled spinner; error → retry', (tester) async {
      await tester.pumpWidget(screen(relationState: const AsyncLoading()));
      await tester.pump();
      expect(find.byKey(const Key('friend_loading_button')), findsOneWidget);
      expect(find.byKey(const Key('profile_chat_button')), findsNothing);

      await tester.pumpWidget(
          screen(relationState: AsyncError(StateError('x'), StackTrace.empty)));
      await settle(tester);
      expect(find.byKey(const Key('friend_error_button')), findsOneWidget);
      expect(find.text('Повторити'), findsOneWidget);
      // follow still works while the friend state is unavailable
      expect(find.byKey(const Key('profile_follow_button')), findsOneWidget);
    });
  });

  group('FriendshipActions (real class, fake repositories)', () {
    Future<List<String>> run(FriendshipRelation relation,
        Future<void> Function(FriendshipActions a) act) async {
      final spy = _SpyFriends();
      final c = ProviderContainer(overrides: <Override>[
        friendshipRelationRepositoryProvider
            .overrideWithValue(_FixedRelationRepo(relation)),
        friendsRepositoryProvider.overrideWithValue(spy),
      ]);
      addTearDown(c.dispose);
      await act(c.read(friendshipActionsProvider));
      return spy.log;
    }

    test('sendRequest sends only when there is no relation', () async {
      expect(await run(FriendshipRelation.none, (a) => a.sendRequest('u2')),
          ['send:u2']);
      for (final state in [
        FriendshipState.sentPending,
        FriendshipState.receivedPending,
        FriendshipState.friends,
        FriendshipState.unknown,
      ]) {
        expect(
            await run(FriendshipRelation(state, friendshipId: 'f'),
                (a) => a.sendRequest('u2')),
            isEmpty,
            reason: '$state must never send a request');
      }
    });

    test('acceptRequest accepts only a received pending request', () async {
      expect(
          await run(
              const FriendshipRelation(FriendshipState.receivedPending,
                  friendshipId: 'f1'),
              (a) => a.acceptRequest('u2')),
          ['accept:f1']);
      for (final state in [
        FriendshipState.none,
        FriendshipState.sentPending,
        FriendshipState.friends,
        FriendshipState.unknown,
      ]) {
        expect(
            await run(FriendshipRelation(state, friendshipId: 'f'),
                (a) => a.acceptRequest('u2')),
            isEmpty,
            reason: '$state must never accept');
      }
    });
  });

  group('safety', () {
    testWidgets('double tap sends one request (busy guard)', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(screen(friendGate: gate));
      await settle(tester);
      final add = find.byKey(const Key('friend_add_button'));
      await tester.tap(add);
      await tester.pump();
      await tester.tap(add, warnIfMissed: false);
      await tester.pump();
      expect(friendLog, ['send:u2']);
      expect(tester.widget<ButtonStyleButton>(add).onPressed, isNull);
      gate.complete();
      await settle(tester);
    });

    testWidgets('a failed action shows a message and recovers', (tester) async {
      await tester.pumpWidget(screen(friendFails: true));
      await settle(tester);
      await tester.tap(find.byKey(const Key('friend_add_button')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Не вдалося виконати дію. Спробуйте ще раз.'),
          findsOneWidget);
      // buttons are usable again
      expect(
          tester
              .widget<ButtonStyleButton>(
                  find.byKey(const Key('friend_add_button')))
              .onPressed,
          isNotNull);
    });

    testWidgets('own profile has no social buttons at all', (tester) async {
      await tester.pumpWidget(screen(data: profile(isSelf: true)));
      await settle(tester);
      for (final k in [
        'profile_social_actions',
        'profile_follow_button',
        'profile_unfollow_button',
        'friend_add_button',
        'profile_chat_button',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });
  });

  group('follow', () {
    testWidgets('"Стежити" → follow call; "Стежу" → unfollow call',
        (tester) async {
      await tester.pumpWidget(screen());
      await settle(tester);
      await tester.tap(find.byKey(const Key('profile_follow_button')));
      await tester.pump();
      expect(followCalls, [('u2', true)]);

      await tester.pumpWidget(screen(data: profile(isFollowing: true)));
      await settle(tester);
      expect(find.text('Стежу'), findsWidgets);
      await tester.tap(find.byKey(const Key('profile_unfollow_button')));
      await tester.pump();
      expect(followCalls, [('u2', false)]);
    });

    testWidgets('double tap on follow runs once while busy', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(screen(followGate: gate));
      await settle(tester);
      final b = find.byKey(const Key('profile_follow_button'));
      await tester.tap(b);
      await tester.pump();
      await tester.tap(b, warnIfMissed: false);
      await tester.pump();
      expect(followCalls, [('u2', true)]);
      expect(tester.widget<ButtonStyleButton>(b).onPressed, isNull);
      gate.complete();
      await settle(tester);
    });

    testWidgets('follow and friendship are independent', (tester) async {
      await tester.pumpWidget(screen(
          data: profile(isFollowing: true),
          relation: const FriendshipRelation(FriendshipState.sentPending,
              friendshipId: 'f')));
      await settle(tester);
      expect(find.byKey(const Key('profile_unfollow_button')), findsOneWidget);
      expect(find.byKey(const Key('friend_sent_button')), findsOneWidget);
    });
  });

  group('buttons fit', () {
    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('all states at ${width}dp @ ${scale}x, equal height',
            (tester) async {
          for (final rel in [
            FriendshipRelation.none,
            const FriendshipRelation(FriendshipState.sentPending),
            const FriendshipRelation(FriendshipState.receivedPending,
                friendshipId: 'f'),
            const FriendshipRelation(FriendshipState.friends),
            const FriendshipRelation(FriendshipState.unknown),
          ]) {
            await tester.pumpWidget(screen(
                relation: rel,
                data:
                    profile(isFollowing: rel.state == FriendshipState.friends),
                width: width,
                scale: scale));
            await settle(tester);
            expect(tester.takeException(), isNull);
            final follow = find.byWidgetPredicate((w) =>
                w.key == const Key('profile_follow_button') ||
                w.key == const Key('profile_unfollow_button'));
            final friend = find.byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('friend_') &&
                (w.key! as ValueKey<String>).value.endsWith('_button'));
            expect(follow, findsOneWidget);
            expect(friend, findsOneWidget);
            expect(
                tester.getSize(follow).height, tester.getSize(friend).height);
            expect(tester.getSize(follow).height,
                greaterThanOrEqualTo(AppSizes.buttonHeight));
          }
        });
      }
    }
  });
}
