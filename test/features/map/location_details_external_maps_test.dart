import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';
import 'package:flutter_application_1/features/map/providers/comments_provider.dart';
import 'package:flutter_application_1/features/map/providers/locations_provider.dart';
import 'package:flutter_application_1/features/map/providers/network_provider.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';

/// Location Details External Maps Phase 3A. Mirrors the harness already
/// established in `owner_location_management_test.dart` for pumping the
/// real, production `LocationDetailsContent` (not a stand-in) -- same
/// provider overrides for the same reasons (comments avoided since
/// `_CommentsContent` needs a live Supabase session; `locationDetailsProvider`
/// and `publicProfileProvider` stubbed with fixed data). The new
/// `launchExternalMapOverride` seam is exercised the same way
/// `updateLocationOverride`/`deleteLocationOverride` already are.
void main() {
  LocationModel location({
    String id = 'location-1',
    String userId = 'owner-1',
    String status = 'draft',
    double latitude = 50.4547,
    double longitude = 30.5238,
  }) =>
      LocationModel(
        id: id,
        userId: userId,
        title: 'Голосіївський парк',
        description: 'Опис локації',
        category: 'nature',
        latitude: latitude,
        longitude: longitude,
        createdAt: DateTime.utc(2026),
        status: status,
      );

  Widget subject({
    required LocationModel testLocation,
    String? currentUserId = 'someone-else',
    ExternalMapLauncher? launchExternalMapOverride,
    VoidCallback? onBuildRoute,
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
              onBuildRoute: onBuildRoute ?? () {},
              currentUserIdOverride: () => currentUserId,
              launchExternalMapOverride: launchExternalMapOverride,
            ),
          ),
        ),
      );

  testWidgets('A: "Відкрити" renders on canonical Location Details',
      (tester) async {
    await tester.pumpWidget(subject(testLocation: location()));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('details_open_external_action')), findsOneWidget);
    expect(find.text('Відкрити'), findsOneWidget);
  });

  testWidgets('B: the real coordinates are passed to the external-map launcher',
      (tester) async {
    Uri? received;
    final testLocation =
        location(latitude: 49.9935, longitude: 36.2304); // Kharkiv, distinct
    await tester.pumpWidget(subject(
      testLocation: testLocation,
      launchExternalMapOverride: (uri) async {
        received = uri;
        return true;
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('details_open_external_action')));
    await tester.pump();

    expect(received, isNotNull);
    expect(received!.queryParameters['query'],
        '${testLocation.latitude},${testLocation.longitude}');
    expect(received!.host, 'www.google.com');
  });

  testWidgets('C: the existing "Маршрут" action remains functional',
      (tester) async {
    var routeTapped = 0;
    await tester.pumpWidget(subject(
      testLocation: location(),
      onBuildRoute: () => routeTapped++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('details_route_action')));
    await tester.pump();

    expect(routeTapped, 1);
  });

  testWidgets('D: launch failure (returns false) is handled without a crash',
      (tester) async {
    await tester.pumpWidget(subject(
      testLocation: location(),
      launchExternalMapOverride: (uri) async => false,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('details_open_external_action')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Не вдалося відкрити карти.'), findsOneWidget);
  });

  testWidgets('D: launch failure (throws) is handled without a crash',
      (tester) async {
    await tester.pumpWidget(subject(
      testLocation: location(),
      launchExternalMapOverride: (uri) async => throw Exception('no handler'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('details_open_external_action')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Не вдалося відкрити карти.'), findsOneWidget);
  });

  testWidgets('E: non-owner details still render correctly', (tester) async {
    await tester.pumpWidget(subject(
      testLocation: location(status: 'approved'),
      currentUserId: 'someone-else',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Голосіївський парк'), findsOneWidget);
    expect(find.byKey(const Key('details_route_action')), findsOneWidget);
    expect(
        find.byKey(const Key('details_open_external_action')), findsOneWidget);
    expect(find.byKey(const Key('location_details_edit_action')), findsNothing);
    expect(
        find.byKey(const Key('location_details_delete_action')), findsNothing);
  });

  // F: owner draft/rejected Edit/Delete gating is unchanged, "Відкрити" is
  // present regardless of gating. Written as four independent tests
  // (rather than one loop over four sequential pumps) so each gets a
  // clean widget tree and test binding -- the same shared-binding-leak
  // hazard already documented in Search Phase 2B's own test suite
  // (`search_screen_phase2b_test.dart`).
  const ownerGatingByStatus = <String, bool>{
    'draft': true,
    'rejected': true,
    'pending': false,
    'approved': false,
  };
  for (final entry in ownerGatingByStatus.entries) {
    testWidgets(
        'F: owner + ${entry.key} -> Edit/Delete ${entry.value ? "shown" : "hidden"}, '
        '"Відкрити" always present', (tester) async {
      await tester.pumpWidget(subject(
        testLocation: location(status: entry.key),
        currentUserId: 'owner-1',
      ));
      await tester.pumpAndSettle();

      final editDeleteMatcher = entry.value ? findsOneWidget : findsNothing;
      expect(find.byKey(const Key('location_details_edit_action')),
          editDeleteMatcher);
      expect(find.byKey(const Key('location_details_delete_action')),
          editDeleteMatcher);
      expect(find.byKey(const Key('details_open_external_action')),
          findsOneWidget);
    });
  }

  group('G: responsive CTA layout (owner+draft, maximum content)', () {
    const widths = [320.0, 360.0, 390.0, 430.0];
    const scales = [1.0, 1.3, 1.5];
    for (final width in widths) {
      for (final scale in scales) {
        testWidgets(
            'CTA row fits ${width}dp @ ${scale}x, no overflow, all actions reachable',
            (tester) async {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
              ),
              child: subject(
                testLocation: location(status: 'draft'),
                currentUserId: 'owner-1',
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}dp, scale $scale');
          expect(find.byKey(const Key('details_route_action')), findsOneWidget);
          expect(find.byKey(const Key('details_open_external_action')),
              findsOneWidget);
          expect(find.byKey(const Key('location_details_edit_action')),
              findsOneWidget);
          expect(find.byKey(const Key('location_details_delete_action')),
              findsOneWidget);
        });
      }
    }
  });
}
