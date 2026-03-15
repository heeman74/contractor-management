/// Unit tests for GPS capture display and coordinate validation logic.
///
/// Tests cover:
/// 1. GpsCaptureButton renders "Capture Location" when no GPS data on job
/// 2. GpsCaptureButton shows coordinates with N/S E/W suffixes for positive lat/lng
/// 3. GpsCaptureButton shows S/W suffixes for negative lat/lng (southern/western hemisphere)
/// 4. GpsCaptureButton displays geocoded address when gpsAddress is set
/// 5. GpsCaptureButton hides coordinate display when no GPS data at all
/// 6. Capture Location button remains available even when address exists (re-capture)
///
/// Note: Geolocator is a platform plugin and cannot be mocked at the platform
/// level in pure unit/widget tests. Only the display and validation behavior
/// is tested here — capture flow tests are in gps_capture_widget_test.dart.
library;

import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/widgets/gps_capture_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

JobEntity _makeJob({
  String id = 'job-1',
  double? gpsLatitude,
  double? gpsLongitude,
  String? gpsAddress,
}) {
  final now = DateTime.now();
  return JobEntity(
    id: id,
    companyId: 'co-1',
    description: 'Fix water main',
    tradeType: 'plumber',
    status: 'scheduled',
    priority: 'medium',
    statusHistory: const [],
    tags: const [],
    gpsLatitude: gpsLatitude,
    gpsLongitude: gpsLongitude,
    gpsAddress: gpsAddress,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

Widget buildGpsButton(JobEntity job) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: GpsCaptureButton(job: job),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GpsCapture', () {
    testWidgets('renders Capture Location button when no GPS data on job',
        (tester) async {
      final job = _makeJob();
      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      expect(find.text('Capture Location'), findsOneWidget);
      expect(find.textContaining('Coordinates:'), findsNothing);
    });

    testWidgets(
        'shows coordinates with N/E suffixes for positive lat/lng (northern/eastern hemisphere)',
        (tester) async {
      final job = _makeJob(
        gpsLatitude: 51.50735,
        gpsLongitude: 0.12776,
      );

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      expect(find.textContaining('Coordinates:'), findsOneWidget);
      expect(find.textContaining('51.50735N'), findsOneWidget);
      expect(find.textContaining('0.12776E'), findsOneWidget);
    });

    testWidgets(
        'shows coordinates with S/W suffixes for negative lat/lng (southern/western hemisphere)',
        (tester) async {
      final job = _makeJob(
        gpsLatitude: -33.86882,
        gpsLongitude: -151.20929,
      );

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      expect(find.textContaining('Coordinates:'), findsOneWidget);
      expect(find.textContaining('33.86882S'), findsOneWidget);
      expect(find.textContaining('151.20929W'), findsOneWidget);
    });

    testWidgets('displays geocoded address when gpsAddress is set',
        (tester) async {
      final job = _makeJob(
        gpsLatitude: 43.65107,
        gpsLongitude: -79.34788,
        gpsAddress: '350 Bay St, Toronto, ON M5H 2S6',
      );

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      expect(find.text('350 Bay St, Toronto, ON M5H 2S6'), findsOneWidget);
      // When address is set, coordinates line should NOT appear
      expect(find.textContaining('Coordinates:'), findsNothing);
    });

    testWidgets('hides coordinate display when no GPS data at all',
        (tester) async {
      final job = _makeJob();

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      expect(find.textContaining('Coordinates:'), findsNothing);
      expect(find.byIcon(Icons.place), findsNothing);
    });

    testWidgets('Capture Location button remains available even when address exists',
        (tester) async {
      final job = _makeJob(
        gpsLatitude: 40.71280,
        gpsLongitude: -74.00600,
        gpsAddress: '123 Broadway, New York, NY',
      );

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      // Button for re-capture should always be present
      expect(find.text('Capture Location'), findsOneWidget);
    });
  });
}
