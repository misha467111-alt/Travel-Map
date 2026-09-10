import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_screen.dart';
import 'package:flutter_application_1/features/profile/presentation/saved_screen.dart';

void main() {
  const profile = UserProfile(
    id: 'user-1',
    name: 'Надзвичайно довге ім’я українського мандрівника',
    email: 'long.traveler.username@example.com',
    level: 'Дослідник',
    xp: 320,
    locationsCount: 12,
  );
  final location = LocationModel(
    id: 'saved-1',
    userId: 'user-1',
    title: 'Ботанічний сад',
    description: 'Тихе зелене місце для прогулянок.',
    category: 'nature',
    latitude: 50.45,
    longitude: 30.52,
    createdAt: DateTime.utc(2026),
  );

  Widget profileSubject({
    ValueChanged<String>? onDestination,
    VoidCallback? onLogout,
  }) =>
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Профіль')),
            body: ProfileContent(
              profile: profile,
              savedCountOverride: 4,
              achievementProgressOverride: const (unlocked: 3, total: 8),
              inviteBalanceOverride: 2,
              onDestination: onDestination,
              onLogout: onLogout,
            ),
          ),
        ),
      );

  testWidgets('profile shows canonical identity, XP, stats and progression',
      (tester) async {
    await tester.pumpWidget(profileSubject());

    expect(find.text(profile.name), findsOneWidget);
    expect(find.text(profile.email), findsOneWidget);
    expect(find.byKey(const Key('profile_avatar_fallback')), findsOneWidget);
    expect(find.text(profile.level), findsOneWidget);
    expect(find.text('320 XP'), findsOneWidget);
    expect(find.text('320 / 700 XP'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('profile_action_invites')),
      180,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('3 із 8'), findsOneWidget);
    expect(find.text('Доступно: 2'), findsOneWidget);
  });

  testWidgets('every visible profile destination and logout are wired',
      (tester) async {
    final opened = <String>[];
    var loggedOut = false;
    await tester.pumpWidget(profileSubject(
      onDestination: opened.add,
      onLogout: () => loggedOut = true,
    ));

    for (final destination in [
      'friends',
      'chat',
      'saved',
      'routes',
      'achievements',
      'invites',
      'top',
      'settings',
    ]) {
      final finder = find.byKey(Key('profile_action_$destination'));
      await tester.scrollUntilVisible(
        finder,
        160,
        scrollable: find.byType(Scrollable),
      );
      final centerY = tester.getCenter(finder).dy;
      if (centerY > 560) {
        await tester.drag(find.byType(Scrollable), const Offset(0, -70));
        await tester.pump();
      } else if (centerY < 80) {
        await tester.drag(find.byType(Scrollable), const Offset(0, 70));
        await tester.pump();
      }
      await tester.tap(finder);
      expect(opened, contains(destination));
      final tile = tester.widget<ListTile>(finder);
      expect(tile.trailing, isA<Icon>());
    }

    final logout = find.byKey(const Key('profile_action_logout'));
    await tester.scrollUntilVisible(
      logout,
      160,
      scrollable: find.byType(Scrollable),
    );
    if (tester.getCenter(logout).dy > 560) {
      await tester.drag(find.byType(Scrollable), const Offset(0, -70));
      await tester.pump();
    }
    await tester.tap(logout);
    expect(loggedOut, isTrue);
    expect(tester.widget<ListTile>(logout).trailing, isNull);
  });

  testWidgets('saved page shows canonical compact card and wires actions',
      (tester) async {
    LocationModel? opened;
    LocationModel? removed;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: SavedPage(
          locations: AsyncData([location]),
          onUnsave: (value) => removed = value,
          onOpen: (value) => opened = value,
        ),
      ),
    ));

    expect(find.text('Закладки'), findsOneWidget);
    expect(find.byKey(const Key('location_image_placeholder')), findsOneWidget);
    expect(find.text('🌲 Природа'), findsOneWidget);
    expect(find.text('nature'), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.text(location.title));
    expect(opened?.id, location.id);
    await tester.tap(find.byIcon(Icons.bookmark));
    expect(removed?.id, location.id);
  });

  testWidgets('saved empty and loading states are explicit and functional',
      (tester) async {
    var discovered = false;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: SavedPage(
          locations: const AsyncData([]),
          onUnsave: (_) {},
          onOpen: (_) {},
          onDiscover: () => discovered = true,
        ),
      ),
    ));
    expect(find.text('Закладок поки немає'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved_discover_cta')));
    expect(discovered, isTrue);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: SavedPage(
          locations: const AsyncLoading(),
          onUnsave: (_) {},
          onOpen: (_) {},
        ),
      ),
    ));
    expect(find.byKey(const Key('saved_loading_state')), findsOneWidget);
  });

  testWidgets('saved card uses the canonical image URL when it exists',
      (tester) async {
    final withImage = LocationModel(
      id: location.id,
      userId: location.userId,
      title: location.title,
      description: location.description,
      category: location.category,
      latitude: location.latitude,
      longitude: location.longitude,
      createdAt: location.createdAt,
      imageUrl: 'https://example.com/saved.jpg',
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: SavedPage(
          locations: AsyncData([withImage]),
          onUnsave: (_) {},
          onOpen: (_) {},
        ),
      ),
    ));

    final image = tester.widget<Image>(
      find.byKey(const Key('location_real_image')),
    );
    expect((image.image as NetworkImage).url, withImage.imageUrl);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets('profile and saved fit ${width}dp at ${scale}x',
          (tester) async {
        Widget shell(Widget child) => MediaQuery(
              data: MediaQueryData(
                size: Size(width, 760),
                textScaler: TextScaler.linear(scale),
              ),
              child: SizedBox(width: width, child: child),
            );

        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: shell(ProfileContent(
              profile: profile,
              savedCountOverride: 4,
              achievementProgressOverride: const (unlocked: 3, total: 8),
              inviteBalanceOverride: 2,
              onDestination: (_) {},
              onLogout: () {},
            )),
          ),
        ));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: shell(SavedPage(
              locations: AsyncData([location]),
              onUnsave: (_) {},
              onOpen: (_) {},
            )),
          ),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
