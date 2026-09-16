// Phase 2.2A1 (Create Location UX v2 data-path preparation). These
// constants fix the exact canonical shapes the new
// `create_location_with_xp` RPC parameters expect -- amenities,
// opening-hours, and the default timezone -- ahead of the Create
// Location UI work that will actually expose them (not part of this
// phase; see the phase's own scope). Kept as plain pure-Dart constants
// so they're directly unit-testable with no widget/Supabase dependency.

/// Canonical backend-accepted amenity values (see
/// `locations_amenities_canonical_check` in
/// `supabase/migrations/202608290003_location_details_metadata.sql`).
/// Order matches the DB constraint's own array literal, and these are
/// the exact 6 keys `_AmenitiesGrid` in `map_screen.dart` already maps
/// to icons/labels for Location Details.
const List<String> locationAmenityKeys = [
  'parking',
  'wifi',
  'toilet',
  'accessibility',
  'pets',
  'food',
];

/// Default timezone for a newly created location that specifies an
/// opening-hours schedule. Hardcoded rather than device-derived: Dart's
/// own `DateTime` has no way to produce a real IANA zone name (only
/// abbreviations/raw UTC offsets), and the database's `timezone` column
/// is validated against real `pg_catalog.pg_timezone_names` -- a raw
/// Dart-derived value would fail that check outright. Never surfaced to
/// the user; matches the app's current entirely-Kyiv-centered user base.
const String defaultLocationTimezone = 'Europe/Kyiv';

/// The 7 canonical day keys, in the exact order/spelling
/// `travel_opening_hours_is_valid` requires all of to be present.
const List<String> openingHoursDayKeys = [
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];

const List<String> _weekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri'];
const List<String> _weekendKeys = ['sat', 'sun'];

/// The canonical "closed that day" representation -- an empty interval
/// list. `travel_opening_hours_is_valid` requires every day key present
/// even when its value is empty; `travel_location_is_open_now` correctly
/// treats an empty array as "not open" for that day (its
/// `jsonb_array_elements` loop simply yields zero rows).
const List<Map<String, String>> closedDaySchedule = [];

/// The canonical "24/7" representation: every day has one interval whose
/// `open` time equals its `close` time. Verified against the actual
/// `travel_location_is_open_now()` function body (not assumed): an
/// interval where `opens_at = closes_at` is explicitly treated as
/// "always open" and returns `true` on the very first (current-day)
/// check -- `supabase/migrations/202608290001_reference_filters_v2.sql`,
/// the `if opens_at = closes_at ... then return true` branch.
Map<String, dynamic> alwaysOpenSchedule() => {
      for (final day in openingHoursDayKeys)
        day: const [
          {'open': '00:00', 'close': '00:00'},
        ],
    };

/// A simple default weekly schedule matching the approved Create
/// Location v2 concept ("Пн-Пт 09:00-18:00, Сб-Нд Вихідний"): every
/// weekday gets the same interval, weekend days are closed. Fixes the
/// exact JSON shape ahead of the UI that will build it.
Map<String, dynamic> defaultWeekdaySchedule({
  String open = '09:00',
  String close = '18:00',
}) =>
    {
      for (final day in _weekdayKeys)
        day: [
          {'open': open, 'close': close},
        ],
      for (final day in _weekendKeys) day: closedDaySchedule,
    };
