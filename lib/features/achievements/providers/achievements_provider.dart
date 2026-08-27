import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/achievement_model.dart';

class AchievementsRepository {
  const AchievementsRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<AchievementModel>> fetchAchievements() async {
    final rows = await _supabase.rpc<List<dynamic>>('get_achievement_progress');

    return rows.map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return AchievementModel(
        key: row['achievement_key']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        description: row['description']?.toString() ?? '',
        icon: row['icon']?.toString() ?? 'place',
        unlockCondition: row['unlock_condition']?.toString() ?? '',
        category: row['category']?.toString() ?? 'Інше',
        progress: (row['progress'] as num? ?? 0).toDouble(),
        target: (row['target'] as num? ?? 1).toDouble(),
        isUnlocked: row['is_unlocked'] == true,
        unlockedAt: row['unlocked_at'] == null
            ? null
            : DateTime.tryParse(row['unlocked_at'].toString()),
      );
    }).toList(growable: false);
  }
}

final achievementsRepositoryProvider = Provider<AchievementsRepository>((ref) {
  return AchievementsRepository(Supabase.instance.client);
});

final achievementsProvider =
    FutureProvider.autoDispose<List<AchievementModel>>((ref) {
  return ref.watch(achievementsRepositoryProvider).fetchAchievements();
});
