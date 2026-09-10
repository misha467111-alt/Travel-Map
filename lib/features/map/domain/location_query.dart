import 'location_model.dart';

class AuthorSummary {
  const AuthorSummary({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? avatarUrl;
}

class LocationQueryItem {
  const LocationQueryItem({
    required this.location,
    required this.author,
    this.distanceMeters,
  });

  final LocationModel location;
  final AuthorSummary author;
  final double? distanceMeters;

  factory LocationQueryItem.fromRpcRow(Map<String, dynamic> row) {
    final location = LocationModel.fromMap(row);
    return LocationQueryItem(
      location: location,
      author: AuthorSummary(
        id: location.userId,
        name: (row['author_name'] as String?)?.trim().isNotEmpty == true
            ? (row['author_name'] as String).trim()
            : 'Мандрівник',
        avatarUrl: _optionalString(row['author_avatar_url']),
      ),
      distanceMeters: (row['distance_m'] as num?)?.toDouble(),
    );
  }

  static String? _optionalString(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}

class LocationCursor {
  const LocationCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;
}

class LocationPage {
  const LocationPage({required this.items, required this.hasMore});

  final List<LocationQueryItem> items;
  final bool hasMore;

  LocationCursor? get nextCursor => items.isEmpty
      ? null
      : LocationCursor(
          createdAt: items.last.location.createdAt,
          id: items.last.location.id,
        );
}

int boundedPageSize(int requested, {int maximum = 50}) =>
    requested.clamp(1, maximum);

class MapViewportBounds {
  const MapViewportBounds({
    required this.minLatitude,
    required this.minLongitude,
    required this.maxLatitude,
    required this.maxLongitude,
  });

  final double minLatitude;
  final double minLongitude;
  final double maxLatitude;
  final double maxLongitude;

  bool materiallyDiffersFrom(MapViewportBounds other) {
    final latitudeSpan = (maxLatitude - minLatitude).abs().clamp(0.001, 180);
    final longitudeSpan = (maxLongitude - minLongitude).abs().clamp(0.001, 360);
    return (minLatitude - other.minLatitude).abs() > latitudeSpan * 0.2 ||
        (maxLatitude - other.maxLatitude).abs() > latitudeSpan * 0.2 ||
        (minLongitude - other.minLongitude).abs() > longitudeSpan * 0.2 ||
        (maxLongitude - other.maxLongitude).abs() > longitudeSpan * 0.2;
  }
}

class MapViewportQuery {
  const MapViewportQuery({
    required this.bounds,
    this.category,
    this.userLatitude,
    this.userLongitude,
    this.maximumDistanceMeters,
    this.minimumRating,
    this.openNow = false,
    this.familyOnly = false,
    this.sort = 'newest',
  });
  final MapViewportBounds bounds;
  final String? category;
  final double? userLatitude;
  final double? userLongitude;
  final double? maximumDistanceMeters;
  final double? minimumRating;
  final bool openNow;
  final bool familyOnly;
  final String sort;

  @override
  bool operator ==(Object other) =>
      other is MapViewportQuery &&
      other.bounds.minLatitude == bounds.minLatitude &&
      other.bounds.minLongitude == bounds.minLongitude &&
      other.bounds.maxLatitude == bounds.maxLatitude &&
      other.bounds.maxLongitude == bounds.maxLongitude &&
      other.category == category &&
      other.userLatitude == userLatitude &&
      other.userLongitude == userLongitude &&
      other.maximumDistanceMeters == maximumDistanceMeters &&
      other.minimumRating == minimumRating &&
      other.openNow == openNow &&
      other.familyOnly == familyOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
        bounds.minLatitude,
        bounds.minLongitude,
        bounds.maxLatitude,
        bounds.maxLongitude,
        category,
        userLatitude,
        userLongitude,
        maximumDistanceMeters,
        minimumRating,
        openNow,
        familyOnly,
        sort,
      );
}
