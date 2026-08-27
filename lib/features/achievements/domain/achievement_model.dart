class AchievementModel {
  const AchievementModel({
    required this.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.unlockCondition,
    this.category = 'general',
    required this.progress,
    required this.target,
    required this.isUnlocked,
    this.unlockedAt,
  });

  final String key;
  final String name;
  final String description;
  final String icon;
  final String unlockCondition;
  final String category;
  final double progress;
  final double target;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  double get progressFraction =>
      target <= 0 ? 0 : (progress / target).clamp(0, 1);
}
