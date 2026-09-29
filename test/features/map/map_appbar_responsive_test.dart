import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';

/// Search Phase 2A — responsive safety check for the Map AppBar now that it
/// carries a third action (Search, added alongside the pre-existing
/// Notifications and Filters buttons).
///
/// This does NOT pump the full [MapScreen] (see `map_search_action_test.dart`
/// and `map_quick_actions_test.dart` for why: it depends on a live provider
/// graph). Instead it reconstructs the exact AppBar `title`/`actions`
/// configuration from `map_screen.dart`'s `build()` — same `toolbarHeight`,
/// `titleSpacing`, title text/style, `actionsIconTheme`, and per-action
/// `IconButton.styleFrom` sizing (32x32 minimum/maximum, 18 icon size, 6
/// padding) — substituting a plain icon for the two provider-backed/private
/// actions (`_NotificationsButton`, the Filters `IconButton`) since only
/// their size (not their behavior) affects overflow, and using the real,
/// public [MapSearchAction] for the third.
void main() {
  final sameStyle = IconButton.styleFrom(
    minimumSize: const Size.square(32),
    maximumSize: const Size.square(32),
    iconSize: 18,
    padding: const EdgeInsets.all(6),
    backgroundColor: Colors.transparent,
    side: const BorderSide(color: Colors.white24),
    shape: const CircleBorder(),
  );

  Widget harness() => MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 48,
            titleSpacing: 12,
            title: const Text(
              'Travel Map',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            actionsIconTheme: const IconThemeData(size: 18),
            actions: [
              IconButton(
                style: sameStyle,
                tooltip: 'Сповіщення',
                onPressed: () {},
                icon: const Badge(
                  label: Text('3'),
                  child: Icon(Icons.notifications_outlined),
                ),
              ),
              IconButton(
                style: sameStyle,
                tooltip: 'Фільтри',
                onPressed: () {},
                icon: const Icon(Icons.filter_alt_outlined),
              ),
              MapSearchAction(onPressed: () {}),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
      );

  const widths = [320.0, 360.0, 390.0, 430.0];
  const scales = [1.0, 1.3, 1.5];

  for (final width in widths) {
    for (final scale in scales) {
      testWidgets(
          'Map AppBar (3 actions) does not overflow at ${width}dp @ ${scale}x',
          (tester) async {
        tester.view.physicalSize =
            Size(width, 800) * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: harness(),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'AppBar overflowed at ${width}dp, textScale $scale');
      });
    }
  }
}
