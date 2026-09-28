import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/navigation/domain/adventure_discovery.dart';

/// Adventure Transport & Time Discovery Phase 2: proves the one pure
/// source of truth for the Adventure discovery radius exactly preserves
/// the proven legacy `_TransportMode`/`_travelRadiusKm` calculation from
/// (now-dead) `_LocationsListScreen` -- same speeds, same formula
/// (`min(userRadiusKm, speedKmH(transport) * travelMinutes / 60)`).
void main() {
  test('T01 walking effective radius', () {
    // 4.5 km/h * 60 min / 60 = 4.5 km, well under a generous user radius.
    expect(
      adventureEffectiveRadiusKm(
        userRadiusKm: 50,
        transport: AdventureTransportMode.walk,
        travelMinutes: 60,
      ),
      closeTo(4.5, 1e-9),
    );
  });

  test('T02 cycling effective radius', () {
    // 14.0 km/h * 60 min / 60 = 14.0 km.
    expect(
      adventureEffectiveRadiusKm(
        userRadiusKm: 50,
        transport: AdventureTransportMode.bike,
        travelMinutes: 60,
      ),
      closeTo(14.0, 1e-9),
    );
  });

  test('T03 driving effective radius', () {
    // 45.0 km/h * 60 min / 60 = 45.0 km.
    expect(
      adventureEffectiveRadiusKm(
        userRadiusKm: 50,
        transport: AdventureTransportMode.car,
        travelMinutes: 60,
      ),
      closeTo(45.0, 1e-9),
    );
  });

  test('T04 user radius binds when it is the smaller value', () {
    // Driving for 60 min reaches 45km, but the user only wants 5km.
    expect(
      adventureEffectiveRadiusKm(
        userRadiusKm: 5,
        transport: AdventureTransportMode.car,
        travelMinutes: 60,
      ),
      closeTo(5.0, 1e-9),
    );
  });

  test('T05 transport/time radius binds when it is the smaller value', () {
    // Walking for 10 min only reaches 4.5 * 10 / 60 = 0.75km, well under
    // a generous 50km user radius.
    expect(
      adventureEffectiveRadiusKm(
        userRadiusKm: 50,
        transport: AdventureTransportMode.walk,
        travelMinutes: 10,
      ),
      closeTo(0.75, 1e-9),
    );
  });

  test('T06 minimum 10-minute time', () {
    // Cycling: 14.0 * 10 / 60 = 2.333... km.
    expect(
      adventureEffectiveRadiusKm(
        userRadiusKm: 50,
        transport: AdventureTransportMode.bike,
        travelMinutes: 10,
      ),
      closeTo(14.0 * 10 / 60, 1e-9),
    );
  });

  test('T07 maximum 180-minute time', () {
    // Walking: 4.5 * 180 / 60 = 13.5 km, still under a generous user radius.
    expect(
      adventureEffectiveRadiusKm(
        userRadiusKm: 50,
        transport: AdventureTransportMode.walk,
        travelMinutes: 180,
      ),
      closeTo(13.5, 1e-9),
    );
  });

  test('adventureTransportSpeedKmH matches the proven legacy values', () {
    expect(adventureTransportSpeedKmH(AdventureTransportMode.walk), 4.5);
    expect(adventureTransportSpeedKmH(AdventureTransportMode.bike), 14.0);
    expect(adventureTransportSpeedKmH(AdventureTransportMode.car), 45.0);
  });
}
