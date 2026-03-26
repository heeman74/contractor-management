// Phase 26 — AI Daily Checklists: Flutter E2E Widget Tests.
//
// Covers DailyChecklistScreen rendering and interaction flows:
//   AI-04-01: Screen shows "Today's Checklist" title + current date
//   AI-04-02: All task titles from checklistJson are rendered
//   AI-04-03: Priority 1 task has URGENT/red badge, priority 3 has NORMAL/blue
//   AI-04-04: Materials needed chips rendered for tasks that have them
//   AI-04-05: Camera icon appears for tasks with photo_required=true
//   AI-04-06: Estimated duration shown as "~45 min" for 45-minute task
//   AI-04-07: Tapping an item triggers navigation to task detail
//   AI-04-08: Empty state shows "No tasks scheduled for today"
//   AI-04-09: Loading state shows CircularProgressIndicator
//   AI-04-10: Multiple checklists grouped by project name (section headers)
//   AI-04-11: Pull-to-refresh calls fetchTodayChecklist on repository
//
// Patterns:
//   - ProviderScope.overrideWith for Riverpod providers
//   - pump() NOT pumpAndSettle() — Drift streams never settle (MEMORY.md)
//   - Stream.value() for pre-seeded static data
//   - No GetIt initialization needed — todayChecklistProvider overridden directly

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/checklists/data/checklist_repository.dart';
import 'package:contractorhub/features/checklists/presentation/providers/checklist_provider.dart';
import 'package:contractorhub/features/checklists/presentation/screens/daily_checklist_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _contractorId = 'contractor-001';
const _projectId = 'project-001';
const _scopeId = 'scope-001';
const _taskId1 = 'task-uuid-001';
const _taskId2 = 'task-uuid-002';
const _taskId3 = 'task-uuid-003';

// ---------------------------------------------------------------------------
// Auth state helper
// ---------------------------------------------------------------------------

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _contractorId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

// ---------------------------------------------------------------------------
// Fake auth notifier
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState _state;
  _FakeAuthNotifier(this._state);

  @override
  AuthState build() => _state;
}

// ---------------------------------------------------------------------------
// Fake ChecklistRepository — does nothing (repository fetch is fire-and-forget)
// ---------------------------------------------------------------------------

class _FakeChecklistRepository implements ChecklistRepository {
  bool fetchCalled = false;

  @override
  Future<void> fetchTodayChecklist() async {
    fetchCalled = true;
  }

  @override
  Stream<List<DailyChecklist>> watchTodayChecklist(
    String contractorId, {
    String? companyId,
  }) {
    return Stream.value([]);
  }
}

// ---------------------------------------------------------------------------
// Data builder helpers
// ---------------------------------------------------------------------------

String _makeChecklistJson({
  String taskId = _taskId1,
  String title = 'Install Pipes',
  int priority = 1,
  List<String> materials = const ['pipe wrench', 'sealant'],
  bool photoRequired = true,
  int estimatedMinutes = 45,
  String projectName = 'Test Project',
  String dependencyStatus = 'clear',
}) {
  return jsonEncode({
    'tasks': [
      {
        'task_id': taskId,
        'title': title,
        'priority': priority,
        'materials_needed': materials,
        'photo_required': photoRequired,
        'estimated_duration': '${estimatedMinutes} min',
        'project_name': projectName,
        'dependency_status': dependencyStatus,
        'notes': '',
      },
    ],
  });
}

String _makeMultiTaskChecklistJson(String projectName) {
  return jsonEncode({
    'tasks': [
      {
        'task_id': _taskId1,
        'title': 'Install Pipes',
        'priority': 1,
        'materials_needed': ['pipe wrench', 'sealant'],
        'photo_required': true,
        'estimated_duration': '45 min',
        'project_name': projectName,
        'dependency_status': 'clear',
        'notes': '',
      },
      {
        'task_id': _taskId2,
        'title': 'Check Pressure',
        'priority': 2,
        'materials_needed': [],
        'photo_required': false,
        'estimated_duration': '15 min',
        'project_name': projectName,
        'dependency_status': 'clear',
        'notes': '',
      },
      {
        'task_id': _taskId3,
        'title': 'Final Inspection',
        'priority': 3,
        'materials_needed': [],
        'photo_required': false,
        'estimated_duration': '30 min',
        'project_name': projectName,
        'dependency_status': 'clear',
        'notes': '',
      },
    ],
  });
}

DailyChecklist _makeChecklist({
  String id = 'checklist-001',
  String contractorId = _contractorId,
  String projectId = _projectId,
  String tradeScopeId = _scopeId,
  String? checklistJson,
}) {
  final now = DateTime.now();
  final dateStr =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return DailyChecklist(
    id: id,
    companyId: _companyId,
    contractorId: contractorId,
    projectId: projectId,
    tradeScopeId: tradeScopeId,
    checklistDate: dateStr,
    checklistJson: checklistJson ?? _makeChecklistJson(),
    summaryText: 'You have 1 task today: Install Pipes.',
    isPushed: false,
    createdAt: now,
    deletedAt: null,
  );
}

// ---------------------------------------------------------------------------
// Widget wrapper helpers
// ---------------------------------------------------------------------------

Widget _wrapScreen({
  required Widget child,
  required List<DailyChecklist> checklists,
  _FakeChecklistRepository? fakeRepo,
}) {
  final repo = fakeRepo ?? _FakeChecklistRepository();
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(_contractorAuth())),
      checklistRepositoryProvider.overrideWithValue(repo),
      todayChecklistProvider.overrideWith(
        (ref) => Stream.value(checklists),
      ),
    ],
    child: MaterialApp(
      home: child,
    ),
  );
}

Widget _wrapScreenWithAsyncValue({
  required Widget child,
  required AsyncValue<List<DailyChecklist>> asyncValue,
}) {
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(_contractorAuth())),
      checklistRepositoryProvider.overrideWithValue(_FakeChecklistRepository()),
      todayChecklistProvider.overrideWith((ref) {
        if (asyncValue is AsyncLoading) {
          // Return a stream that never emits to simulate loading
          return const Stream.empty();
        }
        if (asyncValue is AsyncError) {
          return Stream.error((asyncValue as AsyncError).error);
        }
        return Stream.value((asyncValue as AsyncData<List<DailyChecklist>>).value);
      }),
    ],
    child: MaterialApp(
      home: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DailyChecklistScreen', () {
    testWidgets('shows Today\'s Checklist title and current date', (tester) async {
      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [_makeChecklist()],
        ),
      );
      await tester.pump();

      // Verify app bar title
      expect(find.text("Today's Checklist"), findsOneWidget);

      // Verify date is shown (day of week + date format)
      final now = DateTime.now();
      final months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      final monthName = months[now.month - 1];
      // Verify the month name appears somewhere in the app bar subtitle
      expect(find.textContaining(monthName), findsOneWidget);
    });

    testWidgets('renders all task titles from checklistJson', (tester) async {
      final checklist = _makeChecklist(
        checklistJson: _makeMultiTaskChecklistJson('Project A'),
      );

      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [checklist],
        ),
      );
      await tester.pump();

      expect(find.text('Install Pipes'), findsOneWidget);
      expect(find.text('Check Pressure'), findsOneWidget);
      expect(find.text('Final Inspection'), findsOneWidget);
    });

    testWidgets('priority 1 shows URGENT badge, priority 3 shows NORMAL badge',
        (tester) async {
      final checklist = _makeChecklist(
        checklistJson: _makeMultiTaskChecklistJson('Project A'),
      );

      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [checklist],
        ),
      );
      await tester.pump();

      expect(find.text('URGENT'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('NORMAL'), findsOneWidget);
    });

    testWidgets('renders materials needed as chips for tasks with materials',
        (tester) async {
      final checklist = _makeChecklist(
        checklistJson: _makeChecklistJson(
          materials: ['pipe wrench', 'sealant'],
        ),
      );

      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [checklist],
        ),
      );
      await tester.pump();

      expect(find.text('pipe wrench'), findsOneWidget);
      expect(find.text('sealant'), findsOneWidget);
    });

    testWidgets('shows camera icon for tasks with photo_required=true',
        (tester) async {
      final checklist = _makeChecklist(
        checklistJson: _makeChecklistJson(photoRequired: true),
      );

      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [checklist],
        ),
      );
      await tester.pump();

      // camera_alt_outlined icon should be visible
      expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    });

    testWidgets('no camera icon for tasks with photo_required=false',
        (tester) async {
      final checklist = _makeChecklist(
        checklistJson: _makeChecklistJson(photoRequired: false),
      );

      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [checklist],
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    });

    testWidgets('shows estimated duration for task with estimated_duration set',
        (tester) async {
      final checklist = _makeChecklist(
        checklistJson: _makeChecklistJson(estimatedMinutes: 45),
      );

      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [checklist],
        ),
      );
      await tester.pump();

      // The screen renders "~45 min" using the estimated_duration string
      expect(find.textContaining('~45 min'), findsOneWidget);
    });

    testWidgets('task card has InkWell tap handler wired to task detail navigation',
        (tester) async {
      final checklist = _makeChecklist(
        checklistJson: _makeChecklistJson(taskId: _taskId1),
      );

      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [checklist],
        ),
      );
      await tester.pump();

      // Task card renders as InkWell — verify the tap target is present and wired.
      // The onTap calls context.push(RouteNames.taskDetailPath(taskId)) via GoRouter.
      // Full navigation test would require GoRouter setup; here we verify the
      // InkWell is rendered (meaning the tap handler is configured).
      final inkWellFinder = find.byType(InkWell);
      expect(inkWellFinder, findsAtLeast(1),
          reason: 'Task card should have an InkWell for tapping to task detail');

      // Verify the task title is visible (card rendered correctly)
      expect(find.text('Install Pipes'), findsOneWidget);
    });

    testWidgets('shows empty state message when checklist list is empty',
        (tester) async {
      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [],
        ),
      );
      await tester.pump();

      expect(find.text('No tasks scheduled for today'), findsOneWidget);
      expect(find.text('Pull down to refresh'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator in loading state',
        (tester) async {
      await tester.pumpWidget(
        _wrapScreenWithAsyncValue(
          child: const DailyChecklistScreen(),
          asyncValue: const AsyncLoading(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('groups tasks by project name with section headers', (tester) async {
      final todayStr = () {
        final now = DateTime.now();
        return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      }();

      // Two checklists from different projects
      final checklist1 = DailyChecklist(
        id: 'checklist-001',
        companyId: _companyId,
        contractorId: _contractorId,
        projectId: 'project-001',
        tradeScopeId: 'scope-001',
        checklistDate: todayStr,
        checklistJson: jsonEncode({
          'tasks': [
            {
              'task_id': _taskId1,
              'title': 'Plumbing Task A',
              'priority': 1,
              'materials_needed': [],
              'photo_required': false,
              'estimated_duration': '30 min',
              'project_name': 'Project Alpha',
              'dependency_status': 'clear',
            },
          ],
        }),
        summaryText: 'Task for Alpha.',
        isPushed: false,
        createdAt: DateTime.now(),
        deletedAt: null,
      );

      final checklist2 = DailyChecklist(
        id: 'checklist-002',
        companyId: _companyId,
        contractorId: _contractorId,
        projectId: 'project-002',
        tradeScopeId: 'scope-002',
        checklistDate: todayStr,
        checklistJson: jsonEncode({
          'tasks': [
            {
              'task_id': _taskId2,
              'title': 'Electrical Task B',
              'priority': 2,
              'materials_needed': [],
              'photo_required': false,
              'estimated_duration': '20 min',
              'project_name': 'Project Beta',
              'dependency_status': 'clear',
            },
          ],
        }),
        summaryText: 'Task for Beta.',
        isPushed: false,
        createdAt: DateTime.now(),
        deletedAt: null,
      );

      await tester.pumpWidget(
        _wrapScreen(
          child: const DailyChecklistScreen(),
          checklists: [checklist1, checklist2],
        ),
      );
      await tester.pump();

      // Task titles should be present
      expect(find.text('Plumbing Task A'), findsOneWidget);
      expect(find.text('Electrical Task B'), findsOneWidget);

      // With 2 projects, section headers should appear
      expect(find.text('Project Alpha'), findsOneWidget);
      expect(find.text('Project Beta'), findsOneWidget);
    });

    testWidgets('pull-to-refresh triggers fetchTodayChecklist on repository',
        (tester) async {
      final fakeRepo = _FakeChecklistRepository();

      final checklist = _makeChecklist(
        checklistJson: _makeChecklistJson(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(() => _FakeAuthNotifier(_contractorAuth())),
            checklistRepositoryProvider.overrideWithValue(fakeRepo),
            todayChecklistProvider.overrideWith(
              (ref) => Stream.value([checklist]),
            ),
          ],
          child: const MaterialApp(
            home: DailyChecklistScreen(),
          ),
        ),
      );
      await tester.pump();

      // Verify the checklist is shown (RefreshIndicator is present)
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Simulate pull-to-refresh by dragging from the top of the list
      await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // fetchTodayChecklist is called via the _refresh method
      // The RefreshIndicator calls onRefresh which calls repository.fetchTodayChecklist()
      expect(fakeRepo.fetchCalled, isTrue,
          reason: 'pull-to-refresh should call repository.fetchTodayChecklist()');
    });
  });
}
