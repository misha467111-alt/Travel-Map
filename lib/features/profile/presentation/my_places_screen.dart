import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design.dart';
import '../../map/domain/location_model.dart';
import '../../map/presentation/location_card.dart';
import '../../map/presentation/map_screen.dart';
import '../../social/providers/public_profile_provider.dart';
import '../providers/my_places_provider.dart';

/// Phase 3.3-D -- "Мої місця": the signed-in user's own places in three
/// separate lists: created (authored by me), saved (my bookmarks) and visited
/// (my confirmed check-ins). Private by construction: it is only reachable from
/// the OWN profile and every source is owner-scoped (`owner_id`, local
/// bookmarks, `check_ins` readable only by their owner).
class MyPlacesScreen extends StatelessWidget {
  const MyPlacesScreen({
    required this.ownerId,
    this.initialTab = 0,
    this.onOpenLocation,
    super.key,
  });

  final String ownerId;
  final int initialTab;

  /// How a place is opened; defaults to the existing location details screen.
  final void Function(BuildContext, LocationModel)? onOpenLocation;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: initialTab.clamp(0, 2),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Мої місця'),
            bottom: const TabBar(
              // Scrollable: a label is never clipped on a narrow screen or with a
              // large system font.
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              tabs: [
                Tab(key: Key('my_places_tab_created'), text: 'Створені'),
                Tab(key: Key('my_places_tab_saved'), text: 'Збережені'),
                Tab(key: Key('my_places_tab_visited'), text: 'Відвідані'),
              ],
            ),
          ),
          body: TabBarView(children: [
            _CreatedTab(
                ownerId: ownerId, open: onOpenLocation ?? _openLocation),
            _SavedTab(open: onOpenLocation ?? _openLocation),
            _VisitedTab(
                ownerId: ownerId, open: onOpenLocation ?? _openLocation),
          ]),
        ),
      );
}

void _openLocation(BuildContext context, LocationModel location) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => LocationDetailsScreen(location: location),
  ));
}

String _statusLabel(String status) => switch (status) {
      'draft' => 'Чернетка',
      'pending' => 'На модерації',
      'approved' => 'Схвалено',
      'rejected' => 'Відхилено',
      'archived' => 'В архіві',
      _ => '',
    };

String _date(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
}

/// Shared loading / empty / error scaffolding of one list.
class _PlacesList<T> extends StatelessWidget {
  const _PlacesList({
    required this.value,
    required this.keyName,
    required this.emptyIcon,
    required this.emptyText,
    required this.onRetry,
    required this.builder,
    this.header,
    this.footer,
  });

  final AsyncValue<List<T>> value;
  final String keyName;
  final IconData emptyIcon;
  final String emptyText;
  final VoidCallback onRetry;
  final Widget Function(BuildContext, T) builder;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return value.when(
      loading: () => Center(
        child: CircularProgressIndicator(
            key: Key('my_places_loading_$keyName'), color: AppColors.accent),
      ),
      error: (_, __) => Center(
        key: Key('my_places_error_$keyName'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined,
                size: 44, color: AppColors.accent),
            const SizedBox(height: AppSpacing.md),
            Text('Не вдалося завантажити', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторити'),
            ),
          ]),
        ),
      ),
      data: (items) => items.isEmpty && header == null
          ? Center(
              key: Key('my_places_empty_$keyName'),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(emptyIcon, size: 44, color: AppColors.accent),
                  const SizedBox(height: AppSpacing.md),
                  Text(emptyText,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium),
                ]),
              ),
            )
          : RefreshIndicator(
              color: AppColors.accent,
              onRefresh: () async => onRetry(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm,
                    AppSpacing.lg, AppSpacing.xxl),
                children: [
                  if (header != null) header!,
                  for (final item in items) builder(context, item),
                  if (footer != null) footer!,
                  if (items.isEmpty)
                    Padding(
                      key: Key('my_places_empty_$keyName'),
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(emptyText,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium),
                    ),
                ],
              ),
            ),
    );
  }
}

/// How many created places are requested at a time.
const _createdPage = 100;

class _CreatedTab extends ConsumerStatefulWidget {
  const _CreatedTab({required this.ownerId, required this.open});

  final String ownerId;
  final void Function(BuildContext, LocationModel) open;

  @override
  ConsumerState<_CreatedTab> createState() => _CreatedTabState();
}

class _CreatedTabState extends ConsumerState<_CreatedTab> {
  int _limit = _createdPage;

  @override
  Widget build(BuildContext context) {
    final ownerId = widget.ownerId;
    final key = (ownerId: ownerId, limit: _limit);
    final locations = ref.watch(myCreatedLocationsProvider(key));
    final total = ref.watch(myCreatedCountProvider(ownerId)).value;
    final theme = Theme.of(context);
    final shown = locations.value?.length ?? 0;
    // More exist when the exact total says so; without a total, a full page
    // means there may be more.
    final hasMore = total != null ? shown < total : shown >= _limit;
    return _PlacesList<LocationModel>(
      value: locations,
      keyName: 'created',
      emptyIcon: Icons.add_location_alt_outlined,
      emptyText: 'Ви ще не створили жодної локації',
      onRetry: () {
        ref.invalidate(myCreatedLocationsProvider(key));
        ref.invalidate(myCreatedCountProvider(ownerId));
      },
      header: total == null || total == 0
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                  shown < total
                      ? 'Показано $shown із $total'
                      : 'Усього: $total',
                  key: const Key('my_places_created_total'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: AppColors.accent)),
            ),
      footer: hasMore
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: OutlinedButton(
                key: const Key('my_places_created_more'),
                onPressed: () => setState(() => _limit += _createdPage),
                child: const Text('Показати ще'),
              ),
            )
          : null,
      builder: (context, location) {
        final label = _statusLabel(location.status);
        return Column(
          key: Key('my_place_${location.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocationCard(
              location: location,
              compact: true,
              onTap: () => widget.open(context, location),
            ),
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                    left: AppSpacing.sm, bottom: AppSpacing.xs),
                child: Text('Статус: $label',
                    key: Key('my_place_status_${location.id}'),
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: location.status == 'approved'
                            ? AppColors.accent
                            : AppColors.textSecondary)),
              ),
          ],
        );
      },
    );
  }
}

class _SavedTab extends ConsumerWidget {
  const _SavedTab({required this.open});

  final void Function(BuildContext, LocationModel) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idsState = ref.watch(savedPublicLocationsProvider);
    final ids = idsState.value ?? const <String>{};
    final AsyncValue<List<LocationModel>> locations = idsState.hasError
        ? AsyncError<List<LocationModel>>(
            idsState.error!, idsState.stackTrace ?? StackTrace.empty)
        : !idsState.hasValue
            ? const AsyncLoading<List<LocationModel>>()
            : ids.isEmpty
                ? const AsyncData<List<LocationModel>>([])
                : ref.watch(mySavedLocationsProvider(ids));
    final theme = Theme.of(context);
    final shown = locations.value?.length ?? 0;
    return _PlacesList<LocationModel>(
      value: locations,
      keyName: 'saved',
      emptyIcon: Icons.bookmark_outline,
      emptyText: 'У вас ще немає збережених локацій',
      onRetry: () {
        ref.invalidate(savedPublicLocationsProvider);
        if (ids.isNotEmpty) ref.invalidate(mySavedLocationsProvider(ids));
      },
      header: ids.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                  shown < ids.length
                      ? 'Показано $shown із ${ids.length}'
                      : 'Збережено: ${ids.length}',
                  key: const Key('my_places_saved_total'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: AppColors.accent)),
            ),
      builder: (context, location) => Column(
        key: Key('my_place_${location.id}'),
        children: [
          LocationCard(
            location: location,
            compact: true,
            isSaved: ids.contains(location.id),
            onTap: () => open(context, location),
            onBookmarkTap: () => ref
                .read(savedPublicLocationsProvider.notifier)
                .toggle(location.id),
          ),
        ],
      ),
    );
  }
}

class _VisitedTab extends ConsumerWidget {
  const _VisitedTab({required this.ownerId, required this.open});

  final String ownerId;
  final void Function(BuildContext, LocationModel) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visited = ref.watch(myVisitedPlacesProvider(ownerId));
    final theme = Theme.of(context);
    final total = visited.value?.total ?? 0;
    final exact = visited.value?.isComplete ?? true;
    final shown = visited.value?.places.length ?? 0;
    return _PlacesList<(VisitedPlace, LocationModel)>(
      value: visited.whenData((v) => v.places),
      keyName: 'visited',
      emptyIcon: Icons.flag_outlined,
      emptyText: 'Підтверджених відвідувань ще немає',
      onRetry: () => ref.invalidate(myVisitedPlacesProvider(ownerId)),
      header: total == 0
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // UNIQUE places; the number of check-ins per place is shown
                  // on each place and is a different thing.
                  Text('Унікальних місць: $total${exact ? '' : '+'}',
                      key: const Key('my_places_visited_total'),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: AppColors.accent)),
                  if (shown < total)
                    Text('Показано $shown із $total',
                        key: const Key('my_places_visited_hidden'),
                        style: theme.textTheme.labelSmall),
                ],
              ),
            ),
      builder: (context, item) {
        final (visit, location) = item;
        return Column(
          key: Key('my_place_${location.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LocationCard(
              location: location,
              compact: true,
              onTap: () => open(context, location),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: AppSpacing.sm, bottom: AppSpacing.xs),
              child: Text(
                  'Остання: ${_date(visit.lastVisit)} · '
                  '${visit.visits} ${visit.visits == 1 ? 'відвідування' : 'відвідувань'}',
                  key: Key('my_place_visit_${location.id}'),
                  style: theme.textTheme.labelMedium),
            ),
          ],
        );
      },
    );
  }
}
