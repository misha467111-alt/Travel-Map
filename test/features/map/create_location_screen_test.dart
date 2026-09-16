import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/features/map/domain/location_categories.dart';
import 'package:flutter_application_1/features/map/domain/location_metadata.dart';
import 'package:flutter_application_1/features/map/domain/location_query.dart';
import 'package:flutter_application_1/features/map/presentation/create_location_screen.dart';
import 'package:flutter_application_1/features/map/providers/locations_provider.dart';

/// UI/UX Phase 2 + Phase 2.2B (Create Location UX v2): `CreateLocationScreen`
/// replaces the old `_AddLocationDialog`, and Phase 2.2B adds the compact
/// category/amenities/opening-hours selectors, the address field, and
/// "Змінити" (re-pick the map point without losing any other entered
/// field). Every test here uses the widget's `createLocationOverride`
/// seam instead of touching `locationsRepositoryProvider`/a real
/// `SupabaseClient` (constructing one spins up a real isolate and
/// background HTTP/auth/realtime clients -- unsafe and unnecessary for a
/// presentation-layer test). The override matches
/// `LocationsRepository.createLocation`'s exact signature, so it proves
/// the screen calls the real contract correctly without needing a live
/// backend.
void main() {
  const point = LatLng(50.12345, 30.54321);

  Future<void> pump(
    WidgetTester tester, {
    CreateLocationCall? createLocationOverride,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: CreateLocationScreen(
            point: point,
            createLocationOverride: createLocationOverride,
          ),
        ),
      ),
    );
    // The title field is autofocus: true, which schedules its own
    // scroll-into-view a frame or two after the initial build. Settling
    // that here, before any test-driven scroll, avoids it firing later
    // (mid pumpAndSettle, after a deliberate scroll to the submit button)
    // and yanking the view back up to the title field.
    await tester.pumpAndSettle();
  }

  // The form is taller than the default 800x600 test viewport, so a plain
  // tester.tap() on the submit button/lower fields misses them -- scroll
  // them into view first, exactly as a real user's own scroll would
  // before their tap could land.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    // A just-completed enterText on the still-focused title field can
    // itself schedule a delayed "keep the focused field visible" scroll,
    // same as autofocus does on first build -- settle that first so it
    // can't fire later and undo our own scroll to the target below.
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(finder));
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  Future<void> openSheet(WidgetTester tester, Key fieldKey) async {
    await tapVisible(tester, find.byKey(fieldKey));
    await tester.pumpAndSettle();
  }

  testWidgets('renders with header and every compact form section',
      (tester) async {
    await pump(tester);
    expect(find.text('Нова локація'), findsOneWidget);
    expect(
        find.byKey(const Key('create_location_title_field')), findsOneWidget);
    expect(find.byKey(const Key('create_location_description_field')),
        findsOneWidget);
    expect(find.byKey(const Key('create_location_category_field')),
        findsOneWidget);
    expect(find.byKey(const Key('create_location_amenities_field')),
        findsOneWidget);
    expect(
        find.byKey(const Key('create_location_hours_field')), findsOneWidget);
    expect(find.byKey(const Key('create_location_coordinates_card')),
        findsOneWidget);
    expect(find.byKey(const Key('create_location_change_location_button')),
        findsOneWidget);
    expect(
        find.byKey(const Key('create_location_address_field')), findsOneWidget);
    expect(
        find.byKey(const Key('create_location_submit_button')), findsOneWidget);
    // The full category grid is no longer permanently on the main form --
    // it only exists inside the bottom sheet the compact row opens.
    expect(
        find.byKey(const Key('create_location_category_grid')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty title blocks submission and never calls createLocation',
      (tester) async {
    var callCount = 0;
    await pump(
      tester,
      createLocationOverride: ({
        required title,
        required description,
        required latitude,
        required longitude,
        required category,
        imageBytes,
        address,
        amenities,
        openingHours,
        timezone,
        requestId,
      }) async {
        callCount++;
      },
    );

    await tapVisible(
        tester, find.byKey(const Key('create_location_submit_button')));
    await tester.pump();

    expect(callCount, 0);
    expect(find.text('Введіть назву місця.'), findsOneWidget);
  });

  testWidgets('description field accepts and shows entered text',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byKey(const Key('create_location_description_field')),
        'Опис локації');
    await tester.pump();
    expect(find.text('Опис локації'), findsOneWidget);
  });

  group('category (compact selector)', () {
    testWidgets(
        'opening the selector shows every canonical real category, never '
        'all or general', (tester) async {
      await pump(tester);
      await openSheet(tester, const Key('create_location_category_field'));

      for (final category
          in referenceLocationCategories.where((c) => c.key != 'all')) {
        expect(find.byKey(Key('create_location_category_${category.key}')),
            findsOneWidget);
      }
      expect(
          find.byKey(const Key('create_location_category_all')), findsNothing);
      expect(find.byKey(const Key('create_location_category_general')),
          findsNothing);
    });

    testWidgets('default submitted category is real, never all or general',
        (tester) async {
      String? submittedCategory;
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submittedCategory = category;
        },
      );
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submittedCategory, isNotNull);
      expect(submittedCategory, isNot('all'));
      expect(submittedCategory, isNot('general'));
    });

    testWidgets('selecting a category updates the compact row and submission',
        (tester) async {
      String? submittedCategory;
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submittedCategory = category;
        },
      );
      await openSheet(tester, const Key('create_location_category_field'));
      await tapVisible(
          tester, find.byKey(const Key('create_location_category_historic')));
      await tester.pumpAndSettle();

      final historic =
          referenceLocationCategories.firstWhere((c) => c.key == 'historic');
      expect(find.text(historic.label), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submittedCategory, 'historic');
    });
  });

  group('amenities (Phase 2.2B)', () {
    testWidgets('nothing selected submits amenities as null', (tester) async {
      List<String>? submitted = ['not called'];
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submitted = amenities;
        },
      );
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submitted, isNull);
    });

    testWidgets('all six canonical amenities are offered and map correctly',
        (tester) async {
      await pump(tester);
      await openSheet(tester, const Key('create_location_amenities_field'));

      const expectedLabels = {
        'parking': 'Паркінг',
        'wifi': 'Wi-Fi',
        'toilet': 'Туалет',
        'accessibility': 'Доступність',
        'pets': 'З тваринами',
        'food': 'Їжа',
      };
      expect(locationAmenityKeys.toSet(), expectedLabels.keys.toSet());
      for (final key in locationAmenityKeys) {
        expect(find.byKey(Key('create_location_amenity_$key')), findsOneWidget);
        expect(find.text(expectedLabels[key]!), findsOneWidget);
      }
    });

    testWidgets('selecting amenities forwards exactly the selected keys',
        (tester) async {
      List<String>? submitted;
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submitted = amenities;
        },
      );
      await openSheet(tester, const Key('create_location_amenities_field'));
      await tester.tap(find.byKey(const Key('create_location_amenity_wifi')));
      await tester.tap(find.byKey(const Key('create_location_amenity_pets')));
      await tester.pump();
      await tapVisible(
          tester, find.byKey(const Key('create_location_amenities_done')));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submitted, unorderedEquals(['wifi', 'pets']));
    });
  });

  group('opening hours (Phase 2.2B)', () {
    testWidgets('default is unspecified -> null hours and null timezone',
        (tester) async {
      Map<String, dynamic>? submittedHours = {'not': 'called'};
      String? submittedTz = 'not called';
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submittedHours = openingHours;
          submittedTz = timezone;
        },
      );
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submittedHours, isNull);
      expect(submittedTz, isNull);
    });

    testWidgets(
        '24/7 selection serializes every day as open and sets '
        'Europe/Kyiv', (tester) async {
      Map<String, dynamic>? submittedHours;
      String? submittedTz;
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submittedHours = openingHours;
          submittedTz = timezone;
        },
      );
      await openSheet(tester, const Key('create_location_hours_field'));
      await tapVisible(
          tester, find.byKey(const Key('create_location_hours_always')));
      await tapVisible(
          tester, find.byKey(const Key('create_location_hours_done')));
      await tester.pumpAndSettle();

      expect(find.text('Цілодобово'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submittedHours, alwaysOpenSchedule());
      expect(submittedTz, defaultLocationTimezone);
    });

    testWidgets(
        'scheduled selection serializes closed days as [] and keeps every '
        'day key present', (tester) async {
      Map<String, dynamic>? submittedHours;
      String? submittedTz;
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submittedHours = openingHours;
          submittedTz = timezone;
        },
      );
      await openSheet(tester, const Key('create_location_hours_field'));
      await tapVisible(
          tester, find.byKey(const Key('create_location_hours_scheduled')));
      await tester.pumpAndSettle();
      // Default open-day selection is Mon-Fri (see defaultWeekdaySchedule);
      // Sat/Sun start unselected -- exercise the toggle explicitly on one
      // weekday too, to prove per-day toggling (not just the default)
      // reaches the payload.
      await tester.tap(find.byKey(const Key('create_location_hours_day_mon')));
      await tester.pump();
      await tapVisible(
          tester, find.byKey(const Key('create_location_hours_done')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submittedTz, defaultLocationTimezone);
      final hours = submittedHours!;
      expect(hours.keys.toSet(), openingHoursDayKeys.toSet());
      expect(hours['mon'], closedDaySchedule,
          reason: 'toggled off in the sheet above');
      expect(hours['sat'], closedDaySchedule);
      expect(hours['sun'], closedDaySchedule);
      expect(hours['tue'], isNotEmpty);
      expect((hours['tue'] as List).single['open'], isA<String>());
      expect((hours['tue'] as List).single['close'], isA<String>());
    });
  });

  group('address (Phase 2.2B)', () {
    testWidgets('empty address submits null', (tester) async {
      String? submitted = 'not called';
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submitted = address;
        },
      );
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submitted, isNull);
    });

    testWidgets('whitespace-only address submits null', (tester) async {
      String? submitted = 'not called';
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submitted = address;
        },
      );
      await tester.enterText(
          find.byKey(const Key('create_location_address_field')), '   ');
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submitted, isNull);
    });

    testWidgets('entered address is forwarded trimmed', (tester) async {
      String? submitted;
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          submitted = address;
        },
      );
      await tester.enterText(
          find.byKey(const Key('create_location_address_field')),
          '  вул. Хрещатик, 1  ');
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(submitted, 'вул. Хрещатик, 1');
    });
  });

  group('location point (Phase 2.2B)', () {
    testWidgets('coordinates card shows the supplied LatLng', (tester) async {
      await pump(tester);
      expect(find.text('50.12345, 30.54321'), findsOneWidget);
    });

    testWidgets('confirmed coordinates are submitted unchanged',
        (tester) async {
      double? capturedLatitude;
      double? capturedLongitude;
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          address,
          amenities,
          openingHours,
          timezone,
          requestId,
        }) async {
          capturedLatitude = latitude;
          capturedLongitude = longitude;
        },
      );
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(capturedLatitude, point.latitude);
      expect(capturedLongitude, point.longitude);
    });

    testWidgets(
        '"Змінити" re-picks the point on the map and preserves every '
        'other entered field', (tester) async {
      await pump(tester);
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')),
          'Мій заголовок');
      await tester.enterText(
          find.byKey(const Key('create_location_description_field')),
          'Мій опис');
      await tester.enterText(
          find.byKey(const Key('create_location_address_field')), 'Моя адреса');

      await tapVisible(tester,
          find.byKey(const Key('create_location_change_location_button')));
      await tester.pumpAndSettle();

      // Now inside the pushed LocationPickScreen -- select a new point and
      // confirm exactly the way a real user would.
      final map = tester.widget<GoogleMap>(find.descendant(
        of: find.byKey(const Key('location_pick_map')),
        matching: find.byType(GoogleMap),
      ));
      map.onTap!(const LatLng(51.0, 31.0));
      await tester.pump();
      await tester.tap(find.byKey(const Key('location_pick_confirm_button')));
      await tester.pumpAndSettle();

      // Back on the form: new coordinates, every other field intact.
      expect(find.text('51.00000, 31.00000'), findsOneWidget);
      expect(find.text('Мій заголовок'), findsOneWidget);
      expect(find.text('Мій опис'), findsOneWidget);
      expect(find.text('Моя адреса'), findsOneWidget);
    });

    testWidgets('"Змінити" cancel leaves the original point untouched',
        (tester) async {
      await pump(tester);
      await tapVisible(tester,
          find.byKey(const Key('create_location_change_location_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_pick_cancel_button')));
      await tester.pumpAndSettle();

      expect(find.text('50.12345, 30.54321'), findsOneWidget);
    });
  });

  testWidgets(
      'submit shows a loading state, disables the button, and a rapid '
      'double tap sends only one request', (tester) async {
    var callCount = 0;
    final completer = Completer<void>();
    await pump(
      tester,
      createLocationOverride: ({
        required title,
        required description,
        required latitude,
        required longitude,
        required category,
        imageBytes,
        address,
        amenities,
        openingHours,
        timezone,
        requestId,
      }) async {
        callCount++;
        await completer.future;
      },
    );
    await tester.enterText(
        find.byKey(const Key('create_location_title_field')), 'Test');

    await tapVisible(
        tester, find.byKey(const Key('create_location_submit_button')));
    await tester.pump();
    // Still in flight -- a rapid second tap must be a no-op.
    await tester.tap(find.byKey(const Key('create_location_submit_button')));
    await tester.pump();

    expect(callCount, 1,
        reason: 'rapid double tap must result in exactly one request');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final submitButton = tester.widget<FilledButton>(
        find.byKey(const Key('create_location_submit_button')));
    expect(submitButton.onPressed, isNull,
        reason: 'submit must be disabled while a request is in flight');

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('failure re-enables submit and preserves entered form state',
      (tester) async {
    await pump(
      tester,
      createLocationOverride: ({
        required title,
        required description,
        required latitude,
        required longitude,
        required category,
        imageBytes,
        address,
        amenities,
        openingHours,
        timezone,
        requestId,
      }) async {
        throw StateError('network failure');
      },
    );
    await tester.enterText(
        find.byKey(const Key('create_location_title_field')), 'Мій заголовок');
    await tester.enterText(
        find.byKey(const Key('create_location_description_field')), 'Мій опис');
    await tapVisible(
        tester, find.byKey(const Key('create_location_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Не вдалося зберегти локацію. Спробуйте ще раз.'),
        findsOneWidget);
    expect(find.text('Мій заголовок'), findsOneWidget);
    expect(find.text('Мій опис'), findsOneWidget);
    final submitButton = tester.widget<FilledButton>(
        find.byKey(const Key('create_location_submit_button')));
    expect(submitButton.onPressed, isNotNull,
        reason: 'submit must be re-enabled after a failure');
  });

  testWidgets(
      'successful create pops the screen with true so the caller can '
      'invalidate/show the pending-review message', (tester) async {
    bool? poppedWith;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    poppedWith = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => CreateLocationScreen(
                          point: point,
                          createLocationOverride: ({
                            required title,
                            required description,
                            required latitude,
                            required longitude,
                            required category,
                            imageBytes,
                            address,
                            amenities,
                            openingHours,
                            timezone,
                            requestId,
                          }) async {},
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('create_location_title_field')), 'Test');
    await tapVisible(
        tester, find.byKey(const Key('create_location_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create_location_title_field')), findsNothing,
        reason: 'screen must have popped after a successful create');
    expect(poppedWith, isTrue);
  });

  testWidgets(
      'viewportLocationsProvider is invalidated exactly once on success',
      (tester) async {
    const query = MapViewportQuery(
      bounds: MapViewportBounds(
        minLatitude: 0,
        minLongitude: 0,
        maxLatitude: 1,
        maxLongitude: 1,
      ),
    );
    var evaluationCount = 0;
    final container = ProviderContainer(overrides: [
      viewportLocationsProvider.overrideWith((ref, query) async {
        evaluationCount++;
        return const MapLocationResult(items: [], totalCount: 0);
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(viewportLocationsProvider(query), (_, __) {},
        fireImmediately: true);
    expect(evaluationCount, 1,
        reason: 'the override runs synchronously up to its first await, '
            'which fireImmediately triggers right away');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: CreateLocationScreen(
            point: point,
            createLocationOverride: ({
              required title,
              required description,
              required latitude,
              required longitude,
              required category,
              imageBytes,
              address,
              amenities,
              openingHours,
              timezone,
              requestId,
            }) async {},
          ),
        ),
      ),
    );
    // Settle the autofocus-driven scroll-into-view before scrolling
    // elsewhere ourselves -- see the `pump` helper's comment above.
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('create_location_title_field')), 'Test');
    await tapVisible(
        tester, find.byKey(const Key('create_location_submit_button')));
    await tester.pumpAndSettle();

    expect(evaluationCount, 2,
        reason: 'exactly one invalidation-triggered re-evaluation, '
            'on top of the initial one');
  });

  // Mirrors the responsive-fit pattern already used elsewhere in this
  // suite (e.g. batch8_review_settings_test.dart): a real SizedBox width
  // constraint plus MediaQuery data for scale/keyboard, checked purely
  // for absence of overflow -- not a tap interaction, which the
  // MediaQuery-only override doesn't actually resize the test window for.
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets(
          'fits ${width}dp at ${scale}x with keyboard open, no overflow',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 760),
                  textScaler: TextScaler.linear(scale),
                  viewInsets: const EdgeInsets.only(bottom: 280),
                ),
                child: SizedBox(
                  width: width,
                  child: CreateLocationScreen(point: point),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('create_location_submit_button')),
            findsOneWidget);
      });
    }
  }

  group('Phase 2.2A1', () {
    testWidgets('title field enforces the 100-character limit', (
      tester,
    ) async {
      await pump(tester);
      final titleField = tester.widget<TextField>(
        find.byKey(const Key('create_location_title_field')),
      );
      expect(titleField.maxLength, locationTitleMaxLength);

      await tester.enterText(
        find.byKey(const Key('create_location_title_field')),
        'a' * 250,
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              widget.controller.text.length == locationTitleMaxLength,
        ),
        findsOneWidget,
        reason: 'Flutter\'s own maxLength enforcement must clip input at '
            'exactly $locationTitleMaxLength characters',
      );
    });

    testWidgets('description field enforces the 1500-character limit', (
      tester,
    ) async {
      await pump(tester);
      final descriptionField = tester.widget<TextField>(
        find.byKey(const Key('create_location_description_field')),
      );
      expect(descriptionField.maxLength, locationDescriptionMaxLength);

      await tester.enterText(
        find.byKey(const Key('create_location_description_field')),
        'a' * 2000,
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              widget.controller.text.length == locationDescriptionMaxLength,
        ),
        findsOneWidget,
        reason: 'Flutter\'s own maxLength enforcement must clip input at '
            'exactly $locationDescriptionMaxLength characters',
      );
    });

    testWidgets(
        'old required call behavior remains compatible: leaving every '
        'Phase 2.2B selector at its default omits all four optional '
        'metadata params exactly like before that UI existed', (tester) async {
      String? capturedAddress = 'not called';
      List<String>? capturedAmenities = ['not called'];
      Map<String, dynamic>? capturedOpeningHours = {'not': 'called'};
      String? capturedTimezone = 'not called';
      await pump(
        tester,
        createLocationOverride: ({
          required title,
          required description,
          required latitude,
          required longitude,
          required category,
          imageBytes,
          requestId,
          address,
          amenities,
          openingHours,
          timezone,
        }) async {
          capturedAddress = address;
          capturedAmenities = amenities;
          capturedOpeningHours = openingHours;
          capturedTimezone = timezone;
        },
      );
      await tester.enterText(
          find.byKey(const Key('create_location_title_field')), 'Test');
      await tapVisible(
          tester, find.byKey(const Key('create_location_submit_button')));
      await tester.pumpAndSettle();

      expect(capturedAddress, isNull);
      expect(capturedAmenities, isNull);
      expect(capturedOpeningHours, isNull);
      expect(capturedTimezone, isNull);
    });
  });
}
