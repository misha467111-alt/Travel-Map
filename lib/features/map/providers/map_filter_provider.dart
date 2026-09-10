import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_categories.dart';

enum LocationSort { newest, nearest, rating }

class MapFilterState {
  const MapFilterState({
    this.category = 'all',
    this.distanceIndex = 3,
    this.minimumRating,
    this.openNow = false,
    this.familyOnly = false,
    this.sort = LocationSort.newest,
  });
  final String category;
  final int distanceIndex;
  final double? minimumRating;
  final bool openNow;
  final bool familyOnly;
  final LocationSort sort;

  double? get maximumDistanceMeters => distanceIndex == 3
      ? null
      : const [1000.0, 10000.0, 50000.0][distanceIndex];
  String get rpcSort => sort.name;

  MapFilterState copyWith({
    String? category,
    int? distanceIndex,
    double? minimumRating,
    bool clearRating = false,
    bool? openNow,
    bool? familyOnly,
    LocationSort? sort,
  }) =>
      MapFilterState(
        category: category ?? this.category,
        distanceIndex: distanceIndex ?? this.distanceIndex,
        minimumRating: clearRating ? null : minimumRating ?? this.minimumRating,
        openNow: openNow ?? this.openNow,
        familyOnly: familyOnly ?? this.familyOnly,
        sort: sort ?? this.sort,
      );
}

class MapFilters {
  const MapFilters({required this.pending, required this.applied});
  final MapFilterState pending;
  final MapFilterState applied;
}

final mapFilterProvider = NotifierProvider<MapFilterNotifier, MapFilters>(
  MapFilterNotifier.new,
);

class MapFilterNotifier extends Notifier<MapFilters> {
  @override
  MapFilters build() => const MapFilters(
        pending: MapFilterState(),
        applied: MapFilterState(),
      );

  void updatePending(MapFilterState value) =>
      state = MapFilters(pending: value, applied: state.applied);
  void apply() => state = MapFilters(
        pending: state.pending,
        applied: state.pending,
      );
  void resetPending() => updatePending(const MapFilterState());
  void selectCategory(String category) {
    if (!locationCategoryByKey.containsKey(category) || category == 'general') {
      return;
    }
    final value = state.applied.copyWith(category: category);
    state = MapFilters(pending: value, applied: value);
  }
}
