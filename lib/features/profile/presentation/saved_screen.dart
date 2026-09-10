import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/domain/location_model.dart';
import '../../map/presentation/location_card.dart';
import '../../map/presentation/map_screen.dart';
import '../../map/providers/locations_provider.dart';
import '../../navigation/presentation/scalable_locations_screen.dart';
import '../../social/providers/public_profile_provider.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedIdsState = ref.watch(savedPublicLocationsProvider);
    final savedIds = savedIdsState.value ?? const <String>{};
    final locationsState = savedIdsState.hasValue
        ? ref.watch(savedLocationsProvider(savedIds))
        : const AsyncLoading<List<LocationModel>>();
    return SavedPage(
      locations: locationsState,
      onRefresh: () => ref.invalidate(savedLocationsProvider(savedIds)),
      onUnsave: (location) =>
          ref.read(savedPublicLocationsProvider.notifier).toggle(location.id),
      onOpen: (location) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocationDetailsScreen(location: location),
        ),
      ),
      onDiscover: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ScalableLocationsScreen(
            mode: ScalableLocationListMode.discover,
          ),
        ),
      ),
    );
  }
}

class SavedPage extends StatelessWidget {
  const SavedPage({
    required this.locations,
    required this.onUnsave,
    required this.onOpen,
    this.onRefresh,
    this.onDiscover,
    super.key,
  });

  final AsyncValue<List<LocationModel>> locations;
  final ValueChanged<LocationModel> onUnsave;
  final ValueChanged<LocationModel> onOpen;
  final VoidCallback? onRefresh;
  final VoidCallback? onDiscover;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: const Text('Закладки',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: SavedContent(
          locations: locations,
          onUnsave: onUnsave,
          onOpen: onOpen,
          onRefresh: onRefresh,
          onDiscover: onDiscover,
        ),
      );
}

class SavedContent extends StatelessWidget {
  const SavedContent({
    required this.locations,
    required this.onUnsave,
    required this.onOpen,
    this.onRefresh,
    this.onDiscover,
    super.key,
  });

  final AsyncValue<List<LocationModel>> locations;
  final ValueChanged<LocationModel> onUnsave;
  final ValueChanged<LocationModel> onOpen;
  final VoidCallback? onRefresh;
  final VoidCallback? onDiscover;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final effectiveScale =
        mediaQuery.textScaler.scale(1).clamp(1.0, 1.12).toDouble();
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(effectiveScale)),
      child: SafeArea(
        child: locations.when(
          data: (items) => items.isEmpty
              ? SavedEmptyState(onDiscover: onDiscover)
              : RefreshIndicator(
                  onRefresh: () async => onRefresh?.call(),
                  child: ListView.builder(
                    key: const Key('saved_location_list'),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final location = items[index];
                      return LocationCard(
                        key: Key('saved_card_${location.id}'),
                        location: location,
                        compact: true,
                        isSaved: true,
                        onBookmarkTap: () => onUnsave(location),
                        onTap: () => onOpen(location),
                      );
                    },
                  ),
                ),
          loading: () => const SavedLoadingState(),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 42, color: Color(0xFFD4A017)),
                const SizedBox(height: 12),
                const Text('Не вдалося завантажити закладки'),
                if (onRefresh != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: onRefresh,
                    child: const Text('Спробувати ще раз'),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class SavedEmptyState extends StatelessWidget {
  const SavedEmptyState({this.onDiscover, super.key});
  final VoidCallback? onDiscover;

  @override
  Widget build(BuildContext context) => Center(
        key: const Key('saved_empty_state'),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF14231D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bookmark_border_rounded,
                  size: 34, color: Color(0xFFD4A017)),
              const SizedBox(height: 8),
              Text('Закладок поки немає',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Зберігайте цікаві місця, щоб швидко повернутися до них.',
                textAlign: TextAlign.center,
              ),
              if (onDiscover != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('saved_discover_cta'),
                  onPressed: onDiscover,
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Відкривати місця'),
                ),
              ],
            ]),
          ),
        ),
      );
}

class SavedLoadingState extends StatelessWidget {
  const SavedLoadingState({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        key: Key('saved_loading_state'),
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
}
