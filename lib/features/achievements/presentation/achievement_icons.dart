import 'package:flutter/material.dart';

/// Maps the `icon` key of an achievement (as returned by the
/// `get_achievement_progress` RPC) to a Material icon. Shared by the
/// Achievements screen and the Premium Profile strip; unknown keys fall back
/// to a place pin. The keys and the server data are not changed here.
IconData achievementIconFor(String icon) => switch (icon) {
      'map' => Icons.map,
      'explore' => Icons.explore,
      'radar' => Icons.radar,
      'public' => Icons.public,
      'emoji_events' => Icons.emoji_events,
      'pin' => Icons.location_on,
      'hiking' => Icons.hiking,
      'directions' => Icons.directions_walk,
      'flag' => Icons.flag,
      'terrain' => Icons.terrain,
      'workspace' => Icons.workspace_premium,
      'person_add' => Icons.person_add,
      'groups' => Icons.groups,
      'diversity' => Icons.diversity_3,
      'group_work' => Icons.group_work,
      'hub' => Icons.hub,
      'photo' => Icons.photo_camera,
      'camera' => Icons.camera_alt,
      'collections' => Icons.collections,
      'photo_album' => Icons.photo_album,
      'camera_alt' => Icons.camera,
      'route' => Icons.route,
      'travel' => Icons.travel_explore,
      'flight' => Icons.flight_takeoff,
      'comment' => Icons.comment,
      'forum' => Icons.forum,
      'reviews' => Icons.rate_review,
      'level' => Icons.military_tech,
      'trophy' => Icons.emoji_events,
      _ => Icons.place,
    };
