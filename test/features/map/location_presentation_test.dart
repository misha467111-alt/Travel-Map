import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/presentation/location_card.dart';

void main() {
  test('canonical category values map to localized presentation labels', () {
    expect(locationCategoryLabel('cafe'), 'Кафе');
    expect(locationCategoryLabel('nature'), 'Природа');
    expect(locationCategoryLabel('culture'), 'Культура');
    expect(locationCategoryLabel('entertainment'), 'Розваги');
    expect(locationCategoryLabel('general'), 'Локація');
  });
}
