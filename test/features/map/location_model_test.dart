import 'package:flutter_application_1/features/map/domain/location_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const longitude = 30.52;
  const latitude = 50.45;

  Map<String, dynamic> row(dynamic point) => {
        'id': 'location-id',
        'user_id': 'user-id',
        'title': 'Kyiv',
        'description': null,
        'image_url': 'https://example.supabase.co/location.jpg',
        'location': point,
        'created_at': '2026-08-25T12:00:00Z',
      };

  test('parses a GeoJSON map', () {
    final location = LocationModel.fromMap(
      row({
        'type': 'Point',
        'coordinates': [longitude, latitude],
      }),
    );

    expect(location.longitude, longitude);
    expect(location.latitude, latitude);
    expect(location.category, 'general');
    expect(
      location.imageUrl,
      'https://example.supabase.co/location.jpg',
    );
  });

  test('parses a supported category', () {
    final location = LocationModel.fromMap(
        {...row('POINT(30.52 50.45)'), 'category': 'nature'});
    expect(location.category, 'nature');
  });

  test('parses a GeoJSON string', () {
    final location = LocationModel.fromMap(
      row('{"type":"Point","coordinates":[30.52,50.45]}'),
    );

    expect(location.longitude, longitude);
    expect(location.latitude, latitude);
  });

  test('parses WKT and EWKT points', () {
    for (final point in [
      'POINT(30.52 50.45)',
      'SRID=4326;POINT(30.52 50.45)',
    ]) {
      final location = LocationModel.fromMap(row(point));
      expect(location.longitude, longitude);
      expect(location.latitude, latitude);
    }
  });

  test('parses a little-endian PostGIS EWKB point', () {
    final location = LocationModel.fromMap(
      row('0101000020E610000085EB51B81E853E40713D0AD7A3384940'),
    );

    expect(location.longitude, closeTo(longitude, 0.000001));
    expect(location.latitude, closeTo(50.4425, 0.000001));
  });
}
