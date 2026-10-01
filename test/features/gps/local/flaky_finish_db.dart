import 'dart:async';

import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';

/// Test seam: throws from [finishRecordingLocally] while [failFinish] is
/// set, counts calls, and can hold every [appendRoutePoint] open on
/// [appendGate] -- the hooks needed to prove local-finalization failure
/// handling and the finish-vs-in-flight-point ordering deterministically,
/// without altering production code.
class FlakyFinishDb extends GpsLocalDatabase {
  FlakyFinishDb(super.executor) : super.forTesting();
  bool failFinish = false;
  int finishCalls = 0;

  /// While non-null, an [appendRoutePoint] call is "in flight" (issued by
  /// the controller, not yet entered into the database) until completed.
  Completer<void>? appendGate;

  @override
  Future<bool> appendRoutePoint({
    required String ownerId,
    required String recordedRouteId,
    required double latitude,
    required double longitude,
    double? altitude,
    double? horizontalAccuracy,
    double? verticalAccuracy,
    double? speed,
    double? speedAccuracy,
    double? heading,
    double? headingAccuracy,
    required DateTime recordedAt,
    String? provider,
  }) async {
    final gate = appendGate;
    if (gate != null) await gate.future;
    return super.appendRoutePoint(
      ownerId: ownerId,
      recordedRouteId: recordedRouteId,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      horizontalAccuracy: horizontalAccuracy,
      verticalAccuracy: verticalAccuracy,
      speed: speed,
      speedAccuracy: speedAccuracy,
      heading: heading,
      headingAccuracy: headingAccuracy,
      recordedAt: recordedAt,
      provider: provider,
    );
  }

  @override
  Future<void> finishRecordingLocally({
    required String ownerId,
    required String routeId,
    required DateTime occurredAt,
  }) {
    finishCalls++;
    if (failFinish) return Future.error(StateError('disk full'));
    return super.finishRecordingLocally(
        ownerId: ownerId, routeId: routeId, occurredAt: occurredAt);
  }
}
