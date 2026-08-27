import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/check_in_repository.dart';

class SupabaseCheckInRepository implements CheckInRepository {
  const SupabaseCheckInRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<CheckInResult> checkIn({
    required String locationId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
  }) async {
    final value =
        await _client.rpc<Map<String, dynamic>>('create_check_in', params: {
      'target_location_id': locationId,
      'user_lat': latitude,
      'user_lng': longitude,
      'gps_accuracy_m': accuracyMeters,
    });
    return CheckInResult(
      id: value['check_in_id'] as String,
      xpAwarded: value['xp_awarded'] as int,
    );
  }
}
