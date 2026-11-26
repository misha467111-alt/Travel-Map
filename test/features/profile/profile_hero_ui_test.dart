import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/achievements/domain/achievement_model.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database_provider.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_statistics.dart';
import 'package:flutter_application_1/features/gps/recording/gps_journey_summary.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_forest_art.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_places_section.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_route_sketch.dart';
import 'package:flutter_application_1/features/profile/presentation/profile_screen.dart';
import 'package:flutter_application_1/features/profile/presentation/traveler_profile_header.dart';
import 'package:flutter_application_1/features/profile/providers/my_places_provider.dart';
import 'package:flutter_application_1/features/profile/providers/profile_journey_data_provider.dart';
import 'package:flutter_application_1/features/profile/providers/profile_journey_stats_provider.dart';
import 'package:flutter_application_1/features/social/domain/public_profile.dart';

/// Phase 3.4-B / B1 -- Premium Forest profile: hero, medals, recent-Journey
/// cards and the route outline. Everything shown is real data; nothing is
/// invented.
void main() {
  const widths = [320.0, 360.0, 430.0];
  const scales = [1.0, 1.3, 1.5];

  Widget host(Widget child, {double width = 400, double scale = 1}) =>
      ProviderScope(
        key: UniqueKey(),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 800), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
      );

  group('TravelerProfileHeader (hero)', () {
    Widget own({double width = 400, double scale = 1, String name = 'Іван'}) =>
        host(
            TravelerProfileHeader(
              name: name,
              subtitle: 'ivan@example.com',
              level: 'Дослідник',
              xp: 320,
              onAvatarTap: () {},
              nameAction: IconButton(
                  tooltip: 'Змінити ім’я',
                  onPressed: () {},
                  icon: const Icon(Icons.edit_outlined)),
            ),
            width: width,
            scale: scale);

    Widget public({double width = 400, double scale = 1}) => host(
        const TravelerProfileHeader(
          name: 'Travel Seed',
          level: 'Новачок',
          xp: 0,
          counters: [
            TravelerCounter(keyName: 'locations', label: 'Локації', value: 51),
            TravelerCounter(keyName: 'followers', label: 'Стежать', value: 3),
            TravelerCounter(keyName: 'following', label: 'Стежу', value: null),
          ],
        ),
        width: width,
        scale: scale);

    testWidgets('own hero: artwork, avatar, name, rank, level and XP',
        (tester) async {
      await tester.pumpWidget(own());
      expect(find.byKey(const Key('traveler_profile_header')), findsOneWidget);
      expect(find.byKey(const Key('forest_hero_art')), findsOneWidget);
      expect(find.byKey(const Key('profile_avatar')), findsOneWidget);
      expect(find.text('Іван'), findsOneWidget);
      expect(find.text('ivan@example.com'), findsOneWidget);
      expect(find.text('Рівень 3'), findsOneWidget);
      expect(find.text('Дослідник'), findsOneWidget);
      expect(find.text('320 XP'), findsOneWidget);
      expect(find.text('320 / 600 XP'), findsOneWidget);
      expect(find.byKey(const Key('profile_xp_progress')), findsOneWidget);
      expect(find.byTooltip('Змінити аватар'), findsOneWidget);
      // The statistics are separate tiles on the own profile, not in the hero.
      expect(find.byKey(const Key('profile_counter_locations')), findsNothing);
    });

    testWidgets('public hero: no e-mail, no edit controls, real counters only',
        (tester) async {
      await tester.pumpWidget(public());
      expect(find.byKey(const Key('profile_subtitle')), findsNothing);
      expect(find.byTooltip('Змінити аватар'), findsNothing);
      expect(find.byTooltip('Змінити ім’я'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byKey(const Key('forest_hero_art')), findsOneWidget);
      Finder counter(String k, String v) => find.descendant(
          of: find.byKey(Key('profile_counter_$k')), matching: find.text(v));
      expect(counter('locations', '51'), findsOneWidget);
      expect(counter('followers', '3'), findsOneWidget);
      // An unavailable value is an em dash, never a made-up zero.
      expect(counter('following', '—'), findsOneWidget);
    });

    testWidgets('the hero is as tall as its content, also in a tall parent',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 2000,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: TravelerProfileHeader(
                      name: 'Іван', level: 'Новачок', xp: 0),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(
          tester
              .getSize(find.byKey(const Key('traveler_profile_header')))
              .height,
          lessThan(500));
    });

    testWidgets('a picture that fails to load falls back to the avatar icon',
        (tester) async {
      await tester.pumpWidget(host(const TravelerProfileHeader(
          name: 'Іван',
          level: 'Новачок',
          xp: 0,
          avatarUrl: 'http://127.0.0.1:1/missing.png')));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('profile_avatar_fallback')), findsOneWidget);
    });

    for (final width in widths) {
      for (final scale in scales) {
        testWidgets('own hero fits ${width}dp @ ${scale}x', (tester) async {
          await tester.pumpWidget(own(
              width: width,
              scale: scale,
              name: 'Дуже довге імʼя мандрівника для перевірки переносу'));
          expect(tester.takeException(), isNull);
        });

        testWidgets('public hero fits ${width}dp @ ${scale}x', (tester) async {
          await tester.pumpWidget(public(width: width, scale: scale));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('hero contrast (rendered pixels)', () {
    double lin(int c) {
      final s = c / 255;
      return s <= 0.03928
          ? s / 12.92
          : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    }

    double lum(double r, double g, double b) =>
        0.2126 * lin(r.round()) +
        0.7152 * lin(g.round()) +
        0.0722 * lin(b.round());

    for (final width in widths) {
      testWidgets('the e-mail is >= 4.5:1 over the artwork at ${width}dp',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('shot'),
                child: Container(
                  color: AppColors.background,
                  padding: const EdgeInsets.all(16),
                  child: const TravelerProfileHeader(
                      name: 'Іван',
                      subtitle: 'ivan@example.com',
                      level: 'Дослідник',
                      xp: 320),
                ),
              ),
            ),
          ),
        ));
        final rect = tester.getRect(find.byKey(const Key('profile_subtitle')));
        final text =
            tester.widget<Text>(find.byKey(const Key('profile_subtitle')));
        final fg = text.style!.color!;
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('shot')));
          final image = await boundary.toImage(pixelRatio: 1);
          final data =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          int px(int x, int y, int ch) =>
              data.getUint8((y * image.width + x) * 4 + ch);
          var worst = double.infinity;
          // The background just above and just below the line of text.
          for (final y in [rect.top.floor() - 2, rect.bottom.ceil() + 2]) {
            for (var x = rect.left.floor(); x < rect.right.ceil(); x += 3) {
              final bg = [for (var c = 0; c < 3; c++) px(x, y, c).toDouble()];
              final a = fg.a;
              final blended = [
                fg.r * 255 * a + bg[0] * (1 - a),
                fg.g * 255 * a + bg[1] * (1 - a),
                fg.b * 255 * a + bg[2] * (1 - a),
              ];
              final lt = lum(blended[0], blended[1], blended[2]);
              final lb = lum(bg[0], bg[1], bg[2]);
              final ratio =
                  (math.max(lt, lb) + 0.05) / (math.min(lt, lb) + 0.05);
              worst = math.min(worst, ratio);
            }
          }
          expect(worst, greaterThanOrEqualTo(4.5),
              reason: 'worst contrast ${worst.toStringAsFixed(2)}:1');
        });
      });
    }
  });

  group('forest artwork', () {
    testWidgets('paints at any size, even degenerate ones', (tester) async {
      for (final size in const [
        Size(320, 220),
        Size(430, 400),
        Size(1, 1),
        Size(300, 0),
        Size(0, 300),
      ]) {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: SizedBox.fromSize(
                  size: size, child: const ForestHeroBackground())),
        ));
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    test('the painter never needs to repaint for the same size', () {
      const painter = ForestHeroPainter();
      expect(painter.shouldRepaint(const ForestHeroPainter()), isFalse);
    });

    testWidgets('is hidden from the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 200, height: 100, child: ForestHeroBackground()),
      ));
      expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
      handle.dispose();
    });
  });

  group('hero artwork stays inside its box (Phase 3.4-B2)', () {
    /// Renders [child] on a flat 1:1 canvas and returns the RGBA bytes.
    Future<({ByteData data, int width, int height})> render(
        WidgetTester tester, Widget child, Size view) async {
      tester.view.physicalSize = view;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: const Key('shot'), child: child),
          ),
        ),
      ));
      late ({ByteData data, int width, int height}) out;
      await tester.runAsync(() async {
        final boundary = tester
            .renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
        final image = await boundary.toImage(pixelRatio: 1);
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        out = (data: data, width: image.width, height: image.height);
      });
      return out;
    }

    List<int> pixel(
        ({ByteData data, int width, int height}) img, int x, int y) {
      final i = (y * img.width + x) * 4;
      return [for (var c = 0; c < 4; c++) img.data.getUint8(i + c)];
    }

    testWidgets('nothing is painted outside the canvas (trunks, edge trees)',
        (tester) async {
      const sentinel = Color(0xFFFF00FF);
      const margin = 12;
      for (final size in const [
        Size(280, 200),
        Size(330, 270),
        Size(150, 120)
      ]) {
        final img = await render(
          tester,
          Container(
            color: sentinel,
            padding: const EdgeInsets.all(12),
            child: SizedBox.fromSize(
                size: size, child: const ForestHeroBackground()),
          ),
          Size(size.width + 2 * margin, size.height + 2 * margin),
        );
        var leaked = 0;
        bool isSentinel(List<int> px) =>
            px[0] == 255 && px[1] == 0 && px[2] == 255;
        for (var y = 0; y < img.height; y++) {
          for (var x = 0; x < img.width; x++) {
            final inside = x >= margin &&
                x < img.width - margin &&
                y >= margin &&
                y < img.height - margin;
            if (!inside && !isSentinel(pixel(img, x, y))) leaked++;
          }
        }
        expect(leaked, 0,
            reason: 'artwork leaked into the margin around $size');
      }
    });

    testWidgets('the clip does not remove the artwork inside the box',
        (tester) async {
      final img = await render(
        tester,
        const SizedBox(width: 300, height: 240, child: ForestHeroBackground()),
        const Size(300, 240),
      );
      // Sky glow, mountains and the tree line are all there: the bottom rows are
      // the dark tree colour, the top rows the lighter sky, and they differ.
      final top = pixel(img, 150, 4);
      final bottom = pixel(img, 150, 236);
      expect(top[3], 255);
      expect(bottom[3], 255);
      expect(top[1], greaterThan(bottom[1]),
          reason: 'sky is lighter than the dark tree line');
      var distinct = <int>{};
      for (var y = 0; y < 240; y += 6) {
        final px = pixel(img, 150, y);
        distinct.add(px[0] * 65536 + px[1] * 256 + px[2]);
      }
      expect(distinct.length, greaterThan(8),
          reason: 'a gradient with ridges and trees, not a flat fill');
    });

    for (final public in [false, true]) {
      testWidgets(
          'the gold border is continuous on the bottom, left and right '
          '(${public ? "public" : "own"} hero)', (tester) async {
        final header = public
            ? const TravelerProfileHeader(
                name: 'Іван',
                level: 'Новачок',
                xp: 0,
                counters: [
                  TravelerCounter(keyName: 'a', label: 'Локації', value: 5),
                  TravelerCounter(keyName: 'b', label: 'Стежать', value: 2),
                ],
              )
            : const TravelerProfileHeader(
                name: 'Іван',
                subtitle: 'ivan@example.com',
                level: 'Дослідник',
                xp: 320,
              );
        final img = await render(
          tester,
          Container(
              color: AppColors.background,
              padding: const EdgeInsets.all(16),
              child: header),
          const Size(360, 900),
        );
        final rect =
            tester.getRect(find.byKey(const Key('traveler_profile_header')));
        // The border is 45 % gold over the hero's own colour.
        final expected = [
          for (final c in [
            [AppColors.accent.r, AppColors.elevated.r],
            [AppColors.accent.g, AppColors.elevated.g],
            [AppColors.accent.b, AppColors.elevated.b],
          ])
            (c[0] * 255 * 0.45 + c[1] * 255 * 0.55).round()
        ];
        bool isBorder(List<int> px) {
          for (var c = 0; c < 3; c++) {
            if ((px[c] - expected[c]).abs() > 10) return false;
          }
          return true;
        }

        // Straight parts only: the 18 px corners are rounded.
        final left = rect.left.round();
        final right = rect.right.round() - 1;
        final bottom = rect.bottom.round() - 1;
        final top = rect.top.round();
        final h = rect.height.round();
        final w = rect.width.round();
        int missing(Iterable<List<int>> px) =>
            px.where((p) => !isBorder(p)).length;
        final leftPx = [
          for (var y = top + 20; y < top + h - 20; y++) pixel(img, left, y)
        ];
        final rightPx = [
          for (var y = top + 20; y < top + h - 20; y++) pixel(img, right, y)
        ];
        final bottomPx = [
          for (var x = left + 20; x < left + w - 20; x++) pixel(img, x, bottom)
        ];
        expect(missing(bottomPx), 0, reason: 'bottom border has gaps');
        expect(missing(leftPx), 0, reason: 'left border has gaps');
        expect(missing(rightPx), 0, reason: 'right border has gaps');

        // The rounded corners (radius 18, border 1): the middle of the arc, at 45
        // degrees, must show the border -- the artwork must not paint over it.
        // The arc is anti-aliased, so look for a clearly border-bright pixel
        // (the border's red is ~102, the artwork's at most ~64 at the top, the dark tree
        // line ~20) among the 3x3 neighbours.
        const radius = 18.0;
        const mid = radius - 0.5;
        final arc = mid * math.sqrt1_2;
        final corners = <String, Offset>{
          'top-left': Offset(rect.left + radius - arc, rect.top + radius - arc),
          'top-right':
              Offset(rect.right - radius + arc, rect.top + radius - arc),
          'bottom-left':
              Offset(rect.left + radius - arc, rect.bottom - radius + arc),
          'bottom-right':
              Offset(rect.right - radius + arc, rect.bottom - radius + arc),
        };
        for (final entry in corners.entries) {
          var brightest = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final px = pixel(img, entry.value.dx.floor() + dx,
                  entry.value.dy.floor() + dy);
              if (px[0] > brightest) brightest = px[0];
            }
          }
          expect(brightest, greaterThanOrEqualTo(55),
              reason: '${entry.key} corner arc of the border is covered '
                  '(brightest red $brightest)');
        }
      });
    }
  });

  group('HexMedal', () {
    testWidgets('shows the real icon and a hexagon frame', (tester) async {
      await tester.pumpWidget(host(const Align(
          alignment: Alignment.centerLeft,
          child: HexMedal(
              icon: Icons.location_on, iconKey: Key('medal_icon'), size: 64))));
      expect(find.byKey(const Key('medal_icon')), findsOneWidget);
      expect(tester.widget<Icon>(find.byKey(const Key('medal_icon'))).color,
          AppColors.accent);
      expect(tester.getSize(find.byType(HexMedal)), const Size(64, 64));
    });

    test('the hexagon fits its box and is symmetric', () {
      const size = Size(60, 60);
      final bounds = hexagonPath(size).getBounds();
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(60));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(60));
      expect(bounds.center.dx, closeTo(30, 0.001));
      expect(bounds.center.dy, closeTo(30, 0.001));
      // Pointy-top: the vertical extent is the full diameter.
      expect(bounds.height, closeTo(56, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Route outline: pure helpers
  // ---------------------------------------------------------------------------
  group('route outline: pure helpers', () {
    const mPerDeg = 111194.9266;

    /// A straight track of [meters] going north from (50, 30) in [n] points.
    SketchRun northLine(double meters, {int n = 10}) => [
          for (var i = 0; i < n; i++)
            (lat: 50.0 + (meters / mPerDeg) * i / (n - 1), lon: 30.0),
        ];

    test('simplifySketchRun keeps short runs as they are', () {
      final run = northLine(500, n: 50);
      expect(simplifySketchRun(run), same(run));
    });

    test('a long straight run collapses to its two ends', () {
      final run = northLine(5000, n: 5000);
      final out = simplifySketchRun(run);
      expect(out.length, lessThanOrEqualTo(routeSketchMaxPoints));
      expect(out.first, run.first);
      expect(out.last, run.last);
      expect(out.length, 2);
    });

    test('the characteristic turns of a long run are kept (not an even stride)',
        () {
      // East 500 pts, then north 500, then west 500: two sharp corners.
      final run = <SketchPoint>[
        for (var i = 0; i < 500; i++) (lat: 50.0, lon: 30.0 + i * 0.00002),
        for (var i = 0; i < 500; i++) (lat: 50.0 + i * 0.00002, lon: 30.00998),
        for (var i = 0; i < 500; i++)
          (lat: 50.00998, lon: 30.00998 - i * 0.00002),
      ];
      final out = simplifySketchRun(run);
      expect(out.length, lessThanOrEqualTo(routeSketchMaxPoints));
      expect(out.first, run.first);
      expect(out.last, run.last);
      // The two corners (indices 499 and 999) survive exactly.
      expect(out, contains(run[499]));
      expect(out, contains(run[999]));
    });

    test('every run is simplified on its own and runs are never merged', () {
      final a = northLine(2000, n: 2000);
      final b = [
        for (final p in northLine(2000, n: 2000))
          (lat: p.lat + 0.05, lon: 30.1),
      ];
      final out = buildSketchRuns([a, b]);
      expect(out, hasLength(2));
      expect(out[0].first, a.first);
      expect(out[0].last, a.last);
      expect(out[1].first, b.first);
      expect(out[1].last, b.last);
      expect(out[0], isNot(contains(b.first)));
      expect(out[1], isNot(contains(a.last)));
    });

    test('buildSketchRuns: nothing in, nothing out; one point is kept', () {
      expect(buildSketchRuns(const []), isEmpty);
      expect(buildSketchRuns([const []]), isEmpty);
      final single = <SketchRun>[
        [(lat: 50.0, lon: 30.0)]
      ];
      expect(buildSketchRuns(single), single);
    });

    group('too small to be a route (GPS noise around one spot)', () {
      bool tooSmall(double meters) => isSketchTooSmall([northLine(meters)]);

      test('0 m, 5 m and 20 m are noise', () {
        expect(tooSmall(0), isTrue);
        expect(tooSmall(5), isTrue);
        expect(tooSmall(20), isTrue);
        expect(tooSmall(29), isTrue);
      });

      test('30 m is the smallest drawable route', () {
        expect(tooSmall(30), isFalse);
        expect(tooSmall(31), isFalse);
      });

      test('a normal route is drawable', () {
        expect(tooSmall(1500), isFalse);
      });

      test('fewer than two points is never a route', () {
        expect(isSketchTooSmall(const []), isTrue);
        expect(
            isSketchTooSmall([
              [(lat: 50.0, lon: 30.0)]
            ]),
            isTrue);
      });

      test('projectSketch draws nothing for noise and never stretches it', () {
        for (final meters in [0.0, 5.0, 20.0]) {
          expect(
              projectSketch([northLine(meters)], const Size(100, 100)), isEmpty,
              reason: '$meters m');
        }
        expect(
            projectSketch([northLine(30)], const Size(100, 100)), isNotEmpty);
        expect(
            projectSketch([northLine(1500)], const Size(100, 100)), isNotEmpty);
      });

      test('the extent is the longest side of the box, in metres', () {
        expect(sketchExtentMeters([northLine(500)]), closeTo(500, 0.5));
        expect(sketchExtentMeters(const []), 0);
      });
    });

    test('projectSketch: no room draws nothing', () {
      expect(projectSketch([northLine(500)], const Size(15, 15)), isEmpty);
      expect(projectSketch([northLine(500)], Size.zero), isEmpty);
    });

    test('projectSketch fits the padded box and keeps the shape', () {
      final run = <SketchPoint>[
        (lat: 50.000, lon: 30.000),
        (lat: 50.001, lon: 30.000),
        (lat: 50.001, lon: 30.002),
        (lat: 50.000, lon: 30.002),
      ];
      const size = Size(120, 80);
      final out = projectSketch([run], size, padding: 10).single;
      expect(out, hasLength(4));
      for (final o in out) {
        expect(o.dx, inInclusiveRange(10 - 1e-9, 110 + 1e-9));
        expect(o.dy, inInclusiveRange(10 - 1e-9, 70 + 1e-9));
        expect(o.dx.isFinite && o.dy.isFinite, isTrue);
      }
      // North is up: a larger latitude has a smaller y.
      expect(out[1].dy, lessThan(out[0].dy));
      // Aspect preserved (longitude scaled by cos of the latitude).
      final width = out[2].dx - out[1].dx;
      final height = out[0].dy - out[1].dy;
      final expected = 0.002 * math.cos(50.0005 * math.pi / 180) / 0.001;
      expect(width / height, closeTo(expected, 1e-6));
    });

    test('projectSketch keeps runs apart: one list of offsets per run', () {
      final a = northLine(500);
      final b = [
        for (final p in northLine(500)) (lat: p.lat + 0.02, lon: 30.02),
      ];
      final out = projectSketch([a, b], const Size(100, 100));
      expect(out, hasLength(2));
      expect(out[0], hasLength(a.length));
      expect(out[1], hasLength(b.length));
    });

    test('projectSketch never produces NaN for a perfectly horizontal track',
        () {
      final out = projectSketch([
        [
          (lat: 50.0, lon: 30.0),
          (lat: 50.0, lon: 30.01),
        ]
      ], const Size(100, 60))
          .single;
      expect(out.every((o) => o.dx.isFinite && o.dy.isFinite), isTrue);
      expect(out.first.dy, out.last.dy);
    });
  });

  // ---------------------------------------------------------------------------
  // Per-Journey data (local Drift only)
  // ---------------------------------------------------------------------------
  group('profileJourneyDataProvider (local Drift only)', () {
    late GpsLocalDatabase db;
    setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    ProviderContainer container() {
      final c = ProviderContainer(
          overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)]);
      addTearDown(c.dispose);
      return c;
    }

    final t0 = DateTime.utc(2026, 1, 1, 10);

    Future<void> straight(String id, int points,
        {double accuracy = 5, String owner = 'me', bool finish = true}) async {
      await db.createLocalRecordedRoute(id: id, ownerId: owner, startedAt: t0);
      for (var i = 0; i < points; i++) {
        await db.appendRoutePoint(
          ownerId: owner,
          recordedRouteId: id,
          latitude: 50.0 + i * 0.00004,
          longitude: 30.0,
          horizontalAccuracy: accuracy,
          speed: 1.5,
          recordedAt: t0.add(Duration(seconds: 3 * i)),
        );
      }
      if (finish) {
        await db.finishRecordingLocally(
            ownerId: owner,
            routeId: id,
            occurredAt: t0.add(Duration(seconds: 3 * points + 1)));
      }
    }

    Future<ProfileJourneyData?> read(ProviderContainer c, String id,
            {String owner = 'me'}) =>
        c.read(
            profileJourneyDataProvider((ownerId: owner, routeId: id)).future);

    test('a confirmed track gives its outline; first and last are kept',
        () async {
      await straight('a', 60);
      final data = (await read(container(), 'a'))!;
      expect(data.runs, hasLength(1));
      expect(data.runs.single.first.lat, closeTo(50.0, 1e-9));
      expect(data.runs.single.last.lat, closeTo(50.0 + 59 * 0.00004, 1e-9));
    });

    test('two runs separated by a long gap and a ~2 km jump stay two runs',
        () async {
      await db.createLocalRecordedRoute(id: 'g', ownerId: 'me', startedAt: t0);
      var sec = 0;
      Future<void> point(double lat, double lon, int dt) async {
        sec += dt;
        await db.appendRoutePoint(
          ownerId: 'me',
          recordedRouteId: 'g',
          latitude: lat,
          longitude: lon,
          horizontalAccuracy: 5,
          speed: 1.5,
          recordedAt: t0.add(Duration(seconds: sec)),
        );
      }

      for (var i = 0; i < 20; i++) {
        await point(50.0 + i * 0.0001, 30.0, 3);
      }
      // 30 minutes of silence, then ~2 km to the east.
      for (var i = 0; i < 20; i++) {
        await point(50.0019 + i * 0.0001, 30.03, i == 0 ? 1800 : 3);
      }
      await db.finishRecordingLocally(
          ownerId: 'me',
          routeId: 'g',
          occurredAt: t0.add(Duration(seconds: sec + 1)));

      final data = (await read(container(), 'g'))!;
      expect(data.runs, hasLength(2), reason: 'two independent runs');
      expect(data.runs[0], hasLength(20));
      expect(data.runs[1], hasLength(20));
      // First and last of EACH run are kept.
      expect(data.runs[0].first, (lat: 50.0, lon: 30.0));
      expect(data.runs[0].last.lat, closeTo(50.0019, 1e-9));
      expect(data.runs[1].first.lat, closeTo(50.0019, 1e-9));
      expect(data.runs[1].first.lon, closeTo(30.03, 1e-9));
      expect(data.runs[1].last.lat, closeTo(50.0038, 1e-9));
      // No segment crosses the gap: inside each run the longitude never moves.
      for (final run in data.runs) {
        for (var i = 1; i < run.length; i++) {
          expect((run[i].lon - run[i - 1].lon).abs(), lessThan(1e-9));
        }
      }
      // The gap is not part of the distance either.
      expect(data.statistics.totalDistanceMeters, lessThan(500));
    });

    test('a long track is simplified to the point budget', () async {
      await straight('long', 400);
      final data = (await read(container(), 'long'))!;
      expect(data.runs.fold<int>(0, (n, r) => n + r.length),
          lessThanOrEqualTo(routeSketchMaxPoints));
    });

    test('unreliable (low accuracy) points are not drawn', () async {
      await straight('bad', 30, accuracy: 500);
      final data = (await read(container(), 'bad'))!;
      expect(data.runs, isEmpty);
    });

    test('another owner\'s, a missing or an unfinished Journey has no data',
        () async {
      await straight('a', 30);
      await straight('open', 30, finish: false);
      final c = container();
      expect(await read(c, 'a', owner: 'other'), isNull);
      expect(await read(c, 'missing'), isNull);
      expect(await read(c, 'open'), isNull);
    });

    test('the numbers are exactly the canonical Summary numbers', () async {
      await straight('a', 61);
      final data = (await read(container(), 'a'))!;
      final summary = (await loadGpsJourneySummary(
          db: db, ownerId: 'me', routeId: 'a', now: DateTime.now().toUtc()))!;
      expect(data.statistics.totalDistanceMeters,
          summary.statistics.totalDistanceMeters);
      expect(data.statistics.moving, summary.statistics.moving);
      expect(data.statistics.elapsed, summary.statistics.elapsed);
    });
  });

  // ---------------------------------------------------------------------------
  // Profile totals follow the finished Journeys
  // ---------------------------------------------------------------------------
  group('profileJourneyStatsProvider follows new Journeys', () {
    late GpsLocalDatabase db;
    setUp(() => db = GpsLocalDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    final t0 = DateTime.utc(2026, 1, 1, 10);

    Future<void> finish(String id, int points) async {
      await db.createLocalRecordedRoute(id: id, ownerId: 'me', startedAt: t0);
      for (var i = 0; i < points; i++) {
        await db.appendRoutePoint(
          ownerId: 'me',
          recordedRouteId: id,
          latitude: 50.0 + i * 0.00004,
          longitude: 30.0,
          horizontalAccuracy: 5,
          speed: 1.5,
          recordedAt: t0.add(Duration(seconds: 3 * i)),
        );
      }
      await db.finishRecordingLocally(
          ownerId: 'me',
          routeId: id,
          occurredAt: t0.add(Duration(seconds: 3 * points + 1)));
    }

    Future<double> canonical(String id) async => (await loadGpsJourneySummary(
            db: db, ownerId: 'me', routeId: id, now: DateTime.now().toUtc()))!
        .statistics
        .totalDistanceMeters;

    Future<ProfileJourneyStats> until(
        ProviderContainer c, bool Function(ProfileJourneyStats) ok) async {
      for (var i = 0; i < 100; i++) {
        final v = c.read(profileJourneyStatsProvider('me')).value;
        if (v != null && ok(v)) return v;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('the totals never reached the expected state: '
          '${c.read(profileJourneyStatsProvider('me'))}');
    }

    test(
        'count and distance update when a Journey is finished, no double '
        'counting', () async {
      final c = ProviderContainer(
          overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)]);
      addTearDown(c.dispose);
      // The profile tab keeps this alive, exactly like here.
      c.listen(profileJourneyStatsProvider('me'), (_, __) {});

      final before = await c.read(profileJourneyStatsProvider('me').future);
      expect(before.count, 0);
      expect(before.confirmedDistanceMeters, 0);

      await finish('a', 21);
      final da = await canonical('a');
      final one = await until(c, (s) => s.count == 1);
      expect(one.confirmedDistanceMeters, da);

      await finish('b', 11);
      final dB = await canonical('b');
      final two = await until(c, (s) => s.count == 2);
      expect(two.confirmedDistanceMeters, da + dB,
          reason: 'sum of both, each counted once');

      // An unrelated change of the same Journeys does not change the totals.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final again = c.read(profileJourneyStatsProvider('me')).value!;
      expect(again.count, 2);
      expect(again.confirmedDistanceMeters, da + dB);
    });

    test('an unfinished (active) Journey is not counted', () async {
      final c = ProviderContainer(
          overrides: [gpsLocalDatabaseProvider.overrideWithValue(db)]);
      addTearDown(c.dispose);
      c.listen(profileJourneyStatsProvider('me'), (_, __) {});
      await db.createLocalRecordedRoute(id: 'o', ownerId: 'me', startedAt: t0);
      final stats = await c.read(profileJourneyStatsProvider('me').future);
      expect(stats.count, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // The Journey card
  // ---------------------------------------------------------------------------
  group('ProfileRecentJourneysCard', () {
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

    ProfileJourneyData journeyData(double meters, List<SketchRun> runs) =>
        ProfileJourneyData(
          runs: runs,
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

    final outline = <SketchRun>[
      [
        (lat: 50.0, lon: 30.0),
        (lat: 50.001, lon: 30.001),
        (lat: 50.002, lon: 30.0),
      ]
    ];

    Widget card({
      required AsyncValue<List<LocalRecordedRoute>> journeys,
      List<Override> overrides = const [],
      List<String>? opened,
      VoidCallback? onAll,
      bool loadData = true,
      double width = 400,
      double scale = 1,
    }) =>
        ProviderScope(
          key: UniqueKey(),
          overrides: overrides,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 800), textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: ProfileRecentJourneysCard(
                    ownerId: 'me',
                    journeys: journeys,
                    onOpenJourney: (id) => opened?.add(id),
                    onOpenAll: onAll,
                    loadData: loadData,
                  ),
                ),
              ),
            ),
          ),
        );

    Override data(String id, double meters, List<SketchRun> runs) =>
        profileJourneyDataProvider((ownerId: 'me', routeId: id))
            .overrideWith((ref) async => journeyData(meters, runs));

    testWidgets('real date, confirmed distance, moving time and the outline',
        (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(card(
        journeys: AsyncData([route('j1', title: 'Прогулянка')]),
        overrides: [data('j1', 1239, outline)],
        opened: opened,
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Прогулянка'), findsOneWidget);
      expect(find.text('1.24 км'), findsOneWidget);
      expect(find.text('50 хв 0 с'), findsOneWidget);
      expect(find.byKey(const Key('profile_route_sketch')), findsOneWidget);
      expect(
          find.byKey(const Key('profile_route_sketch_fallback')), findsNothing);
      await tester.tap(find.byKey(const Key('profile_journey_j1')));
      expect(opened, ['j1']);
    });

    testWidgets('a track with a gap is painted as separate paths, never joined',
        (tester) async {
      final twoRuns = <SketchRun>[
        [for (var i = 0; i < 20; i++) (lat: 50.0 + i * 0.0001, lon: 30.0)],
        [for (var i = 0; i < 20; i++) (lat: 50.0019 + i * 0.0001, lon: 30.03)],
      ];
      await tester.pumpWidget(card(
        journeys: AsyncData([route('j1')]),
        overrides: [data('j1', 400, twoRuns)],
      ));
      await tester.pump();
      await tester.pump();
      final sketch =
          tester.renderObject(find.byKey(const Key('profile_route_sketch')));
      // Two runs: a glow and a line each = 4 paths, then the two end dots.
      expect(
          sketch,
          paints
            ..path()
            ..path()
            ..path()
            ..path()
            ..circle()
            ..circle());
      expect(
          sketch,
          isNot(paints
            ..path()
            ..path()
            ..path()
            ..path()
            ..path()));
    });

    testWidgets('a noise-sized track shows the quiet fallback, no scribble',
        (tester) async {
      final noise = <SketchRun>[
        [
          for (var i = 0; i < 30; i++)
            (lat: 50.0 + (i % 3) * 0.00001, lon: 30.0 + (i % 2) * 0.00001)
        ]
      ];
      await tester.pumpWidget(card(
        journeys: AsyncData([route('j1')]),
        overrides: [data('j1', 0, noise)],
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('profile_route_sketch')), findsNothing);
      expect(find.byKey(const Key('profile_route_sketch_fallback')),
          findsOneWidget);
      expect(find.text('0 м'), findsOneWidget);
    });

    testWidgets('no confirmed points: a quiet fallback, no invented route',
        (tester) async {
      await tester.pumpWidget(card(
        journeys: AsyncData([route('j1')]),
        overrides: [data('j1', 176, const [])],
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('profile_route_sketch')), findsNothing);
      expect(find.byKey(const Key('profile_route_sketch_fallback')),
          findsOneWidget);
      expect(find.text('176 м'), findsOneWidget);
    });

    testWidgets('loading reserves the room of the numbers: no layout shift',
        (tester) async {
      final done = Completer<ProfileJourneyData?>();
      await tester.pumpWidget(card(
        journeys: AsyncData([route('j1')]),
        overrides: [
          profileJourneyDataProvider((ownerId: 'me', routeId: 'j1'))
              .overrideWith((ref) => done.future),
        ],
      ));
      await tester.pump();
      final key = find.byKey(const Key('profile_journey_j1'));
      final loadingHeight = tester.getSize(key).height;
      expect(find.byKey(const Key('profile_journey_metric_placeholder')),
          findsNWidgets(2));
      expect(find.byKey(const Key('profile_route_sketch_fallback')),
          findsOneWidget);

      done.complete(journeyData(1239, outline));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('profile_journey_metric_placeholder')),
          findsNothing);
      expect(find.text('1.24 км'), findsOneWidget);
      expect(tester.getSize(key).height, loadingHeight);
    });

    testWidgets('a failing read does not hide the card', (tester) async {
      await tester.pumpWidget(card(
        journeys: AsyncData([route('j1')]),
        overrides: [
          profileJourneyDataProvider((ownerId: 'me', routeId: 'j1'))
              .overrideWith((ref) async => throw StateError('db')),
        ],
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('profile_journey_j1')), findsOneWidget);
      expect(find.byKey(const Key('profile_route_sketch_fallback')),
          findsOneWidget);
      expect(find.byKey(const Key('profile_journey_metric_placeholder')),
          findsNothing);
    });

    testWidgets('loadData: false reads nothing and shows only placeholders',
        (tester) async {
      var reads = 0;
      await tester.pumpWidget(card(
        loadData: false,
        journeys: AsyncData([route('j1')]),
        overrides: [
          profileJourneyDataProvider((ownerId: 'me', routeId: 'j1'))
              .overrideWith((ref) async {
            reads++;
            return journeyData(1, outline);
          }),
        ],
      ));
      await tester.pump();
      await tester.pump();
      expect(reads, 0);
      expect(find.byKey(const Key('profile_journey_j1')), findsOneWidget);
    });

    testWidgets('the card is one button for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(card(
        journeys: AsyncData([route('j1', title: 'Прогулянка')]),
        overrides: [data('j1', 1239, outline)],
      ));
      await tester.pump();
      await tester.pump();
      // One merged, tappable node that reads the whole card.
      final cardNode =
          find.bySemanticsLabel(RegExp('Прогулянка.*1.24 км', dotAll: true));
      expect(cardNode, findsOneWidget);
      expect(
          tester
              .getSemantics(cardNode)
              .getSemanticsData()
              .flagsCollection
              .isButton,
          isTrue);
      handle.dispose();
    });

    testWidgets('"Усі →" appears only when it can open the history',
        (tester) async {
      var all = 0;
      await tester
          .pumpWidget(card(journeys: const AsyncData([]), onAll: () => all++));
      await tester.tap(find.byKey(const Key('profile_journeys_all')));
      expect(all, 1);

      await tester.pumpWidget(card(journeys: const AsyncData([])));
      expect(find.byKey(const Key('profile_journeys_all')), findsNothing);
    });

    testWidgets('empty, error and loading are explicit', (tester) async {
      await tester.pumpWidget(card(journeys: const AsyncData([])));
      expect(find.byKey(const Key('profile_journeys_empty')), findsOneWidget);
      await tester.pumpWidget(
          card(journeys: AsyncError(StateError('x'), StackTrace.empty)));
      expect(find.byKey(const Key('profile_journeys_error')), findsOneWidget);
      await tester.pumpWidget(card(journeys: const AsyncLoading()));
      expect(find.byKey(const Key('profile_journeys_loading')), findsOneWidget);
    });

    testWidgets('only the 3 most recent are shown', (tester) async {
      await tester.pumpWidget(card(
        journeys: AsyncData([for (var i = 0; i < 5; i++) route('r$i')]),
        overrides: [for (var i = 0; i < 5; i++) data('r$i', 100, outline)],
      ));
      await tester.pump();
      expect(find.byKey(const Key('profile_journey_r0')), findsOneWidget);
      expect(find.byKey(const Key('profile_journey_r2')), findsOneWidget);
      expect(find.byKey(const Key('profile_journey_r3')), findsNothing);
    });

    for (final width in widths) {
      for (final scale in scales) {
        testWidgets('fits ${width}dp @ ${scale}x', (tester) async {
          await tester.pumpWidget(card(
            width: width,
            scale: scale,
            journeys: AsyncData([
              route('j1', title: 'Дуже довга назва подорожі для перевірки'),
              route('j2'),
            ]),
            overrides: [
              data('j1', 12345, outline),
              data('j2', 80, outline),
            ],
          ));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // The whole own profile
  // ---------------------------------------------------------------------------
  group('whole own profile', () {
    const me = UserProfile(
      id: 'me',
      name: 'Іван',
      email: 'ivan@example.com',
      level: 'Дослідник',
      xp: 320,
      locationsCount: 12,
    );

    AchievementModel award(String key, String name) => AchievementModel(
          key: key,
          name: name,
          description: 'd',
          icon: 'pin',
          unlockCondition: 'c',
          progress: 1,
          target: 1,
          isUnlocked: true,
          unlockedAt: DateTime(2026, 1, 2),
        );

    Widget profile({double width = 400, double scale = 1}) => ProviderScope(
          key: UniqueKey(),
          child: MaterialApp(
            theme: buildAppTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 800), textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: ProfileContent(
                  profile: me,
                  savedCountOverride: 4,
                  achievementProgressOverride: const (unlocked: 2, total: 35),
                  unlockedAchievementsOverride: [
                    award('a', 'Перша мітка'),
                    award('b', 'Дуже довга назва нагороди для перевірки'),
                  ],
                  inviteBalanceOverride: 1,
                  createdPlacesOverride: const AsyncData(3),
                  visitedPlacesOverride: const AsyncData(2),
                  recentJourneysOverride: const AsyncData([]),
                  followCountsOverride: const AsyncData(
                      FollowCounts(followers: 21, following: 34)),
                  journeyStatsOverride: const AsyncData(ProfileJourneyStats(
                      count: 12, confirmedDistanceMeters: 146800)),
                  onDestination: (_) {},
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );

    testWidgets('keeps the approved order and every section', (tester) async {
      await tester.pumpWidget(profile());
      final order = <Finder>[
        find.byKey(const Key('traveler_profile_header')),
        find.byKey(const Key('profile_stat_journeys')),
        find.byKey(const Key('profile_follow_row')),
      ];
      final ys = [for (final f in order) tester.getTopLeft(f).dy];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));

      // Below the fold, in the approved order: journeys, achievements, places.
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_action_places_created')), 200,
          scrollable: scroll);
      double y(Finder f) => tester.getTopLeft(f).dy;
      final journeysY = y(find.text('Останні подорожі'));
      final achievementsY = y(find.text('Досягнення'));
      final placesY = y(find.text('Мої місця'));
      expect(journeysY, lessThan(achievementsY));
      expect(achievementsY, lessThan(placesY));
      for (final k in [
        'profile_action_places_created',
        'profile_action_friends',
        'profile_action_saved',
        'profile_action_settings',
        'profile_action_logout',
      ]) {
        await tester.scrollUntilVisible(find.byKey(Key(k)), 200,
            scrollable: scroll);
        expect(find.byKey(Key(k)), findsOneWidget);
      }
    });

    testWidgets('real values only: counts and distance come from the data',
        (tester) async {
      await tester.pumpWidget(profile());
      Finder inTile(String k, String v) =>
          find.descendant(of: find.byKey(Key(k)), matching: find.text(v));
      // Locations = the exact created count (3), not the profile figure (12).
      expect(inTile('profile_counter_locations', '3'), findsOneWidget);
      expect(inTile('profile_stat_journeys', '12'), findsOneWidget);
      expect(inTile('profile_stat_distance', '146.80 км'), findsOneWidget);
    });

    testWidgets('the follow strip is read out as one sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(profile());
      expect(find.bySemanticsLabel('Стежать: 21. Стежу: 34.'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('"Усі →" says which section it opens', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(profile());
      await tester.scrollUntilVisible(
          find.byKey(const Key('profile_action_achievements')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.bySemanticsLabel('Усі: Досягнення'), findsOneWidget);
      handle.dispose();
    });

    for (final width in widths) {
      for (final scale in scales) {
        testWidgets('whole profile fits ${width}dp @ ${scale}x',
            (tester) async {
          await tester.pumpWidget(profile(width: width, scale: scale));
          final scroll = find.byType(Scrollable).first;
          for (final k in [
            'profile_follow_row',
            'profile_action_achievements',
            'profile_action_places_created',
            'profile_action_logout',
          ]) {
            await tester.scrollUntilVisible(find.byKey(Key(k)), 200,
                scrollable: scroll);
          }
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // IndexedStack: a hidden profile tab does no GPS work
  // ---------------------------------------------------------------------------
  group('profile tab in an IndexedStack', () {
    const me = UserProfile(
      id: 'me',
      name: 'Іван',
      email: 'ivan@example.com',
      level: 'Дослідник',
      xp: 320,
      locationsCount: 12,
    );

    testWidgets(
        'nothing is read while hidden; showing loads it; coming back refreshes '
        'the created count', (tester) async {
      var statsReads = 0, journeyReads = 0, createdReads = 0, visitedReads = 0;
      var index = 1; // 0 = the profile, 1 = another tab
      late StateSetter setTab;
      final route = LocalRecordedRoute(
        id: 'j1',
        ownerId: 'me',
        transportMode: 'walking',
        status: RecordedRouteStatus.completed,
        visibility: 'private',
        startedAt: DateTime.utc(2026, 3, 5, 10),
        endedAt: DateTime.utc(2026, 3, 5, 11),
        createdAt: DateTime.utc(2026, 3, 5, 10),
        updatedAt: DateTime.utc(2026, 3, 5, 11),
        syncStatus: RouteSyncStatus.synced,
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          profileJourneyStatsProvider('me').overrideWith((ref) async {
            statsReads++;
            return const ProfileJourneyStats(
                count: 1, confirmedDistanceMeters: 100);
          }),
          profileJourneyDataProvider((ownerId: 'me', routeId: 'j1'))
              .overrideWith((ref) async {
            journeyReads++;
            return null;
          }),
          myCreatedCountProvider('me').overrideWith((ref) async {
            createdReads++;
            return 3;
          }),
          myVisitedPlacesProvider('me').overrideWith((ref) async {
            visitedReads++;
            return const VisitedPlaces(total: 2, places: []);
          }),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: StatefulBuilder(builder: (context, set) {
            setTab = set;
            return Scaffold(
              body: IndexedStack(index: index, children: [
                ProfileContent(
                  profile: me,
                  savedCountOverride: 0,
                  achievementProgressOverride: const (unlocked: 0, total: 35),
                  unlockedAchievementsOverride: const [],
                  inviteBalanceOverride: 0,
                  recentJourneysOverride: AsyncData([route]),
                  followCountsOverride:
                      const AsyncData(FollowCounts(followers: 1, following: 2)),
                  onDestination: (_) {},
                  onLogout: () {},
                ),
                const SizedBox.expand(),
              ]),
            );
          }),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(statsReads, 0, reason: 'hidden: no totals');
      expect(journeyReads, 0, reason: 'hidden: no GPS points');
      expect(createdReads, 0);
      expect(visitedReads, 0);

      setTab(() => index = 0);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(statsReads, 1);
      expect(journeyReads, 1);
      expect(createdReads, 1);
      expect(visitedReads, 1);

      // Away and back: the created count is read again (a location may have
      // been created on the map); the GPS data is NOT recomputed.
      setTab(() => index = 1);
      await tester.pump();
      setTab(() => index = 0);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(createdReads, 2, reason: 'refreshed on return');
      expect(statsReads, 1);
      expect(journeyReads, 1);
    });
  });
}
