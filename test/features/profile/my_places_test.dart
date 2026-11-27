import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/providers/locations_provider.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/profile/presentation/my_places_screen.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_screen.dart';
import 'package:flutter_application_1/features/profile/providers/my_places_provider.dart';
import 'package:flutter_application_1/features/profile/providers/profile_journey_stats_provider.dart';
import 'package:flutter_application_1/features/profile/providers/profile_journey_data_provider.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';

class _FakeSaved extends SavedPublicLocationsNotifier {
  _FakeSaved(this.ids, this.toggled);
  final Set<String> ids;
  final List<String> toggled;

  @override
  Future<Set<String>> build() async => ids;

  @override
  Future<void> toggle(String locationId) async => toggled.add(locationId);
}

/// Phase 3.3-D -- own places (created / saved / visited) and recent Journeys.
void main() {
  LocationModel place(String id, String title,
          {String status = 'approved', String? description}) =>
      LocationModel(
        id: id,
        userId: 'me',
        title: title,
        description: description ?? 'Опис $title',
        category: 'nature',
        latitude: 50.45,
        longitude: 30.52,
        createdAt: DateTime.utc(2026, 1, 1),
        status: status,
      );

  group('aggregateVisits (pure)', () {
    test('one entry per location_id; repeats do not add places', () {
      final v = aggregateVisits([
        {'location_id': 'a', 'created_at': '2026-03-01T10:00:00Z'},
        {'location_id': 'a', 'created_at': '2026-03-05T10:00:00Z'},
        {'location_id': 'a', 'created_at': '2026-03-03T10:00:00Z'},
        {'location_id': 'b', 'created_at': '2026-03-04T10:00:00Z'},
      ]);
      expect(v.map((e) => e.locationId), ['a', 'b']);
      expect(v.first.visits, 3);
      expect(v.first.lastVisit, DateTime.utc(2026, 3, 5, 10));
      expect(v.last.visits, 1);
    });

    test('sorted by the latest visit, newest first', () {
      final v = aggregateVisits([
        {'location_id': 'old', 'created_at': '2026-01-01T00:00:00Z'},
        {'location_id': 'new', 'created_at': '2026-06-01T00:00:00Z'},
        {'location_id': 'mid', 'created_at': '2026-03-01T00:00:00Z'},
      ]);
      expect(v.map((e) => e.locationId), ['new', 'mid', 'old']);
    });

    test('empty input and unusable rows are ignored', () {
      expect(aggregateVisits(const []), isEmpty);
      expect(
          aggregateVisits([
            {'location_id': null, 'created_at': '2026-01-01T00:00:00Z'},
            {'location_id': '', 'created_at': '2026-01-01T00:00:00Z'},
            {'location_id': 'x', 'created_at': 'not a date'},
          ]),
          isEmpty);
    });
  });

  final toggled = <String>[];

  Widget places({
    int tab = 0,
    String owner = 'me',
    List<Override> overrides = const [],
    double width = 400,
    double scale = 1,
    void Function(BuildContext, LocationModel)? onOpen,
  }) {
    toggled.clear();
    return ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: MyPlacesScreen(
              ownerId: owner, initialTab: tab, onOpenLocation: onOpen),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump();
  }

  group('created', () {
    testWidgets('shows my locations with their moderation status',
        (tester) async {
      // The list builds lazily: a tall screen, so all four places are built.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(places(overrides: [
        myCreatedLocationsProvider((ownerId: 'me', limit: 100))
            .overrideWith((ref) async => [
                  place('1', 'Мій парк'),
                  place('2', 'Чернетка місця', status: 'draft'),
                  place('3', 'На перевірці', status: 'pending'),
                  place('4', 'Відхилене', status: 'rejected'),
                ]),
      ]));
      await settle(tester);
      expect(find.text('Мій парк'), findsOneWidget);
      Finder status(String id) => find.byKey(Key('my_place_status_$id'));
      expect(tester.widget<Text>(status('1')).data, 'Статус: Схвалено');
      expect(tester.widget<Text>(status('2')).data, 'Статус: Чернетка');
      expect(tester.widget<Text>(status('3')).data, 'Статус: На модерації');
      expect(tester.widget<Text>(status('4')).data, 'Статус: Відхилено');
    });

    testWidgets('the list is scoped to the given owner', (tester) async {
      await tester.pumpWidget(places(owner: 'me', overrides: [
        myCreatedLocationsProvider((ownerId: 'me', limit: 100))
            .overrideWith((ref) async => [place('1', 'Моя')]),
        myCreatedLocationsProvider((ownerId: 'someone-else', limit: 100))
            .overrideWith((ref) async => [place('9', 'Чужа')]),
      ]));
      await settle(tester);
      expect(find.text('Моя'), findsOneWidget);
      expect(find.text('Чужа'), findsNothing);
    });

    testWidgets('empty, loading and error with retry', (tester) async {
      await tester.pumpWidget(places(overrides: [
        myCreatedLocationsProvider((ownerId: 'me', limit: 100))
            .overrideWith((ref) async => []),
      ]));
      await settle(tester);
      expect(find.byKey(const Key('my_places_empty_created')), findsOneWidget);

      final never = Completer<List<LocationModel>>();
      await tester.pumpWidget(places(overrides: [
        myCreatedLocationsProvider((ownerId: 'me', limit: 100))
            .overrideWith((ref) => never.future),
      ]));
      await tester.pump();
      expect(
          find.byKey(const Key('my_places_loading_created')), findsOneWidget);

      var calls = 0;
      await tester.pumpWidget(places(overrides: [
        myCreatedLocationsProvider((ownerId: 'me', limit: 100))
            .overrideWith((ref) async {
          calls++;
          throw StateError('offline');
        }),
      ]));
      await settle(tester);
      expect(find.byKey(const Key('my_places_error_created')), findsOneWidget);
      await tester.tap(find.text('Повторити'));
      await settle(tester);
      expect(calls, 2);
    });

    testWidgets('tapping a place opens that location', (tester) async {
      final opened = <LocationModel>[];
      await tester.pumpWidget(places(
        onOpen: (context, l) => opened.add(l),
        overrides: [
          myCreatedLocationsProvider((ownerId: 'me', limit: 100))
              .overrideWith((ref) async => [place('1', 'Мій парк')]),
        ],
      ));
      await settle(tester);
      await tester.tap(find.text('Мій парк'));
      await tester.pump();
      expect(opened.single.id, '1');
    });
  });

  group('saved', () {
    testWidgets('my bookmarks via the existing bookmark system',
        (tester) async {
      final ids = {'a', 'b'};
      await tester.pumpWidget(places(tab: 1, overrides: [
        savedPublicLocationsProvider
            .overrideWith(() => _FakeSaved(ids, toggled)),
        mySavedLocationsProvider(ids).overrideWith(
            (ref) async => [place('a', 'Збережене А'), place('b', 'Б')]),
      ]));
      await settle(tester);
      expect(find.text('Збережене А'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.bookmark).first);
      await tester.pump();
      expect(toggled, ['a']);
    });

    testWidgets('no bookmarks -> empty state', (tester) async {
      await tester.pumpWidget(places(tab: 1, overrides: [
        savedPublicLocationsProvider
            .overrideWith(() => _FakeSaved(<String>{}, toggled)),
      ]));
      await settle(tester);
      expect(find.byKey(const Key('my_places_empty_saved')), findsOneWidget);
    });
  });

  group('visited', () {
    testWidgets('unique places, last visit and repeat count', (tester) async {
      await tester.pumpWidget(places(tab: 2, overrides: [
        myVisitedPlacesProvider('me').overrideWith((ref) async => VisitedPlaces(
              total: 3,
              places: [
                (
                  VisitedPlace(
                      locationId: 'a',
                      lastVisit: DateTime.utc(2026, 3, 5, 10),
                      visits: 3),
                  place('a', 'Відвідане А')
                ),
                (
                  VisitedPlace(
                      locationId: 'b',
                      lastVisit: DateTime.utc(2026, 3, 4, 10),
                      visits: 1),
                  place('b', 'Відвідане Б')
                ),
              ],
            )),
      ]));
      await settle(tester);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('my_places_visited_total')))
              .data,
          'Унікальних місць: 3');
      // a place that can no longer be loaded is counted but not listed
      expect(find.byKey(const Key('my_places_visited_hidden')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const Key('my_place_visit_a'))).data,
          contains('3 відвідувань'));
      expect(
          tester.widget<Text>(find.byKey(const Key('my_place_visit_b'))).data,
          contains('1 відвідування'));
      expect(find.text('Відвідане А'), findsOneWidget);
    });

    testWidgets('no check-ins -> empty, never a made-up place', (tester) async {
      await tester.pumpWidget(places(tab: 2, overrides: [
        myVisitedPlacesProvider('me').overrideWith(
            (ref) async => const VisitedPlaces(total: 0, places: [])),
      ]));
      await settle(tester);
      expect(find.byKey(const Key('my_places_empty_visited')), findsOneWidget);
      expect(find.byKey(const Key('my_places_visited_total')), findsNothing);
    });

    testWidgets('error shows retry', (tester) async {
      await tester.pumpWidget(places(tab: 2, overrides: [
        myVisitedPlacesProvider('me')
            .overrideWith((ref) async => throw StateError('x')),
      ]));
      await settle(tester);
      expect(find.byKey(const Key('my_places_error_visited')), findsOneWidget);
    });
  });

  testWidgets('tabs: the three lists are separate', (tester) async {
    final savedIds = {'2'};
    await tester.pumpWidget(places(overrides: [
      myCreatedLocationsProvider((ownerId: 'me', limit: 100))
          .overrideWith((ref) async => [place('1', 'Створене')]),
      savedPublicLocationsProvider
          .overrideWith(() => _FakeSaved(savedIds, toggled)),
      mySavedLocationsProvider(savedIds)
          .overrideWith((ref) async => [place('2', 'Збережене')]),
      myVisitedPlacesProvider('me').overrideWith((ref) async => VisitedPlaces(
            total: 1,
            places: [
              (
                VisitedPlace(
                    locationId: '3',
                    lastVisit: DateTime.utc(2026, 1, 1),
                    visits: 1),
                place('3', 'Відвідане')
              ),
            ],
          )),
    ]));
    await settle(tester);
    expect(find.text('Створене'), findsOneWidget);
    expect(find.text('Збережене'), findsNothing);
    await tester.tap(find.byKey(const Key('my_places_tab_saved')));
    await tester.pumpAndSettle();
    expect(find.text('Збережене'), findsOneWidget);
    expect(find.text('Створене'), findsNothing);
    await tester.tap(find.byKey(const Key('my_places_tab_visited')));
    await tester.pumpAndSettle();
    expect(find.text('Відвідане'), findsOneWidget);
  });

  group('own profile sections', () {
    const me = UserProfile(
      id: 'me',
      name: 'Іван',
      email: 'i@e.com',
      level: 'Новачок',
      xp: 10,
      locationsCount: 12,
    );

    LocalRecordedRoute route(String id, {String? title}) => LocalRecordedRoute(
          id: id,
          ownerId: 'me',
          title: title,
          transportMode: 'walking',
          status: RecordedRouteStatus.completed,
          visibility: 'private',
          startedAt: DateTime.utc(2026, 3, 5, 10),
          endedAt: DateTime.utc(2026, 3, 5, 11),
          createdAt: DateTime.utc(2026, 3, 5, 10),
          updatedAt: DateTime.utc(2026, 3, 5, 11),
          syncStatus: RouteSyncStatus.synced,
        );

    ProfileJourneyData journeyData(String id, double meters) =>
        ProfileJourneyData(
          runs: const [],
          statistics: GpsJourneyStatistics(
            totalDistanceMeters: meters,
            elapsed: const Duration(hours: 1),
            moving: const Duration(minutes: 50),
            paused: const Duration(minutes: 10),
            averageSpeedMps: 1,
            maxSpeedMps: 2,
            elevationGainMeters: 0,
            elevationLossMeters: 0,
          ),
        );

    Widget profile({
      AsyncValue<int> created = const AsyncData(3),
      AsyncValue<int> visited = const AsyncData(2),
      AsyncValue<List<LocalRecordedRoute>> journeys = const AsyncData([]),
      Map<String, double> journeyMeters = const {},
      List<String>? opened,
      List<Override> overrides = const [],
      double width = 400,
      double scale = 1,
    }) =>
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            // The per-Journey data is read from the local GPS database; tests
            // never open it (no data unless a test overrides it).
            for (final r in journeys.value ?? const <LocalRecordedRoute>[])
              profileJourneyDataProvider((ownerId: 'me', routeId: r.id))
                  .overrideWith((ref) async => journeyMeters[r.id] == null
                      ? null
                      : journeyData(r.id, journeyMeters[r.id]!)),
            ...overrides,
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 800), textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: ProfileContent(
                  profile: me,
                  savedCountOverride: 4,
                  achievementProgressOverride: const (unlocked: 1, total: 35),
                  unlockedAchievementsOverride: const [],
                  inviteBalanceOverride: 0,
                  createdPlacesOverride: created,
                  visitedPlacesOverride: visited,
                  recentJourneysOverride: journeys,
                  followCountsOverride: const AsyncData(
                      FollowCounts(followers: 21, following: 34)),
                  journeyStatsOverride: const AsyncData(ProfileJourneyStats(
                      count: 0, confirmedDistanceMeters: 0)),
                  onDestination: opened?.add,
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );

    Finder sub(String dest, String text) => find.descendant(
        of: find.byKey(Key('profile_action_$dest')), matching: find.text(text));

    testWidgets('real counts: created, saved, visited', (tester) async {
      await tester.pumpWidget(profile());
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_action_places_created')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Мої місця'), findsOneWidget);
      expect(sub('places_created', '3'), findsOneWidget);
      expect(sub('places_saved', '4'), findsOneWidget);
      expect(sub('places_visited', '2'), findsOneWidget);
    });

    testWidgets('loading and error never show a made-up number',
        (tester) async {
      await tester.pumpWidget(profile(
          created: const AsyncLoading(),
          visited: AsyncError(StateError('x'), StackTrace.empty)));
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_action_places_created')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(sub('places_created', 'Завантаження…'), findsOneWidget);
      expect(sub('places_visited', 'Недоступно'), findsOneWidget);
    });

    testWidgets('created is an exact total, not the size of a page',
        (tester) async {
      await tester.pumpWidget(profile(created: const AsyncData(250)));
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_action_places_created')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(sub('places_created', '250'), findsOneWidget);
      expect(sub('places_created', '100+'), findsNothing);
    });

    testWidgets('visited: "N+" only when not all check-ins were read',
        (tester) async {
      await tester.pumpWidget(profile(visited: const AsyncData(7)));
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_action_places_visited')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(sub('places_visited', '7'), findsOneWidget);
    });

    testWidgets('rows report their destination', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(profile(opened: opened));
      for (final d in ['places_created', 'places_saved', 'places_visited']) {
        final f = find.byKey(Key('profile_action_$d'));
        await tester.scrollUntilVisible(f, 200,
            scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(f);
        await tester.pump();
        await tester.tap(f);
      }
      expect(opened, ['places_created', 'places_saved', 'places_visited']);
    });

    testWidgets('recent Journeys: confirmed distance, duration, navigation',
        (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(profile(
        opened: opened,
        journeys: AsyncData([route('j1', title: 'Прогулянка'), route('j2')]),
        journeyMeters: {'j1': 1239, 'j2': 176},
      ));
      final j1 = find.byKey(const Key('profile_journey_j1'));
      await tester.scrollUntilVisible(j1, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.pump();
      expect(find.text('Прогулянка'), findsOneWidget);
      expect(find.textContaining('1.24 км'), findsOneWidget);
      expect(find.textContaining('176 м'), findsOneWidget);
      expect(find.textContaining('50 хв'), findsWidgets);
      await tester.ensureVisible(j1);
      await tester.pump();
      await tester.tap(j1);
      expect(opened, ['journey:j1']);
    });

    testWidgets('recent Journeys: empty / error / loading', (tester) async {
      await tester.pumpWidget(profile());
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_journeys_empty')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Подорожей ще немає'), findsOneWidget);

      await tester.pumpWidget(
          profile(journeys: AsyncError(StateError('x'), StackTrace.empty)));
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_journeys_error')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('profile_journeys_error')), findsOneWidget);

      await tester.pumpWidget(profile(journeys: const AsyncLoading()));
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_journeys_loading')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('profile_journeys_loading')), findsOneWidget);
    });

    testWidgets('only the 3 most recent Journeys are listed', (tester) async {
      await tester.pumpWidget(profile(
        journeys: AsyncData([for (var i = 0; i < 5; i++) route('r$i')]),
        journeyMeters: {for (var i = 0; i < 5; i++) 'r$i': 100},
      ));
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_journey_r0')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('profile_journey_r2')), findsOneWidget);
      expect(find.byKey(const Key('profile_journey_r3')), findsNothing);
    });

    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('fits ${width}dp @ ${scale}x', (tester) async {
          await tester.pumpWidget(profile(
            width: width,
            scale: scale,
            journeys: AsyncData([
              route('j1', title: 'Дуже довга назва подорожі для перевірки')
            ]),
            journeyMeters: {'j1': 12345},
          ));
          for (final k in [
            'profile_action_places_created',
            'profile_journey_j1'
          ]) {
            await tester.scrollUntilVisible(find.byKey(Key(k)), 200,
                scrollable: find.byType(Scrollable).first);
          }
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('adaptive: my places screen', () {
    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('fits ${width}dp @ ${scale}x', (tester) async {
          await tester
              .pumpWidget(places(width: width, scale: scale, overrides: [
            myCreatedLocationsProvider((ownerId: 'me', limit: 100))
                .overrideWith((ref) async => [
                      place('1',
                          'Дуже довга назва локації для перевірки переносу тексту',
                          status: 'pending'),
                    ]),
          ]));
          await settle(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('completeness of the totals', () {
    test('readAllPages reads page by page until a short page', () async {
      final calls = <(int, int)>[];
      final r = await readAllPages((from, to) async {
        calls.add((from, to));
        final total = 1200;
        final n = (total - from).clamp(0, to - from + 1);
        return [
          for (var i = 0; i < n; i++) {'i': from + i}
        ];
      }, pageSize: 500, maxPages: 10);
      expect(r.rows, hasLength(1200));
      expect(r.complete, isTrue);
      expect(calls, [(0, 499), (500, 999), (1000, 1499)]);
    });

    test('an exactly full last page still ends with an empty read', () async {
      var calls = 0;
      final r = await readAllPages((from, to) async {
        calls++;
        return from == 0
            ? [
                for (var i = 0; i < 500; i++) {'i': i}
              ]
            : [];
      }, pageSize: 500, maxPages: 10);
      expect(r.rows, hasLength(500));
      expect(r.complete, isTrue);
      expect(calls, 2);
    });

    test('the page bound marks the result incomplete (never exact)', () async {
      final r = await readAllPages(
          (from, to) async => [
                for (var i = from; i <= to; i++) {'i': i}
              ],
          pageSize: 10,
          maxPages: 3);
      expect(r.rows, hasLength(30));
      expect(r.complete, isFalse);
    });

    test('unique places are not the number of check-ins', () {
      final v = aggregateVisits([
        for (var i = 0; i < 600; i++)
          {
            'location_id': 'p${i % 3}',
            'created_at':
                '2026-03-${(i % 28 + 1).toString().padLeft(2, '0')}T10:00:00Z'
          },
      ]);
      expect(v, hasLength(3), reason: '600 check-ins at 3 places');
      expect(v.fold<int>(0, (s, e) => s + e.visits), 600);
    });

    test('loadLocationsInBatches reads ids 50 at a time', () async {
      final repo = _BatchRepo();
      final ids = [for (var i = 0; i < 120; i++) 'id$i'];
      final out = await loadLocationsInBatches(repo, ids);
      expect(repo.batches, [50, 50, 20]);
      expect(out, hasLength(120));
    });

    test('results are keyed by owner: B never receives A\'s numbers', () async {
      final container = ProviderContainer(overrides: [
        myCreatedCountProvider('A').overrideWith((ref) async => 7),
        myCreatedCountProvider('B').overrideWith((ref) async => 2),
        myVisitedPlacesProvider('A').overrideWith(
            (ref) async => const VisitedPlaces(total: 9, places: [])),
        myVisitedPlacesProvider('B').overrideWith(
            (ref) async => const VisitedPlaces(total: 0, places: [])),
      ]);
      addTearDown(container.dispose);
      expect(await container.read(myCreatedCountProvider('A').future), 7);
      expect(await container.read(myCreatedCountProvider('B').future), 2);
      expect(
          (await container.read(myVisitedPlacesProvider('B').future)).total, 0);
    });

    test('paging asks for disjoint, consecutive ranges (no overlap, no gap)',
        () async {
      final ranges = <(int, int)>[];
      await readAllPages((from, to) async {
        ranges.add((from, to));
        return [
          for (var i = from; i <= to; i++) {'i': i}
        ];
      }, pageSize: 100, maxPages: 4);
      expect(ranges, [(0, 99), (100, 199), (200, 299), (300, 399)]);
    });

    test('a repeated check-in row does not add a place or a second entry', () {
      final v = aggregateVisits([
        {'location_id': 'p1', 'created_at': '2026-03-05T10:00:00Z'},
        {'location_id': 'p1', 'created_at': '2026-03-05T10:00:00Z'},
        {'location_id': 'p2', 'created_at': '2026-03-04T10:00:00Z'},
      ]);
      expect(v.map((e) => e.locationId), ['p1', 'p2']);
    });

    testWidgets('created: exact total, "Показати ще" loads the next page',
        (tester) async {
      // The list builds lazily: a tall screen, so its footer is built.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(places(overrides: [
        myCreatedCountProvider('me').overrideWith((ref) async => 5),
        myCreatedLocationsProvider((ownerId: 'me', limit: 100)).overrideWith(
            (ref) async =>
                [for (var i = 0; i < 3; i++) place('a$i', 'Місце $i')]),
        myCreatedLocationsProvider((ownerId: 'me', limit: 200)).overrideWith(
            (ref) async =>
                [for (var i = 0; i < 5; i++) place('a$i', 'Місце $i')]),
      ]));
      await settle(tester);
      Text total() =>
          tester.widget<Text>(find.byKey(const Key('my_places_created_total')));
      expect(total().data, 'Показано 3 із 5');
      // Each card has a row with its map action now, so the button is below the
      // 600 dp test screen: scroll to it first.
      await tester
          .ensureVisible(find.byKey(const Key('my_places_created_more')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('my_places_created_more')));
      await settle(tester);
      expect(total().data, 'Усього: 5');
      expect(find.byKey(const Key('my_places_created_more')), findsNothing);
    });

    testWidgets('saved: real number of bookmarks, honest when fewer load',
        (tester) async {
      final ids = {'a', 'b', 'c'};
      await tester.pumpWidget(places(tab: 1, overrides: [
        savedPublicLocationsProvider
            .overrideWith(() => _FakeSaved(ids, toggled)),
        mySavedLocationsProvider(ids)
            .overrideWith((ref) async => [place('a', 'Лише одна')]),
      ]));
      await settle(tester);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('my_places_saved_total')))
              .data,
          'Показано 1 із 3');
    });

    testWidgets('visited: an incomplete history is shown as "N+"',
        (tester) async {
      await tester.pumpWidget(places(tab: 2, overrides: [
        myVisitedPlacesProvider('me').overrideWith((ref) async => VisitedPlaces(
              total: 40,
              isComplete: false,
              places: [
                (
                  VisitedPlace(
                      locationId: 'a',
                      lastVisit: DateTime.utc(2026, 3, 5),
                      visits: 2),
                  place('a', 'А')
                ),
              ],
            )),
      ]));
      await settle(tester);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('my_places_visited_total')))
              .data,
          'Унікальних місць: 40+');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('my_places_visited_hidden')))
              .data,
          'Показано 1 із 40');
    });
  });
}

class _BatchRepo implements LocationsRepository {
  final List<int> batches = [];

  @override
  Future<List<LocationModel>> fetchLocationsByIds(Iterable<String> ids) async {
    final list = ids.toList();
    batches.add(list.length);
    return [
      for (final id in list)
        LocationModel(
          id: id,
          userId: 'me',
          title: id,
          description: '',
          category: 'nature',
          latitude: 0,
          longitude: 0,
          createdAt: DateTime.utc(2026),
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
