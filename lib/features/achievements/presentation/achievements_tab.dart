import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../domain/achievement_model.dart';
import '../providers/achievements_provider.dart';
import 'achievement_icons.dart';

/// "Мої досягнення" -- Premium Forest. Data, RPC (`get_achievement_progress`)
/// and unlock rules are server-side and unchanged; this only presents them.
/// Unlocked awards come first (the server order is otherwise kept), locked
/// ones are muted and show real progress.
class AchievementsTab extends ConsumerWidget {
  const AchievementsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(achievementsProvider);
    return value.when(
      data: (items) => items.isEmpty
          ? _CenteredMessage(
              key: const Key('achievements_empty'),
              icon: Icons.emoji_events_outlined,
              text: 'Досягнень поки немає',
              actionLabel: 'Оновити',
              onAction: () => ref.invalidate(achievementsProvider),
            )
          : AchievementsList(
              items: items,
              onRefresh: () async => ref.invalidate(achievementsProvider),
            ),
      loading: () => const Center(
        child: CircularProgressIndicator(
            key: Key('achievements_loading'), color: AppColors.accent),
      ),
      error: (error, _) => _CenteredMessage(
        key: const Key('achievements_error'),
        icon: Icons.cloud_off_outlined,
        text: 'Не вдалося завантажити досягнення',
        hint: 'Перевірте з’єднання та спробуйте ще раз.',
        actionLabel: 'Повторити',
        onAction: () => ref.invalidate(achievementsProvider),
      ),
    );
  }
}

/// The scrollable collection for an already-loaded list (stateless: tests and
/// the screen share it).
class AchievementsList extends StatelessWidget {
  const AchievementsList({required this.items, this.onRefresh, super.key});

  final List<AchievementModel> items;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final unlocked = items.where((item) => item.isUnlocked).length;
    // Stable: unlocked first, server order otherwise preserved.
    final ordered = [
      ...items.where((a) => a.isUnlocked),
      ...items.where((a) => !a.isUnlocked),
    ];
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _Centered(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child:
                  AchievementsHeader(unlocked: unlocked, total: items.length),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: ordered.length,
          itemBuilder: (_, i) => _Centered(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xs),
              child: AchievementCard(ordered[i]),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
    return onRefresh == null
        ? scroll
        : RefreshIndicator(
            color: AppColors.accent, onRefresh: onRefresh!, child: scroll);
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
          child: child,
        ),
      );
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.hint,
    super.key,
  });

  final IconData icon;
  final String text;
  final String? hint;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.accent),
            const SizedBox(height: AppSpacing.md),
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(hint!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Мої досягнення", X із N and the gold overall progress bar.
class AchievementsHeader extends StatelessWidget {
  const AchievementsHeader(
      {required this.unlocked, required this.total, super.key});

  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total == 0 ? 0.0 : unlocked / total;
    return Container(
      key: const Key('achievements_header'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.emoji_events, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('Мої досягнення', style: theme.textTheme.titleLarge),
            ),
            Text('${(fraction * 100).round()}%',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: AppColors.accent)),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text('Відкрито $unlocked із $total',
              key: const Key('achievements_count'),
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              key: const Key('achievements_progress'),
              value: fraction,
              minHeight: 10,
              backgroundColor: AppColors.border,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// One award: a gold medal when unlocked, a muted one with real progress when
/// locked.
class AchievementCard extends StatelessWidget {
  const AchievementCard(this.achievement, {super.key});

  final AchievementModel achievement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = achievement;
    final unlocked = a.isUnlocked;
    final at = a.unlockedAt;
    return Container(
      key: Key('achievement_${a.key}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: unlocked ? AppColors.elevated : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
            color: unlocked
                ? AppColors.accent.withValues(alpha: 0.7)
                : AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unlocked
                      ? AppColors.accent
                      : AppColors.border.withValues(alpha: 0.6),
                ),
                child: Icon(achievementIconFor(a.icon),
                    key: Key('achievement_icon_${a.key}'),
                    size: 27,
                    color: unlocked
                        ? AppColors.onAccent
                        : AppColors.textSecondary),
              ),
              if (!unlocked)
                const CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.background,
                  child: Icon(Icons.lock,
                      size: 12, color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: unlocked
                            ? AppColors.accent
                            : AppColors.textPrimary)),
                const SizedBox(height: AppSpacing.xs),
                Text(a.description,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
                if (unlocked)
                  Row(children: [
                    const Icon(Icons.check_circle,
                        size: 15, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                          at == null
                              ? 'Розблоковано'
                              : 'Розблоковано ${_date(at.toLocal())}',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600)),
                    ),
                  ])
                else ...[
                  Text(a.unlockCondition, style: theme.textTheme.labelSmall),
                  if (a.target > 0) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      child: LinearProgressIndicator(
                        key: Key('achievement_progress_${a.key}'),
                        value: a.progressFraction,
                        minHeight: 6,
                        backgroundColor: AppColors.border,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                        '${a.progress.toStringAsFixed(0)} / '
                        '${a.target.toStringAsFixed(0)}',
                        style: theme.textTheme.labelMedium),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
