import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/features/gps/location/location_source.dart';

/// TEST K (GPS-4B2): the platform-specific settings `GpsSamplingSettings`
/// hands to geolocator are pure Dart values -- this exercises exactly what
/// `forCurrentPlatform()` will pass to the plugin on each platform without
/// touching any real platform channel, which `flutter test` cannot do
/// anyway. It cannot verify the *native* Android/iOS side actually behaves
/// as configured (that is GPS-4B3's real-device job), only that the Dart
/// side asks for the right thing.
void main() {
  final originalOverride = debugDefaultTargetPlatformOverride;

  tearDown(() {
    debugDefaultTargetPlatformOverride = originalOverride;
  });

  group('GpsSamplingSettings.forCurrentPlatform on Android', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    test('always attaches a foreground-service notification config', () {
      final settings =
          GpsSamplingSettings.forCurrentPlatform() as AndroidSettings;

      expect(settings.foregroundNotificationConfig, isNotNull,
          reason: 'this is what starts the Android foreground service that '
              'keeps sampling alive while backgrounded/locked');
    });

    test('the notification is ongoing and clearly identifies recording', () {
      final settings =
          GpsSamplingSettings.forCurrentPlatform() as AndroidSettings;
      final config = settings.foregroundNotificationConfig!;

      expect(config.setOngoing, isTrue,
          reason: 'the user must not be able to dismiss the notification '
              'while a recording it represents is still active');
      expect(config.notificationTitle, isNotEmpty);
      expect(config.notificationText, isNotEmpty);
    });

    test('enables a wake lock but not a Wi-Fi lock', () {
      final settings =
          GpsSamplingSettings.forCurrentPlatform() as AndroidSettings;
      final config = settings.foregroundNotificationConfig!;

      expect(config.enableWakeLock, isTrue,
          reason: 'without it Android may batch/delay delivery until the '
              'next wake, contradicting continuous background recording');
      expect(config.enableWifiLock, isFalse,
          reason: 'GPS sampling has no need to keep the Wi-Fi radio awake');
    });

    test('preserves the existing accuracy/distance/interval sampling profile',
        () {
      final settings =
          GpsSamplingSettings.forCurrentPlatform() as AndroidSettings;

      expect(settings.accuracy, LocationAccuracy.best);
      expect(settings.distanceFilter, 4);
      expect(settings.intervalDuration, const Duration(seconds: 3));
    });
  });

  group('GpsSamplingSettings.forCurrentPlatform on iOS (GPS-4B4B)', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    test(
        'enables background location updates so an already-started '
        'foreground recording keeps delivering after backgrounding, '
        'without requesting Always authorization', () {
      final settings =
          GpsSamplingSettings.forCurrentPlatform() as AppleSettings;

      expect(settings.allowBackgroundLocationUpdates, isTrue,
          reason: 'When In Use authorization is sufficient here because '
              'every position stream is started while the app is '
              'foregrounded -- see GpsSamplingSettings doc comment');
      expect(settings.showBackgroundLocationIndicator, isFalse,
          reason: 'only has an effect under Always authorization, which '
              'this app deliberately never requests');
    });
  });
}
