import 'package:flutter/material.dart';

import '../../../core/theme/app_design.dart';
import '../domain/xp_levels.dart';
import 'profile_forest_art.dart';

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

/// The shared "Premium Forest" hero of a traveler profile -- used by the
/// signed-in user's own profile and by another user's public profile: a
/// procedural forest skyline, the avatar in a gold ring, name, rank, level and
/// the XP progress.
///
/// Own profile passes [onAvatarTap] / [nameAction] / [subtitle] (e-mail) and no
/// [counters] (its statistics are separate tiles); a public profile passes none
/// of the former and may pass [counters] and an [action] (follow button).
/// Everything shown is real data supplied by the caller.
class TravelerProfileHeader extends StatelessWidget {
  const TravelerProfileHeader({
    required this.name,
    required this.level,
    required this.xp,
    this.counters = const [],
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
      clipBehavior: Clip.antiAlias,
      // The 1 px gold border is drawn ABOVE the artwork (a foreground
      // decoration) so the artwork can never cover it, corners included. It is
      // the former 45 % gold over the hero colour, pre-blended to be opaque, so
      // it looks exactly as before. The 1 px padding keeps the old inset.
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
            color: Color.alphaBlend(
                AppColors.accent.withValues(alpha: 0.45), AppColors.elevated)),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: ForestHeroBackground()),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Avatar(
                        hasAvatar: hasAvatar,
                        avatarUrl: avatarUrl,
                        onAvatarTap: onAvatarTap),
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
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(height: 1.1),
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
                              // Over the artwork, so lighter than the usual
                              // secondary text: >= 4.5:1 at every width (see
                              // the hero test).
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textPrimary
                                      .withValues(alpha: 0.9)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                // A glass panel keeps the text readable over the artwork.
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (counters.isNotEmpty) ...[
                        _CountersRow(counters: counters),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Container(
                        key: const Key('profile_xp_progress'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              // Flexible: on a very narrow screen the pill
                              // shortens instead of overflowing the row.
                              Flexible(
                                  child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accentTint(0.18),
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.pill),
                                  border: Border.all(
                                      color: AppColors.accent
                                          .withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.workspace_premium,
                                          color: AppColors.accent, size: 16),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text('Рівень $tier',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                    color: AppColors.accent,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                      ),
                                    ]),
                              )),
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
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                              child: LinearProgressIndicator(
                                value: xpProgressWithinLevel(xp),
                                minHeight: 10,
                                color: AppColors.accent,
                                backgroundColor: AppColors.border,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            if (nextXp != null) ...[
                              Text('$xp / $nextXp XP',
                                  style: theme.textTheme.labelMedium),
                              Text('До наступного рівня: ${nextXp - xp} XP',
                                  style: theme.textTheme.labelSmall),
                            ] else
                              Text('Максимальний рівень досягнуто',
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(color: AppColors.accent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(width: double.infinity, child: action),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatefulWidget {
  const _Avatar({
    required this.hasAvatar,
    required this.avatarUrl,
    required this.onAvatarTap,
  });

  final bool hasAvatar;
  final String? avatarUrl;
  final VoidCallback? onAvatarTap;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  /// The picture could not be loaded: show the same fallback as for no avatar.
  bool _failed = false;

  @override
  void didUpdateWidget(_Avatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) _failed = false;
  }

  @override
  Widget build(BuildContext context) {
    final showImage = widget.hasAvatar && !_failed;
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.background,
            border: Border.all(color: AppColors.accent, width: 2),
            boxShadow: [
              BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.25),
                  blurRadius: 14),
            ],
          ),
          child: CircleAvatar(
            key: const Key('profile_avatar'),
            radius: 42,
            backgroundColor: AppColors.surface,
            backgroundImage: showImage ? NetworkImage(widget.avatarUrl!) : null,
            onBackgroundImageError: showImage
                ? (_, __) {
                    if (mounted) setState(() => _failed = true);
                  }
                : null,
            child: showImage
                ? null
                : const Icon(Icons.person,
                    key: Key('profile_avatar_fallback'),
                    size: 40,
                    color: AppColors.accent),
          ),
        ),
        if (widget.onAvatarTap != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: AppColors.accent,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Змінити аватар',
                onPressed: widget.onAvatarTap,
                icon: const Icon(Icons.camera_alt, color: AppColors.onAccent),
                iconSize: 15,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 28, height: 28),
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
    );
  }
}

/// One counter: the value (a spinner while loading, an em dash when it is not
/// available -- never a made-up zero) above its label. Keyed
/// `profile_counter_<keyName>`. Shared by the hero (public profile) and the
/// own profile's follow strip.
class TravelerCounterTile extends StatelessWidget {
  const TravelerCounterTile({required this.counter, super.key});

  final TravelerCounter counter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: Key('profile_counter_${counter.keyName}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 28,
          child: Center(
            child: counter.loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent))
                : Text(counter.value == null ? '—' : '${counter.value}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: AppColors.textPrimary)),
          ),
        ),
        Text(counter.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium),
      ],
    );
  }
}

class _CountersRow extends StatelessWidget {
  const _CountersRow({required this.counters});

  final List<TravelerCounter> counters;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < counters.length; i++) ...[
          if (i > 0) Container(width: 1, height: 32, color: AppColors.border),
          Expanded(child: TravelerCounterTile(counter: counters[i])),
        ],
      ]);
}
