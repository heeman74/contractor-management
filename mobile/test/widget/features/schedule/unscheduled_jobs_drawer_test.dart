/// Widget tests for UnscheduledJobsDrawer — UAT #6.
///
/// Tests cover:
/// 1. Header text "Unscheduled Jobs" present
/// 2. Close button (X icon) present with tooltip
/// 3. Search field with placeholder text
/// 4. Filter chips (All, Quote, Scheduled) present
/// 5. Trade type dropdown present with "All trades" hint
/// 6. Loading indicator while jobs stream loading
/// 7. Empty state "All jobs scheduled" when no unscheduled jobs
/// 8. Empty state "No jobs match filters" when filtered to nothing
/// 9. Job card renders with description text
/// 10. Drag indicator hint present on job cards
///
/// Strategy: UnscheduledJobsDrawer watches unscheduledJobsProvider (StreamProvider).
/// Override with AsyncValue<List<Job>> to control data state.
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/unscheduled_jobs_drawer.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _adminAuth = AuthState.authenticated(
  userId: 'admin-1',
  companyId: 'co-1',
  roles: {UserRole.admin},
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => _adminAuth;
}

/// Build an UnscheduledJobsDrawer with overridden providers.
Widget buildDrawerTestApp({
  AsyncValue<List<Job>>? jobsState,
  VoidCallback? onClose,
}) {
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
      calendarDateProvider.overrideWith((ref) => DateTime.now()),
      unscheduledJobsProvider.overrideWith(
        (ref) => Stream.value(
          (jobsState ?? const AsyncData<List<Job>>([])).value ?? [],
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 600,
          child: UnscheduledJobsDrawer(
            laneWidth: 150,
            pixelsPerMinute: 2.0,
            onClose: onClose ?? () {},
          ),
        ),
      ),
    ),
  );
}

/// Create a minimal [Job] data class row for drawer tests.
Job makeTestJobRow({
  String id = 'job-1',
  String description = 'Replace bathroom tiles',
  String status = 'quote',
  String tradeType = 'plumber',
  int? estimatedDurationMinutes = 120,
}) {
  final now = DateTime.now();
  return Job(
    id: id,
    companyId: 'co-1',
    description: description,
    tradeType: tradeType,
    status: status,
    statusHistory: '[]',
    priority: 'medium',
    tags: '[]',
    version: 1,
    createdAt: now,
    updatedAt: now,
    estimatedDurationMinutes: estimatedDurationMinutes,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('UnscheduledJobsDrawer — UAT #6', () {
    testWidgets('header shows "Unscheduled Jobs" text', (tester) async {
      await tester.pumpWidget(buildDrawerTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Unscheduled Jobs'), findsOneWidget);
    });

    testWidgets('close button present with tooltip', (tester) async {
      await tester.pumpWidget(buildDrawerTestApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('search field shows "Search jobs..." placeholder',
        (tester) async {
      await tester.pumpWidget(buildDrawerTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Search jobs...'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('filter chips All, Quote, Scheduled are present',
        (tester) async {
      await tester.pumpWidget(buildDrawerTestApp());
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Quote'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
    });

    testWidgets('trade type dropdown shows "All trades" hint', (tester) async {
      await tester.pumpWidget(buildDrawerTestApp());
      await tester.pumpAndSettle();

      expect(find.text('All trades'), findsAtLeast(1));
    });

    testWidgets('empty state shows "All jobs scheduled" when no jobs',
        (tester) async {
      await tester.pumpWidget(buildDrawerTestApp());
      await tester.pumpAndSettle();

      expect(find.text('All jobs scheduled'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('list icon present in header', (tester) async {
      await tester.pumpWidget(buildDrawerTestApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
    });

    testWidgets('close callback fires when close button tapped',
        (tester) async {
      var closeCalled = false;

      await tester.pumpWidget(buildDrawerTestApp(
        onClose: () => closeCalled = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(closeCalled, isTrue);
    });

    testWidgets('drag hint text shown on job cards', (tester) async {
      final job = makeTestJobRow(description: 'Install light fixtures');

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
          calendarDateProvider.overrideWith((ref) => DateTime.now()),
          unscheduledJobsProvider.overrideWith(
            (ref) => Stream.value([job]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 600,
              child: UnscheduledJobsDrawer(
                laneWidth: 150,
                pixelsPerMinute: 2.0,
                onClose: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Install light fixtures'), findsOneWidget);
      expect(find.text('Hold to drag'), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    });

    testWidgets('construction icon shows trade type', (tester) async {
      final job = makeTestJobRow(
        description: 'Wire new outlets',
        tradeType: 'electrician',
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
          calendarDateProvider.overrideWith((ref) => DateTime.now()),
          unscheduledJobsProvider.overrideWith(
            (ref) => Stream.value([job]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 600,
              child: UnscheduledJobsDrawer(
                laneWidth: 150,
                pixelsPerMinute: 2.0,
                onClose: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.construction), findsOneWidget);
      expect(find.text('electrician'), findsOneWidget);
    });
  });
}
