class FollowModel {
  const FollowModel({
    required this.followerId,
    required this.followingId,
    required this.createdAt,
  });

  final String followerId;
  final String followingId;
  final DateTime createdAt;

  factory FollowModel.fromMap(Map<String, dynamic> map) {
    return FollowModel(
      followerId: map['follower_id'] as String,
      followingId: map['following_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
