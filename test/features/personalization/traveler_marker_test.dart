import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/presentation/clustered_location_map.dart';
import 'package:flutter_application_1/features/navigation/presentation/main_navigation_screen.dart'
    show openSecondarySection;
import 'package:flutter_application_1/features/personalization/personalization_screen.dart';
import 'package:flutter_application_1/features/personalization/traveler_marker.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_screen.dart';

Future<List<int>> _pixels(TravelerMarkerStyle style, Color color) async {
  final recorder = ui.PictureRecorder();
  paintTravelerMarker(Canvas(recorder), 48, style: style, color: color);
  final image = await recorder.endRecording().toImage(48, 48);
  final data = await image.toByteData();
  return data!.buffer.asUint8List();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('settings and defaults', () {
    test('S01 the default is the classic pink dot (the existing marker)', () {
      expect(TravelerMarkerSettings.defaults.style, TravelerMarkerStyle.dot);
      expect(TravelerMarkerSettings.defaults.color, TravelerMarkerColor.pink);
      expect(TravelerMarkerColor.pink.color, const Color(0xFFEC407A));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(travelerMarkerProvider),
          TravelerMarkerSettings.defaults);
    });

    test('S02 three styles and six colours exist', () {
      expect(TravelerMarkerStyle.values.map((s) => s.name),
          ['dot', 'arrow', 'traveler']);
      expect(TravelerMarkerColor.values.map((c) => c.name),
          ['gold', 'pink', 'blue', 'green', 'purple', 'orange']);
      expect(TravelerMarkerColor.values.map((c) => c.color).toSet().length, 6);
    });

    test('S03 equality and cache key', () {
      expect(const TravelerMarkerSettings(), const TravelerMarkerSettings());
      expect(
          const TravelerMarkerSettings(style: TravelerMarkerStyle.arrow)
              .cacheKey,
          'arrow_pink');
    });
  });

  group('persistence', () {
    test('P01 a choice survives a restart (new container)', () async {
      final first = ProviderContainer();
      first.read(travelerMarkerProvider);
      await first.read(travelerMarkerProvider.notifier).select(
          style: TravelerMarkerStyle.traveler, color: TravelerMarkerColor.blue);
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.read(travelerMarkerProvider);
      await pumpEventQueue();
      expect(
          second.read(travelerMarkerProvider),
          const TravelerMarkerSettings(
              style: TravelerMarkerStyle.traveler,
              color: TravelerMarkerColor.blue));
    });

    test('P02 unknown or corrupt stored values fall back to the defaults',
        () async {
      SharedPreferences.setMockInitialValues({
        TravelerMarkerStore.styleKey: 'hologram',
        TravelerMarkerStore.colorKey: 'teal',
      });
      expect(await TravelerMarkerStore.load(), TravelerMarkerSettings.defaults);
      SharedPreferences.setMockInitialValues({
        TravelerMarkerStore.styleKey: 'arrow',
      });
      final partial = await TravelerMarkerStore.load();
      expect(partial.style, TravelerMarkerStyle.arrow);
      expect(partial.color, TravelerMarkerColor.pink);
    });

    test('P03 a choice made before the stored value loads is kept', () async {
      SharedPreferences.setMockInitialValues({
        TravelerMarkerStore.colorKey: 'green',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(travelerMarkerProvider);
      await container
          .read(travelerMarkerProvider.notifier)
          .select(color: TravelerMarkerColor.orange);
      await pumpEventQueue();
      expect(container.read(travelerMarkerProvider).color,
          TravelerMarkerColor.orange);
    });
  });

  group('rendering', () {
    testWidgets('R01 every style x colour paints, and each look is distinct',
        (tester) async {
      final seen = <String, List<int>>{};
      await tester.runAsync(() async {
        for (final style in TravelerMarkerStyle.values) {
          for (final color in TravelerMarkerColor.values) {
            seen['${style.name}_${color.name}'] =
                await _pixels(style, color.color);
          }
        }
      });
      expect(seen.length, 18);
      final distinct = seen.values.map((p) => Object.hashAll(p)).toSet();
      expect(distinct.length, 18, reason: 'all 18 looks differ');
    });

    testWidgets('R02 bitmaps are cached: one render per combination',
        (tester) async {
      TravelerMarkerIcons.clearForTest();
      await tester.runAsync(() async {
        const a = TravelerMarkerSettings();
        final first = await TravelerMarkerIcons.iconFor(a);
        final again = await TravelerMarkerIcons.iconFor(a);
        expect(identical(first, again), isTrue);
        expect(TravelerMarkerIcons.renderedCount, 1);
        for (final style in TravelerMarkerStyle.values) {
          for (final color in TravelerMarkerColor.values) {
            await TravelerMarkerIcons.iconFor(
                TravelerMarkerSettings(style: style, color: color));
          }
        }
        expect(TravelerMarkerIcons.renderedCount, 18);
        await TravelerMarkerIcons.iconFor(a);
        expect(TravelerMarkerIcons.renderedCount, 18,
            reason: 'revisiting a look does not redraw it');
      });
    });

    testWidgets('R03 the bitmap is a PNG with the expected map size',
        (tester) async {
      TravelerMarkerIcons.clearForTest();
      await tester.runAsync(() async {
        final dot =
            await TravelerMarkerIcons.iconFor(const TravelerMarkerSettings())
                as BytesMapBitmap;
        final arrow = await TravelerMarkerIcons.iconFor(
                const TravelerMarkerSettings(style: TravelerMarkerStyle.arrow))
            as BytesMapBitmap;
        expect((dot.width, dot.height), (32.0, 32.0)); // the familiar dot size
        expect((arrow.width, arrow.height), (40.0, 40.0));
        expect(dot.byteData.length, greaterThan(100));
      });
    });
  });

  group('map configuration', () {
    Widget map({BitmapDescriptor? icon, Color? color}) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 480,
              child: ClusteredLocationMap(
                initialTarget: const LatLng(50.45, 30.52),
                userPosition: const LatLng(50.46, 30.53),
                locations: const [],
                polylines: const {},
                onLocationTap: (_) {},
                onLongPress: (_) {},
                onViewportChanged: (_) {},
                userLocationIcon: icon,
                userLocationColor: color,
              ),
            ),
          ),
        );

    testWidgets(
        'M01 the personalized icon and accent reach the user marker '
        'and the accuracy halo', (tester) async {
      final icon = BitmapDescriptor.defaultMarkerWithHue(120);
      await tester
          .pumpWidget(map(icon: icon, color: TravelerMarkerColor.green.color));
      final gm = tester.widget<GoogleMap>(find.byType(GoogleMap));
      final marker = gm.markers
          .firstWhere((m) => m.markerId.value == 'current_user_location');
      expect(identical(marker.icon, icon), isTrue);
      expect(marker.position, const LatLng(50.46, 30.53));
      expect(marker.anchor, const Offset(.5, .5));
      final halo = gm.circles.single;
      expect(halo.fillColor.toARGB32() & 0x00FFFFFF,
          TravelerMarkerColor.green.color.toARGB32() & 0x00FFFFFF);
      expect(halo.radius, 90);
    });

    testWidgets('M02 without personalization the halo keeps its pink default',
        (tester) async {
      await tester.pumpWidget(map());
      final halo =
          tester.widget<GoogleMap>(find.byType(GoogleMap)).circles.single;
      expect(halo.fillColor, const Color(0xFFEC407A).withValues(alpha: 0.13));
      expect(halo.strokeColor, const Color(0xFFEC407A).withValues(alpha: 0.4));
    });

    testWidgets('M03 no location: no marker and no halo, no error',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 480,
            child: ClusteredLocationMap(
              initialTarget: const LatLng(50.45, 30.52),
              userPosition: null,
              locations: const [],
              polylines: const {},
              onLocationTap: (_) {},
              onLongPress: (_) {},
              onViewportChanged: (_) {},
              userLocationIcon: BitmapDescriptor.defaultMarkerWithHue(0),
              userLocationColor: Colors.blue,
            ),
          ),
        ),
      ));
      final gm = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(gm.markers, isEmpty);
      expect(gm.circles, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('screen', () {
    Widget screen() => ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const PersonalizationScreen(),
          ),
        );

    testWidgets('U01 shows three styles, six colours and a live preview',
        (tester) async {
      await tester.pumpWidget(screen());
      for (final s in TravelerMarkerStyle.values) {
        expect(find.byKey(Key('marker_style_${s.name}')), findsOneWidget);
      }
      for (final c in TravelerMarkerColor.values) {
        expect(find.byKey(Key('marker_color_${c.name}')), findsOneWidget);
      }
      expect(find.byKey(const Key('marker_preview')), findsOneWidget);
      expect(find.text('Класична точка, Рожевий'), findsOneWidget);
    });

    testWidgets('U02 every choice updates the preview and is persisted',
        (tester) async {
      await tester.pumpWidget(screen());
      for (final s in TravelerMarkerStyle.values) {
        for (final c in TravelerMarkerColor.values) {
          await tester.tap(find.byKey(Key('marker_style_${s.name}')));
          await tester.tap(find.byKey(Key('marker_color_${c.name}')));
          await tester.pump();
          expect(find.text('${s.label}, ${c.label}'), findsOneWidget);
          final preview = tester.widget<TravelerMarkerPreview>(find.descendant(
              of: find.byKey(const Key('marker_preview')),
              matching: find.byType(TravelerMarkerPreview)));
          expect(preview.style, s);
          expect(preview.color, c);
        }
      }
      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(TravelerMarkerStore.styleKey), 'traveler');
        expect(prefs.getString(TravelerMarkerStore.colorKey), 'orange');
      });
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('U03 fits $width dp at 1.12x text', (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
              size: Size(width, 640),
              textScaler: const TextScaler.linear(1.12)),
          child: screen(),
        ));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('profile navigation', () {
    const profile = UserProfile(
      id: 'user-1',
      name: 'Мандрівник',
      email: 'a@b.c',
      level: 'Дослідник',
      xp: 10,
      locationsCount: 1,
    );

    testWidgets('N01 Profile has "Персоналізація" and reports its destination',
        (tester) async {
      String? destination;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ProfileContent(
              profile: profile,
              savedCountOverride: 0,
              achievementProgressOverride: const (unlocked: 0, total: 1),
              inviteBalanceOverride: 0,
              onDestination: (d) => destination = d,
            ),
          ),
        ),
      ));
      final entry = find.byKey(const Key('profile_action_personalization'));
      await tester.scrollUntilVisible(entry, 160,
          scrollable: find.byType(Scrollable));
      expect(find.text('Персоналізація'), findsOneWidget);
      await tester.tap(entry);
      expect(destination, 'personalization');
    });

    testWidgets('N02 the destination opens the personalization screen',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSecondarySection(context, 'personalization'),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonalizationScreen), findsOneWidget);
    });
  });

  group('Phase 3 layout', () {
    Widget screen() => ProviderScope(
          child: MaterialApp(
              theme: buildAppTheme(), home: const PersonalizationScreen()),
        );

    for (final width in [320.0, 360.0]) {
      testWidgets(
          'L01 short card labels, aligned cards and one swatch row '
          'at $width dp', (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(screen());

        for (final label in ['Точка', 'Стрілка', 'Мандрівник']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('Навігаційна стрілка'), findsNothing);
        expect(find.text('Мандрівник з рюкзаку'), findsNothing);
        // The three cards share one top and one height.
        final cards = [
          for (final s in TravelerMarkerStyle.values)
            tester.getRect(find.byKey(Key('marker_style_${s.name}'))),
        ];
        expect(cards.map((r) => r.top).toSet().length, 1);
        expect(cards.map((r) => r.height).toSet().length, 1);
        // All six colour swatches on a single row.
        final tops = {
          for (final c in TravelerMarkerColor.values)
            tester.getRect(find.byKey(Key('marker_color_${c.name}'))).top,
        };
        expect(tops.length, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('L02 the preview keeps the full style name', (tester) async {
      await tester.pumpWidget(screen());
      await tester.tap(find.byKey(const Key('marker_style_traveler')));
      await tester.pump();
      expect(find.text('Мандрівник з рюкзаком, Рожевий'), findsOneWidget);
    });
  });
}
