import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/location_model.dart';
import 'locations_provider.dart';

const locationCategories = <String>[
  'general',
  'cafe',
  'nature',
  'culture',
  'entertainment',
];

final mapFilterProvider = NotifierProvider<MapFilterNotifier, String>(
  MapFilterNotifier.new,
);

class MapFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all';

  void select(String category) {
    if (category == 'all' || locationCategories.contains(category)) {
      state = category;
    }
  }
}

final filteredLocationsProvider = Provider<AsyncValue<List<LocationModel>>>(
  (ref) {
    final category = ref.watch(mapFilterProvider);
    return ref.watch(fetchLocationsProvider).whenData((locations) {
      if (category == 'all') return locations;
      return locations
          .where((location) => location.category == category)
          .toList(growable: false);
    });
  },
);
