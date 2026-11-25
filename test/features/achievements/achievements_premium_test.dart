import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/achievements/domain/achievement_model.dart';
import 'package:flutter_application_1/features/achievements/presentation/achievement_branches.dart';
import 'package:flutter_application_1/features/achievements/presentation/achievement_icons.dart';
import 'package:flutter_application_1/features/achievements/presentation/achievements_tab.dart';
import 'package:flutter_application_1/features/achievements/providers/achievements_provider.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_screen.dart';
import 'package:flutter_application_1/features/profile/providers/profile_journey_stats_provider.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';

/// Phase 3.3-C -- the achievements tree: 7 real branches, 35 awards.
void main() {
  // The real catalogue: category -> (award count, first sort_order).
  const catalogue = <(String, int, int)>[
    ('Локації', 6, 10),
    ('Відвідування', 6, 110),
    ('Соціальне', 5, 210),
    ('Фото', 5, 310),
    ('Відстань', 6, 410),
    ('Спільнота', 3, 510),
    ('Рівні', 4, 610),
  ];
  const icons = ['pin', 'map', 'explore', 'route', 'trophy', 'weird_unknown'];

  /// All 35 awards. [unlockedPerBranch] = how many of each branch (from the
  /// start) are unlocked.
  List<AchievementModel> all({
    Map<String, int> unlocked = const {},
    DateTime? at,
  }) {
    final out = <AchievementModel>[];
    for (final (category, count, first) in catalogue) {
      final n = unlocked[category] ?? 0;
      for (var i = 0; i < count; i++) {
        final isUnlocked = i < n;
        out.add(AchievementModel(
          key: '${category}_$i',
          name: '$category $i',
          description: 'Опис $category $i',
          icon: icons[i % icons.length],
          unlockCondition: 'Умова $category $i',
          category: category,
          progress: isUnlocked ? (i + 1) * 10.0 : (i == n ? 3 : 0),
          target: (i + 1) * 10.0,
          isUnlocked: isUnlocked,
          unlockedAt: isUnlocked ? (at ?? DateTime.utc(2026, 3, 5 + i)) : null,
          sortOrder: first + i * 10,
        ));
      }
    }
    return out;
  }

  Widget list(
    List<AchievementModel> items, {
    bool expandAll = true,
    double width = 400,
    double scale = 1,
  }) =>
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 760), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: AchievementsList(items: items, expandAll: expandAll)),
        ),
      );

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget screen(List<Override> overrides, {double width = 400}) =>
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 760)),
            child: const Scaffold(body: AchievementsTab()),
          ),
        ),
      );

  Override data(List<AchievementModel> v) =>
      achievementsProvider.overrideWith((ref) async => v);

  group('branch model (pure)', () {
    test('7 real categories, 35 awards, in server order', () {
      final b = buildAchievementBranches(all());
      expect(b.map((e) => e.category), [for (final c in catalogue) c.$1]);
      expect(b.map((e) => e.total), [for (final c in catalogue) c.$2]);
      expect(b.fold<int>(0, (s, e) => s + e.total), 35);
    });

    test('nodes follow sort_order even if the input is shuffled', () {
      final shuffled = all().reversed.toList();
      final b = buildAchievementBranches(shuffled);
      for (final branch in b) {
        final orders = branch.nodes.map((n) => n.sortOrder).toList();
        expect([...orders]..sort(), orders, reason: branch.category);
      }
      expect(b.first.category, 'Локації');
    });

    test('an award repeated by key appears once', () {
      final items = all();
      final b = buildAchievementBranches([...items, items.first, items[7]]);
      expect(b.fold<int>(0, (s, e) => s + e.total), 35);
    });

    test('a duplicate key keeps the best state and the first position', () {
      AchievementModel a(String key, bool unlocked, double progress,
              {int sort = 10}) =>
          AchievementModel(
              key: key,
              name: key,
              description: 'd',
              icon: 'pin',
              unlockCondition: 'c',
              category: 'Локації',
              progress: progress,
              target: 10,
              isUnlocked: unlocked,
              sortOrder: sort);
      // locked copy first, unlocked copy later -> stays unlocked
      var b = buildAchievementBranches(
          [a('x', false, 1), a('y', false, 0, sort: 20), a('x', true, 10)]);
      expect(b.single.nodes.map((n) => n.key), ['x', 'y']);
      expect(b.single.nodes.first.isUnlocked, isTrue);
      expect(b.single.nextTarget!.key, 'y');
      // both locked -> the larger progress wins
      b = buildAchievementBranches([a('x', false, 2), a('x', false, 7)]);
      expect(b.single.nodes.single.progress, 7);
      // unlocked copy first -> a later locked copy cannot undo it
      b = buildAchievementBranches([a('x', true, 10), a('x', false, 3)]);
      expect(b.single.nodes.single.isUnlocked, isTrue);
      expect(b.single.unlocked, 1);
    });

    test('next target: first locked in sort_order, at most one per branch', () {
      final b = buildAchievementBranches(all(unlocked: {'Фото': 2}));
      for (final branch in b) {
        final firstLocked = branch.nodes.where((n) => !n.isUnlocked).toList();
        expect(branch.nextTarget,
            firstLocked.isEmpty ? isNull : same(firstLocked.first));
      }
    });

    test('counts, fraction and next target', () {
      final b = buildAchievementBranches(
          all(unlocked: {'Локації': 2, 'Фото': 5, 'Рівні': 0}));
      final loc = b.firstWhere((e) => e.category == 'Локації');
      expect((loc.unlocked, loc.total), (2, 6));
      expect(loc.fraction, closeTo(2 / 6, 1e-9));
      expect(loc.nextTarget!.key, 'Локації_2');
      final photo = b.firstWhere((e) => e.category == 'Фото');
      expect(photo.isComplete, isTrue);
      expect(photo.nextTarget, isNull);
      final lvl = b.firstWhere((e) => e.category == 'Рівні');
      expect(lvl.unlocked, 0);
      expect(lvl.nextTarget!.key, 'Рівні_0');
    });

    test('an unknown category still gets a branch and a fallback icon', () {
      final b = buildAchievementBranches([
        const AchievementModel(
            key: 'x',
            name: 'X',
            description: 'd',
            icon: 'pin',
            unlockCondition: 'c',
            category: 'Нове',
            progress: 0,
            target: 1,
            isUnlocked: false),
      ]);
      expect(b.single.category, 'Нове');
      expect(branchIconFor('Нове'), Icons.emoji_events);
      expect(branchIconFor('Локації'), Icons.place);
    });

    test('sortOrder defaults to 0 when the RPC row has none', () {
      const m = AchievementModel(
          key: 'k',
          name: 'n',
          description: 'd',
          icon: 'pin',
          unlockCondition: 'c',
          progress: 0,
          target: 1,
          isUnlocked: false);
      expect(m.sortOrder, 0);
    });
  });

  group('tree UI', () {
    testWidgets('header: title, X із 35, gold bar', (tester) async {
      await tester.pumpWidget(screen([
        data(all(unlocked: {'Локації': 3}))
      ]));
      await tester.pump();
      await tester.pump();
      expect(find.text('Мої досягнення'), findsOneWidget);
      expect(find.text('Відкрито 3 із 35'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
          find.byKey(const Key('achievements_progress')));
      expect(bar.value, closeTo(3 / 35, 1e-9));
      expect(bar.color, AppColors.accent);
    });

    testWidgets('7 branches with X / Y; all 35 nodes exist, once each',
        (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all(unlocked: {'Локації': 2})));
      for (final (category, count, _) in catalogue) {
        expect(find.byKey(Key('achievement_branch_$category')), findsOneWidget,
            reason: category);
        final n = category == 'Локації' ? 2 : 0;
        expect(find.text('$n / $count'), findsWidgets);
      }
      var nodes = 0;
      for (final a in all()) {
        expect(find.byKey(Key('achievement_${a.key}')), findsOneWidget,
            reason: a.key);
        nodes++;
      }
      expect(nodes, 35);
    });

    testWidgets('nodes are drawn in sort_order, top to bottom', (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all().reversed.toList()));
      final ys = [
        for (var i = 0; i < 6; i++)
          tester.getTopLeft(find.byKey(Key('achievement_Локації_$i'))).dy
      ];
      expect([...ys]..sort(), ys);
    });

    testWidgets(
        'unlocked: real icon; locked: lock; one next target per open '
        'branch', (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all(unlocked: {'Локації': 2, 'Фото': 5})));

      Icon icon(String k) =>
          tester.widget<Icon>(find.byKey(Key('achievement_icon_$k')));
      expect(icon('Локації_0').icon, Icons.location_on); // pin
      expect(icon('Локації_1').icon, Icons.map);
      expect(icon('Локації_2').icon, Icons.lock_outline);
      // exactly one "Наступна ціль" in the partially filled branch
      expect(
          find.byKey(const Key('achievement_next_Локації_2')), findsOneWidget);
      expect(find.byKey(const Key('achievement_next_Локації_3')), findsNothing);
      // a finished branch has none, and says so
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('achievement_next_Фото_$i')), findsNothing);
      }
      expect(
          find.byKey(const Key('achievement_branch_complete')), findsOneWidget);
      // zero progress: the first node is the target
      expect(find.byKey(const Key('achievement_next_Спільнота_0')),
          findsOneWidget);
    });

    testWidgets('partial progress is the real value', (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all(unlocked: {'Локації': 2})));
      final p = tester.widget<LinearProgressIndicator>(
          find.byKey(const Key('achievement_progress_Локації_2')));
      expect(p.value, closeTo(3 / 30, 1e-9));
      expect(
          find.descendant(
              of: find.byKey(const Key('achievement_Локації_2')),
              matching: find.text('3 / 30')),
          findsOneWidget);
    });

    testWidgets('default expansion: branches in progress open, others closed',
        (tester) async {
      bigView(tester);
      await tester.pumpWidget(
          list(all(unlocked: {'Локації': 2, 'Фото': 5}), expandAll: false));
      expect(find.byKey(const Key('achievement_Локації_0')), findsOneWidget);
      // finished and untouched branches start collapsed
      expect(find.byKey(const Key('achievement_Фото_0')), findsNothing);
      expect(find.byKey(const Key('achievement_Рівні_0')), findsNothing);
      // collapsed header shows the next goal
      expect(find.text('Далі: Рівні 0'), findsOneWidget);
    });

    testWidgets('with no progress at all the first branch is open',
        (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all(), expandAll: false));
      expect(find.byKey(const Key('achievement_Локації_0')), findsOneWidget);
      expect(find.byKey(const Key('achievement_Відвідування_0')), findsNothing);
    });

    testWidgets('tapping a branch header expands and collapses it',
        (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all(), expandAll: false));
      await tester
          .tap(find.byKey(const Key('achievement_branch_toggle_Відвідування')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('achievement_Відвідування_0')), findsOneWidget);
      await tester
          .tap(find.byKey(const Key('achievement_branch_toggle_Відвідування')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('achievement_Відвідування_0')), findsNothing);
    });

    testWidgets('a fully completed branch shows N / N', (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all(unlocked: {'Рівні': 4})));
      expect(
          tester
              .widget<Text>(
                  find.byKey(const Key('achievement_branch_count_Рівні')))
              .data,
          '4 / 4');
      final bar = tester.widget<LinearProgressIndicator>(
          find.byKey(const Key('achievement_branch_progress_Рівні')));
      expect(bar.value, 1);
    });
  });

  group('details', () {
    testWidgets('unlocked award: real data, date, XP not provided',
        (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all(unlocked: {'Локації': 2})));
      await tester.tap(find.byKey(const Key('achievement_Локації_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('achievement_detail_sheet')), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('achievement_detail_name')))
              .data,
          'Локації 1');
      expect(find.text('Опис Локації 1'), findsOneWidget);
      expect(find.text('Умова Локації 1'), findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const Key('achievement_detail_progress')))
              .data,
          '20 / 20');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('achievement_detail_date')))
              .data,
          '06.03.2026');
      // the RPC has no XP per award: there is no XP row at all
      expect(find.textContaining('XP'), findsNothing);
      expect(find.byKey(const Key('achievement_detail_xp')), findsNothing);
      expect(find.text('Розблоковано'), findsWidgets);
    });

    testWidgets('locked award: partial progress and "Ще ні"', (tester) async {
      bigView(tester);
      await tester.pumpWidget(list(all(unlocked: {'Локації': 2})));
      await tester.tap(find.byKey(const Key('achievement_Локації_2')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(
                  find.byKey(const Key('achievement_detail_progress')))
              .data,
          '3 / 30');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('achievement_detail_date')))
              .data,
          'Ще ні');
      expect(find.text('Заблоковано'), findsOneWidget);
    });

    testWidgets('no target in the data -> "Недоступний", nothing invented',
        (tester) async {
      bigView(tester);
      await tester.pumpWidget(list([
        const AchievementModel(
            key: 'z',
            name: 'Без цілі',
            description: 'd',
            icon: 'pin',
            unlockCondition: 'c',
            category: 'Локації',
            progress: 0,
            target: 0,
            isUnlocked: false),
      ]));
      expect(find.text('Прогрес недоступний'), findsOneWidget);
      await tester.tap(find.byKey(const Key('achievement_z')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(
                  find.byKey(const Key('achievement_detail_progress')))
              .data,
          'Недоступний');
    });
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

  group('adaptive', () {
    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('no overflow at ${width}dp @ ${scale}x', (tester) async {
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final items = all(unlocked: {'Локації': 3, 'Рівні': 4});
          items[3] = AchievementModel(
              key: items[3].key,
              name: 'Дуже довга назва нагороди для перевірки переносу тексту',
              description: 'Дуже довгий опис, який переноситься на рядки',
              icon: 'map',
              unlockCondition: 'Довга умова розблокування нагороди',
              category: items[3].category,
              progress: 3,
              target: 10,
              isUnlocked: false,
              sortOrder: items[3].sortOrder);
          await tester.pumpWidget(list(items, width: width, scale: scale));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('achievement_Локації_3')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('opens from the Premium Profile with real medal icons',
      (tester) async {
    final items = all(unlocked: {'Локації': 2});
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [data(items)],
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
            createdPlacesOverride: const AsyncData(3),
            visitedPlacesOverride: const AsyncData(2),
            recentJourneysOverride: const AsyncData([]),
            followCountsOverride:
                const AsyncData(FollowCounts(followers: 21, following: 34)),
            journeyStatsOverride: const AsyncData(
                ProfileJourneyStats(count: 0, confirmedDistanceMeters: 0)),
            onLogout: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(
        tester
            .widget<Icon>(find.byKey(const Key('profile_medal_icon_Локації_0')))
            .icon,
        Icons.location_on);
    expect(
        tester
            .widget<Icon>(find.byKey(const Key('profile_medal_icon_Локації_1')))
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
    expect(find.byKey(const Key('achievement_branch_Локації')), findsOneWidget);
  });
}
