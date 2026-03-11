import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimerNotifier', () {
    test('build restores active session from Drift',
        skip: 'Wave 0 stub — implementation in plan 06-05', () {
      // Will test: build() queries TimeEntryDao for active session and restores elapsed time
    });

    test('clockIn starts Timer.periodic',
        skip: 'Wave 0 stub — implementation in plan 06-05', () {
      // Will test: clockIn() creates a TimeEntry and starts a 1-second periodic timer
    });

    test('clockOut stops timer and resets state',
        skip: 'Wave 0 stub — implementation in plan 06-05', () {
      // Will test: clockOut() cancels Timer, sets clockedOutAt, resets elapsed seconds to 0
    });
  });
}
