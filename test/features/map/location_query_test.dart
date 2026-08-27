import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_query.dart';

Map<String, dynamic> row({
  String id = '11111111-1111-1111-1111-111111111111',
  String title = 'Карпати',
  String category = 'nature',
  double? distance,
}) =>
    {
      'id': id,
      'user_id': '22222222-2222-2222-2222-222222222222',
      'title': title,
      'description': 'Гірська локація',
      'coordinates': {
        'type': 'Point',
        'coordinates': [24.5, 48.5],
      },
      'created_at': '2026-08-27T10:00:00Z',
      'image_url': null,
      'category': category,
      'status': 'approved',
      'visibility': 'public',
      'moderation': 'approved',
      'updated_at': null,
      'author_name': 'Олена',
      'author_avatar_url': 'https://example.com/avatar.jpg',
      if (distance != null) 'distance_m': distance,
    };

void main() {
  test('maps explicit RPC row and lightweight author summary', () {
    final item = LocationQueryItem.fromRpcRow(row());

    expect(item.location.title, 'Карпати');
    expect(item.location.latitude, 48.5);
    expect(item.location.longitude, 24.5);
    expect(item.author.name, 'Олена');
    expect(item.author.avatarUrl, 'https://example.com/avatar.jpg');
    expect(item.distanceMeters, isNull);
  });

  test('maps nearby distance', () {
    final item = LocationQueryItem.fromRpcRow(row(distance: 1234.5));
    expect(item.distanceMeters, 1234.5);
  });

  test('empty page has no next cursor', () {
    const page = LocationPage(items: [], hasMore: false);
    expect(page.nextCursor, isNull);
  });

  test('next cursor is derived from the final deterministic row', () {
    final first = LocationQueryItem.fromRpcRow(row());
    final second = LocationQueryItem.fromRpcRow(row(
      id: '33333333-3333-3333-3333-333333333333',
      title: 'Озеро',
    ));
    final page = LocationPage(items: [first, second], hasMore: true);

    expect(page.nextCursor?.id, second.location.id);
    expect(page.nextCursor?.createdAt, second.location.createdAt);
  });

  test('page limits are hard bounded', () {
    expect(boundedPageSize(0), 1);
    expect(boundedPageSize(30), 30);
    expect(boundedPageSize(1000), 50);
    expect(boundedPageSize(1000, maximum: 500), 500);
  });

  test('category remains canonical through RPC mapping', () {
    final item = LocationQueryItem.fromRpcRow(row(category: 'cafe'));
    expect(item.location.category, 'cafe');
  });
}
