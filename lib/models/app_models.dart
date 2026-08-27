import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:uuid/uuid.dart';

import '../features/map/domain/location_model.dart';

enum PlaceCategory {
  rest,
  landscape,
  sights,
  food,
  photo,
  swimming,
  fishing,
  camping,
  romantic
}

extension PlaceCategoryExt on PlaceCategory {
  String get label {
    switch (this) {
      case PlaceCategory.rest:
        return '🏕️ Відпочинок';
      case PlaceCategory.landscape:
        return '🌄 Краєвиди';
      case PlaceCategory.sights:
        return '🏛️ Історичні';
      case PlaceCategory.food:
        return '🍽️ Заклади';
      case PlaceCategory.photo:
        return '📸 Фото';
      case PlaceCategory.swimming:
        return '🏊 Купання';
      case PlaceCategory.fishing:
        return '🎣 Риболовля';
      case PlaceCategory.camping:
        return '🏕️ Кемпінги';
      case PlaceCategory.romantic:
        return '❤️ Романтичні';
    }
  }
}

class LocationPreview {
  const LocationPreview({
    required this.id,
    required this.title,
    required this.description,
    required this.position,
    required this.category,
    required this.authorId,
    required this.imageUrls,
  });

  final String id;
  final String title;
  final String description;
  final gm.LatLng position;
  final PlaceCategory category;
  final String authorId;
  final List<String> imageUrls;

  factory LocationPreview.fromLocationJson(Map<String, dynamic> json) {
    final location = LocationModel.fromMap(json);
    return LocationPreview(
      id: location.id,
      title: location.title,
      description: location.description ?? '',
      position: gm.LatLng(location.latitude, location.longitude),
      category: _categoryFromCanonical(location.category),
      authorId: location.userId,
      imageUrls: [
        if (location.imageUrl != null) location.imageUrl!,
      ],
    );
  }

  static PlaceCategory _categoryFromCanonical(dynamic value) => switch (value) {
        'cafe' => PlaceCategory.food,
        'nature' => PlaceCategory.landscape,
        'culture' => PlaceCategory.sights,
        'entertainment' => PlaceCategory.rest,
        _ => PlaceCategory.rest,
      };
}

class CustomRouteItem {
  final String id;
  String title;
  String description;
  String author;
  String authorId;
  List<gm.LatLng> points;
  List<String> likedByUsers;

  CustomRouteItem(
      {required this.id,
      required this.title,
      required this.description,
      required this.author,
      required this.authorId,
      required this.points,
      List<String>? likedByUsers})
      : likedByUsers = likedByUsers ?? [];

  int get likesCount => likedByUsers.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'author': author,
        'author_id': authorId,
        'points':
            points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        'liked_by_users': likedByUsers
      };

  factory CustomRouteItem.fromJson(Map<String, dynamic> json) =>
      CustomRouteItem(
          id: json['id'] ?? const Uuid().v4(),
          title: json['title'] ?? '',
          description: json['description'] ?? '',
          author: json['author'] ?? '',
          authorId: json['author_id'] ?? 'sys',
          points: (json['points'] as List? ?? [])
              .map((p) => gm.LatLng((p['lat'] as num?)?.toDouble() ?? 50.45,
                  (p['lng'] as num?)?.toDouble() ?? 30.52))
              .toList(),
          likedByUsers: List<String>.from(json['liked_by_users'] ?? []));
}
