import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_categories.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/domain/location_query.dart';
import 'package:flutter_application_1/features/map/presentation/create_location_screen.dart'
    show locationTitleMaxLength, locationDescriptionMaxLength;
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';
import 'package:flutter_application_1/features/map/providers/comments_provider.dart';
import 'package:flutter_application_1/features/map/providers/locations_provider.dart';
import 'package:flutter_application_1/features/map/providers/network_provider.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';

/// Owner Location Management Phase 1. `LocationDetailsContent` reads
/// `Supabase.instance.client.auth.currentUser?.id` directly (same as the
/// pre-existing `_CommentsContent` delete-icon gate it sits beside), which
/// cannot be faked in a widget test without new Supabase-mocking
/// infrastructure this codebase doesn't have (see
/// `gps_logout_guard_test.dart`'s own comment on the identical
/// limitation). Two complementary strategies are used here instead:
///
/// 1. [canManageLocationOwnership] itself is public and pure, so the full
///    owner/status gating matrix (E01-E08) is proven directly, with full
///    honesty, as plain unit tests.
/// 2. The Edit/Delete *behavior* once the gate is open (E09-E18, D01-D07)
///    is proven through the real `LocationDetailsContent` widget, using
///    its `currentUserIdOverride`/`updateLocationOverride`/
///    `deleteLocationOverride` test-only seams -- the same kind of
///    override `CreateLocationScreen.createLocationOverride` already
///    established in this codebase.
void main() {
  LocationModel location({
    String id = 'location-1',
    String userId = 'owner-1',
    String status = 'draft',
    String category = 'nature',
    String title = 'Ліс біля Боярки',
    String? description = 'Опис локації',
  }) =>
      LocationModel(
        id: id,
        userId: userId,
        title: title,
        description: description,
        category: category,
        latitude: 50.45,
        longitude: 30.52,
        createdAt: DateTime.utc(2026),
        status: status,
      );

  group('E01-E08 canManageLocationOwnership (pure gating matrix)', () {
    test('E01 owner + draft: manageable', () {
      expect(
        canManageLocationOwnership(
          currentUserId: 'owner-1',
          location: location(status: 'draft'),
        ),
        isTrue,
      );
    });

    test('E02 owner + rejected: manageable', () {
      expect(
        canManageLocationOwnership(
          currentUserId: 'owner-1',
          location: location(status: 'rejected'),
        ),
        isTrue,
      );
    });

    test('E03 owner + pending: not manageable', () {
      expect(
        canManageLocationOwnership(
          currentUserId: 'owner-1',
          location: location(status: 'pending'),
        ),
        isFalse,
      );
    });

    test('E04 owner + approved: not manageable', () {
      expect(
        canManageLocationOwnership(
          currentUserId: 'owner-1',
          location: location(status: 'approved'),
        ),
        isFalse,
      );
    });

    test('E05 owner + archived: not manageable', () {
      expect(
        canManageLocationOwnership(
          currentUserId: 'owner-1',
          location: location(status: 'archived'),
        ),
        isFalse,
      );
    });

    test('E06 non-owner + draft: not manageable', () {
      expect(
        canManageLocationOwnership(
          currentUserId: 'someone-else',
          location: location(status: 'draft'),
        ),
        isFalse,
      );
    });

    test('E07 non-owner + rejected: not manageable', () {
      expect(
        canManageLocationOwnership(
          currentUserId: 'someone-else',
          location: location(status: 'rejected'),
        ),
        isFalse,
      );
    });

    test('E08 signed-out (null current user): not manageable', () {
      expect(
        canManageLocationOwnership(
          currentUserId: null,
          location: location(status: 'draft'),
        ),
        isFalse,
      );
    });
  });

  group('Edit/Delete widget behavior (production LocationDetailsContent)',
      () {
    Widget subject({
      required LocationModel testLocation,
      String? currentUserId = 'owner-1',
      UpdateLocationCall? updateLocationOverride,
      DeleteLocationCall? deleteLocationOverride,
    }) =>
        ProviderScope(
          overrides: [
            isOnlineProvider.overrideWithValue(true),
            locationDetailsProvider(testLocation.id).overrideWith(
              (ref) async => LocationDetailsData(
                location: testLocation,
                photoUrls: const [],
                tags: const [],
              ),
            ),
            // _CommentsContent (pre-existing, untouched) reads
            // Supabase.instance.client.auth.currentUser directly and
            // throws without a live session -- the same hard wall
            // gps_logout_guard_test.dart documents. Erroring this
            // provider routes comments.when() to its error branch
            // instead, so _CommentsContent is never built.
            commentsProvider(testLocation.id).overrideWith(
              (ref) async => throw StateError('comments avoided in test'),
            ),
            publicProfileProvider(testLocation.userId).overrideWith(
              (ref) async => PublicProfile(
                id: testLocation.userId,
                name: 'Travel Seed',
                xp: 0,
                level: 'Мандрівник',
                followersCount: 0,
                followingCount: 0,
                isFollowing: false,
                locations: const [],
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LocationDetailsContent(
                location: testLocation,
                onBuildRoute: () {},
                currentUserIdOverride: () => currentUserId,
                updateLocationOverride: updateLocationOverride,
                deleteLocationOverride: deleteLocationOverride,
              ),
            ),
          ),
        );

    testWidgets(
        'owner + draft shows Edit/Delete; non-owner does not (D07 too)',
        (tester) async {
      final draft = location(status: 'draft');
      await tester.pumpWidget(subject(testLocation: draft));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('location_details_edit_action')),
          findsOneWidget);
      expect(find.byKey(const Key('location_details_delete_action')),
          findsOneWidget);
    });

    testWidgets('pending owner shows neither Edit nor Delete', (tester) async {
      final pending = location(status: 'pending');
      await tester.pumpWidget(subject(testLocation: pending));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('location_details_edit_action')),
          findsNothing);
      expect(find.byKey(const Key('location_details_delete_action')),
          findsNothing);
    });

    testWidgets('non-owner never sees Edit/Delete on a draft location',
        (tester) async {
      final draft = location(status: 'draft');
      await tester.pumpWidget(
          subject(testLocation: draft, currentUserId: 'someone-else'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('location_details_edit_action')),
          findsNothing);
      expect(find.byKey(const Key('location_details_delete_action')),
          findsNothing);
    });

    testWidgets('E09/E10 Edit opens the dialog with existing fields populated',
        (tester) async {
      final draft =
          location(status: 'draft', title: 'Мій заголовок', category: 'cafe');
      await tester.pumpWidget(subject(testLocation: draft));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_details_edit_action')));
      await tester.pumpAndSettle();

      expect(find.text('Редагувати локацію'), findsOneWidget);
      // The same title/description also render in the details screen
      // underneath the dialog, so assert the dialog fields' own
      // controller values rather than a plain (ambiguous) text finder.
      final titleField = tester.widget<TextField>(
          find.byKey(const Key('location_edit_title_field')));
      final descriptionField = tester.widget<TextField>(
          find.byKey(const Key('location_edit_description_field')));
      expect(titleField.controller!.text, 'Мій заголовок');
      expect(descriptionField.controller!.text, 'Опис локації');
    });

    testWidgets('E11 empty title cannot submit', (tester) async {
      var callCount = 0;
      final draft = location(status: 'draft');
      await tester.pumpWidget(subject(
        testLocation: draft,
        updateLocationOverride: ({
          required locationId,
          required title,
          required description,
          required category,
        }) async {
          callCount++;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_details_edit_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('location_edit_title_field')), '');
      await tester.tap(find.byKey(const Key('location_edit_save_button')));
      await tester.pumpAndSettle();

      expect(callCount, 0);
      expect(find.text('Редагувати локацію'), findsOneWidget,
          reason: 'dialog must stay open when title is empty');
    });

    testWidgets(
        'E12/E13/E14 valid edit calls the repository path exactly once '
        'with the correct location id and fields', (tester) async {
      var callCount = 0;
      String? capturedId;
      String? capturedTitle;
      String? capturedDescription;
      String? capturedCategory;
      final draft = location(status: 'draft', id: 'loc-42');
      await tester.pumpWidget(subject(
        testLocation: draft,
        updateLocationOverride: ({
          required locationId,
          required title,
          required description,
          required category,
        }) async {
          callCount++;
          capturedId = locationId;
          capturedTitle = title;
          capturedDescription = description;
          capturedCategory = category;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_details_edit_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('location_edit_title_field')), 'Нова назва');
      await tester.enterText(
          find.byKey(const Key('location_edit_description_field')),
          'Новий опис');
      await tester.tap(find.byKey(const Key('location_edit_save_button')));
      await tester.pumpAndSettle();

      expect(callCount, 1);
      expect(capturedId, 'loc-42');
      expect(capturedTitle, 'Нова назва');
      expect(capturedDescription, 'Новий опис');
      expect(capturedCategory, isNotNull);
    });

    testWidgets('E15 no owner/status/moderation/XP/server fields are editable',
        (tester) async {
      final draft = location(status: 'draft');
      await tester.pumpWidget(subject(testLocation: draft));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_details_edit_action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('location_edit_title_field')),
          findsOneWidget);
      expect(find.byKey(const Key('location_edit_description_field')),
          findsOneWidget);
      expect(find.byKey(const Key('location_edit_category_field')),
          findsOneWidget);
      // Exactly these 3 fields -- no owner/status/moderation/rating/XP
      // controls exist anywhere in the dialog.
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('E16 successful edit refreshes production details',
        (tester) async {
      final draft = location(status: 'draft', title: 'Стара назва');
      await tester.pumpWidget(subject(
        testLocation: draft,
        updateLocationOverride: ({
          required locationId,
          required title,
          required description,
          required category,
        }) async {},
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_details_edit_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('location_edit_title_field')), 'Нова назва');
      await tester.tap(find.byKey(const Key('location_edit_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Редагувати локацію'), findsNothing,
          reason: 'dialog closes on success');
      expect(find.text('Зміни збережено'), findsOneWidget);
    });

    testWidgets(
        'E17 update failure shows a coherent error and does not close as '
        'if successful', (tester) async {
      final draft = location(status: 'draft');
      await tester.pumpWidget(subject(
        testLocation: draft,
        updateLocationOverride: ({
          required locationId,
          required title,
          required description,
          required category,
        }) async {
          throw StateError('network failure');
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_details_edit_action')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('location_edit_title_field')), 'Нова назва');
      await tester.tap(find.byKey(const Key('location_edit_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Редагувати локацію'), findsOneWidget,
          reason: 'dialog must not close/pop as if it had succeeded');
      expect(find.text('Не вдалося зберегти зміни.'), findsOneWidget);
    });

    testWidgets('E18 legacy general category cannot be newly selected',
        (tester) async {
      final draft = location(status: 'draft');
      await tester.pumpWidget(subject(testLocation: draft));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_details_edit_action')));
      await tester.pumpAndSettle();

      // Read the internal DropdownButton's own `items` list directly --
      // robust against the open menu's own internal
      // scrolling/virtualization, and a direct assertion on exactly what
      // the widget offers for selection rather than what happens to be
      // laid out on screen.
      final dropdown = tester.widget<DropdownButton<String>>(find.descendant(
        of: find.byKey(const Key('location_edit_category_field')),
        matching: find.byType(DropdownButton<String>),
      ));
      final offeredKeys =
          dropdown.items!.map((item) => item.value).toList(growable: false);
      expect(offeredKeys, isNot(contains(legacyGeneralCategory.key)));
      expect(offeredKeys, isNot(contains('all')));
      expect(
        offeredKeys,
        containsAll(referenceLocationCategories
            .where((c) => c.key != 'all')
            .map((c) => c.key)),
      );
    });

    testWidgets('title/description fields enforce Create\'s exact limits',
        (tester) async {
      final draft = location(status: 'draft');
      await tester.pumpWidget(subject(testLocation: draft));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('location_details_edit_action')));
      await tester.pumpAndSettle();

      final titleField = tester
          .widget<TextField>(find.byKey(const Key('location_edit_title_field')));
      final descriptionField = tester.widget<TextField>(
          find.byKey(const Key('location_edit_description_field')));
      expect(titleField.maxLength, locationTitleMaxLength);
      expect(descriptionField.maxLength, locationDescriptionMaxLength);
    });

    testWidgets('D01/D02 Delete opens confirmation; Cancel performs zero '
        'delete calls', (tester) async {
      var callCount = 0;
      final draft = location(status: 'draft');
      await tester.pumpWidget(subject(
        testLocation: draft,
        deleteLocationOverride: (id) async {
          callCount++;
        },
      ));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('location_details_delete_action')));
      await tester.pumpAndSettle();

      expect(find.text('Видалити локацію?'), findsOneWidget);
      expect(find.text('Цю дію неможливо скасувати.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('location_delete_cancel_button')));
      await tester.pumpAndSettle();

      expect(callCount, 0);
      expect(find.text('Видалити локацію?'), findsNothing);
    });

    testWidgets(
        'D03/D04 Confirm calls the repository delete path exactly once '
        'with the correct location id', (tester) async {
      var callCount = 0;
      String? capturedId;
      final draft = location(status: 'draft', id: 'loc-99');
      await tester.pumpWidget(subject(
        testLocation: draft,
        deleteLocationOverride: (id) async {
          callCount++;
          capturedId = id;
        },
      ));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('location_details_delete_action')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('location_delete_confirm_button')));
      await tester.pumpAndSettle();

      expect(callCount, 1);
      expect(capturedId, 'loc-99');
    });

    testWidgets('D05 successful deletion dismisses the details screen',
        (tester) async {
      final draft = location(status: 'draft');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isOnlineProvider.overrideWithValue(true),
            locationDetailsProvider(draft.id).overrideWith(
              (ref) async => LocationDetailsData(
                location: draft,
                photoUrls: const [],
                tags: const [],
              ),
            ),
            commentsProvider(draft.id).overrideWith(
              (ref) async => throw StateError('comments avoided in test'),
            ),
            publicProfileProvider(draft.userId).overrideWith(
              (ref) async => const PublicProfile(
                id: 'owner-1',
                name: 'Travel Seed',
                xp: 0,
                level: 'Мандрівник',
                followersCount: 0,
                followingCount: 0,
                isFollowing: false,
                locations: [],
              ),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          body: LocationDetailsContent(
                            location: draft,
                            onBuildRoute: () {},
                            currentUserIdOverride: () => 'owner-1',
                            deleteLocationOverride: (id) async {},
                          ),
                        ),
                      ),
                    ),
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

      await tester
          .tap(find.byKey(const Key('location_details_delete_action')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('location_delete_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('location_details_delete_action')),
          findsNothing,
          reason: 'details screen must have popped after successful delete');
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
        'D06 delete failure shows an error and does not falsely report '
        'success', (tester) async {
      final draft = location(status: 'draft');
      await tester.pumpWidget(subject(
        testLocation: draft,
        deleteLocationOverride: (id) async {
          throw StateError('network failure');
        },
      ));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('location_details_delete_action')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('location_delete_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.text('Не вдалося видалити локацію.'), findsOneWidget);
      expect(find.byKey(const Key('location_details_delete_action')),
          findsOneWidget,
          reason: 'details screen must not have been dismissed on failure');
    });

    testWidgets(
        'viewportLocationsProvider is invalidated exactly once after a '
        'successful delete', (tester) async {
      const query = MapViewportQuery(
        bounds: MapViewportBounds(
          minLatitude: 0,
          minLongitude: 0,
          maxLatitude: 1,
          maxLongitude: 1,
        ),
      );
      var evaluationCount = 0;
      final draft = location(status: 'draft');
      final container = ProviderContainer(overrides: [
        isOnlineProvider.overrideWithValue(true),
        locationDetailsProvider(draft.id).overrideWith(
          (ref) async => LocationDetailsData(
            location: draft,
            photoUrls: const [],
            tags: const [],
          ),
        ),
        commentsProvider(draft.id).overrideWith(
          (ref) async => throw StateError('comments avoided in test'),
        ),
        publicProfileProvider(draft.userId).overrideWith(
          (ref) async => const PublicProfile(
            id: 'owner-1',
            name: 'Travel Seed',
            xp: 0,
            level: 'Мандрівник',
            followersCount: 0,
            followingCount: 0,
            isFollowing: false,
            locations: [],
          ),
        ),
        viewportLocationsProvider.overrideWith((ref, query) async {
          evaluationCount++;
          return const MapLocationResult(items: [], totalCount: 0);
        }),
      ]);
      addTearDown(container.dispose);
      container.listen(viewportLocationsProvider(query), (_, __) {},
          fireImmediately: true);
      expect(evaluationCount, 1);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: LocationDetailsContent(
                location: draft,
                onBuildRoute: () {},
                currentUserIdOverride: () => 'owner-1',
                deleteLocationOverride: (id) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('location_details_delete_action')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('location_delete_confirm_button')));
      await tester.pumpAndSettle();

      expect(evaluationCount, 2,
          reason: 'exactly one invalidation-triggered re-evaluation, on '
              'top of the initial one');
    });
  });

  group('Responsive / accessibility (owner Edit dialog)', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.5]) {
        testWidgets('Edit dialog fits ${width}dp at ${scale}x, no overflow',
            (tester) async {
          final draft = LocationModel(
            id: 'location-1',
            userId: 'owner-1',
            title: 'Ліс біля Боярки',
            description: 'Опис локації',
            category: 'nature',
            latitude: 50.45,
            longitude: 30.52,
            createdAt: DateTime.utc(2026),
            status: 'draft',
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                isOnlineProvider.overrideWithValue(true),
                locationDetailsProvider(draft.id).overrideWith(
                  (ref) async => LocationDetailsData(
                    location: draft,
                    photoUrls: const [],
                    tags: const [],
                  ),
                ),
                commentsProvider(draft.id).overrideWith(
                  (ref) async => throw StateError('comments avoided in test'),
                ),
                publicProfileProvider(draft.userId).overrideWith(
                  (ref) async => const PublicProfile(
                    id: 'owner-1',
                    name: 'Travel Seed',
                    xp: 0,
                    level: 'Мандрівник',
                    followersCount: 0,
                    followingCount: 0,
                    isFollowing: false,
                    locations: [],
                  ),
                ),
              ],
              child: MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 760),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: LocationDetailsContent(
                      location: draft,
                      onBuildRoute: () {},
                      currentUserIdOverride: () => 'owner-1',
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester
              .tap(find.byKey(const Key('location_details_edit_action')));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('location_edit_save_button')),
              findsOneWidget);

          await tester.tap(find.byKey(const Key('location_edit_cancel_button')));
          await tester.pumpAndSettle();

          await tester
              .tap(find.byKey(const Key('location_details_delete_action')));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('location_delete_confirm_button')),
              findsOneWidget);
        });
      }
    }
  });
}
