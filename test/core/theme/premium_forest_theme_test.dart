import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_application_1/core/theme/app_design.dart';
import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_application_1/features/map/presentation/clustered_location_map.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Color _hex(String value) =>
    Color(int.parse('FF${value.substring(1)}', radix: 16));

/// Premium Forest design system V1: tokens, theme mapping, accessibility,
/// the dark Google Maps style and the marker cache.
void main() {
  group('tokens', () {
    test('T01 the approved palette', () {
      expect(AppColors.background, const Color(0xFF0B1F1B));
      expect(AppColors.elevated, const Color(0xFF17372F));
      expect(AppColors.accent, const Color(0xFFC6A66A));
      expect(AppColors.textPrimary, const Color(0xFFF4F0E7));
      expect(AppColors.textSecondary, const Color(0xFF8B9B94));
    });

    test('T02 AppColors mirrors the premiumForest palette', () {
      const p = AppPalette.premiumForest;
      expect(AppColors.background, p.background);
      expect(AppColors.surface, p.surface);
      expect(AppColors.elevated, p.elevated);
      expect(AppColors.accent, p.accent);
      expect(AppColors.onAccent, p.onAccent);
      expect(AppColors.textPrimary, p.textPrimary);
      expect(AppColors.textSecondary, p.textSecondary);
      expect(AppColors.border, p.border);
    });

    test('T03 surfaces step up in lightness', () {
      expect(AppColors.background.computeLuminance(),
          lessThan(AppColors.surface.computeLuminance()));
      expect(AppColors.surface.computeLuminance(),
          lessThan(AppColors.elevated.computeLuminance()));
    });

    test('T04 text and accent contrast (WCAG AA or better)', () {
      for (final surface in [
        AppColors.background,
        AppColors.surface,
        AppColors.elevated,
      ]) {
        expect(_contrast(AppColors.textPrimary, surface), greaterThan(7));
        // The specified secondary text is 4.44:1 on the highest surface (just
        // under AA for small text); it is AA on background and cards.
        expect(_contrast(AppColors.textSecondary, surface), greaterThan(4.4));
        expect(_contrast(AppColors.accent, surface), greaterThan(4.5));
      }
      expect(_contrast(AppColors.onAccent, AppColors.accent), greaterThan(7));
    });
  });

  group('theme mapping', () {
    final theme = buildAppTheme();

    test('M01 colour scheme and scaffold', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, AppColors.accent);
      expect(theme.colorScheme.onPrimary, AppColors.onAccent);
      expect(theme.colorScheme.onSurface, AppColors.textPrimary);
      expect(theme.colorScheme.onSurfaceVariant, AppColors.textSecondary);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
    });

    test('M02 shared components read the surface hierarchy', () {
      expect(theme.cardTheme.color, AppColors.surface);
      expect(theme.bottomSheetTheme.backgroundColor, AppColors.elevated);
      expect(theme.dialogTheme.backgroundColor, AppColors.elevated);
      expect(theme.popupMenuTheme.color, AppColors.elevated);
      expect(theme.snackBarTheme.backgroundColor, AppColors.elevated);
      expect(theme.appBarTheme.backgroundColor, AppColors.background);
      expect(theme.navigationBarTheme.backgroundColor, AppColors.background);
      expect(theme.inputDecorationTheme.fillColor, AppColors.surface);
      expect(theme.dividerTheme.color, AppColors.border);
    });

    test('M03 one restrained accent on actions', () {
      expect(theme.floatingActionButtonTheme.backgroundColor, AppColors.accent);
      final filled = theme.filledButtonTheme.style!;
      expect(filled.backgroundColor!.resolve({}), AppColors.accent);
      expect(filled.foregroundColor!.resolve({}), AppColors.onAccent);
      expect(filled.minimumSize!.resolve({})!.height,
          greaterThanOrEqualTo(AppSizes.touchTarget));
      // Disabled is visibly different and still readable.
      final disabled = filled.backgroundColor!.resolve({WidgetState.disabled});
      expect(disabled, isNot(AppColors.accent));
      expect(
          _contrast(filled.foregroundColor!.resolve({WidgetState.disabled})!,
              AppColors.background),
          greaterThan(4.5));
    });

    test('M04 typography hierarchy uses the text tokens', () {
      expect(theme.textTheme.titleMedium!.color, AppColors.textPrimary);
      expect(theme.textTheme.bodyMedium!.color, AppColors.textPrimary);
      expect(theme.textTheme.bodySmall!.color, AppColors.textSecondary);
      expect(theme.textTheme.headlineSmall!.fontSize,
          greaterThan(theme.textTheme.titleLarge!.fontSize!));
    });

    test('M05 a different palette is one argument away (future themes)', () {
      const other = AppPalette(
        background: Color(0xFF101010),
        surface: Color(0xFF181818),
        elevated: Color(0xFF202020),
        accent: Color(0xFF4FC3F7),
        onAccent: Color(0xFF001018),
        textPrimary: Color(0xFFFFFFFF),
        textSecondary: Color(0xFF9E9E9E),
        border: Color(0xFF303030),
      );
      final t = buildAppTheme(other);
      expect(t.colorScheme.primary, other.accent);
      expect(t.scaffoldBackgroundColor, other.background);
      expect(t.cardTheme.color, other.surface);
    });

    test('M06 shared widgets hard-code no legacy gold or old surfaces', () {
      final forbidden = RegExp(
          r'0xFF(D4A017|D6A928|0D1C17|10221B|14231D|09120F|07120F|071A15)');
      final allowed = {
        // Data colours / artwork, not interface chrome.
        'lib/features/map/domain/location_categories.dart',
        'lib/features/personalization/traveler_marker.dart',
        'lib/features/map/presentation/map_reference_icons.dart',
      };
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final path = f.path.replaceAll('\\', '/');
        if (allowed.contains(path)) continue;
        if (forbidden.hasMatch(f.readAsStringSync())) offenders.add(path);
      }
      expect(offenders, isEmpty);
    });
  });

  group('dark Google Maps style', () {
    late List<dynamic> style;
    setUpAll(() {
      style =
          jsonDecode(File(AppMapStyle.assetPath).readAsStringSync()) as List;
    });

    Map<String, dynamic>? rule(
        {String? feature, String? element, String? stylerKey}) {
      for (final r in style.cast<Map<String, dynamic>>()) {
        if (r['featureType'] == feature && r['elementType'] == element) {
          return r;
        }
      }
      return null;
    }

    String? color(Map<String, dynamic>? r) {
      for (final s in (r?['stylers'] as List? ?? const [])) {
        if ((s as Map).containsKey('color')) return s['color'] as String;
      }
      return null;
    }

    test('S01 asset exists, is declared in pubspec, and is the default', () {
      expect(File(AppMapStyle.assetPath).existsSync(), true);
      expect(File('pubspec.yaml').readAsStringSync(),
          contains(AppMapStyle.darkAsset));
      expect(AppMapStyle.assetPath, AppMapStyle.darkAsset);
    });

    test('S02 every colour is a valid hex and the base is dark', () {
      final hex = RegExp(r'^#[0-9a-fA-F]{6}$');
      for (final r in style.cast<Map<String, dynamic>>()) {
        for (final s in r['stylers'] as List) {
          final c = (s as Map)['color'];
          if (c != null) expect(hex.hasMatch(c), true, reason: c as String);
        }
      }
      final base = _hex(color(rule(element: 'geometry'))!);
      expect(base.computeLuminance(), lessThan(0.03));
    });

    test('S03 water is a dark desaturated teal', () {
      final water = _hex(color(rule(feature: 'water', element: 'geometry'))!);
      expect(water.computeLuminance(), lessThan(0.05));
      expect(water.g, greaterThan(water.r));
      expect(water.b, greaterThan(water.r));
    });

    test('S04 parks are distinguishable from the land and green', () {
      final land = _hex(color(rule(element: 'geometry'))!);
      final park = _hex(color(rule(feature: 'poi.park', element: 'geometry'))!);
      expect(park.g, greaterThan(park.r));
      expect(park.g, greaterThan(park.b));
      expect(_contrast(park, land), greaterThan(1.1));
    });

    test('S05 roads are subtle and labels restrained but readable', () {
      final land = _hex(color(rule(element: 'geometry'))!);
      final road = _hex(color(rule(feature: 'road', element: 'geometry'))!);
      expect(_contrast(road, land), lessThan(2.0));
      final labels = _hex(color(rule(element: 'labels.text.fill'))!);
      expect(_contrast(labels, land), greaterThan(4.5));
      // No bright element anywhere: every colour stays dark or mid-tone text.
      for (final r in style.cast<Map<String, dynamic>>()) {
        final c = color(r);
        if (c == null) continue;
        final isText = (r['elementType'] as String?)?.contains('text') ?? false;
        if (!isText) {
          expect(_hex(c).computeLuminance(), lessThan(0.12), reason: c);
        }
      }
    });

    test('S06 POI clutter and map icons are hidden', () {
      final poi = rule(feature: 'poi');
      bool off(Map<String, dynamic>? r) =>
          (r!['stylers'] as List).any((s) => (s as Map)['visibility'] == 'off');
      expect(off(poi), true);
      expect(off(rule(element: 'labels.icon')), true);
    });
  });

  group('marker performance', () {
    testWidgets('K01 POI markers are reused when only the user moves',
        (tester) async {
      final locations = [
        for (var i = 0; i < 50; i++)
          LocationModel(
            id: 'p$i',
            userId: 'u',
            title: 'P$i',
            description: null,
            category: 'nature',
            latitude: 50 + i * 1e-3,
            longitude: 30,
            createdAt: DateTime.utc(2026),
          ),
      ];
      Widget app(LatLng user, List<LocationModel> list) => MaterialApp(
            home: SizedBox(
              width: 320,
              height: 480,
              child: ClusteredLocationMap(
                initialTarget: const LatLng(50, 30),
                userPosition: user,
                locations: list,
                polylines: const {},
                onLocationTap: (_) {},
                onLongPress: (_) {},
                onViewportChanged: (_) {},
              ),
            ),
          );
      await tester.pumpWidget(app(const LatLng(50.1, 30), locations));
      Map<String, Marker> poi() => {
            for (final m
                in tester.widget<GoogleMap>(find.byType(GoogleMap)).markers)
              if (m.markerId.value.startsWith('p')) m.markerId.value: m,
          };
      final first = poi();
      await tester.pumpWidget(app(const LatLng(50.2, 30), locations));
      final second = poi();
      expect(second.length, 50);
      for (final id in first.keys) {
        expect(identical(first[id], second[id]), isTrue,
            reason: '$id was rebuilt although nothing changed');
      }

      // A new list (new query result) does rebuild them.
      await tester.pumpWidget(app(const LatLng(50.2, 30), [...locations]));
      expect(identical(first['p0'], poi()['p0']), isFalse);
      expect(poi().length, 50);
    });
  });
}
