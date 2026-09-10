import 'dart:convert';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../domain/location_model.dart';
import '../domain/location_query.dart';
import 'network_provider.dart';

part 'locations_provider.g.dart';

class LocationsRepository {
  const LocationsRepository(this._supabase);

  final SupabaseClient _supabase;

  static const _bucketName = 'location_images';
  static const _maxImageSize = 10 * 1024 * 1024;

  Future<List<LocationModel>> fetchLocations() async {
    final page = await fetchDiscoverPage(limit: 30);
    return page.items.map((item) => item.location).toList(growable: false);
  }

  Future<MapLocationResult> fetchLocationsInBounds(
    MapViewportQuery query, {
    int limit = 300,
  }) async {
    final bounds = query.bounds;
    final rows = await _supabase.rpc<List<dynamic>>(
      'travel_locations_in_bounds_v2',
      params: {
        'p_min_lng': bounds.minLongitude,
        'p_min_lat': bounds.minLatitude,
        'p_max_lng': bounds.maxLongitude,
        'p_max_lat': bounds.maxLatitude,
        'p_category': query.category,
        'p_search': null,
        'p_user_latitude': query.userLatitude,
        'p_user_longitude': query.userLongitude,
        'p_max_distance_m': query.maximumDistanceMeters,
        'p_min_rating': query.minimumRating,
        'p_open_now': query.openNow,
        'p_family_friendly_only': query.familyOnly,
        'p_sort': query.sort,
        'p_limit': boundedPageSize(limit, maximum: 500),
      },
    );
    final items = rows
        .map((row) => LocationQueryItem.fromRpcRow(
              Map<String, dynamic>.from(row as Map),
            ).location)
        .toList(growable: false);
    final totalCount = rows.isEmpty
        ? 0
        : ((rows.first as Map)['total_count'] as num? ?? items.length).toInt();
    return MapLocationResult(items: items, totalCount: totalCount);
  }

  Future<LocationPage> fetchDiscoverPage({
    LocationCursor? cursor,
    String? category,
    String? search,
    int limit = 30,
  }) async {
    final pageSize = boundedPageSize(limit, maximum: 39);
    final rows = await _supabase.rpc<List<dynamic>>(
      'travel_discover_locations',
      params: {
        'p_cursor_created_at': cursor?.createdAt.toUtc().toIso8601String(),
        'p_cursor_id': cursor?.id,
        'p_category': category,
        'p_search': search,
        'p_limit': pageSize + 1,
      },
    );
    final mapped = rows
        .map((row) => LocationQueryItem.fromRpcRow(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList(growable: true);
    final hasMore = mapped.length > pageSize;
    if (hasMore) mapped.removeLast();
    return LocationPage(items: mapped, hasMore: hasMore);
  }

  Future<List<LocationQueryItem>> fetchNearbyLocations({
    required double latitude,
    required double longitude,
    required double radiusMeters,
    String? category,
    int limit = 40,
  }) async {
    final rows = await _supabase.rpc<List<dynamic>>(
      'travel_nearby_locations',
      params: {
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_radius_m': radiusMeters,
        'p_category': category,
        'p_limit': boundedPageSize(limit),
      },
    );
    return rows
        .map((row) => LocationQueryItem.fromRpcRow(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList(growable: false);
  }

  Future<List<LocationModel>> fetchLocationsByIds(Iterable<String> ids) async {
    final boundedIds = ids.take(50).toList(growable: false);
    if (boundedIds.isEmpty) return const [];
    final rows = await _supabase
        .from('locations')
        .select()
        .inFilter('id', boundedIds)
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .map((row) => LocationModel.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<LocationDetailsData> fetchLocationDetails(String locationId) async {
    final results = await Future.wait<dynamic>([
      _supabase.from('locations').select().eq('id', locationId).single(),
      _supabase
          .from('location_photos')
          .select('storage_path')
          .eq('location_id', locationId)
          .order('sort_order')
          .limit(20),
      _supabase
          .from('location_tags')
          .select('tags(name)')
          .eq('location_id', locationId)
          .limit(30),
    ]);
    final location = LocationModel.fromMap(
      Map<String, dynamic>.from(results[0] as Map),
    );
    final bucket = _supabase.storage.from(_bucketName);
    final photos = (results[1] as List)
        .map((row) => (row as Map)['storage_path'])
        .whereType<String>()
        .map(bucket.getPublicUrl)
        .toList(growable: false);
    final tags = (results[2] as List)
        .map((row) => (row as Map)['tags'])
        .whereType<Map>()
        .map((tag) => tag['name'])
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .map((name) => name.trim())
        .toList(growable: false);
    return LocationDetailsData(
      location: location,
      photoUrls: photos,
      tags: tags,
    );
  }

  Future<void> createLocation({
    required String title,
    required String description,
    required double latitude,
    required double longitude,
    required String category,
    Uint8List? imageBytes,
    String? imageName,
    String? requestId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('Для додавання локації потрібно увійти в акаунт.');
    }

    if (imageBytes != null && imageBytes.lengthInBytes > _maxImageSize) {
      throw const FormatException('Фото має бути не більше 10 МБ.');
    }

    String? uploadedPath;
    String? createdLocationId;
    String? imageUrl;
    try {
      if (imageBytes != null) {
        final fileType = _imageType(imageName);
        uploadedPath = '${user.id}/${const Uuid().v4()}.${fileType.extension}';
        final bucket = _supabase.storage.from(_bucketName);
        await bucket.uploadBinary(
          uploadedPath,
          imageBytes,
          fileOptions: FileOptions(
            contentType: fileType.contentType,
            upsert: false,
          ),
        );
        imageUrl = bucket.getPublicUrl(uploadedPath);
      }

      createdLocationId = await _supabase.rpc<String>(
        'create_location_with_xp',
        params: {
          'location_title': title.trim(),
          'location_description': description.trim(),
          'location_latitude': latitude,
          'location_longitude': longitude,
          'p_category': category,
          'p_image_url': imageUrl,
          'p_request_id': requestId,
        },
      );
      if (uploadedPath != null) {
        await _supabase.from('location_photos').insert({
          'location_id': createdLocationId,
          'storage_path': uploadedPath,
        });
      }
    } catch (_) {
      if (createdLocationId != null) {
        try {
          await _supabase
              .from('locations')
              .delete()
              .eq('id', createdLocationId);
        } catch (_) {
          // Preserve the original create/photo error.
        }
      }
      if (uploadedPath != null) {
        try {
          await _supabase.storage.from(_bucketName).remove([uploadedPath]);
        } catch (_) {
          // Не маскуємо початкову помилку, якщо очищення Storage не вдалося.
        }
      }
      rethrow;
    }
  }

  Future<void> updateLocation({
    required String locationId,
    required String title,
    required String description,
    required String category,
  }) async {
    await _supabase.rpc('update_own_location', params: {
      'p_location_id': locationId,
      'p_title': title.trim(),
      'p_description': description.trim(),
      'p_category': category,
    });
  }

  Future<void> deleteLocation(String locationId) async {
    final photoRows = await _supabase
        .from('location_photos')
        .select('storage_path')
        .eq('location_id', locationId);
    final storagePaths = photoRows
        .map((row) => row['storage_path'] as String?)
        .whereType<String>()
        .toList(growable: false);

    await _supabase.from('locations').delete().eq('id', locationId);
    if (storagePaths.isNotEmpty) {
      await _supabase.storage.from(_bucketName).remove(storagePaths);
    }
  }

  static _ImageType _imageType(String? fileName) {
    final extension = fileName?.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => const _ImageType('png', 'image/png'),
      'webp' => const _ImageType('webp', 'image/webp'),
      'heic' || 'heif' => const _ImageType('heic', 'image/heic'),
      _ => const _ImageType('jpg', 'image/jpeg'),
    };
  }
}

class LocationDetailsData {
  const LocationDetailsData({
    required this.location,
    required this.photoUrls,
    required this.tags,
  });

  final LocationModel location;
  final List<String> photoUrls;
  final List<String> tags;
}

class _ImageType {
  const _ImageType(this.extension, this.contentType);

  final String extension;
  final String contentType;
}

class LocationsCache {
  const LocationsCache(this._preferences);

  final SharedPreferences _preferences;

  String _key(String userId) => 'locations_cache_v1_$userId';

  List<LocationModel> read(String userId) {
    final value = _preferences.getString(_key(userId));
    if (value == null) return const [];
    try {
      final rows = jsonDecode(value) as List<dynamic>;
      return rows
          .map((row) => LocationModel.fromMap(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> write(String userId, List<LocationModel> locations) {
    return _preferences.setString(
      _key(userId),
      jsonEncode(locations.map((location) => location.toCacheMap()).toList()),
    );
  }
}

@riverpod
LocationsRepository locationsRepository(Ref ref) {
  return LocationsRepository(Supabase.instance.client);
}

class MapLocationResult {
  const MapLocationResult({required this.items, required this.totalCount});
  final List<LocationModel> items;
  final int totalCount;
}

final viewportLocationsProvider = FutureProvider.autoDispose
    .family<MapLocationResult, MapViewportQuery>((ref, query) async {
  return ref.watch(locationsRepositoryProvider).fetchLocationsInBounds(query);
});

final filterCountProvider = FutureProvider.autoDispose
    .family<int, MapViewportQuery>((ref, query) async {
  final result = await ref
      .watch(locationsRepositoryProvider)
      .fetchLocationsInBounds(query, limit: 1);
  return result.totalCount;
});

typedef NearbyLocationQuery = ({
  double latitude,
  double longitude,
  double radiusMeters,
  String? category,
});

final nearbyLocationsProvider = FutureProvider.autoDispose
    .family<List<LocationQueryItem>, NearbyLocationQuery>((ref, query) {
  return ref.watch(locationsRepositoryProvider).fetchNearbyLocations(
        latitude: query.latitude,
        longitude: query.longitude,
        radiusMeters: query.radiusMeters,
        category: query.category,
      );
});

final savedLocationsProvider = FutureProvider.autoDispose
    .family<List<LocationModel>, Set<String>>((ref, ids) {
  return ref.watch(locationsRepositoryProvider).fetchLocationsByIds(ids);
});

final locationDetailsProvider = FutureProvider.autoDispose
    .family<LocationDetailsData, String>((ref, locationId) {
  return ref
      .watch(locationsRepositoryProvider)
      .fetchLocationDetails(locationId);
});

@riverpod
Future<LocationsCache> locationsCache(Ref ref) async {
  return LocationsCache(await SharedPreferences.getInstance());
}

@riverpod
Stream<List<LocationModel>> fetchLocations(Ref ref) async* {
  final currentUserId = Supabase.instance.client.auth.currentUser?.id;
  if (currentUserId == null) {
    yield const [];
    return;
  }

  final cache = await ref.watch(locationsCacheProvider.future);
  final cachedLocations = cache.read(currentUserId);
  yield cachedLocations;

  final networkStatus = ref.watch(networkStatusProvider).value;
  if (networkStatus != NetworkStatus.online) return;

  try {
    final remoteLocations =
        await ref.watch(locationsRepositoryProvider).fetchLocations();
    await cache.write(currentUserId, remoteLocations);
    yield remoteLocations;
  } catch (_) {
    // Keep serving stale cache when connectivity exists but the API is
    // temporarily unavailable. A connectivity change or retry refreshes it.
  }
}
