import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../map/domain/location_model.dart';
import '../../map/providers/locations_provider.dart';

/// Phase 3.3-D -- the signed-in user's own places. Three DIFFERENT things:
///  - created:  `locations.owner_id = me`  (any moderation status);
///  - saved:    local bookmarks (`savedPublicLocationsProvider`, unchanged);
///  - visited:  confirmed check-ins (`check_ins`, readable only by their owner).
/// None of this exists for another user's profile.

/// A place the user has a confirmed check-in at: one entry per `location_id`.
class VisitedPlace {
  const VisitedPlace({
    required this.locationId,
    required this.lastVisit,
    required this.visits,
  });

  final String locationId;

  /// The most recent check-in at this place.
  final DateTime lastVisit;

  /// How many check-ins there are at this place (repeats do not add places).
  final int visits;
}

/// Pure aggregation of `check_ins` rows (`location_id`, `created_at`) into
/// unique visited places, most recently visited first. A row without a usable
/// `location_id` or date is ignored.
List<VisitedPlace> aggregateVisits(Iterable<Map<String, dynamic>> rows) {
  final last = <String, DateTime>{};
  final count = <String, int>{};
  for (final row in rows) {
    final id = row['location_id'];
    final at = DateTime.tryParse('${row['created_at']}');
    if (id is! String || id.isEmpty || at == null) continue;
    count[id] = (count[id] ?? 0) + 1;
    final known = last[id];
    if (known == null || at.isAfter(known)) last[id] = at;
  }
  final out = [
    for (final id in last.keys)
      VisitedPlace(locationId: id, lastVisit: last[id]!, visits: count[id]!),
  ]..sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
  return out;
}

/// Check-ins are read in pages of this size...
const _checkInPage = 500;

/// ...and at most this many pages (a safety bound, not an expected size). If it
/// is ever reached the result is flagged incomplete and shown as "N+".
const _checkInMaxPages = 10;

/// Locations are loaded for their ids in batches of this size.
const _idsBatch = 50;
const _idsMaxBatches = 10;

/// The unique visited places of the owner and whether ALL of the owner's
/// check-ins were read ([isComplete]).
class VisitHistory {
  const VisitHistory({required this.places, required this.isComplete});

  final List<VisitedPlace> places;
  final bool isComplete;
}

/// Reads rows page by page with [fetch] (inclusive row range `from..to`) until
/// a page is not full. `complete` is false only if [maxPages] full pages were
/// read without reaching the end. Pure paging logic, testable without Supabase.
Future<({List<Map<String, dynamic>> rows, bool complete})> readAllPages(
  Future<List<Map<String, dynamic>>> Function(int from, int to) fetch, {
  int pageSize = _checkInPage,
  int maxPages = _checkInMaxPages,
}) async {
  final rows = <Map<String, dynamic>>[];
  for (var page = 0; page < maxPages; page++) {
    final chunk = await fetch(page * pageSize, (page + 1) * pageSize - 1);
    rows.addAll(chunk);
    if (chunk.length < pageSize) return (rows: rows, complete: true);
  }
  return (rows: rows, complete: false);
}

class MyPlacesRepository {
  const MyPlacesRepository(this._supabase);

  final SupabaseClient _supabase;

  /// The owner's check-ins (own rows only; RLS), newest first, read page by
  /// page until exhausted. The unique-place total therefore is not limited by
  /// a single query; [VisitHistory.isComplete] is false only if the safety
  /// bound of pages was hit.
  Future<VisitHistory> fetchVisited(String ownerId) async {
    final result = await readAllPages((from, to) async {
      final chunk = await _supabase
          .from('check_ins')
          .select('location_id, created_at')
          .eq('user_id', ownerId)
          .order('created_at', ascending: false)
          // A unique tiebreaker: without it rows with an equal created_at may
          // swap between pages (a skipped place / a repeated row).
          .order('id', ascending: false)
          .range(from, to);
      return chunk.map((r) => Map<String, dynamic>.from(r)).toList();
    });
    return VisitHistory(
        places: aggregateVisits(result.rows), isComplete: result.complete);
  }
}

final myPlacesRepositoryProvider = Provider<MyPlacesRepository>(
  (ref) => MyPlacesRepository(Supabase.instance.client),
);

/// Created by me (`owner_id`): a page of at most [limit] locations.
final myCreatedLocationsProvider = FutureProvider.autoDispose
    .family<List<LocationModel>, ({String ownerId, int limit})>((ref, key) {
  return ref
      .watch(locationsRepositoryProvider)
      .fetchOwnLocations(key.ownerId, limit: key.limit);
});

/// The EXACT number of locations created by me.
final myCreatedCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, ownerId) {
  return ref.watch(locationsRepositoryProvider).countOwnLocations(ownerId);
});

/// Loads the locations for [ids] in batches (the repository reads 50 ids at a
/// time). Ids whose location is not readable are simply absent.
Future<List<LocationModel>> loadLocationsInBatches(
  LocationsRepository repository,
  Iterable<String> ids,
) async {
  final all = ids.toList(growable: false);
  final out = <LocationModel>[];
  for (var b = 0; b < _idsMaxBatches; b++) {
    final start = b * _idsBatch;
    if (start >= all.length) break;
    final end = start + _idsBatch > all.length ? all.length : start + _idsBatch;
    out.addAll(await repository.fetchLocationsByIds(all.sublist(start, end)));
  }
  return out;
}

/// My bookmarks as locations (all of them, in batches; `ids.length` is the
/// real number of bookmarks, the list only has the readable ones).
final mySavedLocationsProvider = FutureProvider.autoDispose
    .family<List<LocationModel>, Set<String>>((ref, ids) {
  return loadLocationsInBatches(ref.watch(locationsRepositoryProvider), ids);
});

/// The visited places with their (loadable) locations. [total] is the number
/// of UNIQUE visited places (not of check-ins); it is exact unless
/// [isComplete] is false, in which case it is "at least". [places] only has
/// those whose location can be loaded.
class VisitedPlaces {
  const VisitedPlaces({
    required this.total,
    required this.places,
    this.isComplete = true,
  });

  final int total;
  final bool isComplete;
  final List<(VisitedPlace, LocationModel)> places;
}

final myVisitedPlacesProvider = FutureProvider.autoDispose
    .family<VisitedPlaces, String>((ref, ownerId) async {
  final history =
      await ref.watch(myPlacesRepositoryProvider).fetchVisited(ownerId);
  final visits = history.places;
  if (visits.isEmpty) {
    return VisitedPlaces(
        total: 0, places: const [], isComplete: history.isComplete);
  }
  final locations = await loadLocationsInBatches(
      ref.watch(locationsRepositoryProvider), visits.map((v) => v.locationId));
  final byId = {for (final l in locations) l.id: l};
  return VisitedPlaces(
    total: visits.length,
    isComplete: history.isComplete,
    places: [
      for (final v in visits)
        if (byId[v.locationId] != null) (v, byId[v.locationId]!),
    ],
  );
});
