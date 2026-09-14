import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/recording/gps_sample_validation.dart';

import '../location/fake_location_source.dart';

void main() {
  group('validateGpsSample', () {
    test('accepts a well-formed position', () {
      final sample = validateGpsSample(testPosition());
      expect(sample, isNotNull);
      expect(sample!.latitude, 50.45);
      expect(sample.longitude, 30.52);
    });

    test('rejects NaN latitude', () {
      final sample = validateGpsSample(testPosition(latitude: double.nan));
      expect(sample, isNull);
    });

    test('rejects infinite longitude', () {
      final sample =
          validateGpsSample(testPosition(longitude: double.infinity));
      expect(sample, isNull);
    });

    test('rejects latitude out of -90..90 range', () {
      expect(validateGpsSample(testPosition(latitude: 91)), isNull);
      expect(validateGpsSample(testPosition(latitude: -91)), isNull);
    });

    test('rejects longitude out of -180..180 range', () {
      expect(validateGpsSample(testPosition(longitude: 181)), isNull);
      expect(validateGpsSample(testPosition(longitude: -181)), isNull);
    });

    test('accepts boundary coordinates', () {
      expect(validateGpsSample(testPosition(latitude: 90, longitude: 180)),
          isNotNull);
      expect(validateGpsSample(testPosition(latitude: -90, longitude: -180)),
          isNotNull);
    });

    test(
        'omits altitude/speed/heading when the platform did not report them, '
        'rather than passing through a meaningless 0.0 placeholder', () {
      final sample = validateGpsSample(testPosition(
        hasAltitude: false,
        hasSpeed: false,
        hasHeading: false,
        hasAccuracy: false,
        hasAltitudeAccuracy: false,
        hasHeadingAccuracy: false,
        hasSpeedAccuracy: false,
      ));
      expect(sample, isNotNull);
      expect(sample!.altitude, isNull);
      expect(sample.speed, isNull);
      expect(sample.heading, isNull);
      expect(sample.horizontalAccuracy, isNull);
      expect(sample.verticalAccuracy, isNull);
      expect(sample.headingAccuracy, isNull);
      expect(sample.speedAccuracy, isNull);
    });

    test(
        'does NOT reject a legitimate high-speed sample -- speed-based '
        'filtering is deliberately not implemented client-side', () {
      final sample = validateGpsSample(testPosition(speed: 90)); // ~324 km/h
      expect(sample, isNotNull);
      expect(sample!.speed, 90);
    });

    test('normalizes the recorded timestamp to UTC', () {
      final sample =
          validateGpsSample(testPosition(timestamp: DateTime(2026, 1, 1, 12)));
      expect(sample!.recordedAt.isUtc, isTrue);
    });
  });
}
