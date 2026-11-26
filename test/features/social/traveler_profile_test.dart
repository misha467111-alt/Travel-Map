import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_screen.dart';
import 'package:flutter_application_1/features/profile/providers/profile_journey_stats_provider.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';
import 'package:flutter_application_1/features/social/presentation/user_profile_screen.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';

class _FakeSaved extends SavedPublicLocationsNotifier {
  @override
  Future<Set<String>> build() async => <String>{};
}

class _FakeFollow extends FollowController {
  _FakeFollow(super.ref, this.calls);
  final List<(String, bool)> calls;

  @override
  Future<void> setFollowing(String userId, bool follow) async =>
      calls.add((userId, follow));
}

/// Phase 3.3-A -- the shared Instagram-style traveler profile, own and public.
void main() {
  final location = LocationModel(
    id: 'loc-1',
    userId: 'u2',
    title: 'Ботанічний сад',
    description: 'Тихе місце.',
    category: 'nature',
    latitude: 50.45,
    longitude: 30.52,
    createdAt: DateTime.utc(2026),
  );

  PublicProfile pub({
    String name = 'Олена Мандрівниця',
    String level = 'Дослідник',
    int xp = 320,
    int followers = 21,
    int following = 34,
    bool isFollowing = false,
    bool isSelf = false,
    int? locationsCount = 2,
    List<LocationModel>? locations,
    String? avatarUrl,
  }) =>
      PublicProfile(
        id: 'u2',
        name: name,
        avatarUrl: avatarUrl,
        xp: xp,
        level: level,
        followersCount: followers,
        followingCount: following,
        isFollowing: isFollowing,
        locations: locations ?? [location],
        locationsCount: locationsCount,
        isSelf: isSelf,
      );

  final List<(String, bool)> followCalls = [];

  Widget publicScreen(
    AsyncValue<PublicProfile> value, {
    double width = 400,
    double scale = 1,
  }) {
    followCalls.clear();
    return ProviderScope(
      key: UniqueKey(),
      overrides: <Override>[
        publicProfileProvider('u2').overrideWith((ref) {
          if (value is AsyncData<PublicProfile>) return value.value;
          if (value is AsyncError<PublicProfile>) throw value.error;
          return Completer<PublicProfile>().future;
        }),
        savedPublicLocationsProvider.overrideWith(_FakeSaved.new),
        followControllerProvider
            .overrideWith((ref) => _FakeFollow(ref, followCalls)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: const UserProfileScreen(userId: 'u2'),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  group('public profile', () {
    testWidgets('shows avatar fallback, name, level, XP and real counters',
        (tester) async {
      await tester.pumpWidget(publicScreen(AsyncData(pub())));
      await settle(tester);

      expect(find.text('Олена Мандрівниця'), findsOneWidget);
      expect(find.byKey(const Key('profile_avatar_fallback')), findsOneWidget);
      expect(find.text('Рівень 3'), findsOneWidget);
      expect(find.text('Дослідник'), findsOneWidget);
      expect(find.text('320 XP'), findsOneWidget);
      expect(find.text('320 / 600 XP'), findsOneWidget);
      Finder counter(String k, String v) => find.descendant(
          of: find.byKey(Key('profile_counter_$k')), matching: find.text(v));
      expect(counter('locations', '2'), findsOneWidget);
      expect(counter('followers', '21'), findsOneWidget);
      expect(counter('following', '34'), findsOneWidget);
      expect(find.text('Стежать'), findsOneWidget);
      expect(find.text('Стежу'), findsOneWidget);
      // no e-mail, no edit controls on someone else's profile
      expect(find.byKey(const Key('profile_subtitle')), findsNothing);
      expect(find.byTooltip('Змінити аватар'), findsNothing);
      expect(find.byTooltip('Змінити ім’я'), findsNothing);
    });

    testWidgets('an unknown locations total is a dash, never a fake zero',
        (tester) async {
      await tester.pumpWidget(
          publicScreen(AsyncData(pub(locationsCount: null, locations: []))));
      await settle(tester);
      expect(
          find.descendant(
              of: find.byKey(const Key('profile_counter_locations')),
              matching: find.text('—')),
          findsOneWidget);
      expect(find.text('Публічних локацій поки немає'), findsOneWidget);
    });

    testWidgets('"Стежити" follows; "Стежу" unfollows', (tester) async {
      await tester.pumpWidget(publicScreen(AsyncData(pub())));
      await settle(tester);
      expect(find.text('Стежити'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile_follow_button')));
      await tester.pump();
      expect(followCalls, [('u2', true)]);

      await tester.pumpWidget(publicScreen(AsyncData(pub(isFollowing: true))));
      await settle(tester);
      expect(find.byKey(const Key('profile_follow_button')), findsNothing);
      await tester.tap(find.byKey(const Key('profile_unfollow_button')));
      await tester.pump();
      expect(followCalls, [('u2', false)]);
    });

    testWidgets('no follow button on the own profile', (tester) async {
      await tester.pumpWidget(publicScreen(AsyncData(pub(isSelf: true))));
      await settle(tester);
      expect(find.byKey(const Key('profile_follow_button')), findsNothing);
      expect(find.byKey(const Key('profile_unfollow_button')), findsNothing);
    });

    testWidgets('private sections of another user are not shown',
        (tester) async {
      await tester.pumpWidget(publicScreen(AsyncData(pub())));
      await settle(tester);
      for (final hidden in [
        'Маршрути',
        'Досягнення',
        'Історія',
        'Закладки',
        'Подорожі',
        'Налаштування',
        'Вийти',
        'Інвайти',
        'Мої місця',
        'Створені',
        'Збережені',
        'Відвідані',
        'Останні подорожі',
        'Історія подорожей',
      ]) {
        expect(find.text(hidden), findsNothing, reason: hidden);
      }
      expect(find.text('Публічні локації'), findsOneWidget);
      expect(find.text('Ботанічний сад'), findsOneWidget);
    });

    testWidgets('max level shows a complete bar', (tester) async {
      await tester.pumpWidget(
          publicScreen(AsyncData(pub(xp: 1500, level: 'Першовідкривач'))));
      await settle(tester);
      expect(find.text('Рівень 5'), findsOneWidget);
      expect(find.text('Максимальний рівень досягнуто'), findsOneWidget);
    });

    testWidgets('loading and error states (with retry)', (tester) async {
      await tester.pumpWidget(publicScreen(const AsyncLoading()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(
          publicScreen(AsyncError(StateError('x'), StackTrace.empty)));
      await settle(tester);
      expect(find.text('Не вдалося завантажити профіль.'), findsOneWidget);
      expect(find.text('Спробувати ще раз'), findsOneWidget);
    });
  });

  group('own profile header', () {
    const me = UserProfile(
      id: 'me',
      name: 'Іван Мандрівник',
      email: 'ivan@example.com',
      level: 'Новачок',
      xp: 40,
      locationsCount: 12,
    );

    Widget own({
      AsyncValue<FollowCounts> counts =
          const AsyncData(FollowCounts(followers: 21, following: 34)),
      double width = 400,
      double scale = 1,
    }) =>
        ProviderScope(
          key: UniqueKey(),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 800), textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: ProfileContent(
                  profile: me,
                  savedCountOverride: 1,
                  achievementProgressOverride: const (unlocked: 1, total: 35),
                  unlockedAchievementsOverride: const [],
                  inviteBalanceOverride: 0,
                  createdPlacesOverride: const AsyncData(3),
                  visitedPlacesOverride: const AsyncData(2),
                  recentJourneysOverride: const AsyncData([]),
                  followCountsOverride: counts,
                  journeyStatsOverride: const AsyncData(ProfileJourneyStats(
                      count: 0, confirmedDistanceMeters: 0)),
                  onDestination: (_) {},
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );

    testWidgets('counters, email and edit controls', (tester) async {
      await tester.pumpWidget(own());
      Finder counter(String k, String v) => find.descendant(
          of: find.byKey(Key('profile_counter_$k')), matching: find.text(v));
      // Locations = the exact created-places count (override 3).
      expect(counter('locations', '3'), findsOneWidget);
      expect(counter('followers', '21'), findsOneWidget);
      expect(counter('following', '34'), findsOneWidget);
      expect(find.text('ivan@example.com'), findsOneWidget);
      expect(find.byTooltip('Змінити аватар'), findsOneWidget);
      expect(find.byTooltip('Змінити ім’я'), findsOneWidget);
      expect(find.byKey(const Key('profile_avatar_fallback')), findsOneWidget);
      expect(find.text('Рівень 1'), findsOneWidget);
    });

    testWidgets('follower counters: loading and error never show zeros',
        (tester) async {
      await tester.pumpWidget(own(counts: const AsyncLoading()));
      expect(
          find.descendant(
              of: find.byKey(const Key('profile_counter_followers')),
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);

      await tester.pumpWidget(
          own(counts: AsyncError(StateError('x'), StackTrace.empty)));
      for (final k in ['followers', 'following']) {
        expect(
            find.descendant(
                of: find.byKey(Key('profile_counter_$k')),
                matching: find.text('—')),
            findsOneWidget);
      }
      // the own locations count is still real
      expect(
          find.descendant(
              of: find.byKey(const Key('profile_counter_locations')),
              matching: find.text('3')),
          findsOneWidget);
    });

    testWidgets('all existing own-profile actions are still present',
        (tester) async {
      await tester.pumpWidget(own());
      final scroll = find.byType(Scrollable).first;
      for (final key in [
        'achievements',
        'friends',
        'chat',
        'invites',
        'top',
        'saved',
        'routes',
        'journeys',
        'personalization',
        'settings',
        'logout',
      ]) {
        await tester.scrollUntilVisible(
            find.byKey(Key('profile_action_$key')), 200,
            scrollable: scroll);
        expect(find.byKey(Key('profile_action_$key')), findsOneWidget,
            reason: key);
      }
    });
  });

  group('adaptive', () {
    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('public profile fits ${width}dp @ ${scale}x',
            (tester) async {
          await tester.pumpWidget(publicScreen(
              AsyncData(pub(
                  name:
                      'Дуже довге ім’я мандрівника для перевірки переносу тексту',
                  level: 'Першовідкривач-дослідник')),
              width: width,
              scale: scale));
          await settle(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
