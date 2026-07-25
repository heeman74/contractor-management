// Task List (Trade Scope Detail) — Flutter E2E widget tests.
//
// TARGET: lib/features/projects/presentation/screens/task_list_screen.dart,
// which is a thin re-export of TradeScopeDetailScreen. This screen is the
// per-scope task list: it shows EVERY task for one trade scope (read-only
// TaskRow cards with a priority left border + status badge + due date), an
// optional Punch List section, and — for GC/admin only — a Billing section.
//
// HOW THIS DIFFERS FROM MyTasksScreen (already covered by
// phase_22_task_execution_e2e_test.dart):
//   - MyTasksScreen = one contractor's INCOMPLETE tasks across ALL scopes,
//     grouped by scope, rendered as interactive TaskChecklistCards (checkbox,
//     photo gate, completion write).
//   - TradeScopeDetailScreen = ALL tasks for ONE scope, rendered as read-only
//     TaskRow cards (no checkbox / no completion write on this screen), plus
//     a Punch List section and a role-gated Billing section, plus an empty
//     state that offers "Start AI Interview".
//
// phase_22 only touches this screen for ONE thing: the D-15 TaskThumbnailRow
// render (admin, 1 task, 2 photos). Everything below is the delta that
// phase_22 does NOT cover.
//
// Coverage (unique to this screen):
//   - Happy path: multiple task rows render with title, status badge, due date
//     (real Drift in-memory DB via getIt — true offline-first path).
//   - Empty state: "No tasks yet" + "Start AI Interview" when no tasks/punch.
//   - AppBar title resolves the scope name from tradeScopesProvider.
//   - Status badge label mapping (Not Started / In Progress / Blocked).
//   - Punch List section renders PunchListCard(s) under a "Punch List" header.
//   - Tasks empty BUT punch items present → NOT the empty state (punch shown).
//   - Error state: "Error loading tasks: ..." when the tasks stream errors.
//   - Role gating: GC/admin sees the "Billing" section; contractor does NOT.
//   - Navigation: tapping a task row pushes the task detail route.
//
// Patterns (copied from phase_22 / contractor_jobs / team_management harness):
//   - ProviderScope overrides for Riverpod StreamProviders.
//   - pump() / pump(Duration) — NEVER pumpAndSettle (Drift never settles).
//   - Stream.value() for pre-seeded async data.
//   - Real AppDatabase(NativeDatabase.memory()) + getIt for the DAO path.
//   - Fake AuthNotifier extending the real AuthNotifier.
//   - GoRouter so context.push (task detail / AI interview) resolves.
//   - Drain Drift's zero-duration close timer at each test end.
//
// Total: 10 tests.

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/billing_milestones/presentation/providers/billing_milestone_providers.dart';
import 'package:contractorhub/features/projects/presentation/providers/billing_summary_providers.dart';
import 'package:contractorhub/features/projects/presentation/providers/project_providers.dart';
import 'package:contractorhub/features/projects/presentation/screens/task_list_screen.dart';
import 'package:contractorhub/features/projects/presentation/widgets/punch_list_card.dart';
import 'package:contractorhub/features/projects/presentation/widgets/task_row.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _contractorId = 'contractor-001';
const _adminId = 'admin-001';

const _projectId = 'project-001';
const _scopeId = 'scope-001';

const _task1Id = 'task-001';
const _task2Id = 'task-002';
const _task3Id = 'task-003';
const _punch1Id = 'punch-001';

// ---------------------------------------------------------------------------
// Auth state helpers
// ---------------------------------------------------------------------------

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _contractorId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

AuthState _adminAuth() => const AuthState.authenticated(
      userId: _adminId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

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
// Data builder helpers
// ---------------------------------------------------------------------------

TradeScope _makeScope({
  String id = _scopeId,
  String tradeName = 'Electrical',
  int sortOrder = 0,
}) {
  final now = DateTime.now();
  return TradeScope(
    id: id,
    companyId: _companyId,
    projectId: _projectId,
    tradeName: tradeName,
    tradeColor: '#3F51B5',
    contractorId: _contractorId,
    status: 'in_progress',
    statusOverride: false,
    sortOrder: sortOrder,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectTask _makeTask({
  String id = _task1Id,
  String scopeId = _scopeId,
  String title = 'Test Task',
  String status = 'not_started',
  String priority = 'medium',
  DateTime? dueDate,
  int sortOrder = 0,
}) {
  final now = DateTime.now();
  return ProjectTask(
    id: id,
    companyId: _companyId,
    tradeScopeId: scopeId,
    title: title,
    status: status,
    sortOrder: sortOrder,
    priority: priority,
    dueDate: dueDate,
    photoRequired: false,
    materialsNeeded: '[]',
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

PunchListItem _makePunch({
  String id = _punch1Id,
  String description = 'Fix crooked outlet plate',
  String priority = 'high',
  String status = 'open',
}) {
  final now = DateTime.now();
  return PunchListItem(
    id: id,
    companyId: _companyId,
    projectId: _projectId,
    tradeScopeId: _scopeId,
    createdBy: _adminId,
    description: description,
    priority: priority,
    status: status,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Widget-tree builder — GoRouter so context.push resolves
// ---------------------------------------------------------------------------

Widget _buildApp({
  required AuthState auth,
  required List<Override> overrides,
  bool disableRetry = false,
}) {
  final router = GoRouter(
    initialLocation: '/scope',
    routes: [
      GoRoute(
        path: '/scope',
        builder: (context, state) => const TradeScopeDetailScreen(
          projectId: _projectId,
          scopeId: _scopeId,
        ),
      ),
      GoRoute(
        path: '/tasks/:taskId',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('TASK DETAIL ${state.pathParameters['taskId']}'),
          ),
        ),
      ),
      GoRoute(
        path: '/ai-interview/:scopeId',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('AI INTERVIEW ${state.pathParameters['scopeId']}'),
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    // Defeat Riverpod 3 auto-retry so error-state overrides settle.
    retry: disableRetry ? (_, __) => null : null,
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      ...overrides,
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Per-task attachment overrides so TaskThumbnailRow inside each TaskRow
/// resolves without reaching into getIt. No photos → empty thumbnail row.
List<Override> _noAttachments(List<String> taskIds) => [
      for (final id in taskIds)
        taskAttachmentsProvider(id).overrideWith(
          (ref) => Stream.value(<TaskAttachment>[]),
        ),
    ];

// ---------------------------------------------------------------------------
// Pump / teardown helpers
// ---------------------------------------------------------------------------

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmount and flush Drift's zero-duration close timer (MEMORY.md).
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Tall surface so cards + billing section lay out on-screen and stay
/// hit-testable.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Real Drift in-memory DB path — tasksProvider streams seeded rows into UI.
  // -------------------------------------------------------------------------

  group('Scope task list — real Drift DB (offline-first)', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.now();

      await db.into(db.companies).insert(CompaniesCompanion.insert(
            id: const Value(_companyId),
            name: 'Test Co',
            createdAt: now,
            updatedAt: now,
          ));
      await db.into(db.projects).insert(ProjectsCompanion.insert(
            id: const Value(_projectId),
            companyId: _companyId,
            name: 'Downtown Reno',
            status: const Value('active'),
            createdAt: now,
            updatedAt: now,
          ));
      await db.into(db.tradeScopes).insert(TradeScopesCompanion.insert(
            id: const Value(_scopeId),
            companyId: _companyId,
            projectId: _projectId,
            tradeName: 'Electrical',
            contractorId: const Value(_contractorId),
            createdAt: now,
            updatedAt: now,
          ));

      // Register DAOs in getIt exactly as service_locator does.
      getIt.registerSingleton<AppDatabase>(db);
      getIt.registerSingleton<TaskDao>(db.taskDao);
      getIt.registerSingleton<TradeScopeDao>(db.tradeScopeDao);
      getIt.registerSingleton<TaskAttachmentDao>(db.taskAttachmentDao);
      getIt.registerSingleton<PunchListItemDao>(db.punchListItemDao);
    });

    tearDown(() async {
      await getIt.reset();
      await db.close();
    });

    Future<void> seedTask({
      required String id,
      required String title,
      required String status,
      String priority = 'medium',
    }) async {
      final now = DateTime.now();
      await db.into(db.projectTasks).insert(ProjectTasksCompanion.insert(
            id: Value(id),
            companyId: _companyId,
            tradeScopeId: _scopeId,
            title: title,
            status: Value(status),
            priority: Value(priority),
            createdAt: now,
            updatedAt: now,
          ));
    }

    testWidgets('renders every task for the scope with title + status badge',
        (tester) async {
      _useTallSurface(tester);
      await seedTask(id: _task1Id, title: 'Rough-in wiring', status: 'in_progress');
      await seedTask(id: _task2Id, title: 'Install panel', status: 'not_started');
      await seedTask(id: _task3Id, title: 'Trim out', status: 'blocked');

      await tester.pumpWidget(
        _buildApp(auth: _contractorAuth(), overrides: const []),
      );
      await _pumpScreen(tester);

      // All three tasks render as read-only TaskRow cards.
      expect(find.byType(TaskRow), findsNWidgets(3));
      expect(find.text('Rough-in wiring'), findsOneWidget);
      expect(find.text('Install panel'), findsOneWidget);
      expect(find.text('Trim out'), findsOneWidget);

      // Status badge label mapping is exercised on real data.
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Not Started'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);

      // DB is the source of truth — 3 tasks persisted for this scope.
      final rows = await (db.select(db.projectTasks)
            ..where((t) => t.tradeScopeId.equals(_scopeId)))
          .get();
      expect(rows.length, 3);

      await _drainTimers(tester);
    });

    testWidgets('AppBar title resolves the scope name from the DB',
        (tester) async {
      _useTallSurface(tester);
      await seedTask(id: _task1Id, title: 'Rough-in wiring', status: 'in_progress');

      await tester.pumpWidget(
        _buildApp(auth: _contractorAuth(), overrides: const []),
      );
      await _pumpScreen(tester);

      // AppBar shows the trade name, not the "Trade Scope" placeholder.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Electrical'),
        ),
        findsOneWidget,
      );

      await _drainTimers(tester);
    });

    testWidgets('empty scope shows "No tasks yet" + Start AI Interview',
        (tester) async {
      _useTallSurface(tester);
      // No tasks and no punch items seeded.

      await tester.pumpWidget(
        _buildApp(auth: _contractorAuth(), overrides: const []),
      );
      await _pumpScreen(tester);

      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.text('Start AI Interview'), findsOneWidget);
      expect(find.byType(TaskRow), findsNothing);

      await _drainTimers(tester);
    });

    testWidgets('tapping a task row navigates to task detail', (tester) async {
      _useTallSurface(tester);
      await seedTask(id: _task1Id, title: 'Rough-in wiring', status: 'in_progress');

      await tester.pumpWidget(
        _buildApp(auth: _contractorAuth(), overrides: const []),
      );
      await _pumpScreen(tester);

      await tester.tap(find.text('Rough-in wiring'));
      await _pumpScreen(tester);

      // GoRouter resolved the task detail route with the tapped task id.
      expect(find.text('TASK DETAIL $_task1Id'), findsOneWidget);

      await _drainTimers(tester);
    });
  });

  // -------------------------------------------------------------------------
  // Provider-override path — targeted UI states (punch list, error, roles).
  // -------------------------------------------------------------------------

  group('Scope task list — punch list section', () {
    testWidgets('renders Punch List header + PunchListCard when items exist',
        (tester) async {
      _useTallSurface(tester);
      final tasks = [_makeTask(title: 'Rough-in wiring', status: 'in_progress')];
      final punch = [_makePunch()];

      await tester.pumpWidget(
        _buildApp(
          auth: _contractorAuth(),
          overrides: [
            tradeScopesProvider(_projectId)
                .overrideWith((ref) => Stream.value([_makeScope()])),
            tasksProvider(_scopeId).overrideWith((ref) => Stream.value(tasks)),
            punchItemsByScopeProvider(_scopeId)
                .overrideWith((ref) => Stream.value(punch)),
            ..._noAttachments([_task1Id]),
          ],
        ),
      );
      await _pumpScreen(tester);

      expect(find.text('Punch List'), findsOneWidget);
      expect(find.byType(PunchListCard), findsOneWidget);
      expect(find.text('Fix crooked outlet plate'), findsOneWidget);
      // The regular task still renders alongside the punch section.
      expect(find.text('Rough-in wiring'), findsOneWidget);

      await _drainTimers(tester);
    });

    testWidgets('no tasks but punch items present → NOT the empty state',
        (tester) async {
      _useTallSurface(tester);
      final punch = [_makePunch(description: 'Seal conduit penetration')];

      await tester.pumpWidget(
        _buildApp(
          auth: _contractorAuth(),
          overrides: [
            tradeScopesProvider(_projectId)
                .overrideWith((ref) => Stream.value([_makeScope()])),
            tasksProvider(_scopeId)
                .overrideWith((ref) => Stream.value(<ProjectTask>[])),
            punchItemsByScopeProvider(_scopeId)
                .overrideWith((ref) => Stream.value(punch)),
          ],
        ),
      );
      await _pumpScreen(tester);

      // Empty state must NOT show — punch items keep the list populated.
      expect(find.text('No tasks yet'), findsNothing);
      expect(find.byType(PunchListCard), findsOneWidget);
      expect(find.text('Seal conduit penetration'), findsOneWidget);

      await _drainTimers(tester);
    });
  });

  group('Scope task list — error state', () {
    testWidgets('shows "Error loading tasks" when the stream errors',
        (tester) async {
      _useTallSurface(tester);

      await tester.pumpWidget(
        _buildApp(
          auth: _contractorAuth(),
          disableRetry: true,
          overrides: [
            tradeScopesProvider(_projectId)
                .overrideWith((ref) => Stream.value([_makeScope()])),
            tasksProvider(_scopeId).overrideWith(
              (ref) => Stream<List<ProjectTask>>.error(
                Exception('db unavailable'),
              ),
            ),
            punchItemsByScopeProvider(_scopeId)
                .overrideWith((ref) => Stream.value(<PunchListItem>[])),
          ],
        ),
      );
      await _pumpScreen(tester);

      expect(find.textContaining('Error loading tasks'), findsOneWidget);
      expect(find.byType(TaskRow), findsNothing);

      await _drainTimers(tester);
    });
  });

  group('Scope task list — role gating of the Billing section', () {
    // Overrides that keep the billing sub-widgets from reaching into getIt.
    List<Override> billingStubs() => [
          billingMilestonesByScope(_scopeId)
              .overrideWith((ref) => Stream.value([])),
          scopeQuotesProvider(_scopeId)
              .overrideWith((ref) => Stream.value([])),
          scopeInvoicesProvider(_scopeId)
              .overrideWith((ref) => Stream.value([])),
        ];

    testWidgets('GC/admin sees the Billing section', (tester) async {
      _useTallSurface(tester);
      final tasks = [_makeTask(title: 'Rough-in wiring', status: 'in_progress')];

      await tester.pumpWidget(
        _buildApp(
          auth: _adminAuth(),
          overrides: [
            tradeScopesProvider(_projectId)
                .overrideWith((ref) => Stream.value([_makeScope()])),
            tasksProvider(_scopeId).overrideWith((ref) => Stream.value(tasks)),
            punchItemsByScopeProvider(_scopeId)
                .overrideWith((ref) => Stream.value(<PunchListItem>[])),
            ..._noAttachments([_task1Id]),
            ...billingStubs(),
          ],
        ),
      );
      await _pumpScreen(tester);

      expect(find.text('Billing'), findsOneWidget);
      expect(find.text('Create Quote'), findsOneWidget);
      expect(find.text('Billing Milestones'), findsOneWidget);

      await _drainTimers(tester);
    });

    testWidgets('contractor does NOT see the Billing section', (tester) async {
      _useTallSurface(tester);
      final tasks = [_makeTask(title: 'Rough-in wiring', status: 'in_progress')];

      await tester.pumpWidget(
        _buildApp(
          auth: _contractorAuth(),
          overrides: [
            tradeScopesProvider(_projectId)
                .overrideWith((ref) => Stream.value([_makeScope()])),
            tasksProvider(_scopeId).overrideWith((ref) => Stream.value(tasks)),
            punchItemsByScopeProvider(_scopeId)
                .overrideWith((ref) => Stream.value(<PunchListItem>[])),
            ..._noAttachments([_task1Id]),
          ],
        ),
      );
      await _pumpScreen(tester);

      // The task still renders, but no billing affordances for a contractor.
      expect(find.text('Rough-in wiring'), findsOneWidget);
      expect(find.text('Billing'), findsNothing);
      expect(find.text('Create Quote'), findsNothing);
      expect(find.text('Billing Milestones'), findsNothing);

      await _drainTimers(tester);
    });
  });

  group('Scope task list — due date + priority rendering', () {
    testWidgets('task with due date shows a "Due ..." line', (tester) async {
      _useTallSurface(tester);
      final tasks = [
        _makeTask(
          title: 'Schedule inspection',
          priority: 'urgent',
          dueDate: DateTime(2026, 8, 15),
        ),
      ];

      await tester.pumpWidget(
        _buildApp(
          auth: _contractorAuth(),
          overrides: [
            tradeScopesProvider(_projectId)
                .overrideWith((ref) => Stream.value([_makeScope()])),
            tasksProvider(_scopeId).overrideWith((ref) => Stream.value(tasks)),
            punchItemsByScopeProvider(_scopeId)
                .overrideWith((ref) => Stream.value(<PunchListItem>[])),
            ..._noAttachments([_task1Id]),
          ],
        ),
      );
      await _pumpScreen(tester);

      expect(find.text('Schedule inspection'), findsOneWidget);
      expect(find.textContaining('Due'), findsOneWidget);

      await _drainTimers(tester);
    });
  });
}
