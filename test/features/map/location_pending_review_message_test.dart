import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/presentation/map_screen.dart';

/// UI/UX Fix Phase 1: `_addLocation` in `map_screen.dart` shows this exact
/// message on a successful `createLocation()` call (see the SnackBar right
/// after `ref.invalidate(viewportLocationsProvider)`). Testing the shared
/// constant directly -- rather than driving the private
/// `_AddLocationDialog`/`_addLocation` flow through a full `GoogleMap`
/// widget harness, which does not exist anywhere in this test suite and
/// would be a disproportionate new fixture for this phase -- still proves
/// the UI text is correct, since the SnackBar has no other source for it.
void main() {
  test('pending-review message never claims the location is already public',
      () {
    expect(locationPendingReviewMessage,
        'Локацію створено та відправлено на перевірку');
    expect(locationPendingReviewMessage, contains('перевірку'),
        reason: 'must communicate moderation, not instant publication');
    expect(locationPendingReviewMessage, isNot(contains('успішно додано')),
        reason: 'must not imply the location is already visible to others');
  });
}
