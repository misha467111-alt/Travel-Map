import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/profile/domain/user_profile.dart';
import 'package:flutter_application_1/features/profile/providers/profile_provider.dart';
import 'package:flutter_application_1/features/social/providers/public_profile_provider.dart';

/// Phase 3.3-D safety gate -- `currentProfileProvider` is keepAlive, so it must
/// be re-read when the signed-in ACCOUNT changes; otherwise the previous
/// account's profile (and the places keyed by its id) stays on screen.
class _TestUser extends SignedInUserId {
  _TestUser(this.initial);
  final String? initial;

  @override
  String? build() => initial;

  void set(String? id) => state = id;
}

class _Repo implements ProfileRepository {
  _Repo(this.current);
  String Function() current;
  int reads = 0;

  @override
  Future<UserProfile> fetchCurrentProfile() async {
    reads++;
    final id = current();
    return UserProfile(
      id: id,
      name: 'user $id',
      email: '$id@example.test',
      level: '1',
      xp: 0,
      locationsCount: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('the profile is re-read after the signed-in account changes', () async {
    var who = 'A';
    final repo = _Repo(() => who);
    final container = ProviderContainer(overrides: [
      signedInUserIdProvider.overrideWith(() => _TestUser('A')),
      profileRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    // keepAlive: hold a listener like the profile tab does.
    container.listen(currentProfileProvider, (_, __) {});
    expect((await container.read(currentProfileProvider.future)).id, 'A');

    who = 'B';
    (container.read(signedInUserIdProvider.notifier) as _TestUser).set('B');
    expect((await container.read(currentProfileProvider.future)).id, 'B',
        reason: 'A\'s cached profile must not be shown to B');
    expect(repo.reads, 2);
  });

  test('the same account does not refetch', () async {
    final repo = _Repo(() => 'A');
    final container = ProviderContainer(overrides: [
      signedInUserIdProvider.overrideWith(() => _TestUser('A')),
      profileRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    container.listen(currentProfileProvider, (_, __) {});
    await container.read(currentProfileProvider.future);
    (container.read(signedInUserIdProvider.notifier) as _TestUser).set('A');
    await container.read(currentProfileProvider.future);
    expect(repo.reads, 1);
  });
}
