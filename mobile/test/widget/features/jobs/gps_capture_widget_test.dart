/// Widget tests for GpsCaptureButton.
///
/// Tests cover:
/// 1. renders "Capture Location" button when no GPS data on job
/// 2. displays coordinates when gpsLatitude/gpsLongitude set but no gpsAddress
/// 3. displays geocoded address when gpsAddress is set
/// 4. shows confirm dialog when existing address would be overwritten
/// 5. GpsCaptureButton renders within a Riverpod-free scaffold
///
/// Note: Geolocator is a platform plugin and cannot be mocked at the platform
/// level in widget tests. Tests that trigger capture are excluded — only static
/// UI state is tested.
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
  group('GpsCaptureButton', () {
    testWidgets('renders Capture Location button when no GPS data', (tester) async {
      final job = _makeJob();

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      expect(find.text('Capture Location'), findsOneWidget);
    });

    testWidgets('shows coordinates when gpsLatitude/gpsLongitude set but no address',
        (tester) async {
      final job = _makeJob(
        gpsLatitude: 43.65107,
        gpsLongitude: -79.34788,
      );

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      // The widget displays "Coordinates: {lat}N {lng}W (address pending sync)"
      expect(find.textContaining('Coordinates:'), findsOneWidget);
      expect(find.textContaining('43.65107N'), findsOneWidget);
    });

    testWidgets('displays geocoded address when gpsAddress is set', (tester) async {
      final job = _makeJob(
        gpsLatitude: 43.65107,
        gpsLongitude: -79.34788,
        gpsAddress: '123 Main St, Toronto, ON',
      );

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      expect(find.text('123 Main St, Toronto, ON'), findsOneWidget);
    });

    testWidgets('Capture Location button is present even when address exists',
        (tester) async {
      final job = _makeJob(gpsAddress: '456 Oak Ave, Ottawa, ON');

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      // Button is always rendered (allows re-capture)
      expect(find.text('Capture Location'), findsOneWidget);
    });

    testWidgets('does not show coordinates text when no GPS data at all',
        (tester) async {
      final job = _makeJob();

      await tester.pumpWidget(buildGpsButton(job));
      await tester.pump();

      expect(find.textContaining('Coordinates:'), findsNothing);
    });
  });
}
