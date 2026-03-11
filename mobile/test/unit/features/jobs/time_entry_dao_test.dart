import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimeEntryDao', () {
    test('clockIn creates active entry',
        skip: 'Wave 0 stub — implementation in plan 06-05', () {
      // Will test: clockIn() inserts a TimeEntry row with clockedOutAt = null
    });

    test('clockIn auto-clocks out existing session',
        skip: 'Wave 0 stub — implementation in plan 06-05', () {
      // Will test: calling clockIn() when active session exists sets clockedOutAt on prior row
    });

    test('clockOut computes duration',
        skip: 'Wave 0 stub — implementation in plan 06-06', () {
      // Will test: clockOut() sets clockedOutAt and computes durationMinutes correctly
    });
  });
}
