import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/achievements/domain/achievement_model.dart';
import 'package:flutter_application_1/features/achievements/presentation/achievement_icons.dart';
import 'package:flutter_application_1/features/achievements/presentation/achievements_tab.dart';
import 'package:flutter_application_1/features/achievements/providers/achievements_provider.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_screen.dart';
import 'package:flutter_application_1/features/profile/providers/profile_journey_stats_provider.dart';

/// Phase 3.2A -- Premium Forest "Мої досягнення".
void main() {
  const icons = ['pin', 'map', 'explore', 'route', 'trophy', 'weird_unknown'];

  List<AchievementModel> thirtyFive({int unlocked = 3}) => [
        for (var i = 0; i < 35; i++)
          AchievementModel(
            key: 'k$i',
            name: 'Нагорода $i',
            description: 'Опис нагороди $i',
            icon: icons[i % icons.length],
            unlockCondition: 'Умова $i',
            progress: i < unlocked ? 1 : (i % 4).toDouble(),
            target: i < unlocked ? 1 : 4,
            isUnlocked: i < unlocked,
            unlockedAt: i < unlocked ? DateTime.utc(2026, 3, 5 + i) : null,
          ),
      ];

  Widget screen(List<Override> overrides,
          {double width = 400, double scale = 1}) =>
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 760), textScaler: TextScaler.linear(scale)),
            child: const Scaffold(body: AchievementsTab()),
          ),
        ),
      );

  Override data(List<AchievementModel> list) =>
      achievementsProvider.overrideWith((ref) async => list);

  testWidgets('header: title, X із 35, gold bar, percentage', (tester) async {
    await tester.pumpWidget(screen([data(thirtyFive())]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Мої досягнення'), findsOneWidget);
    expect(find.text('Відкрито 3 із 35'), findsOneWidget);
    expect(find.text('9%'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('achievements_progress')));
    expect(bar.value, closeTo(3 / 35, 1e-9));
    expect(bar.color, AppColors.accent);
  });

  testWidgets('all 35 awards are present; unlocked first', (tester) async {
    tester.view.physicalSize = const Size(400, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen([data(thirtyFive(unlocked: 5))]));
    await tester.pump();
    await tester.pump();

    for (var i = 0; i < 35; i++) {
      expect(find.byKey(Key('achievement_k$i')), findsOneWidget);
    }
    // unlocked (k0..k4) are listed before the first locked one
    expect(
        tester.getTopLeft(find.byKey(const Key('achievement_k4'))).dy,
        lessThan(
            tester.getTopLeft(find.byKey(const Key('achievement_k5'))).dy));
  });

  testWidgets('unlocked are gold with a date; locked are muted with progress',
      (tester) async {
    await tester.pumpWidget(screen([data(thirtyFive(unlocked: 2))]));
    await tester.pump();
    await tester.pump();

    final unlockedCard = find.byKey(const Key('achievement_k0'));
    expect(
        find.descendant(
            of: unlockedCard, matching: find.text('Розблоковано 05.03.2026')),
        findsOneWidget);
    expect(find.descendant(of: unlockedCard, matching: find.byIcon(Icons.lock)),
        findsNothing);
    final unlockedBox =
        tester.widget<Container>(unlockedCard).decoration as BoxDecoration;
    expect((unlockedBox.border! as Border).top.color.a, greaterThan(0.6));

    final locked = find.byKey(const Key('achievement_k2'));
    expect(find.descendant(of: locked, matching: find.byIcon(Icons.lock)),
        findsOneWidget);
    expect(find.descendant(of: locked, matching: find.text('Умова 2')),
        findsOneWidget);
    expect(find.descendant(of: locked, matching: find.text('2 / 4')),
        findsOneWidget);
    final p = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('achievement_progress_k2')));
    expect(p.value, 0.5);
    // order: unlocked above locked
    expect(tester.getTopLeft(unlockedCard).dy,
        lessThan(tester.getTopLeft(locked).dy));
  });

  testWidgets('loading, empty and error states; retry reloads', (tester) async {
    final never = Completer<List<AchievementModel>>();
    await tester.pumpWidget(
        screen([achievementsProvider.overrideWith((ref) => never.future)]));
    await tester.pump();
    expect(find.byKey(const Key('achievements_loading')), findsOneWidget);

    await tester.pumpWidget(screen([data(const [])]));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('achievements_empty')), findsOneWidget);

    var calls = 0;
    await tester.pumpWidget(screen([
      achievementsProvider.overrideWith((ref) async {
        calls++;
        throw StateError('offline');
      }),
    ]));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('achievements_error')), findsOneWidget);
    expect(find.text('Не вдалося завантажити досягнення'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Повторити'));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
  });

  test('icon mapping: known keys map, unknown falls back to a place pin', () {
    expect(achievementIconFor('map'), Icons.map);
    expect(achievementIconFor('route'), Icons.route);
    expect(achievementIconFor('trophy'), Icons.emoji_events);
    expect(achievementIconFor('pin'), Icons.location_on);
    expect(achievementIconFor('weird_unknown'), Icons.place);
  });

  testWidgets('cards show their real icon', (tester) async {
    await tester.pumpWidget(screen([data(thirtyFive())]));
    await tester.pump();
    await tester.pump();
    Icon icon(String k) =>
        tester.widget<Icon>(find.byKey(Key('achievement_icon_$k')));
    expect(icon('k0').icon, Icons.location_on); // pin
    expect(icon('k1').icon, Icons.map);
  });

  group('adaptive', () {
    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('no overflow at ${width}dp @ ${scale}x', (tester) async {
          await tester.pumpWidget(screen([
            data([
              ...thirtyFive().take(4),
              AchievementModel(
                  key: 'long',
                  name: 'Дуже довга назва нагороди для перевірки переносу',
                  description:
                      'Дуже довгий опис, який має переноситись на кілька рядків без обрізання',
                  icon: 'map',
                  unlockCondition: 'Довга умова розблокування нагороди',
                  progress: 3,
                  target: 10,
                  isUnlocked: false),
            ])
          ], width: width, scale: scale));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('opens from the Premium Profile with real medal icons',
      (tester) async {
    final list = thirtyFive(unlocked: 2);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [data(list)],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileContent(
            profile: const UserProfile(
                id: 'u',
                name: 'Іван',
                email: 'i@e.com',
                level: 'Новачок',
                xp: 10,
                locationsCount: 1),
            savedCountOverride: 0,
            inviteBalanceOverride: 0,
            followCountsOverride:
                const AsyncData(FollowCounts(followers: 3, following: 5)),
            journeyStatsOverride: const AsyncData(
                ProfileJourneyStats(count: 0, confirmedDistanceMeters: 0)),
            onLogout: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // The strip shows the real icon of each unlocked award, not a trophy.
    expect(
        tester
            .widget<Icon>(find.byKey(const Key('profile_medal_icon_k0')))
            .icon,
        Icons.location_on);
    expect(
        tester
            .widget<Icon>(find.byKey(const Key('profile_medal_icon_k1')))
            .icon,
        Icons.map);

    await tester.scrollUntilVisible(
        find.byKey(const Key('profile_action_achievements')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester
        .ensureVisible(find.byKey(const Key('profile_action_achievements')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('profile_action_achievements')));
    await tester.pumpAndSettle();

    expect(find.text('Мої досягнення'), findsOneWidget);
    expect(find.text('Відкрито 2 із 35'), findsOneWidget);
  });
}
