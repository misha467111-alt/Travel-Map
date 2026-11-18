import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import '../domain/xp_levels.dart';

/// One counter of the profile header ("Локації", "Стежать", "Стежу").
///
/// [value] `null` means "not available (yet)": a spinner while [loading],
/// otherwise an em dash. Never a made-up zero.
class TravelerCounter {
  const TravelerCounter({
    required this.keyName,
    required this.label,
    required this.value,
    this.loading = false,
  });

  /// Stable suffix of the widget key: `profile_counter_<keyName>`.
  final String keyName;
  final String label;
  final int? value;
  final bool loading;
}

/// The shared, Instagram-style top of a traveler profile -- used by the
/// signed-in user's own profile and by another user's public profile.
///
/// Own profile passes [onAvatarTap] / [nameAction] / [subtitle] (e-mail); a
/// public profile passes none of them and may pass an [action] (follow
/// button). Everything shown is real data supplied by the caller.
class TravelerProfileHeader extends StatelessWidget {
  const TravelerProfileHeader({
    required this.name,
    required this.level,
    required this.xp,
    required this.counters,
    this.subtitle,
    this.avatarUrl,
    this.onAvatarTap,
    this.nameAction,
    this.action,
    super.key,
  });

  final String name;
  final String? subtitle;
  final String level;
  final int xp;
  final String? avatarUrl;
  final List<TravelerCounter> counters;
  final VoidCallback? onAvatarTap;
  final Widget? nameAction;

  /// Full-width action under the counters (e.g. "Стежити").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextXp = xpNextLevelThreshold(xp);
    final tier = xpLevelTier(xp);
    final hasAvatar = avatarUrl?.isNotEmpty == true;
    return Container(
      key: const Key('traveler_profile_header'),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent, width: 2),
                    ),
                    child: CircleAvatar(
                      key: const Key('profile_avatar'),
                      radius: 42,
                      backgroundColor: AppColors.surface,
                      backgroundImage:
                          hasAvatar ? NetworkImage(avatarUrl!) : null,
                      child: hasAvatar
                          ? null
                          : const Icon(Icons.person,
                              key: Key('profile_avatar_fallback'),
                              size: 40,
                              color: AppColors.accent),
                    ),
                  ),
                  if (onAvatarTap != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: AppColors.accent,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Змінити аватар',
                          onPressed: onAvatarTap,
                          icon: const Icon(Icons.camera_alt,
                              color: AppColors.onAccent),
                          iconSize: 15,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 28, height: 28),
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(28),
                            maximumSize: const Size.square(28),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          name,
                          key: const Key('profile_display_name'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              theme.textTheme.titleLarge?.copyWith(height: 1.1),
                        ),
                      ),
                      if (nameAction != null) nameAction!,
                    ]),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        key: const Key('profile_subtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _CountersRow(counters: counters),
          const SizedBox(height: AppSpacing.lg),
          Container(
            key: const Key('profile_xp_progress'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentTint(0.18),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.5)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.workspace_premium,
                          color: AppColors.accent, size: 16),
                      const SizedBox(width: 4),
                      Text('Рівень $tier',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(level,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall),
                  ),
                  Text('$xp XP',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: AppColors.accent)),
                ]),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: xpProgressWithinLevel(xp),
                    minHeight: 10,
                    color: AppColors.accent,
                    backgroundColor: AppColors.border,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (nextXp != null) ...[
                  Text('$xp / $nextXp XP', style: theme.textTheme.labelMedium),
                  Text('До наступного рівня: ${nextXp - xp} XP',
                      style: theme.textTheme.labelSmall),
                ] else
                  Text('Максимальний рівень досягнуто',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.accent)),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(width: double.infinity, child: action),
          ],
        ],
      ),
    );
  }
}

class _CountersRow extends StatelessWidget {
  const _CountersRow({required this.counters});

  final List<TravelerCounter> counters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      for (var i = 0; i < counters.length; i++) ...[
        if (i > 0) Container(width: 1, height: 32, color: AppColors.border),
        Expanded(
          child: Column(
            key: Key('profile_counter_${counters[i].keyName}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 28,
                child: Center(
                  child: counters[i].loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent))
                      : Text(
                          counters[i].value == null
                              ? '—'
                              : '${counters[i].value}',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: AppColors.textPrimary)),
                ),
              ),
              Text(counters[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ],
    ]);
  }
}
