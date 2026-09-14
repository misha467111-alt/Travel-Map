import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database.dart';
import 'package:flutter_application_1/features/gps/local/gps_local_database_provider.dart';

// Tests the centralized logout-guard *decision logic*
// (blockingActiveRecordingIdFor) directly — this is the actual rule
// every real logout entry point (SettingsScreen, ProfileContent) shares
// via blockingActiveRecordingId. Deliberately does not attempt a full
// widget-level tap-through test: blockingActiveRecordingId's thin
// Supabase-touching wrapper reads Supabase.instance.client.auth
// directly (not through an overridable Riverpod provider the way
// ChatConversationController's Supabase dependency is), so unlike the
// chat widget tests (which avoid needing a live session by overriding
// chatConversationStateProvider entirely), there is no equivalent
// bypass available here without either a live Supabase session or new
// Supabase-mocking infrastructure this codebase doesn't have. The
// pure-logic function below carries 100% of the actual decision the
// guard makes, so unit-testing it directly gives full, honest coverage
// of the real behavior without fabricating a misleading widget test.
void main() {
  late GpsLocalDatabase db;

  setUp(() {
    db = GpsLocalDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('no session (null userId) never blocks logout', () async {
    final blockingId = await blockingActiveRecordingIdFor(db, null);
    expect(blockingId, isNull);
  });

  test('no active recording for this account does not block logout', () async {
    final blockingId = await blockingActiveRecordingIdFor(db, 'me');
    expect(blockingId, isNull);
  });

  test('a recording-status route blocks logout', () async {
    await db.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
    final blockingId = await blockingActiveRecordingIdFor(db, 'me');
    expect(blockingId, 'r1');
  });

  test('a paused-status route blocks logout', () async {
    await db.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
    await db.pauseRecording(
        ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
    final blockingId = await blockingActiveRecordingIdFor(db, 'me');
    expect(blockingId, 'r1');
  });

  test('a completed route does not block logout', () async {
    await db.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
    await db.finishRecordingLocally(
        ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
    final blockingId = await blockingActiveRecordingIdFor(db, 'me');
    expect(blockingId, isNull);
  });

  test('a discarded route does not block logout', () async {
    await db.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
    await db.discardRecording(
        ownerId: 'me', routeId: 'r1', occurredAt: DateTime.utc(2026, 1, 1, 1));
    final blockingId = await blockingActiveRecordingIdFor(db, 'me');
    expect(blockingId, isNull);
  });

  test('the guard never deletes, finishes, or discards the blocking route itself',
      () async {
    await db.createLocalRecordedRoute(
        id: 'r1', ownerId: 'me', startedAt: DateTime.utc(2026, 1, 1));
    await blockingActiveRecordingIdFor(db, 'me');

    final route = await db.getRecordedRoute(ownerId: 'me', id: 'r1');
    expect(route, isNotNull);
    expect(route!.status, RecordedRouteStatus.recording,
        reason: 'the guard must only report, never mutate, the recording');
  });

  test('account isolation: an active recording under a different account '
      'never blocks this account\'s logout', () async {
    await db.createLocalRecordedRoute(
        id: 'r1', ownerId: 'accountA', startedAt: DateTime.utc(2026, 1, 1));
    final blockingId = await blockingActiveRecordingIdFor(db, 'accountB');
    expect(blockingId, isNull);
  });
}
