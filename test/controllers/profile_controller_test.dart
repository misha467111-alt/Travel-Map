import 'package:flutter_application_1/controllers/profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Map<String, dynamic> profile({required bool inviteRedeemed}) => {
        'invited_by': inviteRedeemed ? 'inviter-id' : null,
        'xp': 25,
        'invite_balance': 1,
        'is_developer': false,
        'invite_redeemed': inviteRedeemed,
      };

  test('T01 redeemed profile produces the normal authorized state', () async {
    final controller = ProfileController(
      profileFetcher: (_) async => profile(inviteRedeemed: true),
    );

    await controller.handleAuthenticatedUserForTesting(
      authenticatedUserId: 'authorized-user',
    );

    expect(controller.isAuthorized, isTrue);
    expect(controller.needsInviteStep, isFalse);
    expect(controller.isProfileLoading, isFalse);
    expect(controller.profileLoadError, isNull);
    controller.dispose();
  });

  test('T02 unredeemed profile remains protected by the invite gate', () async {
    final controller = ProfileController(
      profileFetcher: (_) async => profile(inviteRedeemed: false),
    );

    await controller.handleAuthenticatedUserForTesting(
      authenticatedUserId: 'uninvited-user',
    );

    expect(controller.isAuthorized, isFalse);
    expect(controller.needsInviteStep, isTrue);
    expect(controller.profileLoadError, isNull);
    controller.dispose();
  });

  test('T03 transient profile failure never becomes invite-required', () async {
    final controller = ProfileController(
      profileFetcher: (_) async => throw Exception('network unavailable'),
    );

    await controller.handleAuthenticatedUserForTesting(
      authenticatedUserId: 'existing-user',
    );

    expect(controller.isAuthorized, isFalse);
    expect(controller.needsInviteStep, isFalse);
    expect(controller.isProfileLoading, isFalse);
    expect(controller.profileLoadError, isNotNull);
    controller.dispose();
  });

  test('T04 transient failure recovers to authorized after a successful load',
      () async {
    var attempts = 0;
    final controller = ProfileController(
      profileFetcher: (_) async {
        attempts++;
        if (attempts == 1) throw Exception('temporary timeout');
        return profile(inviteRedeemed: true);
      },
    );

    await controller.handleAuthenticatedUserForTesting(
      authenticatedUserId: 'existing-user',
    );
    expect(controller.profileLoadError, isNotNull);

    await controller.handleAuthenticatedUserForTesting(
      authenticatedUserId: 'existing-user',
    );

    expect(controller.isAuthorized, isTrue);
    expect(controller.needsInviteStep, isFalse);
    expect(controller.profileLoadError, isNull);
    controller.dispose();
  });

  test('T05 transient failure can recover to a genuine invite-required state',
      () async {
    var attempts = 0;
    final controller = ProfileController(
      profileFetcher: (_) async {
        attempts++;
        if (attempts == 1) throw Exception('temporary timeout');
        return profile(inviteRedeemed: false);
      },
    );

    await controller.handleAuthenticatedUserForTesting(
      authenticatedUserId: 'uninvited-user',
    );
    expect(controller.needsInviteStep, isFalse);

    await controller.handleAuthenticatedUserForTesting(
      authenticatedUserId: 'uninvited-user',
    );

    expect(controller.isAuthorized, isFalse);
    expect(controller.needsInviteStep, isTrue);
    expect(controller.profileLoadError, isNull);
    controller.dispose();
  });

  test('T06 signed-out behavior clears authorization and invite state',
      () async {
    final controller = ProfileController(
      profileFetcher: (_) async => profile(inviteRedeemed: true),
    );
    await controller.handleAuthenticatedUserForTesting(
      authenticatedUserId: 'authorized-user',
    );
    expect(controller.isAuthorized, isTrue);

    await controller.logout();

    expect(controller.isAuthorized, isFalse);
    expect(controller.needsInviteStep, isFalse);
    expect(controller.isProfileLoading, isFalse);
    expect(controller.profileLoadError, isNull);
    controller.dispose();
  });
}
