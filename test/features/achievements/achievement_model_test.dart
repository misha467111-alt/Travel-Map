import 'package:flutter_application_1/features/achievements/domain/achievement_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('achievement progress is clamped between zero and one', () {
    const achievement = AchievementModel(
      key: 'explorer_100km',
      name: 'Explorer',
      description: 'Description',
      icon: 'route',
      unlockCondition: '100 km',
      progress: 125,
      target: 100,
      isUnlocked: true,
    );

    expect(achievement.progressFraction, 1);
  });
}
