class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.level,
    required this.xp,
    required this.locationsCount,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String email;
  final String level;
  final int xp;
  final int locationsCount;
  final String? avatarUrl;

  factory UserProfile.fromMap(Map<String, dynamic> map,
      {required String email, required int locationsCount}) {
    final xp = (map['xp'] as num? ?? 0).toInt();
    final displayName = _firstNonEmpty([
      map['display_name'],
      map['username'],
      map['name'],
      email.split('@').first
    ]);
    return UserProfile(
      id: map['id'] as String,
      name: displayName,
      email: email,
      level: _levelLabel(map['level'], xp),
      xp: xp,
      locationsCount: locationsCount,
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'Мандрівник';
  }

  static String _levelLabel(dynamic value, int xp) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return 'Рівень ${value.toInt()}';
    if (xp >= 500) return 'Мандрівник';
    if (xp >= 100) return 'Дослідник';
    return 'Новачок';
  }
}
