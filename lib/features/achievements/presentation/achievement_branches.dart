import 'package:flutter/material.dart';

import '../domain/achievement_model.dart';

/// One branch of the achievements tree = one real `category` of
/// `achievement_definitions`, with its awards in `sort_order`.
///
/// The server has NO dependencies between awards: the line between two nodes
/// only shows the order of progress; it is not an unlock rule.
class AchievementBranch {
  const AchievementBranch({required this.category, required this.nodes});

  final String category;

  /// Awards of this branch in `sort_order` (ties keep the RPC order); no
  /// duplicates.
  final List<AchievementModel> nodes;

  int get total => nodes.length;
  int get unlocked => nodes.where((n) => n.isUnlocked).length;
  bool get isComplete => total > 0 && unlocked == total;
  double get fraction => total == 0 ? 0 : unlocked / total;

  /// The first locked award in order, or `null` for a finished branch.
  AchievementModel? get nextTarget {
    for (final node in nodes) {
      if (!node.isUnlocked) return node;
    }
    return null;
  }
}

/// Groups [items] into branches by their real `category`. Branches appear in
/// the order of their smallest `sort_order` (the server's own order); an award
/// repeated by `key` is shown once, at its first position, and keeps the best
/// known state (unlocked beats locked, then the larger progress), so a
/// duplicate row can never turn an unlocked award back into a locked one.
List<AchievementBranch> buildAchievementBranches(List<AchievementModel> items) {
  final best = <String, AchievementModel>{};
  final firstIndex = <String, int>{};
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final known = best[item.key];
    if (known == null) {
      best[item.key] = item;
      firstIndex[item.key] = i;
    } else if (_better(item, known)) {
      best[item.key] = item;
    }
  }
  final byCategory = <String, List<(int, AchievementModel)>>{};
  for (final entry in best.entries) {
    final item = entry.value;
    (byCategory[item.category] ??= []).add((firstIndex[entry.key]!, item));
  }
  final branches = <AchievementBranch>[];
  for (final entry in byCategory.entries) {
    final list = entry.value
      ..sort((a, b) {
        final bySort = a.$2.sortOrder.compareTo(b.$2.sortOrder);
        return bySort != 0 ? bySort : a.$1.compareTo(b.$1);
      });
    branches.add(AchievementBranch(
        category: entry.key, nodes: [for (final e in list) e.$2]));
  }
  branches.sort((a, b) {
    final bySort = a.nodes.first.sortOrder.compareTo(b.nodes.first.sortOrder);
    return bySort != 0 ? bySort : a.category.compareTo(b.category);
  });
  return branches;
}

bool _better(AchievementModel a, AchievementModel b) {
  if (a.isUnlocked != b.isUnlocked) return a.isUnlocked;
  return a.progress > b.progress;
}

/// Icon of a branch. Known real categories get their own icon; an unknown one
/// falls back to a trophy.
IconData branchIconFor(String category) => switch (category) {
      'Локації' => Icons.place,
      'Відвідування' => Icons.flag,
      'Соціальне' => Icons.people,
      'Фото' => Icons.photo_camera,
      'Відстань' => Icons.straighten,
      'Спільнота' => Icons.forum,
      'Рівні' => Icons.military_tech,
      _ => Icons.emoji_events,
    };
