import 'package:flutter/material.dart';

class LocationCategoryDefinition {
  const LocationCategoryDefinition(
    this.key,
    this.label,
    this.icon,
    this.referenceColor,
  );
  final String key;
  final String label;
  final IconData icon;
  final Color referenceColor;
}

const referenceLocationCategories = <LocationCategoryDefinition>[
  LocationCategoryDefinition(
      'all', 'Усі', Icons.auto_awesome, Color(0xFFD4A017)),
  LocationCategoryDefinition(
      'cafe', 'Кафе', Icons.local_cafe, Color(0xFFF5F0E6)),
  LocationCategoryDefinition(
      'nature', 'Природа', Icons.park, Color(0xFF69B64C)),
  LocationCategoryDefinition(
      'culture', 'Культура', Icons.account_balance, Color(0xFFE46D65)),
  LocationCategoryDefinition(
      'entertainment', 'Розваги', Icons.theater_comedy, Color(0xFFB45ACB)),
  LocationCategoryDefinition('active_outdoors', 'Активний\nвідпочинок',
      Icons.directions_run, Color(0xFFF09A24)),
  LocationCategoryDefinition(
      'viewpoints', 'Оглядові\nмісця', Icons.photo_camera, Color(0xFF42B7D6)),
  LocationCategoryDefinition(
      'historic', 'Історичні\nмісця', Icons.castle, Color(0xFFD2A36A)),
  LocationCategoryDefinition(
      'events', 'Події', Icons.music_note, Color(0xFFA85AC7)),
  LocationCategoryDefinition(
      'romance', 'Романтика', Icons.favorite, Color(0xFFE94D79)),
  LocationCategoryDefinition(
      'shopping', 'Шопінг', Icons.shopping_bag, Color(0xFFE05BB1)),
  LocationCategoryDefinition(
      'kids', 'Для дітей', Icons.child_care, Color(0xFFF0784E)),
];

const legacyGeneralCategory = LocationCategoryDefinition(
    'general', 'Загальне', Icons.place, Color(0xFFD4A017));

final locationCategoryByKey = <String, LocationCategoryDefinition>{
  for (final value in referenceLocationCategories) value.key: value,
  legacyGeneralCategory.key: legacyGeneralCategory,
};

List<LocationCategoryDefinition> get editableLocationCategories => [
      legacyGeneralCategory,
      ...referenceLocationCategories.where((value) => value.key != 'all'),
    ];

LocationCategoryDefinition locationCategoryDefinition(String key) =>
    locationCategoryByKey[key] ?? legacyGeneralCategory;
