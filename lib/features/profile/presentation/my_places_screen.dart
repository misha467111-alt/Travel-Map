import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_design.dart';
import '../../map/domain/location_model.dart';
import '../../map/presentation/external_map_launcher.dart';
import '../../map/presentation/location_card.dart';
import '../../map/presentation/location_create_flow.dart';
import '../../map/presentation/map_screen.dart';
import '../../map/providers/map_provider.dart';
import '../../social/providers/public_profile_provider.dart';
import '../providers/my_places_provider.dart';

/// Where the pick screen starts when there is no GPS position (the same default
/// region the map filters fall back to). Only a camera centre, never a
/// selection.
const _fallbackPickTarget = LatLng(50.4501, 30.5234);

/// How long "Додати місце" waits for a GPS position before it simply opens the
/// pick screen on [_fallbackPickTarget]. Normally instant: the map tab already
/// resolved the position.
const _gpsWait = Duration(seconds: 3);

/// Phase 3.3-D -- "Мої місця": the signed-in user's own places in three
/// separate lists: created (authored by me), saved (my bookmarks) and visited
/// (my confirmed check-ins). Private by construction: it is only reachable from
/// the OWN profile and every source is owner-scoped (`owner_id`, local
/// bookmarks, `check_ins` readable only by their owner).
///
/// Phase 3.4-C2: "Додати місце" (AppBar, and the empty "Створені" list) runs
/// the same shared create flow as the map ([pickLocationThenCreate]); after a
/// successful create the "Створені" data is refreshed and that tab is shown.
///
/// Phase 3.4-C3: every place has a "map" action that hands its coordinates to
/// an external maps app (the shared [openExternalMap], the same as Location
/// Details' "Відкрити").
class MyPlacesScreen extends ConsumerStatefulWidget {
  const MyPlacesScreen({
    required this.ownerId,
    this.initialTab = 0,
    this.onOpenLocation,
    @visibleForTesting this.launchExternalMapOverride,
    super.key,
  });

  final String ownerId;
  final int initialTab;

  /// How a place is opened; defaults to the existing location details screen.
  final void Function(BuildContext, LocationModel)? onOpenLocation;

  /// Test-only seam: replaces the real `url_launcher` call of the "map" action
  /// (see [openExternalMap]). Production code never sets this.
  @visibleForTesting
  final ExternalMapLauncher? launchExternalMapOverride;

  @override
  ConsumerState<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends ConsumerState<MyPlacesScreen> {
  /// True from the tap until the create flow ends: a second tap cannot push a
  /// second pick screen.
  bool _adding = false;

  /// The GPS position (a camera centre and the "my location" target) or the
  /// fallback; never throws and never waits longer than [_gpsWait]. The
  /// subscription keeps the auto-dispose provider alive while it is awaited.
  Future<({LatLng target, LatLng? gps})> _startPoint() async {
    // `onError`: without it a GPS failure would also be reported as an
    // uncaught error; here it is expected and handled by the fallback below.
    final subscription = ref.listenManual(
      currentPositionProvider,
      (_, __) {},
      onError: (_, __) {},
    );
    try {
      // The map tab has normally resolved the position already: use its state
      // as it is (a known failure means "no GPS" at once -- the provider may be
      // retrying, which `.future` would wait for). Only a position that is
      // still being fetched is awaited, and only for [_gpsWait].
      final known = ref.read(currentPositionProvider);
      final p = known.value ??
          (known.hasError
              ? null
              : await ref
                  .read(currentPositionProvider.future)
                  .timeout(_gpsWait));
      if (p == null) return (target: _fallbackPickTarget, gps: null);
      final gps = LatLng(p.latitude, p.longitude);
      return (target: gps, gps: gps);
    } catch (_) {
      return (target: _fallbackPickTarget, gps: null);
    } finally {
      subscription.close();
    }
  }

  Future<void> _addPlace(TabController tabs) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final start = await _startPoint();
      if (!mounted) return;
      final created = await pickLocationThenCreate(
        context,
        ref,
        initialTarget: start.target,
        userPosition: start.gps,
      );
      if (!created || !mounted) return;
      // The new place is the owner's own row (any moderation status): reload
      // the created list and the exact total (the profile reads the same
      // count), then show it.
      ref.invalidate(myCreatedLocationsProvider);
      ref.invalidate(myCreatedCountProvider);
      tabs.animateTo(0);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Opens this place's coordinates in an external maps app. Missing/invalid
  /// coordinates are not launched; any failure is a SnackBar, as in Location
  /// Details.
  Future<void> _openOnMap(BuildContext context, LocationModel location) async {
    final launched = await openExternalMap(
      location.latitude,
      location.longitude,
      launcher: widget.launchExternalMapOverride,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося відкрити карти.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = widget.ownerId;
    final onOpenLocation = widget.onOpenLocation;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Мої місця'),
          actions: [
            Builder(
              builder: (tabContext) => IconButton(
                key: const Key('my_places_add_place'),
                tooltip: 'Додати місце',
                color: AppColors.accent,
                onPressed: _adding
                    ? null
                    : () => _addPlace(DefaultTabController.of(tabContext)),
                icon: const Icon(Icons.add_location_alt_outlined),
              ),
            ),
          ],
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
            ownerId: ownerId,
            open: onOpenLocation ?? _openLocation,
            // Null while a create flow is running: the empty-state button is
            // disabled exactly like the AppBar one.
            onAddPlace: _adding ? null : _addPlace,
            openMap: _openOnMap,
          ),
          _SavedTab(open: onOpenLocation ?? _openLocation, openMap: _openOnMap),
          _VisitedTab(
            ownerId: ownerId,
            open: onOpenLocation ?? _openLocation,
            openMap: _openOnMap,
          ),
        ]),
      ),
    );
  }
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
    this.emptyAction,
  });

  final AsyncValue<List<T>> value;
  final String keyName;
  final IconData emptyIcon;
  final String emptyText;
  final VoidCallback onRetry;
  final Widget Function(BuildContext, T) builder;
  final Widget? header;
  final Widget? footer;

  /// An action under the text of the plain empty state (not shown while loading,
  /// on error, or when the list has a header).
  final Widget? emptyAction;

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
                  if (emptyAction != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    emptyAction!,
                  ],
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
  const _CreatedTab({
    required this.ownerId,
    required this.open,
    required this.onAddPlace,
    required this.openMap,
  });

  final String ownerId;
  final void Function(BuildContext, LocationModel) open;
  final void Function(BuildContext, LocationModel) openMap;

  /// Starts the create flow (given the screen's tab controller); null disables
  /// the empty-state button.
  final void Function(TabController)? onAddPlace;

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
      emptyAction: FilledButton.icon(
        key: const Key('my_places_empty_add_place'),
        onPressed: widget.onAddPlace == null
            ? null
            : () => widget.onAddPlace!(DefaultTabController.of(context)),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Додати місце'),
      ),
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
            _PlaceFooter(
              location: location,
              openMap: widget.openMap,
              info: label.isEmpty
                  ? null
                  : Text('Статус: $label',
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
  const _SavedTab({required this.open, required this.openMap});

  final void Function(BuildContext, LocationModel) open;
  final void Function(BuildContext, LocationModel) openMap;

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
          _PlaceFooter(location: location, openMap: openMap),
        ],
      ),
    );
  }
}

class _VisitedTab extends ConsumerWidget {
  const _VisitedTab({
    required this.ownerId,
    required this.open,
    required this.openMap,
  });

  final String ownerId;
  final void Function(BuildContext, LocationModel) open;
  final void Function(BuildContext, LocationModel) openMap;

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
            _PlaceFooter(
              location: location,
              openMap: openMap,
              info: Text(
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

/// The row under a place card: its optional info text and the "map" action
/// (Phase 3.4-C3). A separate row, not part of the card, so the action's 48 dp
/// target never overlaps the card's own tap area (details) and the card keeps
/// its width for the text.
class _PlaceFooter extends StatelessWidget {
  const _PlaceFooter({
    required this.location,
    required this.openMap,
    this.info,
  });

  final LocationModel location;
  final void Function(BuildContext, LocationModel) openMap;
  final Widget? info;

  @override
  Widget build(BuildContext context) => Padding(
        // Room below the row only: otherwise it sits half-way between two cards
        // and reads as belonging to the next one.
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: info ?? const SizedBox.shrink(),
            ),
          ),
          IconButton(
            key: Key('my_place_map_${location.id}'),
            tooltip: 'Відкрити в картах: ${location.title}',
            onPressed: () => openMap(context, location),
            color: AppColors.accent,
            iconSize: 22,
            // The theme fixes icon buttons at 40 dp; this one is a full 48 dp
            // target (min == max, or the theme's maximum would contradict it).
            style: IconButton.styleFrom(
              minimumSize: const Size.square(48),
              maximumSize: const Size.square(48),
            ),
            icon: const Icon(Icons.map_outlined),
          ),
        ]),
      );
}
