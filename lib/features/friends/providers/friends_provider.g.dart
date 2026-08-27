// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friends_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(friendsRepository)
final friendsRepositoryProvider = FriendsRepositoryProvider._();

final class FriendsRepositoryProvider extends $FunctionalProvider<
    FriendsRepository,
    FriendsRepository,
    FriendsRepository> with $Provider<FriendsRepository> {
  FriendsRepositoryProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'friendsRepositoryProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$friendsRepositoryHash();

  @$internal
  @override
  $ProviderElement<FriendsRepository> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FriendsRepository create(Ref ref) {
    return friendsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FriendsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FriendsRepository>(value),
    );
  }
}

String _$friendsRepositoryHash() => r'e3baad199d49340efe83b9d53a03541e6c46b01b';

@ProviderFor(acceptedFriends)
final acceptedFriendsProvider = AcceptedFriendsProvider._();

final class AcceptedFriendsProvider extends $FunctionalProvider<
        AsyncValue<List<FriendProfile>>,
        List<FriendProfile>,
        FutureOr<List<FriendProfile>>>
    with
        $FutureModifier<List<FriendProfile>>,
        $FutureProvider<List<FriendProfile>> {
  AcceptedFriendsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'acceptedFriendsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$acceptedFriendsHash();

  @$internal
  @override
  $FutureProviderElement<List<FriendProfile>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<FriendProfile>> create(Ref ref) {
    return acceptedFriends(ref);
  }
}

String _$acceptedFriendsHash() => r'795b5fcd73c28611714d8eaaadd9beb0c7138a84';

@ProviderFor(pendingFriendRequests)
final pendingFriendRequestsProvider = PendingFriendRequestsProvider._();

final class PendingFriendRequestsProvider extends $FunctionalProvider<
        AsyncValue<List<FriendRequest>>,
        List<FriendRequest>,
        FutureOr<List<FriendRequest>>>
    with
        $FutureModifier<List<FriendRequest>>,
        $FutureProvider<List<FriendRequest>> {
  PendingFriendRequestsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'pendingFriendRequestsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$pendingFriendRequestsHash();

  @$internal
  @override
  $FutureProviderElement<List<FriendRequest>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<FriendRequest>> create(Ref ref) {
    return pendingFriendRequests(ref);
  }
}

String _$pendingFriendRequestsHash() =>
    r'619c5d3b7494e7e6a0e912999a4558e652f0abd0';

@ProviderFor(searchFriends)
final searchFriendsProvider = SearchFriendsFamily._();

final class SearchFriendsProvider extends $FunctionalProvider<
        AsyncValue<List<FriendProfile>>,
        List<FriendProfile>,
        FutureOr<List<FriendProfile>>>
    with
        $FutureModifier<List<FriendProfile>>,
        $FutureProvider<List<FriendProfile>> {
  SearchFriendsProvider._(
      {required SearchFriendsFamily super.from, required String super.argument})
      : super(
          retry: null,
          name: r'searchFriendsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$searchFriendsHash();

  @override
  String toString() {
    return r'searchFriendsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<FriendProfile>> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<FriendProfile>> create(Ref ref) {
    final argument = this.argument as String;
    return searchFriends(
      ref,
      argument,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SearchFriendsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$searchFriendsHash() => r'4bbc0ae043f51bdfb0e0c0663a4d38381bf2d8bd';

final class SearchFriendsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<FriendProfile>>, String> {
  SearchFriendsFamily._()
      : super(
          retry: null,
          name: r'searchFriendsProvider',
          dependencies: null,
          $allTransitiveDependencies: null,
          isAutoDispose: true,
        );

  SearchFriendsProvider call(
    String query,
  ) =>
      SearchFriendsProvider._(argument: query, from: this);

  @override
  String toString() => r'searchFriendsProvider';
}
