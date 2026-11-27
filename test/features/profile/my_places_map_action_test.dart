import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/presentation/external_map_launcher.dart';
import 'package:flutter_application_1/features/map/presentation/location_card.dart';
import 'package:flutter_application_1/features/profile/presentation/my_places_screen.dart';
import 'package:flutter_application_1/features/profile/providers/my_places_provider.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

class _FakeSaved extends SavedPublicLocationsNotifier {
  _FakeSaved(this.ids);
  final Set<String> ids;

  @override
  Future<Set<String>> build() async => ids;
}

/// Phase 3.4-C3 -- every place in "Мої місця" has a "map" action that opens its
/// own coordinates in an external maps app through the shared launcher.
void main() {
  LocationModel place(
    String id,
    String title, {
    double lat = 50.45,
    double lng = 30.52,
    String status = 'approved',
  }) =>
      LocationModel(
        id: id,
        userId: 'me',
        title: title,
        description: 'Опис $title',
        category: 'nature',
        latitude: lat,
        longitude: lng,
        createdAt: DateTime.utc(2026, 1, 1),
        status: status,
      );

  // Two places with clearly different coordinates.
  final kyiv = place('kyiv', 'Київський парк', lat: 50.4547, lng: 30.5238);
  final kharkiv =
      place('kharkiv', 'Харківський сад', lat: 49.9935, lng: 36.2304);

  final createdKey = (ownerId: 'me', limit: 100);

  Override created(List<LocationModel> list) =>
      myCreatedLocationsProvider(createdKey).overrideWith((ref) async => list);

  // The family key is a Set (compared by identity): the notifier and the
  // override must share the very same instance, as the screen reads it from the
  // notifier's state.
  List<Override> savedAll(List<LocationModel> list,
      {SavedPublicLocationsNotifier Function(Set<String> ids)? notifier}) {
    final ids = {for (final l in list) l.id};
    return [
      savedPublicLocationsProvider
          .overrideWith(() => notifier?.call(ids) ?? _FakeSaved(ids)),
      mySavedLocationsProvider(ids).overrideWith((ref) async => list),
    ];
  }

  Override visited(List<LocationModel> list) =>
      myVisitedPlacesProvider('me').overrideWith((ref) async => VisitedPlaces(
            total: list.length,
            places: [
              for (final l in list)
                (
                  VisitedPlace(
                      locationId: l.id,
                      lastVisit: DateTime.utc(2026, 3, 5, 10),
                      visits: 2),
                  l
                ),
            ],
          ));

  Widget screen({
    required List<Override> overrides,
    int tab = 0,
    ExternalMapLauncher? launcher,
    void Function(BuildContext, LocationModel)? onOpen,
    double scale = 1,
  }) =>
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
                size: const Size(400, 800),
                textScaler: TextScaler.linear(scale)),
            child: MyPlacesScreen(
              ownerId: 'me',
              initialTab: tab,
              onOpenLocation: onOpen,
              launchExternalMapOverride: launcher,
            ),
          ),
        ),
      );

  Finder mapButton(String id) => find.byKey(Key('my_place_map_$id'));

  Future<void> show(WidgetTester tester, Widget w) async {
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
  }

  Future<void> tapMap(WidgetTester tester, String id) async {
    await tester.ensureVisible(mapButton(id));
    await tester.pump();
    await tester.tap(mapButton(id));
    await tester.pumpAndSettle();
  }

  group('the action is on the cards of every tab', () {
    final tabs = <String, ({int tab, List<Override> overrides})>{
      'Створені': (
        tab: 0,
        overrides: [
          created([kyiv, kharkiv])
        ]
      ),
      'Збережені': (tab: 1, overrides: savedAll([kyiv, kharkiv])),
      'Відвідані': (
        tab: 2,
        overrides: [
          visited([kyiv, kharkiv])
        ]
      ),
    };
    for (final entry in tabs.entries) {
      testWidgets('${entry.key}: one 48 dp map action per card',
          (tester) async {
        await show(tester,
            screen(tab: entry.value.tab, overrides: entry.value.overrides));

        for (final l in [kyiv, kharkiv]) {
          expect(mapButton(l.id), findsOneWidget);
          final button = tester.widget<IconButton>(mapButton(l.id));
          expect(button.tooltip, 'Відкрити в картах: ${l.title}',
              reason: 'accessible name says which place');
          final size = tester.getSize(mapButton(l.id));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        expect(find.byIcon(Icons.map_outlined), findsNWidgets(2));
      });
    }

    testWidgets('a pending place has it too (any moderation status)',
        (tester) async {
      await show(
          tester,
          screen(overrides: [
            created([place('p', 'На модерації', status: 'pending')]),
          ]));
      expect(mapButton('p'), findsOneWidget);
    });

    testWidgets('the existing status text is kept next to it', (tester) async {
      await show(
          tester,
          screen(overrides: [
            created([place('p', 'Чернетка', status: 'draft')]),
          ]));
      expect(
          tester.widget<Text>(find.byKey(const Key('my_place_status_p'))).data,
          'Статус: Чернетка');
      expect(mapButton('p'), findsOneWidget);
    });
  });

  group('opens the coordinates of exactly that card', () {
    final tabs = <String, ({int tab, List<Override> overrides})>{
      'Створені': (
        tab: 0,
        overrides: [
          created([kyiv, kharkiv])
        ]
      ),
      'Збережені': (tab: 1, overrides: savedAll([kyiv, kharkiv])),
      'Відвідані': (
        tab: 2,
        overrides: [
          visited([kyiv, kharkiv])
        ]
      ),
    };
    for (final entry in tabs.entries) {
      testWidgets(entry.key, (tester) async {
        final launched = <Uri>[];
        await show(
            tester,
            screen(
              tab: entry.value.tab,
              overrides: entry.value.overrides,
              launcher: (uri) async {
                launched.add(uri);
                return true;
              },
            ));

        await tapMap(tester, 'kharkiv');
        expect(launched, [externalMapUri(49.9935, 36.2304)]);
        expect(launched.single.queryParameters['query'], '49.9935,36.2304');

        await tapMap(tester, 'kyiv');
        expect(launched, hasLength(2));
        expect(launched.last, externalMapUri(50.4547, 30.5238));
        expect(launched.last.queryParameters['query'], '50.4547,30.5238');
        expect(launched.last.host, 'www.google.com');
        expect(find.text('Не вдалося відкрити карти.'), findsNothing);
      });
    }
  });

  group('invalid coordinates are never launched', () {
    final bad = <String, (double, double)>{
      'latitude NaN': (double.nan, 30.5),
      'longitude NaN': (50.4, double.nan),
      'latitude infinite': (double.infinity, 30.5),
      'longitude infinite': (50.4, double.negativeInfinity),
      'latitude > 90': (90.0001, 30.5),
      'latitude < -90': (-90.0001, 30.5),
      'longitude > 180': (50.4, 180.0001),
      'longitude < -180': (50.4, -180.0001),
    };
    for (final entry in bad.entries) {
      testWidgets(entry.key, (tester) async {
        var launches = 0;
        final opened = <LocationModel>[];
        await show(
            tester,
            screen(
              overrides: [
                created([
                  place('bad', 'Погані координати',
                      lat: entry.value.$1, lng: entry.value.$2),
                ]),
              ],
              onOpen: (context, l) => opened.add(l),
              launcher: (uri) async {
                launches++;
                return true;
              },
            ));

        await tapMap(tester, 'bad');

        expect(launches, 0, reason: 'the launcher is not called');
        expect(find.text('Не вдалося відкрити карти.'), findsOneWidget);
        expect(opened, isEmpty, reason: 'the card was not opened either');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the boundary values themselves are valid', (tester) async {
      final launched = <Uri>[];
      await show(
          tester,
          screen(
            overrides: [
              created([
                place('edge', 'Межа', lat: 90, lng: -180),
                place('zero', 'Нуль', lat: 0, lng: 0),
              ]),
            ],
            launcher: (uri) async {
              launched.add(uri);
              return true;
            },
          ));
      await tapMap(tester, 'edge');
      await tapMap(tester, 'zero');
      expect(launched, [externalMapUri(90, -180), externalMapUri(0, 0)]);
    });
  });

  group('the launcher fails', () {
    testWidgets('refused (false): a SnackBar, nothing else changes',
        (tester) async {
      final opened = <LocationModel>[];
      await show(
          tester,
          screen(
            overrides: [
              created([kyiv])
            ],
            onOpen: (context, l) => opened.add(l),
            launcher: (uri) async => false,
          ));

      await tapMap(tester, 'kyiv');

      expect(find.text('Не вдалося відкрити карти.'), findsOneWidget);
      expect(opened, isEmpty);
      expect(find.text('Київський парк'), findsOneWidget,
          reason: 'still on the list');
      expect(tester.takeException(), isNull);
    });

    testWidgets('throws asynchronously: a SnackBar, no crash', (tester) async {
      await show(
          tester,
          screen(
            overrides: [
              created([kyiv])
            ],
            launcher: (uri) async => throw Exception('no handler'),
          ));

      await tapMap(tester, 'kyiv');

      expect(find.text('Не вдалося відкрити карти.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('throws synchronously: a SnackBar, no crash', (tester) async {
      await show(
          tester,
          screen(
            overrides: [
              created([kyiv])
            ],
            launcher: (uri) => throw StateError('boom'),
          ));

      await tapMap(tester, 'kyiv');

      expect(find.text('Не вдалося відкрити карти.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the card and the action do not conflict', () {
    testWidgets('tapping the card opens that place, not the map',
        (tester) async {
      final opened = <LocationModel>[];
      var launches = 0;
      await show(
          tester,
          screen(
            overrides: [
              created([kyiv, kharkiv])
            ],
            onOpen: (context, l) => opened.add(l),
            launcher: (uri) async {
              launches++;
              return true;
            },
          ));

      await tester.tap(find.text('Харківський сад'));
      await tester.pumpAndSettle();

      expect(opened.map((l) => l.id), ['kharkiv']);
      expect(launches, 0);
    });

    testWidgets('tapping the action opens the map, not the place',
        (tester) async {
      final opened = <LocationModel>[];
      var launches = 0;
      await show(
          tester,
          screen(
            overrides: [
              created([kyiv, kharkiv])
            ],
            onOpen: (context, l) => opened.add(l),
            launcher: (uri) async {
              launches++;
              return true;
            },
          ));

      await tapMap(tester, 'kyiv');

      expect(launches, 1);
      expect(opened, isEmpty);
    });

    testWidgets('the action sits below the card: their areas never overlap',
        (tester) async {
      await show(
          tester,
          screen(overrides: [
            created([kyiv])
          ]));

      final card = tester.getRect(find.byType(LocationCard));
      final action = tester.getRect(mapButton('kyiv'));
      expect(action.top, greaterThanOrEqualTo(card.bottom));
    });

    testWidgets('the bookmark of a saved card still works on its own',
        (tester) async {
      final toggled = <String>[];
      var launches = 0;
      await show(
          tester,
          screen(
            tab: 1,
            overrides:
                savedAll([kyiv], notifier: (ids) => _ToggleSaved(ids, toggled)),
            launcher: (uri) async {
              launches++;
              return true;
            },
          ));

      await tester.tap(find.byIcon(Icons.bookmark));
      await tester.pump();

      expect(toggled, ['kyiv']);
      expect(launches, 0);
    });
  });

  group('narrow screens and large text', () {
    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        for (final tab in [0, 1, 2]) {
          testWidgets('tab $tab fits ${width}dp @ ${scale}x', (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final long = place('long',
                'Дуже довга назва локації для перевірки переносу тексту',
                status: 'pending');
            final overrides = switch (tab) {
              0 => [
                  created([long])
                ],
              1 => savedAll([long]),
              _ => [
                  visited([long])
                ],
            };
            await show(
                tester, screen(tab: tab, scale: scale, overrides: overrides));

            expect(tester.takeException(), isNull);
            final r = tester.getRect(mapButton('long'));
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(width));
            expect(r.width, greaterThanOrEqualTo(48));
            expect(r.height, greaterThanOrEqualTo(48));
            final card = tester.getRect(find.byType(LocationCard));
            expect(r.top, greaterThanOrEqualTo(card.bottom),
                reason: 'the action never covers the card');
          });
        }
      }
    }
  });

  // V1: the action row sat exactly half-way between two cards, so it could be
  // read as belonging to the next one. It now has room below it only.
  group('the action row is grouped with the card above it', () {
    for (final width in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        for (final tab in [0, 1, 2]) {
          testWidgets('tab $tab @ ${width}dp ${scale}x', (tester) async {
            // Tall enough to build both cards and their rows.
            tester.view.physicalSize = Size(width, 1600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final places = [
              place('a', 'Перше місце з довгою назвою', status: 'pending'),
              place('b', 'Друге місце з довгою назвою', status: 'pending'),
            ];
            final overrides = switch (tab) {
              0 => [created(places)],
              1 => savedAll(places),
              _ => [visited(places)],
            };
            await show(
                tester, screen(tab: tab, scale: scale, overrides: overrides));
            expect(tester.takeException(), isNull);

            // The outer rect (with the card's own margin) and the painted
            // surface of each card.
            Rect outer(int i) =>
                tester.getRect(find.byType(LocationCard).at(i));
            Rect surface(int i) => tester.getRect(find
                .descendant(
                    of: find.byType(LocationCard).at(i),
                    matching: find.byType(Material))
                .first);

            // The first card's row: the action and, if the tab has one, its
            // info text (which may wrap and be taller than the action).
            final action = tester.getRect(mapButton('a'));
            final infoKey = switch (tab) {
              0 => const Key('my_place_status_a'),
              2 => const Key('my_place_visit_a'),
              _ => null,
            };
            final info =
                infoKey == null ? null : tester.getRect(find.byKey(infoKey));
            var rowTop = action.top;
            var rowBottom = action.bottom;
            if (info != null) {
              if (info.top < rowTop) rowTop = info.top;
              if (info.bottom > rowBottom) rowBottom = info.bottom;
            }

            expect(action.size, const Size(48, 48),
                reason: 'the touch target is unchanged');
            expect(rowTop, moreOrLessEquals(outer(0).bottom, epsilon: 0.01),
                reason: 'nothing was added above the row');
            expect(outer(1).top - rowBottom,
                moreOrLessEquals(AppSpacing.lg, epsilon: 0.01),
                reason: '16 dp after the row, before the next card');

            final toCardAbove = rowTop - surface(0).bottom;
            final toCardBelow = surface(1).top - rowBottom;
            expect(toCardBelow - toCardAbove,
                moreOrLessEquals(AppSpacing.lg, epsilon: 0.01),
                reason: 'the row is visibly closer to its own card');
          });
        }
      }
    }
  });
}

class _ToggleSaved extends SavedPublicLocationsNotifier {
  _ToggleSaved(this.ids, this.toggled);
  final Set<String> ids;
  final List<String> toggled;

  @override
  Future<Set<String>> build() async => ids;

  @override
  Future<void> toggle(String locationId) async => toggled.add(locationId);
}
