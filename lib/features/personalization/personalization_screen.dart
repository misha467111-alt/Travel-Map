import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_design.dart';
import 'traveler_marker.dart';

/// "Персоналізація": the traveler marker style and colour with a live
/// preview. A choice is saved at once and applied to the main map.
class PersonalizationScreen extends ConsumerWidget {
  const PersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(travelerMarkerProvider);
    final notifier = ref.read(travelerMarkerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Персоналізація')),
      body: SafeArea(
        child: ListView(
          key: const Key('personalization_list'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    KeyedSubtree(
                      key: const Key('marker_preview'),
                      child: TravelerMarkerPreview(
                        style: settings.style,
                        color: settings.color,
                        size: 112,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('${settings.style.label}, ${settings.color.label}',
                        key: const Key('marker_preview_label'),
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Зміни застосовуються до карти одразу',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Стиль маркера', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (final style in TravelerMarkerStyle.values) ...[
                  if (style != TravelerMarkerStyle.values.first)
                    const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _StyleCard(
                      style: style,
                      color: settings.color,
                      selected: settings.style == style,
                      onTap: () => notifier.select(style: style),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Колір маркера', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            // One evenly spaced row (six 48 dp swatches fit even 320 dp).
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final color in TravelerMarkerColor.values)
                  _ColorSwatch(
                    color: color,
                    selected: settings.color == color,
                    onTap: () => notifier.select(color: color),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final TravelerMarkerStyle style;
  final TravelerMarkerColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: style.label,
      child: InkWell(
        key: Key('marker_style_${style.name}'),
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            color: AppColors.surface,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              ExcludeSemantics(
                child:
                    TravelerMarkerPreview(style: style, color: color, size: 56),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                style.shortLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final TravelerMarkerColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: color.label,
        child: InkWell(
          key: Key('marker_color_${color.name}'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: AppSizes.touchTarget,
            height: AppSizes.touchTarget,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.color,
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 22)
                : null,
          ),
        ),
      );
}
