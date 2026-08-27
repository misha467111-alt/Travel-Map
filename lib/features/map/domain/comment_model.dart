class CommentModel {
  const CommentModel({
    required this.id,
    required this.locationId,
    required this.userId,
    required this.userName,
    required this.text,
    required this.rating,
    required this.createdAt,
  });

  final String id;
  final String locationId;
  final String userId;
  final String userName;
  final String text;
  final int? rating;
  final DateTime createdAt;

  factory CommentModel.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    final profileMap =
        profile is Map<String, dynamic> ? profile : const <String, dynamic>{};
    final displayName = profileMap['display_name'] as String?;
    final username = profileMap['username'] as String?;

    return CommentModel(
      id: map['id'] as String,
      locationId: map['location_id'] as String,
      userId: map['author_id'] as String,
      userName: _firstNonEmpty(displayName, username),
      text: map['body'] as String,
      rating: (map['rating'] as num?)?.toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static String _firstNonEmpty(String? first, String? second) {
    if (first != null && first.trim().isNotEmpty) return first.trim();
    if (second != null && second.trim().isNotEmpty) return second.trim();
    return 'Мандрівник';
  }
}
