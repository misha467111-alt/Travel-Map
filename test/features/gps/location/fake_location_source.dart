import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/features/gps/location/location_source.dart';

/// A fully in-memory [LocationSource] for tests — never touches real GPS
/// hardware, real OS permission dialogs, or real location services.
/// Every behavior is scriptable by the test.
class FakeLocationSource implements LocationSource {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.denied;

  /// If set, requestPermission() "grants" this value (updating
  /// [permission] to match) instead of returning [permission]
  /// unchanged — simulates the user actually responding to the OS
  /// prompt. Leave null to simulate the user dismissing/ignoring it.
  LocationPermission? permissionGrantedOnRequest;

  /// Incremented on every requestPermission() call — lets a test assert
  /// the OS prompt would have been shown exactly once, not repeatedly.
  int requestPermissionCallCount = 0;

  final _positionController = StreamController<Position>.broadcast();
  final _serviceStatusController = StreamController<ServiceStatus>.broadcast();

  /// How many times getPositionStream has been subscribed to — lets a
  /// test assert there is never more than one live subscription at a
  /// time (task 10's "prevent duplicate active stream subscriptions").
  int subscribeCallCount = 0;
  int activeSubscriptionCount = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCallCount++;
    if (permissionGrantedOnRequest != null) {
      permission = permissionGrantedOnRequest!;
    }
    return permission;
  }

  @override
  Stream<Position> getPositionStream({required LocationSettings settings}) {
    subscribeCallCount++;
    late StreamController<Position> forwarder;
    forwarder = StreamController<Position>(
      onListen: () => activeSubscriptionCount++,
      onCancel: () => activeSubscriptionCount--,
    );
    final sub = _positionController.stream
        .listen(forwarder.add, onError: forwarder.addError);
    forwarder.onCancel = () {
      activeSubscriptionCount--;
      sub.cancel();
    };
    return forwarder.stream;
  }

  @override
  Stream<ServiceStatus> getServiceStatusStream() =>
      _serviceStatusController.stream;

  void emitPosition(Position position) => _positionController.add(position);
  void emitStreamError(Object error) => _positionController.addError(error);
  void emitServiceStatus(ServiceStatus status) =>
      _serviceStatusController.add(status);

  Future<void> dispose() async {
    await _positionController.close();
    await _serviceStatusController.close();
  }
}

/// Builds a valid, fully-populated [Position] for tests, with sane
/// defaults for every field so a test only has to override what it
/// actually cares about.
Position testPosition({
  double latitude = 50.45,
  double longitude = 30.52,
  DateTime? timestamp,
  double altitude = 100,
  double altitudeAccuracy = 2,
  double accuracy = 5,
  double speed = 1.2,
  double speedAccuracy = 0.5,
  double heading = 90,
  double headingAccuracy = 3,
  bool hasAltitude = true,
  bool hasAccuracy = true,
  bool hasSpeed = true,
  bool hasSpeedAccuracy = true,
  bool hasHeading = true,
  bool hasHeadingAccuracy = true,
  bool hasAltitudeAccuracy = true,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime.utc(2026, 1, 1, 10),
    altitude: altitude,
    altitudeAccuracy: altitudeAccuracy,
    accuracy: accuracy,
    heading: heading,
    headingAccuracy: headingAccuracy,
    speed: speed,
    speedAccuracy: speedAccuracy,
    isMocked: false,
    hasAccuracy: hasAccuracy,
    hasAltitude: hasAltitude,
    hasAltitudeAccuracy: hasAltitudeAccuracy,
    hasHeading: hasHeading,
    hasHeadingAccuracy: hasHeadingAccuracy,
    hasSpeed: hasSpeed,
    hasSpeedAccuracy: hasSpeedAccuracy,
  );
}
