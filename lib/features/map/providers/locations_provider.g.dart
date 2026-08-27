// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'locations_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(locationsRepository)
final locationsRepositoryProvider = LocationsRepositoryProvider._();

final class LocationsRepositoryProvider extends $FunctionalProvider<
    LocationsRepository,
    LocationsRepository,
    LocationsRepository> with $Provider<LocationsRepository> {
  LocationsRepositoryProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'locationsRepositoryProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$locationsRepositoryHash();

  @$internal
  @override
  $ProviderElement<LocationsRepository> $createElement(
          $ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LocationsRepository create(Ref ref) {
    return locationsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocationsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocationsRepository>(value),
    );
  }
}

String _$locationsRepositoryHash() =>
    r'315e03560ecd9e7599fd5b967f43711b5ecc5172';

@ProviderFor(locationsCache)
final locationsCacheProvider = LocationsCacheProvider._();

final class LocationsCacheProvider extends $FunctionalProvider<
        AsyncValue<LocationsCache>, LocationsCache, FutureOr<LocationsCache>>
    with $FutureModifier<LocationsCache>, $FutureProvider<LocationsCache> {
  LocationsCacheProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'locationsCacheProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$locationsCacheHash();

  @$internal
  @override
  $FutureProviderElement<LocationsCache> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<LocationsCache> create(Ref ref) {
    return locationsCache(ref);
  }
}

String _$locationsCacheHash() => r'33928b3ab79cf86087a6e174e62375a69d95d164';

@ProviderFor(fetchLocations)
final fetchLocationsProvider = FetchLocationsProvider._();

final class FetchLocationsProvider extends $FunctionalProvider<
        AsyncValue<List<LocationModel>>,
        List<LocationModel>,
        Stream<List<LocationModel>>>
    with
        $FutureModifier<List<LocationModel>>,
        $StreamProvider<List<LocationModel>> {
  FetchLocationsProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'fetchLocationsProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$fetchLocationsHash();

  @$internal
  @override
  $StreamProviderElement<List<LocationModel>> $createElement(
          $ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<LocationModel>> create(Ref ref) {
    return fetchLocations(ref);
  }
}

String _$fetchLocationsHash() => r'6633fc8d516d0761fb44fe7e445d48af849f6c92';
