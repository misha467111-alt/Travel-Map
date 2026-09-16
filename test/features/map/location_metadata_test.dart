import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/map/domain/location_metadata.dart';

/// Phase 2.2A1: fixes the exact canonical JSON shapes ahead of the RPC/UI
/// work that will actually use them.
void main() {
  test('amenity keys match the DB check constraint exactly', () {
    expect(locationAmenityKeys,
        ['parking', 'wifi', 'toilet', 'accessibility', 'pets', 'food']);
  });

  test('default timezone is a real IANA zone name, never user-facing input',
      () {
    expect(defaultLocationTimezone, 'Europe/Kyiv');
  });

  test('opening hours day keys match the canonical mon..sun order', () {
    expect(
        openingHoursDayKeys, ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']);
  });

  test('24/7 schedule: every day has one open==close interval', () {
    final schedule = alwaysOpenSchedule();

    expect(schedule.keys.toSet(), openingHoursDayKeys.toSet());
    for (final day in openingHoursDayKeys) {
      final intervals = schedule[day] as List;
      expect(intervals, hasLength(1));
      final interval = intervals.single as Map;
      expect(interval['open'], '00:00');
      expect(interval['close'], '00:00');
      expect(interval['open'], interval['close'],
          reason: 'travel_location_is_open_now treats open==close as '
              'always-open for that day');
    }
  });

  test('closed day is a canonical empty interval list', () {
    expect(closedDaySchedule, isEmpty);
  });

  test('default weekday schedule: weekdays open, weekend closed', () {
    final schedule = defaultWeekdaySchedule();

    expect(schedule.keys.toSet(), openingHoursDayKeys.toSet());
    for (final day in ['mon', 'tue', 'wed', 'thu', 'fri']) {
      final intervals = schedule[day] as List;
      expect(intervals, hasLength(1));
      final interval = intervals.single as Map;
      expect(interval['open'], '09:00');
      expect(interval['close'], '18:00');
    }
    for (final day in ['sat', 'sun']) {
      expect(schedule[day], isEmpty);
    }
  });

  test('default weekday schedule accepts custom hours', () {
    final schedule = defaultWeekdaySchedule(open: '10:00', close: '19:30');
    final monday = (schedule['mon'] as List).single as Map;
    expect(monday['open'], '10:00');
    expect(monday['close'], '19:30');
  });
}
