import '../../map/domain/location_model.dart';

class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.name,
    required this.xp,
    required this.level,
    required this.followersCount,
    required this.followingCount,
    required this.isFollowing,
    required this.locations,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final int xp;
  final String level;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final List<LocationModel> locations;
}
