class CheckInResult {
  const CheckInResult({required this.id, required this.xpAwarded});
  final String id;
  final int xpAwarded;
}

abstract interface class CheckInRepository {
  /// [requestId], when supplied, must be generated ONCE per logical
  /// check-in attempt (not per network retry) -- see
  /// `create_check_in`'s own `p_request_id` contract
  /// (supabase/migrations/202609160002_activity_events_foundation.sql).
  /// An exact retry with the same [requestId] returns the original
  /// result instead of creating a second check-in or double-awarding XP;
  /// omitting it reproduces the previous (pre-Phase 2B) behavior exactly.
  Future<CheckInResult> checkIn({
    required String locationId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    String? requestId,
  });
}
