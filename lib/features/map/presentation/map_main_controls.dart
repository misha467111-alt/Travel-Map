import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../domain/location_categories.dart';
import '../providers/map_filter_provider.dart';

/// Main-map UI Phase: the compact controls of the Map screen. Presentation
/// only -- every callback is supplied by `MapScreen`, which keeps the
/// existing navigation and the shared [mapFilterProvider] logic.

/// Whether any applied filter differs from the default (drives the small
/// active-filter indicator).
bool mapFiltersAreActive(MapFilterState filters) =>
    filters.category != 'all' ||
    filters.distanceIndex != 3 ||
    filters.minimumRating != null ||
    filters.openNow ||
    filters.familyOnly ||
    filters.sort != LocationSort.newest;

/// The single compact filter control of the Map's top bar. Opens
/// [showMapFilterSheet]; shows a small dot while any filter is active.
class MapFilterButton extends ConsumerWidget {
  const MapFilterButton({super.key, required this.onOpenAdvanced});

  /// Opens the existing full "Додаткові фільтри" screen.
  final VoidCallback onOpenAdvanced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = mapFiltersAreActive(ref.watch(mapFilterProvider).applied);
    return IconButton(
      key: const Key('map_filter_button'),
      tooltip: active ? 'Фільтри (активні)' : 'Фільтри',
      onPressed: () =>
          showMapFilterSheet(context, onOpenAdvanced: onOpenAdvanced),
      icon: Badge(
        key: const Key('map_filter_active_indicator'),
        isLabelVisible: active,
        smallSize: 8,
        child: const Icon(Icons.tune),
      ),
    );
  }
}

Future<void> showMapFilterSheet(
  BuildContext context, {
  required VoidCallback onOpenAdvanced,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => MapFilterQuickSheet(
        onOpenAdvanced: () {
          Navigator.of(sheetContext).pop();
          onOpenAdvanced();
        },
      ),
    );

/// All existing categories (the shared registry and the shared
/// [mapFilterProvider.selectCategory] logic) in a modal bottom sheet, plus
/// the entry to the existing advanced filters.
class MapFilterQuickSheet extends ConsumerWidget {
  const MapFilterQuickSheet({super.key, required this.onOpenAdvanced});

  final VoidCallback onOpenAdvanced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(mapFilterProvider).applied.category;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const Key('map_filter_sheet'),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Категорії', style: theme.textTheme.titleLarge),
                ),
                TextButton(
                  key: const Key('map_filter_reset'),
                  onPressed: selected == 'all'
                      ? null
                      : () => ref
                          .read(mapFilterProvider.notifier)
                          .selectCategory('all'),
                  child: const Text('Скинути'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final category in referenceLocationCategories)
                  _CategoryChip(
                    category: category,
                    selected: selected == category.key,
                    onTap: () => ref
                        .read(mapFilterProvider.notifier)
                        .selectCategory(category.key),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              key: const Key('map_filter_advanced'),
              onPressed: onOpenAdvanced,
              icon: const Icon(Icons.tune),
              label: const Text('Додаткові фільтри'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final LocationCategoryDefinition category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = category.label.replaceAll('\n', ' ');
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: Key('map_filter_category_${category.key}'),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            color: selected
                ? category.referenceColor.withValues(alpha: 0.22)
                : AppColors.surface,
            border: Border.all(
              color: selected ? category.referenceColor : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, size: 18, color: category.referenceColor),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(label, style: theme.textTheme.labelLarge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One entry of the Map's action menu.
class MapMenuAction {
  const MapMenuAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onSelected,
  });

  final Key key;
  final String label;
  final IconData icon;
  final VoidCallback onSelected;
}

/// The Map's single primary creation button. Opens the expandable action
/// menu ([showMapActionsSheet]); the GPS recording entry is its second item.
class MapCreateMenuButton extends StatelessWidget {
  const MapCreateMenuButton({super.key, required this.actions});

  final List<MapMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    // The same primary gold as the active bottom tab (theme token).
    final scheme = Theme.of(context).colorScheme;
    // Visual diameter 40 dp; the interactive area is the full 48x48.
    return SizedBox(
      width: MapTopBar.hitSize,
      height: MapTopBar.hitSize,
      child: Center(
        child: FloatingActionButton.small(
          key: const Key('map_create_menu_button'),
          tooltip: 'Створити',
          heroTag: null,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          shape: const CircleBorder(),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          onPressed: () => showMapActionsSheet(context, actions: actions),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

Future<void> showMapActionsSheet(
  BuildContext context, {
  required List<MapMenuAction> actions,
}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const Key('map_actions_sheet'),
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl, 0, AppSpacing.xl, 0),
                child: Text(
                  'Швидкі дії',
                  key: const Key('map_actions_heading'),
                  style: Theme.of(sheetContext).textTheme.labelLarge?.copyWith(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
              ),
              for (final action in actions)
                ListTile(
                  key: action.key,
                  dense: true,
                  minTileHeight: AppSizes.touchTarget,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  horizontalTitleGap: AppSpacing.md,
                  leading: Icon(action.icon, size: 22),
                  title: Text(action.label,
                      style: Theme.of(sheetContext).textTheme.bodyLarge),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    action.onSelected();
                  },
                ),
            ],
          ),
        ),
      ),
    );

/// The Map's overflow menu (secondary actions). Notifications live here; a
/// small dot on the icon shows unread ones.
class MapOverflowMenu extends StatelessWidget {
  const MapOverflowMenu({
    super.key,
    required this.unreadCount,
    required this.onOpenNotifications,
  });

  final int unreadCount;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        key: const Key('map_overflow_menu'),
        tooltip: 'Ще',
        icon: Badge(
          key: const Key('map_overflow_unread_indicator'),
          isLabelVisible: unreadCount > 0,
          smallSize: 8,
          child: const Icon(Icons.more_vert),
        ),
        onSelected: (value) {
          if (value == 'notifications') onOpenNotifications();
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            key: const Key('map_overflow_notifications'),
            value: 'notifications',
            child: Row(
              children: [
                const Icon(Icons.notifications_outlined, size: 20),
                const SizedBox(width: AppSpacing.md),
                Text(unreadCount > 0
                    ? 'Сповіщення (${unreadCount > 99 ? '99+' : unreadCount})'
                    : 'Сповіщення'),
              ],
            ),
          ),
        ],
      );
}

/// The Map's floating header over the full-screen map: a compact two-line
/// title on the left; a light, square search button and the filter and
/// overflow circles on the right. No bar, no panel: only the controls float
/// over the map.
class MapTopBar extends StatelessWidget {
  const MapTopBar({
    super.key,
    required this.onSearch,
    required this.onOpenAdvancedFilters,
    required this.unreadCount,
    required this.onOpenNotifications,
    this.subtitle,
  });

  final VoidCallback onSearch;
  final VoidCallback onOpenAdvancedFilters;
  final int unreadCount;
  final VoidCallback onOpenNotifications;

  /// Real context for the second line (for example how many places are on
  /// the map); a neutral tagline when none is known yet.
  final String? subtitle;

  static const double control = 40;

  /// Minimum interactive size of every header and floating control.
  static const double hitSize = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const shadow = [Shadow(blurRadius: 6, color: Color(0xCC000000))];
    final content = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.md, 0),
        child: Row(
          children: [
            Expanded(
              // The title is not interactive: map gestures pass through it.
              child: IgnorePointer(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Travel Map',
                    key: const Key('map_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700, shadows: shadow),
                  ),
                  Text(
                    subtitle ?? 'Відкривай нові місця',
                    key: const Key('map_subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textPrimary.withValues(alpha: 0.75),
                        shadows: shadow),
                  ),
                ],
              )),
            ),
            const SizedBox(width: AppSpacing.sm),
            _SearchButton(onTap: onSearch),
            const SizedBox(width: AppSpacing.sm),
            _RoundSurface(
                child: MapFilterButton(onOpenAdvanced: onOpenAdvancedFilters)),
            const SizedBox(width: AppSpacing.sm),
            _RoundSurface(
              child: MapOverflowMenu(
                unreadCount: unreadCount,
                onOpenNotifications: onOpenNotifications,
              ),
            ),
          ],
        ),
      ),
    );
    // A very soft local scrim keeps the title legible over map labels; it
    // ignores pointers, so map gestures work everywhere except on the controls.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: -24,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const Key('map_header_scrim'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.78),
                    AppColors.background.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        content,
      ],
    );
  }
}

class _RoundSurface extends StatelessWidget {
  const _RoundSurface({required this.child});
  final Widget child;

  // The circle is 40 dp; the button on top of it is a full 48x48 target.
  @override
  Widget build(BuildContext context) => SizedBox(
        width: MapTopBar.hitSize,
        height: MapTopBar.hitSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: MapTopBar.control,
              height: MapTopBar.control,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.background.withValues(alpha: 0.82),
              ),
            ),
            IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(MapTopBar.hitSize),
                  maximumSize: const Size.square(MapTopBar.hitSize),
                  padding: EdgeInsets.zero,
                ),
              ),
              child: child,
            ),
          ],
        ),
      );
}

/// The one light element of the header (the search entry), a rounded square
/// in the primary text colour with a dark icon. Its tap target is 48x48.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Пошук',
        child: InkWell(
          key: const Key('map_search_bar'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: SizedBox(
            width: MapTopBar.hitSize,
            height: MapTopBar.hitSize,
            child: Center(
              child: Container(
                width: MapTopBar.control,
                height: MapTopBar.control,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(Icons.search,
                    size: 22, color: AppColors.background),
              ),
            ),
          ),
        ),
      );
}

/// Distance of the route card from the bottom edge of the map area.
const double routeCardBottomMargin = 16;

/// `GoogleMap.padding` (bottom) while the route card is shown: the card's
/// real height plus a small gap, so Google's logo and attribution sit just
/// above it, fully visible.
double routeCardMapBottomPadding(double cardHeight) =>
    routeCardBottomMargin + cardHeight + 8;

/// Bottom inset of the floating map buttons while the route card is shown:
/// at least 12 dp clear of the card, whatever its height.
double routeCardToolbarInset(double cardHeight, {double? maxInset}) {
  final wanted = routeCardBottomMargin + cardHeight + 12;
  if (maxInset == null) return wanted;
  // Extreme text scales on a small screen: never push the buttons off the
  // top of the screen (they would rather sit over the card than vanish).
  return math.min(wanted, math.max(routeCardBottomMargin, maxInset));
}

/// Reports the laid-out height of [child] after every frame in which it
/// changed (text scale, wrapping and screen width all change it), without
/// influencing the child's own layout.
class MeasuredHeight extends StatefulWidget {
  const MeasuredHeight({
    super.key,
    required this.onHeight,
    required this.child,
    this.epoch,
  });

  /// When this value changes the height is reported again even if it is the
  /// same (for example the card content switched from loading to success).
  final Object? epoch;

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<MeasuredHeight> createState() => _MeasuredHeightState();
}

class _MeasuredHeightState extends State<MeasuredHeight> {
  double? _last;
  Object? _lastEpoch;
  bool _reported = false;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final h = box.size.height;
      if (!_reported || h != _last || widget.epoch != _lastEpoch) {
        _reported = true;
        _last = h;
        _lastEpoch = widget.epoch;
        widget.onHeight(h);
      }
    });
    return widget.child;
  }
}
