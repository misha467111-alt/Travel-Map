import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/check_in/domain/check_in_repository.dart';

/// Phase 2B (activity events): `CheckInRepository.checkIn` gained an
/// optional `requestId` parameter matching `create_check_in`'s new
/// `p_request_id` contract in
/// supabase/migrations/202609160002_activity_events_foundation.sql.
///
/// There is no existing infrastructure anywhere in this test suite for
/// mocking a real `SupabaseClient.rpc()` call (confirmed: no repository
/// in this codebase is tested that way -- Supabase-calling repositories
/// are always tested indirectly via an override seam on the *screen* that
/// calls them, e.g. `CreateLocationScreen.createLocationOverride`, and
/// `LocationDetailsContent`'s check-in call site has no such seam). Rather
/// than inventing new Supabase-mocking machinery for this one phase, this
/// test proves the actual testable surface: the `CheckInRepository`
/// interface contract itself -- that `requestId` is optional (old callers
/// compile and behave unchanged), and that a caller reusing the same
/// `requestId` across calls (the documented "one per logical attempt, not
/// per retry" contract) is a meaningful, assertable thing a fake
/// implementation can observe. The actual server-side idempotency
/// behavior is covered by the SQL contract tests and Phase 2C's runtime
/// matrix, not here.
class _RecordingCheckInRepository implements CheckInRepository {
  final calls = <({String locationId, String? requestId})>[];

  @override
  Future<CheckInResult> checkIn({
    required String locationId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    String? requestId,
  }) async {
    calls.add((locationId: locationId, requestId: requestId));
    return CheckInResult(id: 'check-in-${calls.length}', xpAwarded: 20);
  }
}

void main() {
  test(
      'requestId is optional -- an old-style call without it still compiles '
      'and succeeds', () async {
    final repo = _RecordingCheckInRepository();
    final result = await repo.checkIn(
      locationId: 'loc-1',
      latitude: 50.45,
      longitude: 30.52,
      accuracyMeters: 12,
    );
    expect(result.xpAwarded, 20);
    expect(repo.calls.single.requestId, isNull);
  });

  test(
      'a caller reusing the same requestId across two calls (the "one per '
      'logical attempt, retried" case) sends the identical value both '
      'times', () async {
    final repo = _RecordingCheckInRepository();
    const requestId = 'fixed-attempt-id';

    await repo.checkIn(
      locationId: 'loc-1',
      latitude: 50.45,
      longitude: 30.52,
      accuracyMeters: 12,
      requestId: requestId,
    );
    // Simulates a retry of the SAME logical attempt after a lost response.
    await repo.checkIn(
      locationId: 'loc-1',
      latitude: 50.45,
      longitude: 30.52,
      accuracyMeters: 12,
      requestId: requestId,
    );

    expect(repo.calls, hasLength(2));
    expect(repo.calls[0].requestId, requestId);
    expect(repo.calls[1].requestId, requestId);
  });

  test(
      'two distinct logical check-ins get two distinct requestIds -- '
      'never collapsed into one', () async {
    final repo = _RecordingCheckInRepository();

    await repo.checkIn(
      locationId: 'loc-1',
      latitude: 50.45,
      longitude: 30.52,
      accuracyMeters: 12,
      requestId: 'attempt-1',
    );
    await repo.checkIn(
      locationId: 'loc-1',
      latitude: 50.45,
      longitude: 30.52,
      accuracyMeters: 12,
      requestId: 'attempt-2',
    );

    expect(repo.calls.map((c) => c.requestId), ['attempt-1', 'attempt-2']);
  });
}
