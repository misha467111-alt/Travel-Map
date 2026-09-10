import 'dart:convert';
import 'dart:typed_data';

class LocationModel {
  const LocationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.imageUrl,
    this.status = 'draft',
    this.visibility = 'public',
    this.moderation = 'draft',
    this.updatedAt,
    this.rating,
    this.ratingsCount,
    this.openingHours,
    this.timezone,
    this.isFamilyFriendly,
    this.address,
    this.amenities,
    this.hasParking,
  });

  final String id;
  final String userId;
  final String title;
  final String? description;
  final String category;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String? imageUrl;
  final String status;
  final String visibility;
  final String moderation;
  final DateTime? updatedAt;
  final double? rating;
  final int? ratingsCount;
  final Map<String, dynamic>? openingHours;
  final String? timezone;
  final bool? isFamilyFriendly;
  final String? address;
  final List<String>? amenities;
  final bool? hasParking;

  List<String>? get presentedAmenities {
    if (amenities != null) return amenities;
    return hasParking == true ? const ['parking'] : null;
  }

  Map<String, dynamic> toCacheMap() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'description': description,
        'category': category,
        'latitude': latitude,
        'longitude': longitude,
        'created_at': createdAt.toIso8601String(),
        'image_url': imageUrl,
        'status': status,
        'visibility': visibility,
        'moderation': moderation,
        'updated_at': updatedAt?.toIso8601String(),
        'rating': rating,
        'ratings_count': ratingsCount,
        'opening_hours': openingHours,
        'timezone': timezone,
        'is_family_friendly': isFamilyFriendly,
        'address': address,
        'amenities': amenities,
        'has_parking': hasParking,
      };

  factory LocationModel.fromMap(Map<String, dynamic> map) {
    final coordinates = _coordinatesFrom(map);

    return LocationModel(
      id: map['id'] as String,
      userId: (map['user_id'] ?? map['owner_id']) as String,
      title: (map['title'] ?? map['name']) as String,
      description: map['description'] as String?,
      category: _categoryFrom(map['category']),
      longitude: coordinates.$1,
      latitude: coordinates.$2,
      createdAt: DateTime.parse(map['created_at'] as String),
      imageUrl: _optionalString(map['image_url']),
      status: _optionalString(map['status']) ?? 'draft',
      visibility: _optionalString(map['visibility']) ?? 'public',
      moderation: _optionalString(map['moderation']) ?? 'draft',
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? ''),
      rating: (map['rating'] as num?)?.toDouble(),
      ratingsCount: (map['ratings_count'] as num?)?.toInt(),
      openingHours: map['opening_hours'] is Map
          ? Map<String, dynamic>.from(map['opening_hours'] as Map)
          : null,
      timezone: _optionalString(map['timezone']),
      isFamilyFriendly: map['is_family_friendly'] as bool?,
      address: _optionalString(map['address']),
      amenities: map['amenities'] is List
          ? (map['amenities'] as List)
              .whereType<String>()
              .toList(growable: false)
          : null,
      hasParking: map['has_parking'] as bool?,
    );
  }

  static String _categoryFrom(dynamic value) {
    const supported = {
      'general',
      'cafe',
      'nature',
      'culture',
      'entertainment',
      'active_outdoors',
      'viewpoints',
      'historic',
      'events',
      'romance',
      'shopping',
      'kids',
    };
    return value is String && supported.contains(value) ? value : 'general';
  }

  static String? _optionalString(dynamic value) {
    if (value is! String) return null;
    final result = value.trim();
    return result.isEmpty ? null : result;
  }

  static (double, double) _coordinatesFrom(Map<String, dynamic> map) {
    final longitude = map['longitude'];
    final latitude = map['latitude'];
    if (longitude is num && latitude is num) {
      return _validated(longitude.toDouble(), latitude.toDouble());
    }

    final value = map['coordinates'] ?? map['position'] ?? map['location'];
    return _parsePoint(value);
  }

  static (double, double) _parsePoint(dynamic value) {
    if (value is Map) {
      return _parseCoordinateList(value['coordinates']);
    }
    if (value is List) return _parseCoordinateList(value);

    if (value is String) {
      final text = value.trim();

      try {
        return _parsePoint(jsonDecode(text));
      } on FormatException {
        // The value is not JSON; try the PostGIS text/binary formats below.
      }

      final wktMatch = RegExp(
        r'(?:SRID=\d+;)?POINT\s*\(\s*([-+\d.eE]+)\s+([-+\d.eE]+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (wktMatch != null) {
        return _validated(
          double.parse(wktMatch.group(1)!),
          double.parse(wktMatch.group(2)!),
        );
      }

      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(text) && text.length.isEven) {
        return _parseEwkbPoint(text);
      }
    }

    throw FormatException(
      'Unsupported PostGIS point format: ${value.runtimeType}.',
    );
  }

  static (double, double) _parseCoordinateList(dynamic value) {
    if (value is! List || value.length < 2) {
      throw const FormatException(
        'PostGIS point must contain [longitude, latitude].',
      );
    }
    final longitude = value[0];
    final latitude = value[1];
    if (longitude is! num || latitude is! num) {
      throw const FormatException('PostGIS coordinates must be numbers.');
    }
    return _validated(longitude.toDouble(), latitude.toDouble());
  }

  static (double, double) _parseEwkbPoint(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = int.parse(
        hex.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    if (bytes.length < 21) {
      throw const FormatException('PostGIS EWKB point is incomplete.');
    }

    final data = ByteData.sublistView(bytes);
    final endian = bytes[0] == 0 ? Endian.big : Endian.little;
    final geometryType = data.getUint32(1, endian);
    final hasSrid = geometryType & 0x20000000 != 0;
    final coordinateOffset = hasSrid ? 9 : 5;
    if (bytes.length < coordinateOffset + 16) {
      throw const FormatException('PostGIS EWKB point has no coordinates.');
    }

    return _validated(
      data.getFloat64(coordinateOffset, endian),
      data.getFloat64(coordinateOffset + 8, endian),
    );
  }

  static (double, double) _validated(double longitude, double latitude) {
    if (!longitude.isFinite ||
        !latitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        latitude < -90 ||
        latitude > 90) {
      throw FormatException(
        'Invalid coordinates: [$longitude, $latitude].',
      );
    }
    return (longitude, latitude);
  }
}
