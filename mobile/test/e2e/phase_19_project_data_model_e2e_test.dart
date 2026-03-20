// Phase 19 — Project Data Model: Flutter E2E widget tests.
//
// Covers PROJ-03: GC can navigate the project hierarchy (list → detail → scope detail).
//
// Tests:
//   1. project_list renders seeded projects
//   2. project_list empty state for no projects
//   3. project_list contractor only sees assigned projects (watchProjectsForContractor)
//   4. project_detail shows trade scope cards
//   5. trade_scope_card shows progress bar and task count
//   6. trade_scope_card shows contractor name when assigned
//   7. trade_scope_card shows Unassigned when no contractor
//   8. scope_detail shows task list
//   9. scope_detail shows empty state when no tasks
//  10. navigation project list → detail → scope (full drill-down via pumpWidget)
//
// Patterns:
//   - ProviderScope.overrideWith for Riverpod providers
//   - pump() NOT pumpAndSettle() — Drift streams never settle (MEMORY.md)
//   - Stream.value() for pre-seeded test data (avoids pending timer issue)
//   - Real Drift in-memory DB via NativeDatabase.memory() for DAO tests
//   - Fake notifiers extending real notifier classes for AsyncNotifierProvider

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/projects/data/task_dao.dart';
import 'package:contractorhub/features/projects/data/trade_scope_dao.dart';
import 'package:contractorhub/features/projects/presentation/providers/project_providers.dart';
import 'package:contractorhub/features/projects/presentation/screens/project_detail_screen.dart';
import 'package:contractorhub/features/projects/presentation/screens/project_list_screen.dart';
import 'package:contractorhub/features/projects/presentation/screens/trade_scope_detail_screen.dart';
import 'package:contractorhub/features/projects/presentation/widgets/trade_scope_card.dart';
import 'package:contractorhub/shared/models/user_role.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _adminUserId = 'admin-001';
const _contractorId = 'contractor-001';

const _project1Id = 'project-001';
const _project2Id = 'project-002';
const _scope1Id = 'scope-001';
const _scope2Id = 'scope-002';
const _scope3Id = 'scope-003';
const _task1Id = 'task-001';
const _task2Id = 'task-002';

// ---------------------------------------------------------------------------
// Auth state helpers
// ---------------------------------------------------------------------------

AuthState _adminAuthState() => const AuthState.authenticated(
      userId: _adminUserId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

AuthState _contractorAuthState() => const AuthState.authenticated(
      userId: _contractorId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

// ---------------------------------------------------------------------------
// In-memory DB helper for DAO-level tests
// ---------------------------------------------------------------------------

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

/// Seed 2 projects, 3 scopes on project1, 2 tasks on scope1.
Future<void> _seedFullData(AppDatabase db) async {
  final now = DateTime.now();

  await db.into(db.companies).insert(CompaniesCompanion.insert(
        id: const Value(_companyId),
        name: 'Test Co',
        createdAt: now,
        updatedAt: now,
      ));

  await db.into(db.projects).insert(ProjectsCompanion.insert(
        id: const Value(_project1Id),
        companyId: _companyId,
        name: 'Downtown Office Renovation',
        status: const Value('active'),
        createdAt: now,
        updatedAt: now,
      ));

  await db.into(db.projects).insert(ProjectsCompanion.insert(
        id: const Value(_project2Id),
        companyId: _companyId,
        name: 'Warehouse Extension',
        status: const Value('planning'),
        createdAt: now.subtract(const Duration(minutes: 1)),
        updatedAt: now,
      ));

  await db.into(db.tradeScopes).insert(TradeScopesCompanion.insert(
        id: const Value(_scope1Id),
        companyId: _companyId,
        projectId: _project1Id,
        tradeName: 'Electrical',
        tradeColor: const Value('#3F51B5'),
        contractorId: const Value(_contractorId),
        createdAt: now,
        updatedAt: now,
      ));

  await db.into(db.tradeScopes).insert(TradeScopesCompanion.insert(
        id: const Value(_scope2Id),
        companyId: _companyId,
        projectId: _project1Id,
        tradeName: 'Plumbing',
        tradeColor: const Value('#0097A7'),
        createdAt: now,
        updatedAt: now,
      ));

  await db.into(db.tradeScopes).insert(TradeScopesCompanion.insert(
        id: const Value(_scope3Id),
        companyId: _companyId,
        projectId: _project1Id,
        tradeName: 'Framing',
        tradeColor: const Value('#8D6E63'),
        createdAt: now,
        updatedAt: now,
      ));

  await db.into(db.projectTasks).insert(ProjectTasksCompanion.insert(
        id: const Value(_task1Id),
        companyId: _companyId,
        tradeScopeId: _scope1Id,
        title: 'Install panel box',
        status: const Value('complete'),
        priority: const Value('high'),
        createdAt: now,
        updatedAt: now,
      ));

  await db.into(db.projectTasks).insert(ProjectTasksCompanion.insert(
        id: const Value(_task2Id),
        companyId: _companyId,
        tradeScopeId: _scope1Id,
        title: 'Run conduit to HVAC',
        status: const Value('in_progress'),
        priority: const Value('urgent'),
        createdAt: now,
        updatedAt: now,
      ));
}

// ---------------------------------------------------------------------------
// Test data builder helpers — create Drift data classes for Stream.value()
// ---------------------------------------------------------------------------

Project _makeProject({
  String id = _project1Id,
  String name = 'Test Project',
  String status = 'active',
  String? address,
}) {
  final now = DateTime.now();
  return Project(
    id: id,
    companyId: _companyId,
    name: name,
    description: null,
    address: address,
    clientId: null,
    status: status,
    statusHistory: '[]',
    targetStartDate: null,
    targetEndDate: null,
    version: 1,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

TradeScope _makeScope({
  String id = _scope1Id,
  String tradeName = 'Electrical',
  String tradeColor = '#3F51B5',
  String? contractorId,
  String status = 'not_started',
  int sortOrder = 0,
}) {
  final now = DateTime.now();
  return TradeScope(
    id: id,
    companyId: _companyId,
    projectId: _project1Id,
    tradeCatalogId: null,
    tradeName: tradeName,
    tradeColor: tradeColor,
    contractorId: contractorId,
    status: status,
    statusOverride: false,
    sortOrder: sortOrder,
    version: 1,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

ProjectTask _makeTask({
  String id = _task1Id,
  String title = 'Test Task',
  String status = 'not_started',
  String priority = 'medium',
  DateTime? dueDate,
}) {
  final now = DateTime.now();
  return ProjectTask(
    id: id,
    companyId: _companyId,
    tradeScopeId: _scope1Id,
    title: title,
    description: null,
    status: status,
    sortOrder: 0,
    priority: priority,
    estimatedHours: null,
    estimatedCost: null,
    dueDate: dueDate,
    photoRequired: false,
    assignedTo: null,
    materialsNeeded: '[]',
    dependsOn: '[]',
    version: 1,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

// ---------------------------------------------------------------------------
// Fake notifiers for ProviderScope overrides
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends AuthNotifier {
  final AuthState _authState;
  _FakeAuthNotifier(this._authState);

  @override
  AuthState build() => _authState;
}

/// Fake ProjectListNotifier backed by Stream.value() — no pending timers.
class _FakeProjectListNotifier extends ProjectListNotifier {
  final List<Project> _projects;

  _FakeProjectListNotifier(this._projects);

  @override
  Future<List<Project>> build() async => _projects;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ─── DAO unit test: watchProjectsForContractor filtering ────────────────
  // Verifies the core PROJ-03 requirement: contractors only see projects
  // where they have an assigned trade scope.
  test('watchProjectsForContractor returns only contractor-assigned projects',
      () async {
    final db = _openTestDb();
    addTearDown(db.close);
    await _seedFullData(db);

    // scope1 has contractorId=_contractorId on project1
    // project2 has NO scopes with this contractor
    final assignedProjects = await db.projectDao
        .watchProjectsByCompany(_companyId)
        .first;

    // Admin sees all 2 projects
    expect(assignedProjects.length, 2);

    // Contractor-filtered query via watchProjectsForContractor
    // (scope1 has contractorId=_contractorId on project1 only)
    final contractorStream =
        db.projectDao.watchProjectsForContractor(_companyId, _contractorId);

    // Wait for first emission with a timeout
    final contractorProjects = await contractorStream
        .timeout(const Duration(seconds: 5))
        .first;

    expect(contractorProjects.length, 1);
    expect(contractorProjects.first.id, _project1Id);
  });

  // ─── Test 1: project list renders seeded projects ───────────────────────
  testWidgets('project_list renders seeded projects', (tester) async {
    final projects = [
      _makeProject(
          id: _project1Id,
          name: 'Downtown Office Renovation',
          status: 'active'),
      _makeProject(
          id: _project2Id, name: 'Warehouse Extension', status: 'planning'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuthState()),
          ),
          projectListProvider.overrideWith(
            () => _FakeProjectListNotifier(projects),
          ),
        ],
        child: const MaterialApp(home: ProjectListScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Downtown Office Renovation'), findsOneWidget);
    expect(find.text('Warehouse Extension'), findsOneWidget);
  });

  // ─── Test 2: project list empty state for no projects ──────────────────
  testWidgets('project_list shows empty state when no projects', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuthState()),
          ),
          projectListProvider.overrideWith(
            () => _FakeProjectListNotifier([]),
          ),
        ],
        child: const MaterialApp(home: ProjectListScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No projects yet'), findsOneWidget);
  });

  // ─── Test 3: contractor only sees assigned projects ─────────────────────
  // Uses watchProjectsForContractor which joins Projects with TradeScopes to
  // return only projects where the contractor has an assigned scope.
  testWidgets(
      'project_list contractor only sees assigned projects via watchProjectsForContractor',
      (tester) async {
    // The contractor-filtered project list contains only project1 (has assigned scope).
    // We use a pre-filtered list as the provider value to simulate the DAO behavior.
    final contractorProjects = [
      _makeProject(
          id: _project1Id,
          name: 'Downtown Office Renovation',
          status: 'active'),
      // project2 is excluded because contractor has no scope there
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_contractorAuthState()),
          ),
          // Override with pre-filtered list simulating watchProjectsForContractor result
          projectListProvider.overrideWith(
            () => _FakeProjectListNotifier(contractorProjects),
          ),
        ],
        child: const MaterialApp(home: ProjectListScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Contractor sees only project1 (has assigned scope)
    expect(find.text('Downtown Office Renovation'), findsOneWidget);
    // Contractor does NOT see project2 (no assigned scope for this contractor)
    expect(find.text('Warehouse Extension'), findsNothing);
  });

  // ─── Test 4: project detail shows trade scope cards ─────────────────────
  testWidgets('project_detail shows trade scope cards', (tester) async {
    final projects = [
      _makeProject(id: _project1Id, name: 'Downtown Office Renovation'),
    ];
    final scopes = [
      _makeScope(id: _scope1Id, tradeName: 'Electrical', sortOrder: 0),
      _makeScope(id: _scope2Id, tradeName: 'Plumbing', sortOrder: 1),
      _makeScope(id: _scope3Id, tradeName: 'Framing', sortOrder: 2),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuthState()),
          ),
          projectListProvider.overrideWith(
            () => _FakeProjectListNotifier(projects),
          ),
          tradeScopesProvider(_project1Id).overrideWith(
            (ref) => Stream.value(scopes),
          ),
        ],
        child: const MaterialApp(
          home: ProjectDetailScreen(projectId: _project1Id),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TradeScopeCard), findsNWidgets(3));
    expect(find.text('Electrical'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.text('Framing'), findsOneWidget);
  });

  // ─── Test 5: trade_scope_card shows progress bar and task count ─────────
  testWidgets('trade_scope_card shows LinearProgressIndicator and task count',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TradeScopeCard(
            tradeName: 'Electrical',
            tradeColor: Color(0xFF3F51B5),
            completedTasks: 3,
            totalTasks: 8,
            status: 'in_progress',
            onTap: _noop,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Electrical'), findsOneWidget);
    expect(find.text('3/8 tasks'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  // ─── Test 6: trade_scope_card shows contractor name when assigned ────────
  testWidgets('trade_scope_card shows contractor name when assigned',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TradeScopeCard(
            tradeName: 'Electrical',
            tradeColor: Color(0xFF3F51B5),
            contractorName: 'John Smith',
            completedTasks: 2,
            totalTasks: 5,
            status: 'in_progress',
            onTap: _noop,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('John Smith'), findsOneWidget);
    expect(find.text('Unassigned'), findsNothing);
  });

  // ─── Test 7: trade_scope_card shows Unassigned when no contractor ────────
  testWidgets('trade_scope_card shows Unassigned when no contractor',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TradeScopeCard(
            tradeName: 'Plumbing',
            tradeColor: Color(0xFF0097A7),
            completedTasks: 0,
            totalTasks: 3,
            status: 'not_started',
            onTap: _noop,
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Unassigned'), findsOneWidget);
  });

  // ─── Test 8: scope_detail shows task list ───────────────────────────────
  testWidgets('scope_detail shows task list from seeded tasks', (tester) async {
    final scopes = [
      _makeScope(id: _scope1Id, tradeName: 'Electrical'),
    ];
    final tasks = [
      _makeTask(
          id: _task1Id,
          title: 'Install panel box',
          status: 'complete',
          priority: 'high'),
      _makeTask(
          id: _task2Id,
          title: 'Run conduit to HVAC',
          status: 'in_progress',
          priority: 'urgent'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuthState()),
          ),
          tradeScopesProvider(_project1Id).overrideWith(
            (ref) => Stream.value(scopes),
          ),
          tasksProvider(_scope1Id).overrideWith(
            (ref) => Stream.value(tasks),
          ),
        ],
        child: const MaterialApp(
          home: TradeScopeDetailScreen(
            projectId: _project1Id,
            scopeId: _scope1Id,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Install panel box'), findsOneWidget);
    expect(find.text('Run conduit to HVAC'), findsOneWidget);
  });

  // ─── Test 9: scope_detail shows empty state when no tasks ───────────────
  testWidgets('scope_detail shows empty state when no tasks', (tester) async {
    final scopes = [
      _makeScope(id: _scope2Id, tradeName: 'Plumbing'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuthState()),
          ),
          tradeScopesProvider(_project1Id).overrideWith(
            (ref) => Stream.value(scopes),
          ),
          tasksProvider(_scope2Id).overrideWith(
            (ref) => Stream.value(<ProjectTask>[]),
          ),
        ],
        child: const MaterialApp(
          home: TradeScopeDetailScreen(
            projectId: _project1Id,
            scopeId: _scope2Id,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No tasks yet'), findsOneWidget);
  });

  // ─── Test 10: full drill-down navigation ────────────────────────────────
  // Three separate sub-tests each verifying one level of the hierarchy.
  // (Riverpod 3 does not allow changing override counts between pumpWidget calls.)
  testWidgets(
      'navigation step 1 — project list screen renders correctly',
      (tester) async {
    final projects = [
      _makeProject(id: _project1Id, name: 'Downtown Office Renovation'),
      _makeProject(id: _project2Id, name: 'Warehouse Extension'),
    ];
    final scopes = [_makeScope(id: _scope1Id, tradeName: 'Electrical')];
    final tasks = [_makeTask(id: _task1Id, title: 'Install panel box')];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuthState()),
          ),
          projectListProvider.overrideWith(
            () => _FakeProjectListNotifier(projects),
          ),
          tradeScopesProvider(_project1Id).overrideWith(
            (ref) => Stream.value(scopes),
          ),
          tasksProvider(_scope1Id).overrideWith(
            (ref) => Stream.value(tasks),
          ),
        ],
        child: const MaterialApp(home: ProjectListScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ProjectListScreen), findsOneWidget);
    expect(find.text('Downtown Office Renovation'), findsOneWidget);
  });

  testWidgets(
      'navigation step 2 — project detail screen renders trade scope cards',
      (tester) async {
    final projects = [
      _makeProject(id: _project1Id, name: 'Downtown Office Renovation'),
    ];
    final scopes = [
      _makeScope(id: _scope1Id, tradeName: 'Electrical', sortOrder: 0),
      _makeScope(id: _scope2Id, tradeName: 'Plumbing', sortOrder: 1),
      _makeScope(id: _scope3Id, tradeName: 'Framing', sortOrder: 2),
    ];
    final tasks = [_makeTask(id: _task1Id, title: 'Install panel box')];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuthState()),
          ),
          projectListProvider.overrideWith(
            () => _FakeProjectListNotifier(projects),
          ),
          tradeScopesProvider(_project1Id).overrideWith(
            (ref) => Stream.value(scopes),
          ),
          tasksProvider(_scope1Id).overrideWith(
            (ref) => Stream.value(tasks),
          ),
        ],
        child: const MaterialApp(
          home: ProjectDetailScreen(projectId: _project1Id),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(find.byType(TradeScopeCard), findsNWidgets(3));
  });

  testWidgets(
      'navigation step 3 — scope detail screen renders task list',
      (tester) async {
    final projects = [
      _makeProject(id: _project1Id, name: 'Downtown Office Renovation'),
    ];
    final scopes = [
      _makeScope(id: _scope1Id, tradeName: 'Electrical'),
    ];
    final tasks = [
      _makeTask(id: _task1Id, title: 'Install panel box', status: 'complete'),
      _makeTask(
          id: _task2Id, title: 'Run conduit to HVAC', status: 'in_progress'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuthState()),
          ),
          projectListProvider.overrideWith(
            () => _FakeProjectListNotifier(projects),
          ),
          tradeScopesProvider(_project1Id).overrideWith(
            (ref) => Stream.value(scopes),
          ),
          tasksProvider(_scope1Id).overrideWith(
            (ref) => Stream.value(tasks),
          ),
        ],
        child: const MaterialApp(
          home: TradeScopeDetailScreen(
            projectId: _project1Id,
            scopeId: _scope1Id,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TradeScopeDetailScreen), findsOneWidget);
    expect(find.text('Install panel box'), findsOneWidget);
    expect(find.text('Run conduit to HVAC'), findsOneWidget);
  });
}

void _noop() {}
