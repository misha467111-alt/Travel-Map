import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/domain/location_query.dart';
import 'package:flutter_application_1/features/map/presentation/search_screen.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';

/// Search Phase 2B — Screen 6 reference rebuild.
///
/// Covers: the new Recent/Popular initial state, the deterministic
/// per-device Recent Searches persistence contract, the curated Popular
/// shortcut -> category/query mapping, the new "Скасувати" header, and
/// two previously-uncovered corners of the preserved search engine
/// (error state, bookmark toggle). Debounce/loading/pagination/details/
/// empty-result coverage for the engine itself already lives in
/// `batch5_presentation_test.dart` and is intentionally not duplicated
/// here.
class _FakeRecentSearchesNotifier extends RecentSearchesNotifier {
  _FakeRecentSearchesNotifier(this._seed);
  final List<String> _seed;

  @override
  Future<List<String>> build() async => _seed;

  /// Mirrors the real save rule (via the same pure [mergeRecent]) without
  /// touching SharedPreferences, so widget tests can exercise a real
  /// search -> recorded-as-recent round trip.
  @override
  Future<void> record(String term) async {
    final current = state.value ?? const <String>[];
    final updated = RecentSearchesNotifier.mergeRecent(current, term);
    state = AsyncData(updated);
  }
}

class _FakeSavedPublicLocationsNotifier extends SavedPublicLocationsNotifier {
  _FakeSavedPublicLocationsNotifier(this._ids);
  final Set<String> _ids;

  @override
  Future<Set<String>> build() async => _ids;

  @override
  Future<void> toggle(String locationId) async {
    final current = state.value ?? const <String>{};
    final updated = Set<String>.of(current);
    updated.contains(locationId)
        ? updated.remove(locationId)
        : updated.add(locationId);
    state = AsyncData(updated);
  }
}

void main() {
  group('RecentSearchesNotifier.mergeRecent (pure, deterministic)', () {
    test('whitespace is trimmed', () {
      final result = RecentSearchesNotifier.mergeRecent(const [], '  сад  ');
      expect(result, ['сад']);
    });

    test('blank values are ignored (list returned unchanged)', () {
      const current = ['сад'];
      final result = RecentSearchesNotifier.mergeRecent(current, '   ');
      expect(identical(result, current), isTrue);
    });

    test('dedup is case-insensitive; newest occurrence wins and moves front',
        () {
      final result =
          RecentSearchesNotifier.mergeRecent(const ['Kyiv', 'Lviv'], 'kyiv');
      expect(result, ['kyiv', 'Lviv']);
    });

    test('newest first', () {
      final result = RecentSearchesNotifier.mergeRecent(const ['a', 'b'], 'c');
      expect(result, ['c', 'a', 'b']);
    });

    test('bounded to max 5 entries', () {
      final result = RecentSearchesNotifier.mergeRecent(
        const ['a', 'b', 'c', 'd', 'e'],
        'f',
      );
      expect(result, ['f', 'a', 'b', 'c', 'd']);
      expect(result.length, 5);
    });
  });

  group('Search Phase 2B — initial state', () {
    testWidgets('empty query shows the curated Popular shortcuts',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: LocationSearchScreen()),
      ));

      expect(find.text('Популярні'), findsOneWidget);
      for (final label in const [
        'Парки',
        'Музеї',
        "Кав'ярні",
        'Ресторани',
        'Оглядові майданчики',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('does not inject the reference/demo rows as fake history',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: LocationSearchScreen()),
      ));

      for (final fake in const [
        'Голосіївський парк',
        'Андріївський узвіз',
        'Музеї старої Києва',
      ]) {
        expect(find.text(fake), findsNothing);
      }
      expect(find.text('Недавні запити'), findsNothing);
    });

    testWidgets('stored Recent history renders correctly', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          recentSearchesProvider.overrideWith(
              () => _FakeRecentSearchesNotifier(const ['сад', 'парк'])),
        ],
        child: const MaterialApp(home: LocationSearchScreen()),
      ));
      await tester.pump();

      expect(find.text('Недавні запити'), findsOneWidget);
      expect(find.text('сад'), findsOneWidget);
      expect(find.text('парк'), findsOneWidget);
    });
  });

  testWidgets(
      'Search Phase 2B — recent row tap puts the term in the field and '
      'executes a real search', (tester) async {
    var calls = 0;
    String? receivedSearch;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        recentSearchesProvider
            .overrideWith(() => _FakeRecentSearchesNotifier(const ['сад'])),
      ],
      child: MaterialApp(
        home: LocationSearchScreen(
          savedLocationIds: const {},
          pageLoader: ({cursor, category, search, required limit}) async {
            calls++;
            receivedSearch = search;
            return const LocationPage(items: [], hasMore: false);
          },
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('сад'));
    await tester.pump();

    expect(find.byKey(const ValueKey('search_results')), findsOneWidget);
    expect(calls, 1);
    expect(receivedSearch, 'сад');
    final field =
        tester.widget<TextField>(find.byKey(const Key('travel_search_field')));
    expect(field.controller!.text, 'сад');
  });

  // Search Phase 2B — each Popular row is interactive and maps to the
  // exact designed category/query. Written as five independent tests
  // (rather than one loop over five taps) so each gets a clean widget
  // tree and test binding -- a shared-binding loop was found to leak
  // async state (a stale pending _load from the prior tap's widget
  // resolving against the next iteration's freshly-pumped tree).
  const popularMapping = <String, String?>{
    'Парки': 'nature',
    'Музеї': 'culture',
    "Кав'ярні": 'cafe',
    'Ресторани': null,
    'Оглядові майданчики': 'viewpoints',
  };

  for (final entry in popularMapping.entries) {
    testWidgets(
        'Search Phase 2B — Popular row "${entry.key}" maps to '
        '${entry.value ?? "a real text search"}', (tester) async {
      String? receivedCategory;
      String? receivedSearch;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: LocationSearchScreen(
            savedLocationIds: const {},
            pageLoader: ({cursor, category, search, required limit}) async {
              receivedCategory = category;
              receivedSearch = search;
              return const LocationPage(items: [], hasMore: false);
            },
          ),
        ),
      ));

      await tester.tap(find.text(entry.key));
      await tester.pump();

      expect(find.byKey(const ValueKey('search_results')), findsOneWidget);
      expect(receivedCategory, entry.value);
      expect(receivedSearch, entry.value == null ? entry.key : null);
    });
  }

  group('Search Phase 2B — header', () {
    testWidgets('"Скасувати" cancel action exists', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: LocationSearchScreen()),
      ));

      expect(find.byKey(const Key('search_cancel_action')), findsOneWidget);
      expect(find.text('Скасувати'), findsOneWidget);
    });

    testWidgets('old BackButton presentation is gone', (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: LocationSearchScreen()),
      ));

      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('Cancel pops the Search screen', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LocationSearchScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(LocationSearchScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('search_cancel_action')));
      await tester.pumpAndSettle();

      expect(find.byType(LocationSearchScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
        'clearing the query returns to the initial Popular/Recent state',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: LocationSearchScreen(
            savedLocationIds: const {},
            pageLoader: ({cursor, category, search, required limit}) async =>
                const LocationPage(items: [], hasMore: false),
          ),
        ),
      ));

      await tester.enterText(
          find.byKey(const Key('travel_search_field')), 'сад');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byKey(const ValueKey('search_results')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('travel_search_field')), '');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.byKey(const ValueKey('search_initial')), findsOneWidget);
    });
  });

  group('Search Phase 2B — search engine preservation (error + bookmark)', () {
    testWidgets('error state still works and retry re-issues the same query',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: LocationSearchScreen(
            savedLocationIds: const {},
            pageLoader: ({cursor, category, search, required limit}) async {
              calls++;
              throw Exception('network down');
            },
          ),
        ),
      ));

      await tester.enterText(
          find.byKey(const Key('travel_search_field')), 'сад');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.byKey(const Key('search_error')), findsOneWidget);
      expect(calls, 1);

      await tester.tap(find.text('Спробувати ще раз'));
      await tester.pump();

      expect(calls, 2);
    });

    testWidgets('bookmark toggle is preserved for a real search result',
        (tester) async {
      final location = LocationModel(
        id: 'loc-1',
        userId: 'author-1',
        title: 'Ботанічний сад',
        description: 'Тихе зелене місце для прогулянок.',
        category: 'nature',
        latitude: 50.45,
        longitude: 30.52,
        createdAt: DateTime.utc(2026),
      );
      final item = LocationQueryItem(
        location: location,
        author: const AuthorSummary(id: 'author-1', name: 'Автор'),
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          savedPublicLocationsProvider
              .overrideWith(() => _FakeSavedPublicLocationsNotifier(const {})),
        ],
        child: MaterialApp(
          home: LocationSearchScreen(
            pageLoader: ({cursor, category, search, required limit}) async =>
                LocationPage(items: [item], hasMore: false),
          ),
        ),
      ));

      await tester.enterText(
          find.byKey(const Key('travel_search_field')), 'сад');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text(location.title), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pump();

      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsNothing);
    });
  });

  group('Search Phase 2B — responsive (initial state)', () {
    const widths = [320.0, 360.0, 390.0, 430.0];
    const scales = [1.0, 1.3, 1.5];
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets(
            'initial Recent/Popular state fits ${width}dp @ ${scale}x, no overflow',
            (tester) async {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: ProviderScope(
                overrides: [
                  recentSearchesProvider.overrideWith(
                      () => _FakeRecentSearchesNotifier(const ['сад', 'парк'])),
                ],
                child: const MaterialApp(home: LocationSearchScreen()),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull,
              reason: 'initial state overflowed at ${width}dp, scale $scale');
        });
      }
    }
  });

  group('Search Phase 2B — responsive (active results state)', () {
    const widths = [320.0, 360.0, 390.0, 430.0];
    const scales = [1.0, 1.3, 1.5];
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets(
            'active results state fits ${width}dp @ ${scale}x, no overflow',
            (tester) async {
          final location = LocationModel(
            id: 'loc-responsive',
            userId: 'author-1',
            title: 'Ботанічний сад',
            description: 'Тихе зелене місце для прогулянок.',
            category: 'nature',
            latitude: 50.45,
            longitude: 30.52,
            createdAt: DateTime.utc(2026),
          );
          final item = LocationQueryItem(
            location: location,
            author: const AuthorSummary(id: 'author-1', name: 'Автор'),
          );

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: ProviderScope(
                child: MaterialApp(
                  home: LocationSearchScreen(
                    savedLocationIds: const {},
                    pageLoader: (
                            {cursor, category, search, required limit}) async =>
                        LocationPage(items: [item], hasMore: false),
                  ),
                ),
              ),
            ),
          );
          await tester.enterText(
              find.byKey(const Key('travel_search_field')), 'сад');
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump();

          expect(tester.takeException(), isNull,
              reason: 'results state overflowed at ${width}dp, scale $scale');
        });
      }
    }
  });
}
