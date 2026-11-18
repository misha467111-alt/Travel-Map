import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../../achievements/domain/achievement_model.dart';
import '../../achievements/presentation/achievement_icons.dart';
import '../providers/profile_journey_stats_provider.dart';

/// Phase 3.1 -- Premium Forest building blocks of the traveler profile.
/// Colours, radii and spacing come only from `app_design.dart`.

const double _kMinTap = AppSizes.touchTarget;

BoxDecoration _cardDecoration({Color? color, Color? border}) => BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      border: Border.all(color: border ?? AppColors.border),
    );

/// One statistic tile. [value] is already a display string; [caption] is an
/// optional second line (e.g. the confirmed distance).
class PremiumStatTile extends StatelessWidget {
  const PremiumStatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium),
            ),
          ]),
          const SizedBox(height: AppSpacing.xs),
          if (loading)
            const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent))
          else
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: AppColors.accent)),
          if (caption != null)
            Text(caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// Two-column grid of [PremiumStatTile]s (equal-height rows, no fixed heights, so a
/// larger system font only makes the tiles taller).
class PremiumStatsGrid extends StatelessWidget {
  const PremiumStatsGrid({required this.tiles, super.key});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final last = i + 1 >= tiles.length;
      // An odd last tile spans the full width instead of leaving a gap.
      rows.add(last
          ? tiles[i]
          : IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tiles[i]),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: tiles[i + 1]),
                  ]),
            ));
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: AppSpacing.sm));
    }
    return Column(children: rows);
  }
}

/// Text for the Journey tile from the loader state. Empty and error never
/// invent a number.
({String value, String? caption, bool loading}) journeyTileText(
    AsyncValue<ProfileJourneyStats> state, String Function(double) distance) {
  return state.when(
    loading: () => (value: '', caption: null, loading: true),
    error: (_, __) => (value: '—', caption: 'Недоступно', loading: false),
    data: (stats) => stats.count == 0
        ? (value: '0', caption: 'Ще немає подорожей', loading: false)
        : (
            value: '${stats.count}',
            caption: distance(stats.confirmedDistanceMeters),
            loading: false
          ),
  );
}

/// A titled card of tappable rows (the same `ListTile` rows with the stable
/// `profile_action_*` keys the app already used).
class PremiumActionCard extends StatelessWidget {
  const PremiumActionCard({
    required this.title,
    required this.rows,
    super.key,
  });

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.xs),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Container(
            decoration: _cardDecoration(),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1,
                        indent: AppSpacing.lg + 32,
                        color: AppColors.border),
                  rows[i],
                ],
              ]),
            ),
          ),
        ],
      );
}

/// One tappable row of a [PremiumActionCard].
class PremiumActionRow extends StatelessWidget {
  const PremiumActionRow({
    required this.destination,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    super.key,
  });

  final String destination;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        key: Key('profile_action_$destination'),
        minTileHeight: _kMinTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        leading: Icon(icon,
            color: destructive ? Colors.redAccent : AppColors.accent),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                destructive ? const TextStyle(color: Colors.redAccent) : null),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: destructive
            ? null
            : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () => onTap(destination),
      );
}

/// Compact horizontal strip of REAL unlocked achievements plus progress.
/// [unlocked] == null means the list is not available (loading, error, or only
/// the counters are known): no medals are invented in that case.
class PremiumAchievementsStrip extends StatelessWidget {
  const PremiumAchievementsStrip({
    required this.progress,
    required this.unlocked,
    required this.loading,
    required this.failed,
    required this.onOpenAll,
    super.key,
  });

  final ({int unlocked, int total})? progress;
  final List<AchievementModel>? unlocked;
  final bool loading;
  final bool failed;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medals = unlocked;
    Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(
            child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent))),
      );
    } else if (failed) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('Не вдалося завантажити досягнення',
            key: const Key('profile_achievements_error'),
            style: theme.textTheme.bodySmall),
      );
    } else if (medals != null && medals.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('Нагород ще немає — перша чекає на вас',
            key: const Key('profile_achievements_empty'),
            style: theme.textTheme.bodySmall),
      );
    } else if (medals != null) {
      body = SingleChildScrollView(
        key: const Key('profile_achievements_strip'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final a in medals)
            Container(
              width: 84,
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              child: Column(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentTint(0.2),
                    border: Border.all(color: AppColors.accent, width: 1.5),
                  ),
                  child: Icon(achievementIconFor(a.icon),
                      key: Key('profile_medal_icon_${a.key}'),
                      color: AppColors.accent,
                      size: 24),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(a.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.textPrimary)),
              ]),
            ),
        ]),
      );
    } else {
      body = const SizedBox(height: AppSpacing.xs);
    }

    return PremiumActionCard(
      title: 'Досягнення',
      rows: [
        body,
        PremiumActionRow(
          destination: 'achievements',
          icon: Icons.emoji_events_outlined,
          title: 'Усі досягнення',
          subtitle: progress == null
              ? null
              : '${progress!.unlocked} із ${progress!.total}',
          onTap: (_) => onOpenAll(),
        ),
      ],
    );
  }
}
