import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../../achievements/domain/achievement_model.dart';
import '../../achievements/presentation/achievement_icons.dart';
import '../providers/profile_journey_stats_provider.dart';
import 'profile_forest_art.dart';
import 'traveler_profile_header.dart' show TravelerCounter, TravelerCounterTile;

/// Phase 3.1 -- Premium Forest building blocks of the traveler profile.
/// Colours, radii and spacing come only from `app_design.dart`.

const double _kMinTap = AppSizes.touchTarget;

/// The card decoration of the Premium Forest profile (shared with the other
/// profile files so no second copy of it exists).
BoxDecoration premiumCardDecoration({Color? color, Color? border}) =>
    BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      border: Border.all(color: border ?? AppColors.border),
    );

/// Section title with an optional "Усі →" link on the right.
class PremiumSectionHeader extends StatelessWidget {
  const PremiumSectionHeader({
    required this.title,
    this.trailing,
    this.onAll,
    this.allKey,
    super.key,
  });

  final String title;

  /// A small secondary text before the link (e.g. "2 із 35").
  final String? trailing;
  final VoidCallback? onAll;
  final Key? allKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs, AppSpacing.sm, AppSpacing.xs, AppSpacing.xs),
      child: Row(children: [
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium),
        ),
        if (trailing != null)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: Text(trailing!, style: theme.textTheme.labelMedium),
          ),
        if (onAll != null)
          TextButton(
            key: allKey,
            onPressed: onAll,
            style: TextButton.styleFrom(
              minimumSize:
                  const Size(AppSizes.touchTarget, AppSizes.touchTarget),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Усі →', semanticsLabel: 'Усі: $title'),
          ),
      ]),
    );
  }
}

/// One statistic tile: gold icon, the value, then the label. [value] is already
/// a display string; [caption] is an optional extra line.
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
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.md),
      decoration: premiumCardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: AppColors.accent),
          const SizedBox(height: AppSpacing.xs),
          if (loading)
            const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent))
          else
            Text(value,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: AppColors.textPrimary, height: 1.1)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium),
          if (caption != null)
            Text(caption!,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// A row of equal-height [PremiumStatTile]s (no fixed heights, so a larger
/// system font only makes the tiles taller).
class PremiumStatsRow extends StatelessWidget {
  const PremiumStatsRow({required this.tiles, super.key});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: tiles[i]),
          ],
        ]),
      );
}

/// The compact "Стежать / Стежу" strip: two real counters. It is deliberately
/// NOT tappable: there are no followers / following lists yet, and the friends
/// screen is a different thing (mutual friendships), so it must not be offered
/// as their destination. Each half keeps the stable `profile_counter_<keyName>`
/// key; a loading / unavailable value is a spinner / an em dash, never a
/// made-up zero. Read out as one sentence by screen readers.
class PremiumFollowRow extends StatelessWidget {
  const PremiumFollowRow({
    required this.followers,
    required this.following,
    super.key,
  });

  final TravelerCounter followers;
  final TravelerCounter following;

  static String _spoken(TravelerCounter c) => c.loading
      ? 'завантаження'
      : c.value == null
          ? 'недоступно'
          : '${c.value}';

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '${followers.label}: ${_spoken(followers)}. '
            '${following.label}: ${_spoken(following)}.',
        child: ExcludeSemantics(
          child: Container(
            key: const Key('profile_follow_row'),
            decoration: premiumCardDecoration(),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(children: [
              Expanded(child: TravelerCounterTile(counter: followers)),
              Container(width: 1, height: 36, color: AppColors.border),
              Expanded(child: TravelerCounterTile(counter: following)),
            ]),
          ),
        ),
      );
}

/// The "Локації" tile: the EXACT number of the user's own locations (the same
/// count query "Мої місця" uses). Loading and error never invent a number.
({String value, bool loading}) createdTileText(AsyncValue<int> state) {
  return state.when(
    loading: () => (value: '', loading: true),
    error: (_, __) => (value: '—', loading: false),
    data: (count) => (value: '$count', loading: false),
  );
}

/// Text for the Journey tile from the loader state. Empty and error never
/// invent a number.
({String value, String? caption, bool loading}) journeyTileText(
    AsyncValue<ProfileJourneyStats> state) {
  return state.when(
    loading: () => (value: '', caption: null, loading: true),
    error: (_, __) => (value: '—', caption: 'Недоступно', loading: false),
    data: (stats) => stats.count == 0
        ? (value: '0', caption: 'Ще немає подорожей', loading: false)
        : (value: '${stats.count}', caption: null, loading: false),
  );
}

/// Text for the distance tile: the CONFIRMED distance of all finished
/// Journeys. Loading and error never invent a number.
({String value, bool loading}) distanceTileText(
    AsyncValue<ProfileJourneyStats> state, String Function(double) distance) {
  return state.when(
    loading: () => (value: '', loading: true),
    error: (_, __) => (value: '—', loading: false),
    data: (stats) =>
        (value: distance(stats.confirmedDistanceMeters), loading: false),
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
            decoration: premiumCardDecoration(),
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

/// Compact horizontal strip of REAL unlocked achievements (hexagonal gold
/// medals) plus progress. [unlocked] == null means the list is not available
/// (loading, error, or only the counters are known): no medals are invented in
/// that case. Locked achievements are not shown here.
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
            Semantics(
              label: 'Нагорода: ${a.name}',
              excludeSemantics: true,
              child: Container(
                width: 84,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                child: Column(children: [
                  HexMedal(
                    icon: achievementIconFor(a.icon),
                    iconKey: Key('profile_medal_icon_${a.key}'),
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
            ),
        ]),
      );
    } else {
      body = const SizedBox(height: AppSpacing.xs);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PremiumSectionHeader(
          title: 'Досягнення',
          trailing: progress == null
              ? null
              : '${progress!.unlocked} із ${progress!.total}',
          onAll: onOpenAll,
          allKey: const Key('profile_action_achievements'),
        ),
        Container(
          width: double.infinity,
          decoration: premiumCardDecoration(),
          child: body,
        ),
      ],
    );
  }
}
