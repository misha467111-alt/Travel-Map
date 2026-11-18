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
    this.locationsCount,
    this.isSelf = false,
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

  /// Number of this user's public, approved locations (the real total, not
  /// just the loaded page); `null` when it could not be determined.
  final int? locationsCount;

  /// Whether this is the signed-in user's own profile (no follow button).
  final bool isSelf;
}

/// "Стежать" / "Стежу" counters of any user (rows of `follows`).
class FollowCounts {
  const FollowCounts({required this.followers, required this.following});

  /// Users who follow this user ("Стежать").
  final int followers;

  /// Users this user follows ("Стежу").
  final int following;
}
