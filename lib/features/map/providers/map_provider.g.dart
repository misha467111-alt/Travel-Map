// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(currentPosition)
final currentPositionProvider = CurrentPositionProvider._();

final class CurrentPositionProvider extends $FunctionalProvider<
        AsyncValue<Position>, Position, FutureOr<Position>>
    with $FutureModifier<Position>, $FutureProvider<Position> {
  CurrentPositionProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'currentPositionProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$currentPositionHash();

  @$internal
  @override
  $FutureProviderElement<Position> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Position> create(Ref ref) {
    return currentPosition(ref);
  }
}

String _$currentPositionHash() => r'f203758c0c04a7e9af2eb4fd9c677656a73fbe47';
