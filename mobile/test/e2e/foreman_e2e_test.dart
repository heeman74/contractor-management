// Foreman Feature — E2E Widget Tests.
//
// Covers DailyStatusScreen and StatusHistoryScreen rendering and interaction:
//   FM-01: DailyStatusScreen shows all form fields (project dropdown, status, weather, workers, safety, blockers)
//   FM-02: Submit button triggers validation when status text is empty
//   FM-03: Submit creates status update with correct payload via repository
//   FM-04: Success snackbar appears after successful submit
//   FM-05: Project dropdown shows assigned projects from provider
//   FM-06: StatusHistoryScreen shows status update cards with all fields
//   FM-07: StatusHistoryScreen shows empty state when no updates
//   FM-08: StatusHistoryScreen shows loading state with CircularProgressIndicator
//   FM-09: StatusHistoryScreen shows safety incident chip and blockers section
//   FM-10: Pull-to-refresh triggers reload on StatusHistoryScreen
//
// Patterns:
//   - ProviderScope.overrideWith for Riverpod providers
//   - pump() NOT pumpAndSettle() — Drift streams never settle (MEMORY.md)
//   - Fake repositories returning controlled data
//   - No GetIt initialization needed — providers overridden directly

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractorhub/features/foreman/data/foreman_repository.dart';
import 'package:contractorhub/features/foreman/presentation/providers/foreman_provider.dart';
import 'package:contractorhub/features/foreman/presentation/screens/daily_status_screen.dart';
import 'package:contractorhub/features/foreman/presentation/screens/status_history_screen.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _projectId1 = 'project-001';
const _projectId2 = 'project-002';
const _projectName1 = 'Highway Bridge Repair';
const _projectName2 = 'Office Building Renovation';

// ---------------------------------------------------------------------------
// Fake ForemanRepository
// ---------------------------------------------------------------------------

class _FakeForemanRepository implements ForemanRepository {
  List<Map<String, dynamic>> assignedProjects = [];
  List<Map<String, dynamic>> statusUpdates = [];
  Map<String, dynamic>? latestStatus;

  /// Captured payload from the last createStatusUpdate call.
  Map<String, dynamic>? lastCreatePayload;
  bool createCalled = false;
  bool fetchUpdatesCalled = false;
  bool shouldThrowOnCreate = false;

  @override
  Future<List<Map<String, dynamic>>> fetchAssignedProjects() async {
    return assignedProjects;
  }

  @override
  Future<Map<String, dynamic>> createStatusUpdate(
    Map<String, dynamic> data,
  ) async {
    createCalled = true;
    lastCreatePayload = data;
    if (shouldThrowOnCreate) {
      throw Exception('Server error');
    }
    return {'id': 'status-001', ...data};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStatusUpdates(
    String projectId, {
    int limit = 20,
    int offset = 0,
  }) async {
    fetchUpdatesCalled = true;
    return statusUpdates;
  }

  @override
  Future<Map<String, dynamic>?> fetchLatestStatus(String projectId) async {
    return latestStatus;
  }
}

// ---------------------------------------------------------------------------
// Data helpers
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _twoProjects() => [
      {
        'project_id': _projectId1,
        'project_name': _projectName1,
      },
      {
        'project_id': _projectId2,
        'project_name': _projectName2,
      },
    ];

List<Map<String, dynamic>> _sampleStatusUpdates() => [
      {
        'id': 'update-001',
        'project_id': _projectId1,
        'status_text': 'Completed foundation pouring',
        'report_date': '2026-03-25',
        'weather_conditions': 'Sunny, 72F',
        'workers_on_site': 12,
        'safety_incidents': 0,
        'blockers': null,
      },
      {
        'id': 'update-002',
        'project_id': _projectId1,
        'status_text': 'Electrical wiring in progress',
        'report_date': '2026-03-24',
        'weather_conditions': 'Cloudy, 65F',
        'workers_on_site': 8,
        'safety_incidents': 2,
        'blockers': 'Waiting for permit approval from city',
      },
      {
        'id': 'update-003',
        'project_id': _projectId1,
        'status_text': 'Site preparation ongoing',
        'report_date': '2026-03-23',
        'weather_conditions': null,
        'workers_on_site': 5,
        'safety_incidents': 0,
        'blockers': 'Material delivery delayed',
      },
    ];

// ---------------------------------------------------------------------------
// Widget wrappers
// ---------------------------------------------------------------------------

Widget _wrapDailyStatusScreen({
  required _FakeForemanRepository fakeRepo,
}) {
  return ProviderScope(
    overrides: [
      foremanRepositoryProvider.overrideWithValue(fakeRepo),
      assignedProjectsProvider.overrideWith(
        (ref) async {
          final repo = ref.watch(foremanRepositoryProvider);
          return repo.fetchAssignedProjects();
        },
      ),
    ],
    child: const MaterialApp(
      home: DailyStatusScreen(),
    ),
  );
}

Widget _wrapStatusHistoryScreen({
  required _FakeForemanRepository fakeRepo,
  String projectId = _projectId1,
  String? projectName = _projectName1,
}) {
  return ProviderScope(
    overrides: [
      foremanRepositoryProvider.overrideWithValue(fakeRepo),
    ],
    child: MaterialApp(
      home: StatusHistoryScreen(
        projectId: projectId,
        projectName: projectName,
      ),
    ),
  );
}

/// Wraps StatusHistoryScreen with statusUpdatesProvider returning a loading
/// state that never resolves (empty completer).
Widget _wrapStatusHistoryLoading() {
  final completer = Completer<List<Map<String, dynamic>>>();
  return ProviderScope(
    overrides: [
      foremanRepositoryProvider.overrideWithValue(_FakeForemanRepository()),
      statusUpdatesProvider(_projectId1).overrideWith(
        (ref) => completer.future,
      ),
    ],
    child: MaterialApp(
      home: StatusHistoryScreen(
        projectId: _projectId1,
        projectName: _projectName1,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Scroll helper — the form is long; Submit button is often off-screen.
// ---------------------------------------------------------------------------

Future<void> _scrollToAndTap(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byType(ListView),
    const Offset(0, -100),
  );
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests — DailyStatusScreen
// ---------------------------------------------------------------------------

void main() {
  group('DailyStatusScreen', () {
    testWidgets('FM-01: shows all form fields', (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..assignedProjects = _twoProjects();

      await tester.pumpWidget(_wrapDailyStatusScreen(fakeRepo: fakeRepo));
      await tester.pump(); // Let FutureProvider resolve.
      await tester.pump(); // Rebuild after data arrives.

      // App bar title
      expect(find.text('Daily Status Update'), findsOneWidget);

      // Project dropdown (label text)
      expect(find.text('Project *'), findsOneWidget);

      // Status text field
      expect(find.text('Status Update *'), findsOneWidget);

      // Weather conditions
      expect(find.text('Weather Conditions'), findsOneWidget);

      // Workers on site
      expect(find.text('Workers on Site'), findsOneWidget);

      // Safety incidents
      expect(find.text('Safety Incidents'), findsOneWidget);

      // Blockers
      expect(find.text('Blockers'), findsOneWidget);

      // Submit button
      expect(find.text('Submit Status Update'), findsOneWidget);

      // Add Photos button
      expect(find.text('Add Photos'), findsOneWidget);
    });

    testWidgets('FM-02: submit triggers validation when status text is empty',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..assignedProjects = _twoProjects();

      await tester.pumpWidget(_wrapDailyStatusScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // Select a project first to avoid the "select project" snackbar
      await tester.tap(find.text('Project *'));
      await tester.pump();
      await tester.tap(find.text(_projectName1).last);
      await tester.pump();

      // Scroll to and tap submit without entering status text
      await _scrollToAndTap(tester, find.text('Submit Status Update'));
      await tester.pump();

      // Scroll back up to see validation error on status field
      await tester.dragUntilVisible(
        find.text('Status update is required'),
        find.byType(ListView),
        const Offset(0, 100),
      );
      await tester.pump();

      // Validation error should appear
      expect(find.text('Status update is required'), findsOneWidget);

      // Repository should NOT have been called
      expect(fakeRepo.createCalled, isFalse);
    });

    testWidgets('FM-03: submit creates status update with correct payload',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..assignedProjects = _twoProjects();

      await tester.pumpWidget(_wrapDailyStatusScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // Select project
      await tester.tap(find.text('Project *'));
      await tester.pump();
      await tester.tap(find.text(_projectName1).last);
      await tester.pump();

      // Fill status text
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Status Update *'),
        'Foundation work completed today',
      );

      // Fill weather
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Weather Conditions'),
        'Sunny, 75F',
      );

      // Fill workers
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Workers on Site'),
        '10',
      );

      // Fill safety incidents (clear default "0" first)
      final safetyField =
          find.widgetWithText(TextFormField, 'Safety Incidents');
      await tester.tap(safetyField);
      await tester.pump();
      // Select all and replace
      await tester.enterText(safetyField, '1');

      // Fill blockers — scroll to it first since it may be off-screen
      await tester.dragUntilVisible(
        find.widgetWithText(TextFormField, 'Blockers'),
        find.byType(ListView),
        const Offset(0, -100),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Blockers'),
        'Permit pending',
      );

      // Scroll to and tap submit
      await _scrollToAndTap(tester, find.text('Submit Status Update'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify create was called
      expect(fakeRepo.createCalled, isTrue);

      // Verify payload
      final payload = fakeRepo.lastCreatePayload!;
      expect(payload['project_id'], _projectId1);
      expect(payload['status_text'], 'Foundation work completed today');
      expect(payload['weather_conditions'], 'Sunny, 75F');
      expect(payload['workers_on_site'], 10);
      expect(payload['safety_incidents'], 1);
      expect(payload['blockers'], 'Permit pending');
      expect(payload['report_date'], isNotNull);
    });

    testWidgets('FM-04: shows success snackbar on submit', (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..assignedProjects = _twoProjects();

      await tester.pumpWidget(_wrapDailyStatusScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // Select project
      await tester.tap(find.text('Project *'));
      await tester.pump();
      await tester.tap(find.text(_projectName1).last);
      await tester.pump();

      // Fill status text
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Status Update *'),
        'Progress on framing',
      );

      // Scroll to and tap submit
      await _scrollToAndTap(tester, find.text('Submit Status Update'));
      await tester.pump(const Duration(milliseconds: 100));

      // Snackbar should appear
      expect(
        find.text('Status update submitted successfully'),
        findsOneWidget,
      );
    });

    testWidgets('FM-05: project dropdown shows assigned projects',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..assignedProjects = _twoProjects();

      await tester.pumpWidget(_wrapDailyStatusScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // Open dropdown
      await tester.tap(find.text('Project *'));
      await tester.pump();

      // Both project names should be visible in dropdown items
      expect(find.text(_projectName1), findsWidgets);
      expect(find.text(_projectName2), findsWidgets);
    });

    testWidgets('FM-05b: shows no-projects message when none assigned',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()..assignedProjects = [];

      await tester.pumpWidget(_wrapDailyStatusScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      expect(find.text('No projects assigned to you.'), findsOneWidget);
    });

    testWidgets('FM-04b: shows error snackbar when submit fails',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..assignedProjects = _twoProjects()
        ..shouldThrowOnCreate = true;

      await tester.pumpWidget(_wrapDailyStatusScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // Select project
      await tester.tap(find.text('Project *'));
      await tester.pump();
      await tester.tap(find.text(_projectName1).last);
      await tester.pump();

      // Fill status text
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Status Update *'),
        'Some progress',
      );

      // Scroll to and tap submit
      await _scrollToAndTap(tester, find.text('Submit Status Update'));
      await tester.pump(const Duration(milliseconds: 100));

      // Error snackbar should appear
      expect(find.text('Failed to submit status update'), findsOneWidget);
    });

    testWidgets('FM-02b: shows snackbar when no project selected',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..assignedProjects = _twoProjects();

      await tester.pumpWidget(_wrapDailyStatusScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // Fill status text but do NOT select a project
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Status Update *'),
        'Some progress',
      );

      // Scroll to and tap submit
      await _scrollToAndTap(tester, find.text('Submit Status Update'));
      await tester.pump();

      // Snackbar about selecting project should appear
      // (also shows as dropdown validation error)
      expect(find.text('Please select a project'), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Tests — StatusHistoryScreen
  // ---------------------------------------------------------------------------

  group('StatusHistoryScreen', () {
    testWidgets('FM-06: shows status update cards with all fields',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..statusUpdates = _sampleStatusUpdates();

      await tester.pumpWidget(
          _wrapStatusHistoryScreen(fakeRepo: fakeRepo));
      await tester.pump(); // Let FutureProvider resolve.
      await tester.pump(); // Rebuild.

      // App bar title
      expect(find.text(_projectName1), findsOneWidget);

      // First card: status text, date, weather, workers
      expect(find.text('Completed foundation pouring'), findsOneWidget);
      expect(find.text('2026-03-25'), findsOneWidget);
      expect(find.text('Sunny, 72F'), findsOneWidget);
      expect(find.text('12 workers'), findsOneWidget);

      // Second card: has safety incidents and blockers
      expect(find.text('Electrical wiring in progress'), findsOneWidget);
      expect(find.text('2026-03-24'), findsOneWidget);
    });

    testWidgets('FM-07: shows empty state when no updates', (tester) async {
      final fakeRepo = _FakeForemanRepository()..statusUpdates = [];

      await tester.pumpWidget(
          _wrapStatusHistoryScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      expect(find.text('No status updates yet'), findsOneWidget);
      expect(find.text('Pull down to refresh'), findsOneWidget);
      expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    });

    testWidgets('FM-08: shows loading state with CircularProgressIndicator',
        (tester) async {
      await tester.pumpWidget(_wrapStatusHistoryLoading());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
        'FM-09: shows safety incident chip for updates with incidents > 0',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..statusUpdates = _sampleStatusUpdates();

      await tester.pumpWidget(
          _wrapStatusHistoryScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // Second update has 2 safety incidents -> chip with "2 incident(s)"
      expect(find.text('2 incident(s)'), findsOneWidget);

      // First update has 0 safety incidents -> no incident chip for it
      // (only the second card should have this chip)
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('FM-09b: shows blockers section for updates with blockers',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..statusUpdates = _sampleStatusUpdates();

      await tester.pumpWidget(
          _wrapStatusHistoryScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // "Blockers" label should appear for cards with blocker text
      expect(find.text('Blockers'), findsWidgets);

      // Blocker text from second update
      expect(
        find.text('Waiting for permit approval from city'),
        findsOneWidget,
      );

      // Blocker text from third update
      expect(find.text('Material delivery delayed'), findsOneWidget);

      // Block icon should appear for cards with blockers
      expect(find.byIcon(Icons.block_outlined), findsWidgets);
    });

    testWidgets('FM-10: pull to refresh triggers reload', (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..statusUpdates = _sampleStatusUpdates();

      await tester.pumpWidget(
          _wrapStatusHistoryScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // RefreshIndicator should be present
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Reset the flag after initial fetch
      fakeRepo.fetchUpdatesCalled = false;

      // Simulate pull-to-refresh by dragging from top of list
      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The refresh invalidates the statusUpdatesProvider which re-fetches.
      // Since our FakeRepo tracks fetchUpdatesCalled, verify it was called again.
      expect(fakeRepo.fetchUpdatesCalled, isTrue,
          reason:
              'pull-to-refresh should invalidate provider, triggering re-fetch');
    });

    testWidgets('FM-06b: displays weather and worker chips correctly',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()
        ..statusUpdates = [
          {
            'id': 'update-single',
            'project_id': _projectId1,
            'status_text': 'Roof tiling started',
            'report_date': '2026-03-26',
            'weather_conditions': 'Rainy, 58F',
            'workers_on_site': 6,
            'safety_incidents': 0,
            'blockers': null,
          },
        ];

      await tester.pumpWidget(
          _wrapStatusHistoryScreen(fakeRepo: fakeRepo));
      await tester.pump();
      await tester.pump();

      // Weather chip
      expect(find.text('Rainy, 58F'), findsOneWidget);
      expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);

      // Workers chip
      expect(find.text('6 workers'), findsOneWidget);
      expect(find.byIcon(Icons.people_outlined), findsOneWidget);
    });

    testWidgets('FM-07b: uses projectName as app bar title', (tester) async {
      final fakeRepo = _FakeForemanRepository()..statusUpdates = [];

      await tester.pumpWidget(_wrapStatusHistoryScreen(
        fakeRepo: fakeRepo,
        projectName: 'Custom Project Title',
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Custom Project Title'), findsOneWidget);
    });

    testWidgets('FM-07c: falls back to Status History when projectName is null',
        (tester) async {
      final fakeRepo = _FakeForemanRepository()..statusUpdates = [];

      await tester.pumpWidget(_wrapStatusHistoryScreen(
        fakeRepo: fakeRepo,
        projectName: null,
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Status History'), findsOneWidget);
    });
  });
}
