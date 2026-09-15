import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';

/// The exact channel/method `ios/Runner/AppDelegate.swift` already
/// listens on (its `configureGoogleMaps` handler calls
/// `GMSServices.provideAPIKey`) -- exposed so a test can intercept it via
/// `TestDefaultBinaryMessengerBinding`'s mock handler instead of a second
/// injection mechanism.
@visibleForTesting
const MethodChannel iosGoogleMapsConfigChannel =
    MethodChannel('travel_map/native_config');

/// Passes [apiKey] to `GMSServices.provideAPIKey` on iOS via the existing
/// native `configureGoogleMaps` handler, before any `GoogleMap` widget can
/// be built -- called once from `_AppBootstrap._initialize()` in
/// `main.dart`, which already gates every screen (every Map tab included)
/// behind this same `Future` via its `FutureBuilder`.
///
/// A no-op on every platform except iOS: Android already gets its key at
/// build time via `android/app/build.gradle`'s `manifestPlaceholders` --
/// calling this iOS-only native channel from Android would just be a dead
/// call (nothing on the Android side implements
/// `travel_map/native_config`) for no benefit.
///
/// Throws a [StateError] if [apiKey] is empty, or if the native side
/// rejects the call, so a misconfigured build fails loudly through the
/// same `_BootstrapErrorScreen`/retry flow already used for a missing
/// Supabase configuration -- deliberately not a silently-broken map.
Future<void> configureIosGoogleMapsApiKey(String apiKey) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;

  if (apiKey.isEmpty) {
    throw StateError(
      'Missing GOOGLE_MAPS_IOS_API_KEY. Run with '
      '--dart-define-from-file=.env.',
    );
  }

  try {
    await iosGoogleMapsConfigChannel
        .invokeMethod<void>('configureGoogleMaps', {'apiKey': apiKey});
  } on PlatformException catch (error) {
    throw StateError(
      'Failed to configure Google Maps on iOS: ${error.message}',
    );
  }
}
