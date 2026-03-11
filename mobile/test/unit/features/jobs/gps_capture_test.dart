import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpsCapture', () {
    test('stores raw lat/lng via JobDao.updateJobGps',
        skip: 'Wave 0 stub — implementation in plan 06-04', () {
      // Will test: captureGps() calls JobDao.updateJobGps with raw latitude and longitude
    });

    test('handles permission denied gracefully',
        skip: 'Wave 0 stub — implementation in plan 06-04', () {
      // Will test: LocationPermission.denied results in user-facing error, no crash
    });
  });
}
