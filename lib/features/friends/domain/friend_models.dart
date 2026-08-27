class FriendProfile {
  const FriendProfile({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? avatarUrl;

  factory FriendProfile.fromMap(Map<String, dynamic> map) {
    final name = _firstNonEmpty([
      map['display_name'],
      map['username'],
      map['name'],
    ]);
    return FriendProfile(
      id: map['id'] as String,
      name: name,
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'Користувач';
  }
}

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.sender,
    required this.createdAt,
  });

  final String id;
  final FriendProfile sender;
  final DateTime createdAt;
}
