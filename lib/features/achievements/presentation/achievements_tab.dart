import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../domain/achievement_model.dart';
import '../providers/achievements_provider.dart';
import 'achievement_branches.dart';
import 'achievement_icons.dart';

/// "Мої досягнення" -- Premium Forest, as a tree of branches (one per real
/// category). Data, RPC (`get_achievement_progress`) and unlock rules are
/// server-side and unchanged; this only presents them. There are NO
/// dependencies between awards on the server: a line between two nodes shows
/// the order of progress, never an unlock rule.
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

/// The scrollable tree for an already-loaded list. [expandAll] opens every
/// branch (tests / previews); by default the branches that are in progress are
/// open, or the first one when none is.
class AchievementsList extends StatefulWidget {
  const AchievementsList({
    required this.items,
    this.onRefresh,
    this.expandAll = false,
    super.key,
  });

  final List<AchievementModel> items;
  final Future<void> Function()? onRefresh;
  final bool expandAll;

  @override
  State<AchievementsList> createState() => _AchievementsListState();
}

class _AchievementsListState extends State<AchievementsList> {
  late List<AchievementBranch> _branches;
  final Set<String> _expanded = <String>{};
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _branches = buildAchievementBranches(widget.items);
    _initExpansion();
  }

  @override
  void didUpdateWidget(covariant AchievementsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      _branches = buildAchievementBranches(widget.items);
      if (!_initialised) _initExpansion();
    }
  }

  void _initExpansion() {
    if (_branches.isEmpty) return;
    _initialised = true;
    if (widget.expandAll) {
      _expanded.addAll(_branches.map((b) => b.category));
      return;
    }
    final active = _branches.where((b) => b.unlocked > 0 && !b.isComplete);
    if (active.isNotEmpty) {
      _expanded.addAll(active.map((b) => b.category));
    } else {
      _expanded.add(_branches.first.category);
    }
  }

  void _toggle(String category) => setState(() {
        if (!_expanded.remove(category)) _expanded.add(category);
      });

  @override
  Widget build(BuildContext context) {
    final unlocked = widget.items.where((item) => item.isUnlocked).length;
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _Centered(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: AchievementsHeader(
                  unlocked: unlocked, total: widget.items.length),
            ),
          ),
        ),
        SliverList.builder(
          itemCount: _branches.length,
          itemBuilder: (_, i) => _Centered(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xs),
              child: _BranchCard(
                branch: _branches[i],
                expanded: _expanded.contains(_branches[i].category),
                onToggle: () => _toggle(_branches[i].category),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
    return widget.onRefresh == null
        ? scroll
        : RefreshIndicator(
            color: AppColors.accent,
            onRefresh: widget.onRefresh!,
            child: scroll);
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

String _num(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

/// One branch: icon, name, X / Y, progress, and (expanded) its tree.
class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.expanded,
    required this.onToggle,
  });

  final AchievementBranch branch;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = branch.category;
    final next = branch.nextTarget;
    return Container(
      key: Key('achievement_branch_$c'),
      decoration: BoxDecoration(
        color: branch.unlocked > 0 ? AppColors.elevated : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
            color: branch.isComplete
                ? AppColors.accent
                : branch.unlocked > 0
                    ? AppColors.accent.withValues(alpha: 0.45)
                    : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: Key('achievement_branch_toggle_$c'),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: AppSizes.touchTarget),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: branch.unlocked > 0
                          ? AppColors.accentTint(0.2)
                          : AppColors.border.withValues(alpha: 0.5),
                      border: Border.all(
                          color: branch.unlocked > 0
                              ? AppColors.accent
                              : AppColors.border),
                    ),
                    child: Icon(branchIconFor(c),
                        color: branch.unlocked > 0
                            ? AppColors.accent
                            : AppColors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child:
                                  Text(c, style: theme.textTheme.titleMedium)),
                          if (branch.isComplete)
                            const Padding(
                              padding: EdgeInsets.only(right: AppSpacing.xs),
                              child: Icon(Icons.verified,
                                  key: Key('achievement_branch_complete'),
                                  size: 18,
                                  color: AppColors.accent),
                            ),
                          Text('${branch.unlocked} / ${branch.total}',
                              key: Key('achievement_branch_count_$c'),
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(color: AppColors.accent)),
                        ]),
                        const SizedBox(height: AppSpacing.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          child: LinearProgressIndicator(
                            key: Key('achievement_branch_progress_$c'),
                            value: branch.fraction,
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            color: AppColors.accent,
                          ),
                        ),
                        if (!expanded && next != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text('Далі: ${next.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more,
                        color: AppColors.textSecondary),
                  ),
                ]),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                    child: Column(children: [
                      for (var i = 0; i < branch.nodes.length; i++)
                        _TreeNode(
                          node: branch.nodes[i],
                          previous: i > 0 ? branch.nodes[i - 1] : null,
                          next: i + 1 < branch.nodes.length
                              ? branch.nodes[i + 1]
                              : null,
                          isNextTarget:
                              identical(branch.nextTarget, branch.nodes[i]),
                        ),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// One node of a branch: the connector line (progress order only), the medal
/// and a tappable summary that opens the details.
class _TreeNode extends StatelessWidget {
  const _TreeNode({
    required this.node,
    required this.previous,
    required this.next,
    required this.isNextTarget,
  });

  final AchievementModel node;
  final AchievementModel? previous;
  final AchievementModel? next;
  final bool isNextTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = node;
    final unlocked = a.isUnlocked;
    final at = a.unlockedAt;
    // A segment is gold once the node it leads to has been reached.
    final lineAbove = unlocked ? AppColors.accent : AppColors.border;
    final lineBelow =
        (next?.isUnlocked ?? false) ? AppColors.accent : AppColors.border;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 48,
          child: Column(children: [
            Container(
                width: 2,
                height: 8,
                color: previous == null ? Colors.transparent : lineAbove),
            Container(
              key: Key('achievement_node_${a.key}'),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: unlocked
                    ? AppColors.accent
                    : AppColors.border.withValues(alpha: 0.6),
                border: isNextTarget
                    ? Border.all(color: AppColors.accent, width: 2)
                    : null,
              ),
              child: Icon(
                unlocked ? achievementIconFor(a.icon) : Icons.lock_outline,
                key: Key('achievement_icon_${a.key}'),
                size: 22,
                color: unlocked ? AppColors.onAccent : AppColors.textSecondary,
              ),
            ),
            Expanded(
              child: Container(
                  width: 2,
                  color: next == null ? Colors.transparent : lineBelow),
            ),
          ]),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: InkWell(
              key: Key('achievement_${a.key}'),
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () => showAchievementDetails(context, a),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: AppSizes.touchTarget),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: unlocked
                                  ? AppColors.accent
                                  : AppColors.textPrimary)),
                      if (isNextTarget)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Наступна ціль',
                              key: Key('achievement_next_${a.key}'),
                              style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(height: 2),
                      if (unlocked)
                        Text(
                            at == null
                                ? 'Розблоковано'
                                : 'Розблоковано ${_date(at.toLocal())}',
                            style: theme.textTheme.labelSmall)
                      else if (a.target > 0) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          child: LinearProgressIndicator(
                            key: Key('achievement_progress_${a.key}'),
                            value: a.progressFraction,
                            minHeight: 5,
                            backgroundColor: AppColors.border,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('${_num(a.progress)} / ${_num(a.target)}',
                            style: theme.textTheme.labelSmall),
                      ] else
                        Text('Прогрес недоступний',
                            style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Details of one award: real name, description, progress and threshold and
/// the unlock date. Only server data is shown (the RPC has no XP per award, so
/// there is no XP line).
Future<void> showAchievementDetails(BuildContext context, AchievementModel a) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.elevated,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
    ),
    builder: (_) => AchievementDetails(a),
  );
}

class AchievementDetails extends StatelessWidget {
  const AchievementDetails(this.achievement, {super.key});

  final AchievementModel achievement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = achievement;
    final at = a.unlockedAt;
    Widget row(String label, String value, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                flex: 4,
                child: Text(label, style: theme.textTheme.labelMedium)),
            Expanded(
                flex: 5,
                child: Text(value,
                    key: key,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium)),
          ]),
        );
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('achievement_detail_sheet'),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: a.isUnlocked
                      ? AppColors.accent
                      : AppColors.border.withValues(alpha: 0.6),
                ),
                child: Icon(achievementIconFor(a.icon),
                    size: 28,
                    color: a.isUnlocked
                        ? AppColors.onAccent
                        : AppColors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        key: const Key('achievement_detail_name'),
                        style: theme.textTheme.titleLarge),
                    Text(a.isUnlocked ? 'Розблоковано' : 'Заблоковано',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: a.isUnlocked
                                ? AppColors.accent
                                : AppColors.textSecondary)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.md),
            Text(a.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            const Divider(color: AppColors.border, height: 1),
            row('Умова', a.unlockCondition),
            if (a.target > 0) ...[
              row('Прогрес', '${_num(a.progress)} / ${_num(a.target)}',
                  key: const Key('achievement_detail_progress')),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: a.isUnlocked ? 1 : a.progressFraction,
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ] else
              row('Прогрес', 'Недоступний',
                  key: const Key('achievement_detail_progress')),
            row(
                'Відкрито',
                a.isUnlocked
                    ? (at == null ? 'Так' : _date(at.toLocal()))
                    : 'Ще ні',
                key: const Key('achievement_detail_date')),
          ],
        ),
      ),
    );
  }
}
