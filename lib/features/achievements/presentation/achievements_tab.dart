import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/achievement_model.dart';
import '../providers/achievements_provider.dart';

class AchievementsTab extends ConsumerWidget {
  const AchievementsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(achievementsProvider);
    return value.when(
      data: (items) {
        final unlocked = items.where((item) => item.isUnlocked).length;
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(achievementsProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: _ProgressHeader(
                    unlocked: unlocked,
                    total: items.length,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => _AchievementCard(items[index]),
                    childCount: items.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        MediaQuery.sizeOf(context).width < 520 ? 1 : 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent:
                        MediaQuery.textScalerOf(context).scale(1) > 1.2
                            ? 218
                            : 190,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FilledButton.icon(
            onPressed: () => ref.invalidate(achievementsProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Не вдалося завантажити досягнення'),
          ),
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.unlocked, required this.total});

  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : unlocked / total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF142416),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Досягнення $unlocked / $total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '${(fraction * 100).round()}%',
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            borderRadius: BorderRadius.circular(99),
            backgroundColor: Colors.white12,
            color: Colors.amber,
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard(this.achievement);

  final AchievementModel achievement;

  @override
  Widget build(BuildContext context) {
    final unlocked = achievement.isUnlocked;
    return Card(
      color: unlocked ? const Color(0xFF203E20) : const Color(0xFF121C13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color:
              unlocked ? Colors.amber.withValues(alpha: 0.8) : Colors.white10,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor:
                      unlocked ? Colors.amber : Colors.grey.shade800,
                  child: Icon(
                    _iconFor(achievement.icon),
                    size: 27,
                    color: unlocked ? Colors.black : Colors.grey.shade500,
                  ),
                ),
                if (!unlocked)
                  const CircleAvatar(
                    radius: 11,
                    backgroundColor: Color(0xFF0A120A),
                    child: Icon(Icons.lock, size: 13, color: Colors.white54),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    achievement.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: unlocked ? Colors.amber : Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    achievement.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const Spacer(),
                  if (unlocked)
                    const Row(children: [
                      Icon(Icons.check_circle,
                          size: 15, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text('Розблоковано',
                          style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ])
                  else ...[
                    Text(
                      achievement.unlockCondition,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: achievement.progressFraction,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(99),
                      backgroundColor: Colors.white10,
                      color: Colors.amber,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${achievement.progress.toStringAsFixed(0)} / '
                      '${achievement.target.toStringAsFixed(0)}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String icon) => switch (icon) {
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
}
