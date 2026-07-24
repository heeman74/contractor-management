/// Unit tests for [ScheduleTimeFormat] — the shared time/duration formatter
/// that replaced the duplicated `_formatTime` / `_formatDuration` helpers.
library;

import 'package:contractorhub/features/schedule/domain/schedule_time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleTimeFormat.time', () {
    test('formats midnight as 12:00 AM', () {
      expect(ScheduleTimeFormat.time(DateTime(2025)), '12:00 AM');
    });

    test('formats noon as 12:00 PM', () {
      expect(ScheduleTimeFormat.time(DateTime(2025, 1, 1, 12)), '12:00 PM');
    });

    test('formats morning time with zero-padded minutes', () {
      expect(ScheduleTimeFormat.time(DateTime(2025, 1, 1, 9, 5)), '9:05 AM');
    });

    test('formats afternoon time in 12-hour clock', () {
      expect(ScheduleTimeFormat.time(DateTime(2025, 1, 1, 15, 30)), '3:30 PM');
    });
  });

  group('ScheduleTimeFormat.range', () {
    test('joins start and end with a dash', () {
      final start = DateTime(2025, 1, 1, 15);
      final end = DateTime(2025, 1, 1, 16, 30);
      expect(ScheduleTimeFormat.range(start, end), '3:00 PM - 4:30 PM');
    });
  });

  group('ScheduleTimeFormat.duration', () {
    test('formats sub-hour durations in minutes', () {
      expect(ScheduleTimeFormat.duration(45), '45m');
    });

    test('formats whole hours without minutes', () {
      expect(ScheduleTimeFormat.duration(120), '2h');
    });

    test('formats hours and minutes', () {
      expect(ScheduleTimeFormat.duration(90), '1h 30m');
    });
  });
}
