import 'package:geolocator/geolocator.dart' show LocationPermission;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/location/location_permission_service.dart';
import 'package:flutter_application_1/features/gps/location/location_permission_state.dart';

import 'fake_location_source.dart';

void main() {
  late FakeLocationSource source;
  late LocationPermissionService service;

  setUp(() {
    source = FakeLocationSource();
    service = LocationPermissionService(source);
  });

  tearDown(() => source.dispose());

  group('checkReadiness (never prompts)', () {
    test('reports serviceDisabled without touching permission at all',
        () async {
      source.serviceEnabled = false;
      final readiness = await service.checkReadiness();
      expect(readiness, LocationReadiness.serviceDisabled);
      expect(source.requestPermissionCallCount, 0);
    });

    test('reports granted for whileInUse', () async {
      source.permission = LocationPermission.whileInUse;
      expect(await service.checkReadiness(), LocationReadiness.granted);
    });

    test('reports granted for always', () async {
      source.permission = LocationPermission.always;
      expect(await service.checkReadiness(), LocationReadiness.granted);
    });

    test('reports denied', () async {
      source.permission = LocationPermission.denied;
      expect(await service.checkReadiness(), LocationReadiness.denied);
    });

    test('reports deniedForever', () async {
      source.permission = LocationPermission.deniedForever;
      expect(await service.checkReadiness(), LocationReadiness.deniedForever);
    });

    test('never calls requestPermission', () async {
      source.permission = LocationPermission.denied;
      await service.checkReadiness();
      expect(source.requestPermissionCallCount, 0);
    });
  });

  group('ensureReady (may prompt once)', () {
    test(
        'prompts exactly once when permission is denied and the prompt grants it',
        () async {
      source.permission = LocationPermission.denied;
      source.permissionGrantedOnRequest = LocationPermission.whileInUse;
      final readiness = await service.ensureReady();
      expect(readiness, LocationReadiness.granted);
      expect(source.requestPermissionCallCount, 1);
    });

    test(
        'prompts exactly once when permission is denied and the prompt is refused '
        'again', () async {
      source.permission = LocationPermission.denied;
      // permissionGrantedOnRequest left null: the user dismisses/refuses.
      final readiness = await service.ensureReady();
      expect(readiness, LocationReadiness.denied);
      expect(source.requestPermissionCallCount, 1);
    });

    test('never prompts when permission is already deniedForever', () async {
      source.permission = LocationPermission.deniedForever;
      final readiness = await service.ensureReady();
      expect(readiness, LocationReadiness.deniedForever);
      expect(source.requestPermissionCallCount, 0);
    });

    test('never prompts when location services are disabled', () async {
      source.serviceEnabled = false;
      final readiness = await service.ensureReady();
      expect(readiness, LocationReadiness.serviceDisabled);
      expect(source.requestPermissionCallCount, 0);
    });

    test('never prompts when already granted', () async {
      source.permission = LocationPermission.whileInUse;
      final readiness = await service.ensureReady();
      expect(readiness, LocationReadiness.granted);
      expect(source.requestPermissionCallCount, 0);
    });
  });
}
