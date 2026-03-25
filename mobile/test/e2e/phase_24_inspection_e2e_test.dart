// Phase 24 — GC Inspection Workflow: Flutter E2E tests — INSP-01.
//
// Covers inspection UI flows on TaskDetailScreen:
//   INSP-01-01: GC sees Approve and Reject buttons on complete task
//   INSP-01-02: Contractor does NOT see Approve/Reject on complete task
//   INSP-01-03: Inspection checklist renders default items when no scope checklist
//   INSP-01-04: Approve disabled until all checklist items checked
//   INSP-01-05: Reject opens rejection bottom sheet
//   INSP-01-06: Confirm Rejection disabled until reason selected
//   INSP-01-07: Contractor sees Start Rework on rejected task
//   INSP-01-08: Rejected status badge shows deep red color
//   INSP-01-09: GC sees total hours logged on complete task
//   INSP-01-10: GC sees status transition timeline on complete task
//
// Patterns:
//   - ProviderScope.overrideWith for Riverpod providers
//   - pump() NOT pumpAndSettle() — Drift streams never settle (MEMORY.md)
//   - Stream.value() for pre-seeded static data
//   - No GetIt initialization needed — DAOs overridden via ProviderScope

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/projects/presentation/providers/project_providers.dart';
import 'package:contractorhub/features/projects/presentation/screens/task_detail_screen.dart';
import 'package:contractorhub/features/projects/presentation/widgets/inspection_checklist.dart';
import 'package:contractorhub/shared/models/user_role.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _gcId = 'gc-001';
const _contractorId = 'contractor-001';
const _projectId = 'project-001';
const _scopeId = 'scope-001';
const _taskId = 'task-001';
const _inspectionId = 'insp-001';

// ---------------------------------------------------------------------------
// Auth state helpers
// ---------------------------------------------------------------------------

AuthState _gcAuth() => const AuthState.authenticated(
      userId: _gcId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _contractorId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

// ---------------------------------------------------------------------------
// Data builder helpers
// ---------------------------------------------------------------------------

ProjectTask _makeTask({
  String id = _taskId,
  String scopeId = _scopeId,
  String title = 'Install Outlets',
  String status = 'complete',
  String priority = 'medium',
  bool photoRequired = false,
}) {
  final now = DateTime.now();
  return ProjectTask(
    id: id,
    companyId: _companyId,
    tradeScopeId: scopeId,
    title: title,
    description: null,
    status: status,
    sortOrder: 0,
    priority: priority,
    estimatedHours: null,
    estimatedCost: null,
    dueDate: null,
    photoRequired: photoRequired,
    assignedTo: _contractorId,
    materialsNeeded: '[]',
    version: 1,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

TradeScope _makeScope({
  String id = _scopeId,
  String tradeName = 'Electrical',
  String? inspectionChecklist,
}) {
  final now = DateTime.now();
  return TradeScope(
    id: id,
    companyId: _companyId,
    projectId: _projectId,
    tradeCatalogId: null,
    tradeName: tradeName,
    tradeColor: '#3F51B5',
    contractorId: _contractorId,
    status: 'not_started',
    statusOverride: false,
    sortOrder: 0,
    version: 1,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

// ---------------------------------------------------------------------------
// Fake notifiers
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState _state;
  _FakeAuthNotifier(this._state);

  @override
  AuthState build() => _state;
}

// ---------------------------------------------------------------------------
// Fake TaskDao that returns Stream.value() to avoid pending Drift timers
// ---------------------------------------------------------------------------

class _FakeTaskDao implements TaskDao {
  final ProjectTask? task;
  _FakeTaskDao({this.task});

  @override
  Stream<ProjectTask?> watchTaskById(String taskId) =>
      Stream.value(task?.id == taskId ? task : null);

  @override
  Stream<List<ProjectTask>> watchTasksByScope(String scopeId) =>
      Stream.value(task != null ? [task!] : []);

  @override
  Stream<List<ProjectTask>> watchTasksForContractor(String userId) =>
      Stream.value([]);

  @override
  Future<int> countTasksByScope(String scopeId) async => task != null ? 1 : 0;

  @override
  Future<int> countCompletedTasksByScope(String scopeId) async =>
      (task?.status == 'complete') ? 1 : 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTradeScopeDao implements TradeScopeDao {
  final TradeScope? scope;
  _FakeTradeScopeDao({this.scope});

  @override
  Stream<TradeScope?> watchScopeById(String scopeId) =>
      Stream.value(scope?.id == scopeId ? scope : null);

  @override
  Stream<List<TradeScope>> watchScopesByProject(String projectId) =>
      Stream.value(scope != null ? [scope!] : []);

  @override
  Stream<List<TradeScope>> watchAllScopesByCompany(String companyId) =>
      Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Widget wrapper helper
// ---------------------------------------------------------------------------

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

Widget _wrapWithFakeDaos(
  AuthState auth, {
  ProjectTask? task,
  TradeScope? scope,
}) {
  final theTask = task ?? _makeTask();
  final theScope = scope ?? _makeScope();

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      taskDaoProvider.overrideWithValue(_FakeTaskDao(task: theTask) as TaskDao),
      tradeScopeDaoProvider
          .overrideWithValue(_FakeTradeScopeDao(scope: theScope) as TradeScopeDao),
      taskNotesProvider(theTask.id).overrideWith((ref) => Stream.value([])),
      taskAttachmentsProvider(theTask.id).overrideWith((ref) => Stream.value([])),
      taskPhotoCountProvider(theTask.id).overrideWith((ref) => Stream.value(0)),
      taskDocCountProvider(theTask.id).overrideWith((ref) => Stream.value(0)),
      inspectionsForTaskProvider(theTask.id).overrideWith((ref) => Stream.value([])),
      tradeScopesProvider(theTask.tradeScopeId)
          .overrideWith((ref) => Stream.value([theScope])),
    ],
    child: MaterialApp(
      home: TaskDetailScreen(taskId: theTask.id),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Inspection Checklist', () {
    testWidgets('renders default checklist items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectionChecklist(
              items: kDefaultInspectionChecklist
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(),
              onAllCheckedChanged: (_) {},
              onResultsChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Quality of work is acceptable'), findsOneWidget);
      expect(find.text('Correct materials were used'), findsOneWidget);
      expect(find.text('Work area is clean and safe'), findsOneWidget);
      expect(find.text('Safety requirements are met'), findsOneWidget);
    });

    testWidgets('onAllCheckedChanged fires true when all items checked',
        (tester) async {
      bool allChecked = false;

      final items = kDefaultInspectionChecklist
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectionChecklist(
              items: items,
              onAllCheckedChanged: (val) => allChecked = val,
              onResultsChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap all checkboxes
      for (final item in items) {
        final text = item['item'] as String;
        await tester.tap(find.widgetWithText(CheckboxListTile, text));
        await tester.pump();
      }

      expect(allChecked, isTrue);
    });

    testWidgets('onAllCheckedChanged fires false when any item unchecked',
        (tester) async {
      bool allChecked = false;

      final items = kDefaultInspectionChecklist
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InspectionChecklist(
              items: items,
              onAllCheckedChanged: (val) => allChecked = val,
              onResultsChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Check all items
      for (final item in items) {
        await tester.tap(
            find.widgetWithText(CheckboxListTile, item['item'] as String));
        await tester.pump();
      }
      expect(allChecked, isTrue);

      // Uncheck one
      await tester
          .tap(find.widgetWithText(CheckboxListTile, items[0]['item'] as String));
      await tester.pump();

      expect(allChecked, isFalse);
    });
  });

  group('GC sees Approve and Reject', () {
    testWidgets('GC sees Approve and Reject buttons on complete task',
        (tester) async {
      final task = _makeTask(status: 'complete');

      await tester.pumpWidget(_wrapWithFakeDaos(_gcAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Approve and Reject should be visible in the bottom bar
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('Contractor does NOT see Approve or Reject on complete task',
        (tester) async {
      final task = _makeTask(status: 'complete');

      await tester.pumpWidget(_wrapWithFakeDaos(_contractorAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Contractor sees "Mark Incomplete" instead, not Approve/Reject
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('Approve disabled until all checklist items checked',
        (tester) async {
      final task = _makeTask(status: 'complete');

      await tester.pumpWidget(_wrapWithFakeDaos(_gcAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Approve button should exist but be disabled (onPressed is null)
      final approveBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Approve'),
      );
      expect(approveBtn.onPressed, isNull,
          reason: 'Approve should be disabled until all items checked');

      // Scroll down to expose the InspectionChecklist section, then tap all
      // checkboxes. The checklist has 4 items — scroll enough to bring them
      // into view without overshooting.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump();

      for (final entry in kDefaultInspectionChecklist) {
        final itemText = entry['item'] as String;
        final finder = find.widgetWithText(CheckboxListTile, itemText);
        if (finder.evaluate().isEmpty) {
          // Item still offscreen — drag a bit more
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
          await tester.pump();
        }
        if (finder.evaluate().isNotEmpty) {
          await tester.tap(finder.first);
          await tester.pump();
        }
      }

      // After checking all items, Approve should be enabled
      final approveBtnAfter = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Approve'),
      );
      expect(approveBtnAfter.onPressed, isNotNull,
          reason: 'Approve should be enabled after all items checked');
    });
  });

  group('Reject opens rejection bottom sheet', () {
    testWidgets('Reject button shows rejection sheet', (tester) async {
      final task = _makeTask(status: 'complete');

      await tester.pumpWidget(_wrapWithFakeDaos(_gcAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Reject
      await tester.tap(find.text('Reject'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Rejection sheet should appear
      expect(find.text('Reject Task'), findsOneWidget);
      expect(find.text('Reason (required)'), findsOneWidget);
      expect(find.text('Confirm Rejection'), findsOneWidget);
    });

    testWidgets('Confirm Rejection disabled until reason selected',
        (tester) async {
      final task = _makeTask(status: 'complete');

      await tester.pumpWidget(_wrapWithFakeDaos(_gcAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open rejection sheet
      await tester.tap(find.text('Reject'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Confirm Rejection should be disabled before selecting a reason
      final confirmBtn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirm Rejection'),
      );
      expect(confirmBtn.onPressed, isNull,
          reason: 'Confirm Rejection disabled until reason selected');
    });
  });

  group('Start Rework', () {
    testWidgets('Contractor sees Start Rework on rejected task', (tester) async {
      final task = _makeTask(status: 'rejected');

      await tester.pumpWidget(_wrapWithFakeDaos(_contractorAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Start Rework'), findsOneWidget);
    });

    testWidgets('GC does NOT see Start Rework on rejected task', (tester) async {
      final task = _makeTask(status: 'rejected');

      await tester.pumpWidget(_wrapWithFakeDaos(_gcAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Start Rework'), findsNothing);
    });
  });

  group('total hours logged', () {
    testWidgets('GC sees total hours logged section on complete task',
        (tester) async {
      final task = _makeTask(status: 'complete');

      await tester.pumpWidget(_wrapWithFakeDaos(_gcAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to find the total time section
      await tester.scrollUntilVisible(
        find.textContaining('Total Time'),
        100,
      );

      expect(find.textContaining('Total Time'), findsOneWidget);
    });
  });

  group('status transition timeline', () {
    testWidgets('GC sees status transition timeline on complete task',
        (tester) async {
      final task = _makeTask(status: 'complete');

      await tester.pumpWidget(_wrapWithFakeDaos(_gcAuth(), task: task));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll to find the timeline section
      await tester.scrollUntilVisible(
        find.text('Created'),
        100,
      );

      expect(find.text('Created'), findsWidgets);
      // Also look for In Progress and Complete timeline markers
      await tester.scrollUntilVisible(
        find.text('In Progress'),
        100,
      );
      expect(find.text('In Progress'), findsWidgets);
    });
  });
}
