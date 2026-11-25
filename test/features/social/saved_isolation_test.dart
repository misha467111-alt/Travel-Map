import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';

/// Phase 3.3-D review -- bookmarks are per account: after a logout / login as
/// someone else inside one app session the previous account's bookmarks must
/// neither be shown nor written to, and nothing may be lost.
class _TestUser extends SignedInUserId {
  _TestUser(this.initial);
  final String? initial;

  @override
  String? build() => initial;

  void set(String? id) => state = id;
}

void main() {
  late ProviderContainer container;

  Future<void> start(Map<String, Object> prefs, {String? firstUser}) async {
    SharedPreferences.setMockInitialValues(prefs);
    container = ProviderContainer(overrides: [
      signedInUserIdProvider.overrideWith(() => _TestUser(firstUser)),
    ]);
    addTearDown(container.dispose);
  }

  Future<Set<String>> ids() =>
      container.read(savedPublicLocationsProvider.future);

  /// Changes the signed-in account and waits for the bookmarks to rebuild.
  Future<void> signIn(String? id) async {
    (container.read(signedInUserIdProvider.notifier) as _TestUser).set(id);
    await container.read(savedPublicLocationsProvider.future);
  }

  Future<List<String>?> stored(String key) async =>
      (await SharedPreferences.getInstance()).getStringList(key);

  test('each account reads only its own bookmarks', () async {
    await start({
      'saved_public_locations_A': ['a1', 'a2'],
      'saved_public_locations_B': ['b1'],
    }, firstUser: 'A');
    expect(await ids(), {'a1', 'a2'});
  });

  test('after a login as another account A\'s bookmarks are gone from view',
      () async {
    await start({
      'saved_public_locations_A': ['a1', 'a2'],
      'saved_public_locations_B': ['b1'],
    }, firstUser: 'A');
    expect(await ids(), {'a1', 'a2'});

    await signIn(null); // logout
    expect(await ids(), isEmpty, reason: 'signed out: nothing is shown');
    await signIn('B');
    expect(await ids(), {'b1'});
    expect(await ids(), isNot(contains('a1')));
  });

  test('B toggling a bookmark never writes into A\'s storage', () async {
    await start({
      'saved_public_locations_A': ['a1'],
    }, firstUser: 'A');
    await ids();
    await signIn(null);
    await signIn('B');

    await container.read(savedPublicLocationsProvider.notifier).toggle('b9');
    expect(await stored('saved_public_locations_B'), ['b9']);
    expect(await stored('saved_public_locations_A'), ['a1'],
        reason: 'A is untouched');
  });

  test('nothing is lost: A gets the same bookmarks back after B', () async {
    await start({
      'saved_public_locations_A': ['a1', 'a2'],
    }, firstUser: 'A');
    await ids();
    await signIn('B');
    await container.read(savedPublicLocationsProvider.notifier).toggle('b1');
    await signIn('A');
    expect(await ids(), {'a1', 'a2'});
    await signIn('B');
    expect(await ids(), {'b1'});
  });

  test('A\'s own toggles are persisted under A\'s key', () async {
    await start({
      'saved_public_locations_A': ['a1'],
    }, firstUser: 'A');
    await ids();
    await container.read(savedPublicLocationsProvider.notifier).toggle('a2');
    await container.read(savedPublicLocationsProvider.notifier).toggle('a1');
    expect(await stored('saved_public_locations_A'), ['a2']);
  });

  test('signed out: empty and nothing is persisted (also not as "anonymous")',
      () async {
    await start({
      'saved_public_locations_anonymous': ['legacy'],
    });
    expect(await ids(), isEmpty);
    await container.read(savedPublicLocationsProvider.notifier).toggle('x');
    expect(await stored('saved_public_locations_anonymous'), ['legacy'],
        reason: 'legacy data is left exactly as it was');
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getKeys().where((k) => k.startsWith('saved_public_locations_')),
        {'saved_public_locations_anonymous'});
  });

  test('a user can never see someone else\'s legacy "anonymous" bookmarks',
      () async {
    await start({
      'saved_public_locations_anonymous': ['legacy'],
      'saved_public_locations_A': ['a1'],
    }, firstUser: 'A');
    expect(await ids(), {'a1'});
  });

  test('the key format is unchanged, so existing bookmarks are kept', () async {
    await start({
      'saved_public_locations_user-123': ['x', 'y'],
    }, firstUser: 'user-123');
    expect(await ids(), {'x', 'y'});
  });

  group('races and the account switch', () {
    test('rapid A -> B -> A -> logout -> B ends with exactly B\'s set',
        () async {
      await start({
        'saved_public_locations_A': ['a1'],
        'saved_public_locations_B': ['b1'],
      }, firstUser: 'A');
      await ids();
      final user = container.read(signedInUserIdProvider.notifier) as _TestUser;
      // No await between the switches: only the last account may survive.
      user.set('B');
      user.set('A');
      user.set(null);
      user.set('B');
      expect(await ids(), {'b1'});
    });

    test('a toggle made right after a switch goes to the NEW account only',
        () async {
      await start({
        'saved_public_locations_A': ['a1'],
        'saved_public_locations_B': ['b1'],
      }, firstUser: 'A');
      await ids();
      (container.read(signedInUserIdProvider.notifier) as _TestUser).set('B');
      // The rebuild for B has not finished yet.
      await container.read(savedPublicLocationsProvider.notifier).toggle('b2');
      expect(await stored('saved_public_locations_B'), ['b1', 'b2']);
      expect(await stored('saved_public_locations_A'), ['a1'],
          reason: 'A must not receive a bookmark made as B');
      expect(await ids(), {'b1', 'b2'});
    });

    test('a toggle that is still waiting when the account changes is dropped',
        () async {
      await start({
        'saved_public_locations_A': ['a1'],
        'saved_public_locations_B': ['b1'],
      }, firstUser: 'A');
      await ids();
      final pending =
          container.read(savedPublicLocationsProvider.notifier).toggle('late');
      (container.read(signedInUserIdProvider.notifier) as _TestUser).set('B');
      await pending;
      expect(await stored('saved_public_locations_A'), ['a1']);
      expect(await stored('saved_public_locations_B'), ['b1']);
      expect(await ids(), {'b1'});
    });

    test('logout then login A again restores A without B\'s bookmarks',
        () async {
      await start({
        'saved_public_locations_A': ['a1'],
      }, firstUser: 'A');
      await ids();
      await container.read(savedPublicLocationsProvider.notifier).toggle('a2');
      await signIn(null);
      expect(await ids(), isEmpty);
      await signIn('B');
      await container.read(savedPublicLocationsProvider.notifier).toggle('b1');
      await signIn(null);
      await signIn('A');
      expect(await ids(), {'a1', 'a2'});
      expect(await stored('saved_public_locations_B'), ['b1']);
    });

    test('no legacy key is created or modified by any of this', () async {
      await start({
        'saved_public_locations_anonymous': ['legacy'],
        'saved_public_locations_A': ['a1'],
      }, firstUser: 'A');
      await ids();
      await signIn(null);
      await container.read(savedPublicLocationsProvider.notifier).toggle('x');
      await signIn('A');
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getKeys().where((k) => k.startsWith('saved_public_locations_')),
          {'saved_public_locations_anonymous', 'saved_public_locations_A'});
      expect(await stored('saved_public_locations_anonymous'), ['legacy']);
    });
  });
}
