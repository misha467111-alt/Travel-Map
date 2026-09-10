import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/presentation/clustered_location_map.dart';

void main() {
  group('InitialGpsCameraPolicy', () {
    test('first valid GPS position claims one automatic camera recenter', () {
      final policy = InitialGpsCameraPolicy();

      expect(policy.claimInitialRecenter(), isTrue);
    });

    test('later GPS updates do not claim another automatic recenter', () {
      final policy = InitialGpsCameraPolicy();

      expect(policy.claimInitialRecenter(), isTrue);
      expect(policy.claimInitialRecenter(), isFalse);
      expect(policy.claimInitialRecenter(), isFalse);
    });

    test('a fresh map entry gets its own initial recenter', () {
      final firstEntry = InitialGpsCameraPolicy();
      final nextEntry = InitialGpsCameraPolicy();

      expect(firstEntry.claimInitialRecenter(), isTrue);
      expect(firstEntry.claimInitialRecenter(), isFalse);
      expect(nextEntry.claimInitialRecenter(), isTrue);
    });
  });
}
