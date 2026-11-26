import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/achievements/domain/achievement_model.dart';
import 'package:flutter_application_1/features/achievements/providers/achievements_provider.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database_provider.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_forest_art.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_screen.dart';
import 'package:flutter_application_1/features/profile/providers/profile_journey_stats_provider.dart';

/// Phase 3.1 -- the Premium Forest traveler profile composition.
void main() {
  const profile = UserProfile(
    id: 'user-1',
    name: 'Мандрівник Іван',
    email: 'ivan@example.com',
    level: 'Дослідник',
    xp: 320,
    locationsCount: 12,
  );

  AchievementModel award(String key, String name,
          {bool unlocked = true, DateTime? at}) =>
      AchievementModel(
        key: key,
        name: name,
        description: 'd',
        icon: 'pin',
        unlockCondition: 'c',
        progress: unlocked ? 1 : 0,
        target: 1,
        isUnlocked: unlocked,
        unlockedAt: at,
      );

  Widget subject({
    UserProfile user = profile,
    AsyncValue<ProfileJourneyStats> journeys = const AsyncData(
        ProfileJourneyStats(count: 2, confirmedDistanceMeters: 1500)),
    List<AchievementModel>? achievements,
    ({int unlocked, int total})? progress = const (unlocked: 2, total: 3),
    ValueChanged<String>? onDestination,
    AsyncValue<int> created = const AsyncData(3),
    List<Override> overrides = const [],
    double width = 400,
  }) =>
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: ProfileContent(
                profile: user,
                savedCountOverride: 4,
                achievementProgressOverride: progress,
                unlockedAchievementsOverride: achievements,
                inviteBalanceOverride: 2,
                createdPlacesOverride: created,
                visitedPlacesOverride: const AsyncData(2),
                recentJourneysOverride: const AsyncData([]),
                followCountsOverride:
                    const AsyncData(FollowCounts(followers: 21, following: 34)),
                journeyStatsOverride: journeys,
                onDestination: onDestination,
                onLogout: () {},
              ),
            ),
          ),
        ),
      );

  group('hero', () {
    testWidgets('level, XP, gold bar 10 px and XP to next level',
        (tester) async {
      await tester.pumpWidget(subject());

      expect(find.text('Рівень 3'), findsOneWidget);
      expect(find.text('Дослідник'), findsOneWidget);
      expect(find.text('320 XP'), findsOneWidget);
      expect(find.text('320 / 600 XP'), findsOneWidget);
      expect(find.text('До наступного рівня: 280 XP'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.descendant(
          of: find.byKey(const Key('profile_xp_progress')),
          matching: find.byType(LinearProgressIndicator)));
      expect(bar.minHeight, 10);
      expect(bar.color, AppColors.accent);
      expect(find.byKey(const Key('profile_avatar')), findsOneWidget);
      expect(find.byTooltip('Змінити аватар'), findsOneWidget);
      expect(find.byTooltip('Змінити ім’я'), findsOneWidget);
    });

    testWidgets('maximum level shows a completed bar and no next target',
        (tester) async {
      await tester.pumpWidget(subject(
          user: const UserProfile(
              id: 'u',
              name: 'Макс',
              email: 'm@e.com',
              level: 'Першовідкривач',
              xp: 1500,
              locationsCount: 0)));

      expect(find.text('Рівень 5'), findsOneWidget);
      expect(find.text('Максимальний рівень досягнуто'), findsOneWidget);
      expect(find.textContaining('До наступного'), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(find.descendant(
          of: find.byKey(const Key('profile_xp_progress')),
          matching: find.byType(LinearProgressIndicator)));
      expect(bar.value, 1);
    });
  });

  group('stats row', () {
    testWidgets('Locations, Journeys and Distance share one row',
        (tester) async {
      await tester.pumpWidget(subject());

      Finder inTile(String k, String v) =>
          find.descendant(of: find.byKey(Key(k)), matching: find.text(v));
      // The exact created-places count (the override is 3), not the profile's
      // own figure (12).
      expect(inTile('profile_counter_locations', '3'), findsOneWidget);
      expect(find.text('12'), findsNothing);
      expect(inTile('profile_stat_journeys', '2'), findsOneWidget);
      expect(inTile('profile_stat_distance', '1.50 км'), findsOneWidget);
      final y = [
        for (final k in [
          'profile_counter_locations',
          'profile_stat_journeys',
          'profile_stat_distance'
        ])
          tester.getTopLeft(find.byKey(Key(k))).dy
      ];
      expect(y[0], y[1]);
      expect(y[1], y[2]);
      // Bookmarks and the achievements count are not repeated as tiles.
      expect(find.text('Закладки'), findsNothing);
    });

    testWidgets(
        'Стежать / Стежу: real counters, not a link to the friends list',
        (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(subject(onDestination: opened.add));
      Finder inCounter(String k, String v) => find.descendant(
          of: find.byKey(Key('profile_counter_$k')), matching: find.text(v));
      expect(inCounter('followers', '21'), findsOneWidget);
      expect(inCounter('following', '34'), findsOneWidget);
      final row = find.byKey(const Key('profile_follow_row'));
      // No chevron, no tap target: there are no followers lists yet and the
      // friends screen is a different thing.
      expect(
          find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
          findsNothing);
      expect(find.descendant(of: row, matching: find.byType(InkWell)),
          findsNothing);
      await tester.tap(row);
      expect(opened, isEmpty);
      // The friends list stays reachable from its own row.
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_action_friends')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('profile_action_friends')));
      expect(opened, ['friends']);
    });

    testWidgets('Локації tile: loading and error never show a made-up zero',
        (tester) async {
      final tile = find.byKey(const Key('profile_counter_locations'));
      await tester.pumpWidget(subject(created: const AsyncLoading()));
      expect(
          find.descendant(
              of: tile, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      await tester.pumpWidget(
          subject(created: AsyncError(StateError('x'), StackTrace.empty)));
      expect(
          find.descendant(of: tile, matching: find.text('—')), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.text('0')), findsNothing);
    });

    testWidgets('Distance tile: loading and error never invent a number',
        (tester) async {
      final distance = find.byKey(const Key('profile_stat_distance'));
      await tester.pumpWidget(subject(journeys: const AsyncLoading()));
      expect(
          find.descendant(
              of: distance, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      await tester.pumpWidget(
          subject(journeys: AsyncError(StateError('db'), StackTrace.empty)));
      expect(find.descendant(of: distance, matching: find.text('—')),
          findsOneWidget);
      await tester.pumpWidget(subject(
          journeys: const AsyncData(
              ProfileJourneyStats(count: 0, confirmedDistanceMeters: 0))));
      expect(find.descendant(of: distance, matching: find.text('0 м')),
          findsOneWidget);
    });

    testWidgets('Journey tile: loading, empty and error never invent data',
        (tester) async {
      final journeys = find.byKey(const Key('profile_stat_journeys'));

      await tester.pumpWidget(subject(journeys: const AsyncLoading()));
      expect(
          find.descendant(
              of: journeys, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);

      await tester.pumpWidget(subject(
          journeys: const AsyncData(
              ProfileJourneyStats(count: 0, confirmedDistanceMeters: 0))));
      expect(find.descendant(of: journeys, matching: find.text('0')),
          findsOneWidget);
      expect(find.text('Ще немає подорожей'), findsOneWidget);

      await tester.pumpWidget(
          subject(journeys: AsyncError(StateError('db'), StackTrace.empty)));
      expect(find.descendant(of: journeys, matching: find.text('—')),
          findsOneWidget);
      expect(find.text('Недоступно'), findsOneWidget);
      // The rest of the profile is unaffected.
      expect(find.text('Мандрівник Іван'), findsOneWidget);
    });
  });

  Future<void> revealAchievements(WidgetTester tester) async {
    await tester.scrollUntilVisible(
        find.byKey(const Key('profile_action_achievements')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
  }

  group('achievements strip', () {
    testWidgets('only real unlocked awards, progress X із N', (tester) async {
      await tester.pumpWidget(subject(achievements: [
        award('a', 'Перша мітка', at: DateTime(2026, 1, 2)),
        award('b', 'Картограф', at: DateTime(2026, 2, 1)),
        award('c', 'Закритий приз', unlocked: false),
      ], progress: null));
      await revealAchievements(tester);

      expect(find.text('Перша мітка'), findsOneWidget);
      expect(find.text('Картограф'), findsOneWidget);
      expect(find.text('Закритий приз'), findsNothing);
      expect(find.text('2 із 3'), findsOneWidget);
      // newest first
      expect(tester.getTopLeft(find.text('Картограф')).dx,
          lessThan(tester.getTopLeft(find.text('Перша мітка')).dx));
    });

    testWidgets('empty state when nothing is unlocked', (tester) async {
      await tester.pumpWidget(subject(
          achievements: [award('c', 'Закритий', unlocked: false)],
          progress: null));
      await revealAchievements(tester);
      expect(
          find.byKey(const Key('profile_achievements_empty')), findsOneWidget);
      expect(find.text('Закритий'), findsNothing);
    });

    testWidgets('"Усі →" opens the achievements section', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(subject(onDestination: opened.add));
      await revealAchievements(tester);
      await tester.tap(find.byKey(const Key('profile_action_achievements')));
      expect(opened, ['achievements']);
    });

    testWidgets('medals are gold hexagons with the real award icon',
        (tester) async {
      await tester.pumpWidget(subject(achievements: [
        award('a', 'Перша мітка', at: DateTime(2026, 1, 2)),
      ]));
      await revealAchievements(tester);
      expect(find.byType(HexMedal), findsOneWidget);
      expect(find.byKey(const Key('profile_medal_icon_a')), findsOneWidget);
    });

    testWidgets('RPC error and loading are explicit and non-blocking',
        (tester) async {
      await tester.pumpWidget(subject(
        progress: null,
        overrides: [
          achievementsProvider
              .overrideWith((ref) async => throw StateError('offline')),
        ],
      ));
      await tester.pump();
      await tester.pump();
      await revealAchievements(tester);
      expect(
          find.byKey(const Key('profile_achievements_error')), findsOneWidget);
      expect(
          find.byKey(const Key('profile_action_achievements')), findsOneWidget);

      final never = Completer<List<AchievementModel>>();
      await tester.pumpWidget(subject(
        progress: null,
        overrides: [achievementsProvider.overrideWith((ref) => never.future)],
      ));
      await tester.pump();
      await revealAchievements(tester);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });
  });

  testWidgets('cards are in Ukrainian and the invites balance is shown',
      (tester) async {
    await tester.pumpWidget(subject());
    for (final title in [
      'Останні подорожі',
      'Досягнення',
      'Спільнота',
      'Мої подорожі',
      'Система'
    ]) {
      await tester.scrollUntilVisible(find.text(title), 200,
          scrollable: find.byType(Scrollable).first);
    }
    expect(find.text('Історія подорожей'), findsOneWidget);
    expect(find.byKey(const Key('profile_action_logout')), findsOneWidget);
  });

  testWidgets('no overflow at 320 dp with 1.5x system font', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 760), textScaler: TextScaler.linear(1.5)),
      child: subject(width: 320, achievements: [
        award('a', 'Дуже довга назва нагороди для перевірки')
      ]),
    ));
    expect(tester.takeException(), isNull);
  });

  group('profileJourneyStatsProvider (local Drift only)', () {
    late GpsLocalDatabase db;
    setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    ProviderContainer container() {
      final c = ProviderContainer(
          overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)]);
      addTearDown(c.dispose);
      return c;
    }

    final t0 = DateTime.utc(2026, 1, 1, 10);

    Future<void> journey(String id, int points) async {
      await db.createLocalRecordedRoute(id: id, ownerId: 'me', startedAt: t0);
      for (var i = 0; i < points; i++) {
        await db.appendRoutePoint(
          ownerId: 'me',
          recordedRouteId: id,
          latitude: 50.0 + i * 0.00004,
          longitude: 30.0,
          horizontalAccuracy: 5,
          speed: 1.5,
          recordedAt: t0.add(Duration(seconds: 3 * i)),
        );
      }
      await db.finishRecordingLocally(
          ownerId: 'me',
          routeId: id,
          occurredAt: t0.add(Duration(seconds: 3 * points + 1)));
    }

    test('empty: zero Journeys, zero distance', () async {
      final stats =
          await container().read(profileJourneyStatsProvider('me').future);
      expect(stats.count, 0);
      expect(stats.confirmedDistanceMeters, 0);
    });

    test('count and the summed confirmed distance of completed Journeys',
        () async {
      await journey('a', 21); // ~89 m
      await journey('b', 11); // ~44 m
      final stats =
          await container().read(profileJourneyStatsProvider('me').future);
      expect(stats.count, 2);
      expect(stats.confirmedDistanceMeters, inInclusiveRange(120, 140));
    });

    test('another owner\'s Journeys are not counted', () async {
      await journey('a', 11);
      final stats =
          await container().read(profileJourneyStatsProvider('other').future);
      expect(stats.count, 0);
    });
    test('an unusable local database is an error state, not a crash', () async {
      final c = ProviderContainer(overrides: [
        gpsLocalDatabaseProvider
            .overrideWith((ref) => throw StateError('no local database')),
      ]);
      addTearDown(c.dispose);
      await expectLater(
          c.read(profileJourneyStatsProvider('me').future), throwsA(anything));
    });
  });
}
