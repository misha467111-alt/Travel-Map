import 'package:supabase_flutter/supabase_flutter.dart';

import '../../local/gps_local_database.dart';
import '../domain/gps_sync_repository.dart';

/// Talks to the GPS Sync Phase 3B/3D production backend: the
/// `recorded_routes`/`route_waypoints` tables directly (via PostgREST,
/// the same way every other Supabase-backed repository in this codebase
/// reaches its tables), and the `sync_route_points`/`sync_route_events`/
/// `finalize_recorded_route` RPCs.
class SupabaseGpsSyncRepository implements GpsSyncRepository {
  const SupabaseGpsSyncRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<void> ensureRouteShell({
    required String routeId,
    String? tripId,
    String? title,
    required String transportMode,
    required String visibility,
    required DateTime startedAt,
  }) async {
    final payload = <String, dynamic>{
      'id': routeId,
      'transport_mode': transportMode,
      'visibility': visibility,
      'started_at': startedAt.toIso8601String(),
      if (tripId != null) 'trip_id': tripId,
      if (title != null) 'title': title,
    };
    try {
      // ignoreDuplicates: true -> `Prefer: resolution=ignore-duplicates`,
      // i.e. INSERT-or-skip, never UPDATE-on-conflict. This is what makes
      // "ensure the shell exists" safe to call on every sync pass without
      // ever risking overwriting a row the server (or a previous sync
      // pass) already created -- ownerId/status/createdAt are already
      // server-managed (see the class's own field grants), and this
      // guarantees none of this payload's fields are ever rewritten on an
      // existing row either.
      await _client.from('recorded_routes').upsert(
            payload,
            onConflict: 'id',
            ignoreDuplicates: true,
          );
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<int> syncPoints({
    required String routeId,
    required List<LocalRoutePoint> points,
  }) async {
    try {
      final result = await _client.rpc<Object?>(
        'sync_route_points',
        params: {
          'p_recorded_route_id': routeId,
          'p_points': points.map(_pointPayload).toList(growable: false),
        },
      );
      return _asCursor(result);
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<int> syncEvents({
    required String routeId,
    required List<LocalRouteEvent> events,
  }) async {
    try {
      final result = await _client.rpc<Object?>(
        'sync_route_events',
        params: {
          'p_recorded_route_id': routeId,
          'p_events': events.map(_eventPayload).toList(growable: false),
        },
      );
      return _asCursor(result);
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> upsertWaypoint(LocalWaypoint waypoint) async {
    final insertPayload = <String, dynamic>{
      'id': waypoint.id,
      'recorded_route_id': waypoint.recordedRouteId,
      'waypoint_type': waypoint.waypointType,
      'position': _pointWkt(waypoint.longitude, waypoint.latitude),
      'recorded_at': waypoint.recordedAt.toIso8601String(),
      if (waypoint.title != null) 'title': waypoint.title,
      if (waypoint.note != null) 'note': waypoint.note,
      if (waypoint.altitude != null) 'altitude_m': waypoint.altitude,
      if (waypoint.photoRef != null) 'photo_ref': waypoint.photoRef,
    };
    try {
      await _client.from('route_waypoints').insert(insertPayload);
    } on PostgrestException catch (error) {
      if (error.code != '23505') throw _translate(error);
      // Already exists server-side (a previously-synced waypoint that
      // was locally edited and re-queued) -- fall back to updating only
      // the fields the server actually grants `authenticated` UPDATE on
      // (waypoint_type/title/note/photo_ref -- see route_waypoints'
      // grants in 202609140004_gps_table_acl_hardening.sql). Telemetry/
      // identity fields are immutable once recorded server-side and are
      // never included here.
      try {
        await _client.from('route_waypoints').update({
          'waypoint_type': waypoint.waypointType,
          'title': waypoint.title,
          'note': waypoint.note,
          'photo_ref': waypoint.photoRef,
        }).eq('id', waypoint.id);
      } catch (updateError) {
        throw _translate(updateError);
      }
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> deleteWaypoint(String waypointId) async {
    try {
      await _client.from('route_waypoints').delete().eq('id', waypointId);
    } catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<GpsFinalizeResponse> finalizeRoute(String routeId) async {
    try {
      final result = await _client.rpc<Object?>(
        'finalize_recorded_route',
        params: {'p_recorded_route_id': routeId},
      );
      if (result is Map<String, dynamic>) {
        final id = result['id'];
        final status = result['status'];
        if (id is String && status is String) {
          return GpsFinalizeResponse(id: id, status: status);
        }
      }
      throw GpsSyncException(
        GpsSyncErrorKind.integrityConflict,
        'finalize_recorded_route returned an unexpected shape: $result',
      );
    } on GpsSyncException {
      rethrow;
    } catch (error) {
      throw _translate(error);
    }
  }

  static Map<String, dynamic> _pointPayload(LocalRoutePoint point) => {
        'seq': point.seq,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'altitude_m': point.altitude,
        'horizontal_accuracy_m': point.horizontalAccuracy,
        'vertical_accuracy_m': point.verticalAccuracy,
        'speed_mps': point.speed,
        'speed_accuracy_mps': point.speedAccuracy,
        'heading_deg': point.heading,
        'heading_accuracy_deg': point.headingAccuracy,
        'recorded_at': point.recordedAt.toIso8601String(),
        'provider': point.provider,
      };

  static Map<String, dynamic> _eventPayload(LocalRouteEvent event) => {
        'seq': event.seq,
        'event_type': event.eventType,
        'occurred_at': event.occurredAt.toIso8601String(),
      };

  static String _pointWkt(double longitude, double latitude) =>
      'SRID=4326;POINT($longitude $latitude)';

  static int _asCursor(Object? result) {
    if (result is int) return result;
    if (result is num) return result.toInt();
    throw GpsSyncException(
      GpsSyncErrorKind.integrityConflict,
      'sync RPC returned a non-integer cursor: $result',
    );
  }

  /// Maps the server's classified SQLSTATE codes (see
  /// `202609170001_gps_sync_backend_contract.sql`) onto [GpsSyncErrorKind].
  /// Anything unrecognized -- including a raw network/timeout failure,
  /// which never even reaches Postgres and so is never a
  /// [PostgrestException] at all -- defaults to retryable: an
  /// unclassified error must never permanently bury a route as 'failed'.
  static GpsSyncException _translate(Object error) {
    if (error is GpsSyncException) return error;
    if (error is PostgrestException) {
      switch (error.code) {
        case '28000': // auth required -- session missing/expired
          return GpsSyncException(GpsSyncErrorKind.retryable, error.message);
        case '42501': // owner mismatch / not found-or-access-denied
          return GpsSyncException(
              GpsSyncErrorKind.ownerMismatch, error.message);
        case '23505': // conflicting retry: same identity, different data
          return GpsSyncException(
              GpsSyncErrorKind.integrityConflict, error.message);
        case '22023': // structurally invalid payload
          return GpsSyncException(
              GpsSyncErrorKind.invalidPayload, error.message);
        case '55000': // route already terminal server-side, unexpectedly
          return GpsSyncException(
              GpsSyncErrorKind.integrityConflict, error.message);
        default:
          return GpsSyncException(GpsSyncErrorKind.retryable, error.message);
      }
    }
    return GpsSyncException(GpsSyncErrorKind.retryable, error.toString());
  }
}
