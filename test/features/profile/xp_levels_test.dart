import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/profile/domain/xp_levels.dart';

/// Product Architecture v1.0 Phase 1: xp_levels.dart is the one client
/// mirror of the backend-authoritative thresholds
/// (`profile_level_for_xp`/`travel_level_tier` in
/// supabase/migrations/202608290000_production_canonical_baseline.sql:
/// 0/100/300/600/1000, exactly 5 levels). These tests exercise every
/// boundary explicitly, plus above-max-level behavior.
void main() {
  group('xpLevelTier', () {
    final cases = {
      0: 1,
      99: 1,
      100: 2,
      299: 2,
      300: 3,
      599: 3,
      600: 4,
      999: 4,
      1000: 5,
      1500: 5, // above max: still level 5, never a fake level 6
    };

    cases.forEach((xp, expectedTier) {
      test('xp=$xp -> tier $expectedTier', () {
        expect(xpLevelTier(xp), expectedTier);
      });
    });
  });

  group('xpCurrentLevelFloor', () {
    test('matches the floor of the tier at every boundary', () {
      expect(xpCurrentLevelFloor(0), 0);
      expect(xpCurrentLevelFloor(99), 0);
      expect(xpCurrentLevelFloor(100), 100);
      expect(xpCurrentLevelFloor(299), 100);
      expect(xpCurrentLevelFloor(300), 300);
      expect(xpCurrentLevelFloor(599), 300);
      expect(xpCurrentLevelFloor(600), 600);
      expect(xpCurrentLevelFloor(999), 600);
      expect(xpCurrentLevelFloor(1000), 1000);
      expect(xpCurrentLevelFloor(1500), 1000);
    });
  });

  group('xpNextLevelThreshold', () {
    test('points to the correct next boundary', () {
      expect(xpNextLevelThreshold(0), 100);
      expect(xpNextLevelThreshold(99), 100);
      expect(xpNextLevelThreshold(100), 300);
      expect(xpNextLevelThreshold(299), 300);
      expect(xpNextLevelThreshold(300), 600);
      expect(xpNextLevelThreshold(599), 600);
      expect(xpNextLevelThreshold(600), 1000);
      expect(xpNextLevelThreshold(999), 1000);
    });

    test(
        'is null at and above the maximum level (1000+) -- no fake '
        'level 6', () {
      expect(xpNextLevelThreshold(1000), isNull);
      expect(xpNextLevelThreshold(1500), isNull);
      expect(xpNextLevelThreshold(999999), isNull);
    });
  });

  group('xpProgressWithinLevel', () {
    test('is 0.0 exactly at a level floor', () {
      expect(xpProgressWithinLevel(0), 0);
      expect(xpProgressWithinLevel(100), 0);
      expect(xpProgressWithinLevel(300), 0);
      expect(xpProgressWithinLevel(600), 0);
    });

    test('is relative to the CURRENT level band, not from zero', () {
      // 320 XP is 20/300 of the way from the 300 floor to the 600
      // threshold -- not 320/600, which is what the pre-fix bug computed.
      expect(xpProgressWithinLevel(320), closeTo(20 / 300, 1e-9));
    });

    test('is 1.0 at and above the maximum level', () {
      expect(xpProgressWithinLevel(1000), 1);
      expect(xpProgressWithinLevel(1500), 1);
    });

    test('never exceeds 1.0 or goes below 0.0 at any boundary', () {
      for (final xp in [0, 99, 100, 299, 300, 599, 600, 999, 1000, 5000]) {
        final progress = xpProgressWithinLevel(xp);
        expect(progress, greaterThanOrEqualTo(0));
        expect(progress, lessThanOrEqualTo(1));
      }
    });
  });

  test('exactly 5 levels are defined, matching the fixed product rule', () {
    expect(xpLevelThresholds, [0, 100, 300, 600, 1000]);
    expect(xpLevelThresholds.length, 5);
  });
}
