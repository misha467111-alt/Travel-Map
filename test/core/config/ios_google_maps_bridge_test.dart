import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/core/config/ios_google_maps_bridge.dart';

/// GPS-4B4B / Google Maps iOS wiring fix: proves the native
/// `configureGoogleMaps` channel actually gets called with the configured
/// key on iOS, is never touched on Android, and that a missing/rejected
/// key fails loudly rather than leaving the map silently broken. Uses
/// `TestDefaultBinaryMessengerBinding`'s mock method-call handler to
/// intercept the exact channel `ios/Runner/AppDelegate.swift` listens on,
/// so this cannot touch any real platform channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalOverride = debugDefaultTargetPlatformOverride;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = originalOverride;
    messenger.setMockMethodCallHandler(iosGoogleMapsConfigChannel, null);
  });

  group('configureIosGoogleMapsApiKey on iOS', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    test('passes the configured key to the native configureGoogleMaps call',
        () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(iosGoogleMapsConfigChannel,
          (call) async {
        received = call;
        return null;
      });

      await configureIosGoogleMapsApiKey('test-ios-key');

      expect(received?.method, 'configureGoogleMaps');
      expect(received?.arguments, {'apiKey': 'test-ios-key'});
    });

    test(
        'throws instead of silently leaving the map broken when the key is '
        'empty, and never calls native with it', () async {
      var callCount = 0;
      messenger.setMockMethodCallHandler(iosGoogleMapsConfigChannel,
          (call) async {
        callCount++;
        return null;
      });

      await expectLater(
        () => configureIosGoogleMapsApiKey(''),
        throwsA(isA<StateError>()),
      );
      expect(callCount, 0);
    });

    test('converts a native PlatformException into a StateError', () async {
      messenger.setMockMethodCallHandler(iosGoogleMapsConfigChannel,
          (call) async {
        throw PlatformException(code: 'boom', message: 'native rejected it');
      });

      await expectLater(
        () => configureIosGoogleMapsApiKey('test-ios-key'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('configureIosGoogleMapsApiKey on Android', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('never calls the iOS-only native channel, even with a key present',
        () async {
      var callCount = 0;
      messenger.setMockMethodCallHandler(iosGoogleMapsConfigChannel,
          (call) async {
        callCount++;
        return null;
      });

      await configureIosGoogleMapsApiKey('irrelevant-on-android');

      expect(callCount, 0);
    });

    test('does not throw even when the key is empty (Android ignores it)',
        () async {
      await expectLater(configureIosGoogleMapsApiKey(''), completes);
    });
  });
}
