import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/presentation/review_screen.dart';
import 'package:flutter_application_1/features/navigation/presentation/settings_screen.dart';

void main() {
  final location = LocationModel(
    id: 'location-1',
    userId: 'user-1',
    title: 'Дуже довга назва ботанічного саду для мобільного екрана',
    description: 'Опис',
    category: 'nature',
    latitude: 50.45,
    longitude: 30.52,
    createdAt: DateTime.utc(2026),
  );

  Widget reviewSubject({
    ReviewSubmitter? submitter,
    VoidCallback? onSuccess,
  }) =>
      ProviderScope(
        child: MaterialApp(
          home: ReviewScreen(
            location: location,
            submitter: submitter ?? (text, rating) async {},
            isOnlineOverride: true,
            onSuccess: onSuccess ?? () {},
          ),
        ),
      );

  testWidgets(
      'review has canonical summary, placeholder and localized category',
      (tester) async {
    await tester.pumpWidget(reviewSubject());

    expect(find.text('Новий відгук'), findsOneWidget);
    expect(find.text(location.title), findsOneWidget);
    expect(find.text('🌲 Природа'), findsOneWidget);
    expect(find.text('nature'), findsNothing);
    expect(find.byKey(const Key('location_image_placeholder')), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsNothing);
  });

  testWidgets('review summary uses the canonical image URL when available',
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
      imageUrl: 'https://example.com/review.jpg',
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ReviewScreen(
          location: withImage,
          submitter: (text, rating) async {},
          isOnlineOverride: true,
          onSuccess: () {},
        ),
      ),
    ));

    final image =
        tester.widget<Image>(find.byKey(const Key('location_real_image')));
    expect((image.image as NetworkImage).url, withImage.imageUrl);
  });

  testWidgets('rating interaction and canonical text validation work',
      (tester) async {
    await tester.pumpWidget(reviewSubject());

    await tester.tap(find.byKey(const Key('review_rating_4')));
    await tester.ensureVisible(find.byKey(const Key('review_submit_cta')));
    await tester.tap(find.byKey(const Key('review_submit_cta')));
    await tester.pump();

    expect(find.text('Напишіть кілька слів про це місце'), findsOneWidget);
    final stars = tester.widgetList<Icon>(find.byIcon(Icons.star_rounded));
    expect(stars.length, 4);
  });

  testWidgets(
      'submit loading prevents duplicates and preserves success behavior',
      (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    var success = false;
    await tester.pumpWidget(reviewSubject(
      submitter: (text, rating) {
        calls++;
        expect(text, 'Чудове місце');
        expect(rating, 5);
        return completer.future;
      },
      onSuccess: () => success = true,
    ));
    await tester.enterText(
        find.byKey(const Key('review_text_field')), 'Чудове місце');
    await tester.tap(find.byKey(const Key('review_rating_5')));
    await tester.ensureVisible(find.byKey(const Key('review_submit_cta')));
    await tester.tap(find.byKey(const Key('review_submit_cta')));
    await tester.pump();

    expect(find.byKey(const Key('review_submit_loading')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('review_submit_cta')),
            )
            .onPressed,
        isNull);
    expect(calls, 1);
    completer.complete();
    await tester.pump();
    expect(success, isTrue);
  });

  testWidgets('review error is user-safe and hides backend details',
      (tester) async {
    await tester.pumpWidget(reviewSubject(
      submitter: (_, __) => throw Exception('PostgrestException SQL detail'),
    ));
    await tester.enterText(find.byKey(const Key('review_text_field')), 'Текст');
    await tester.ensureVisible(find.byKey(const Key('review_submit_cta')));
    await tester.tap(find.byKey(const Key('review_submit_cta')));
    await tester.pump();

    expect(find.byKey(const Key('review_submit_error')), findsOneWidget);
    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('SQL'), findsNothing);
  });

  testWidgets('settings exposes only functional controls', (tester) async {
    bool? offline;
    var loggedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        offlineMode: false,
        onOfflineChanged: (value) => offline = value,
        onLogout: () => loggedOut = true,
      ),
    ));

    expect(find.text('Налаштування'), findsOneWidget);
    expect(find.text('ДАНІ ТА ОФЛАЙН'), findsOneWidget);
    expect(find.text('ПРО ЗАСТОСУНОК'), findsOneWidget);
    expect(find.text('ОБЛІКОВИЙ ЗАПИС'), findsOneWidget);
    expect(find.textContaining('2FA'), findsNothing);
    expect(find.textContaining('MB'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await tester.tap(find.byKey(const Key('settings_offline_toggle')));
    expect(offline, isTrue);
    await tester.tap(find.byKey(const Key('settings_logout')));
    expect(loggedOut, isTrue);
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      testWidgets(
          'review and settings fit ${width}dp at ${scale}x with keyboard',
          (tester) async {
        Widget media(Widget child, {double keyboard = 0}) => MediaQuery(
              data: MediaQueryData(
                size: Size(width, 760),
                textScaler: TextScaler.linear(scale),
                viewInsets: EdgeInsets.only(bottom: keyboard),
              ),
              child: SizedBox(width: width, child: child),
            );

        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: media(
              ReviewScreen(
                location: location,
                submitter: (text, rating) async {},
                isOnlineOverride: true,
                onSuccess: () {},
              ),
              keyboard: 280,
            ),
          ),
        ));
        expect(find.byKey(const Key('review_scroll')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(MaterialApp(
          home: media(SettingsPage(
            offlineMode: false,
            onOfflineChanged: (_) {},
            onLogout: () {},
          )),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
