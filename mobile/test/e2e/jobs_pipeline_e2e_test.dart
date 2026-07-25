// Jobs Pipeline — Flutter E2E widget tests.
//
// Exercises the admin job-pipeline dashboard end-to-end:
//   Drift (in-memory) seeded jobs → jobDaoProvider → JobListNotifier
//   (reactive AsyncNotifier stream) → JobsPipelineScreen → kanban / list UI,
//   status filtering, batch-select, and job-detail navigation.
//
// What the SOURCE actually does (verified — differs from a naive spec):
//   * Default view is the KANBAN board (isKanbanViewProvider defaults to true).
//     KanbanBoard renders one column per pipeline stage in lifecycle order —
//     Quote, Scheduled, In Progress, Complete, Invoiced — and DELIBERATELY
//     EXCLUDES the Cancelled stage (cancelled jobs are list-view only). Each
//     column header shows the status label + a count badge.
//   * The only user-facing FILTER is the status FilterChip row, and it is shown
//     ONLY in list view (`if (!isKanban) _FilterChipsRow()`). The screen also
//     wires trade/priority/contractor/client filter providers, but NONE of them
//     have UI controls — only status is reachable, so only status is exercised.
//   * The screen is fully OFFLINE-FIRST and READ-ONLY here: it streams jobs
//     straight from Drift via `dao.watchJobsByCompany`. There is no Dio/HTTP in
//     this screen, so there is nothing to stub with MockDioClient — we seed real
//     Drift rows and assert on the rendered UI.
//   * The screen does NOT role-gate anything at the widget level. JobListNotifier
//     scopes jobs by companyId (not by role), and the "New Job" action is shown
//     to every authenticated role. We assert that (documenting the no-gate
//     reality) rather than a non-existent gate — same finding as team_management.
//   * Batch "Transition Status" is a STUB in the source: it only shows a
//     SnackBar ("Bulk transition for N jobs — pick status"); it does not yet
//     mutate the DB. We assert the SnackBar, not a status write.
//   * Pull-to-refresh calls `getIt<SyncEngine>().syncNow()`. We never trigger it
//     (that would require registering a SyncEngine); it is out of scope.
//
// Coverage:
//   1. Kanban (default) renders each seeded job under the correct pipeline
//      column, with correct per-column count badges; Cancelled is excluded.
//   2. Empty state ("No jobs yet") when the company has no jobs.
//   3. List view shows ALL jobs including Cancelled + the status filter chips.
//   4. Status filter chip narrows the list to the matching status only.
//   5. A status filter that matches nothing shows the "no jobs match" message.
//   6. Tapping a job card navigates to its detail route (/jobs/:id).
//   7. Long-press activates batch mode → action bar → "Transition Status"
//      SnackBar → Cancel clears the selection.
//   8. No role gating: a contractor sees the pipeline and the New Job action.
//
// Harness rules (CLAUDE.md + MEMORY.md):
//   * Real Drift AppDatabase(NativeDatabase.memory()); jobDaoProvider overridden
//     with db.jobDao. No getIt needed (reads flow through the overridden DAO).
//   * ProviderScope overrides authNotifierProvider with a fake AuthNotifier.
//   * pump() / pump(Duration(...)) only — never pumpAndSettle (Drift streams
//     never settle). Each test ends by unmounting to a SizedBox to drain the
//     zero-duration close timer Drift schedules on stream cancellation.

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart';
import 'package:contractorhub/features/jobs/presentation/screens/jobs_pipeline_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _adminUserId = 'admin-001';
const _contractorUserId = 'contractor-001';

// Job ids / descriptions — one job per lifecycle stage (unique descriptions).
const _quoteId = 'job-quote';
const _scheduledId = 'job-scheduled';
const _inProgressId = 'job-inprogress';
const _completeId = 'job-complete';
const _invoicedId = 'job-invoiced';
const _cancelledId = 'job-cancelled';

const _quoteDesc = 'Fix the leaking kitchen faucet';
const _scheduledDesc = 'Install a new gas water heater';
const _inProgressDesc = 'Rewire the detached garage';
const _completeDesc = 'Paint the backyard fence';
const _invoicedDesc = 'Replace the roof shingles';
const _cancelledDesc = 'Demolish the old shed (cancelled)';

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

AuthState _adminAuth() => const AuthState.authenticated(
      userId: _adminUserId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _contractorUserId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

/// Fake AuthNotifier — supplies a fixed AuthState without hitting getIt.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

// ---------------------------------------------------------------------------
// Seed helpers
// ---------------------------------------------------------------------------

Future<void> _seedCompany(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: const Value(_companyId),
          name: 'Test Co',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

/// Insert a job row directly. [minutesAgo] controls newest-first ordering while
/// keeping every job within "Today" so no stray day-count digits are rendered.
Future<void> _seedJob(
  AppDatabase db, {
  required String id,
  required String status,
  required String description,
  int minutesAgo = 0,
  String tradeType = 'Plumbing',
  String priority = 'medium',
}) async {
  final createdAt = DateTime.now().subtract(Duration(minutes: minutesAgo));
  await db.into(db.jobs).insert(
        JobsCompanion.insert(
          id: Value(id),
          companyId: _companyId,
          description: description,
          tradeType: tradeType,
          status: Value(status),
          priority: Value(priority),
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
}

/// Seed exactly one job per lifecycle stage (incl. Cancelled).
/// Quote is newest so it sits at the top of the list view.
Future<void> _seedOnePerStage(AppDatabase db) async {
  await _seedJob(db,
      id: _quoteId, status: 'quote', description: _quoteDesc, minutesAgo: 1);
  await _seedJob(db,
      id: _scheduledId,
      status: 'scheduled',
      description: _scheduledDesc,
      minutesAgo: 2);
  await _seedJob(db,
      id: _inProgressId,
      status: 'in_progress',
      description: _inProgressDesc,
      minutesAgo: 3);
  await _seedJob(db,
      id: _completeId,
      status: 'complete',
      description: _completeDesc,
      minutesAgo: 4);
  await _seedJob(db,
      id: _invoicedId,
      status: 'invoiced',
      description: _invoicedDesc,
      minutesAgo: 5);
  await _seedJob(db,
      id: _cancelledId,
      status: 'cancelled',
      description: _cancelledDesc,
      minutesAgo: 6);
}

// ---------------------------------------------------------------------------
// Widget-tree builder
// ---------------------------------------------------------------------------

/// Mount the pipeline inside a GoRouter so `context.push` (job detail / new job)
/// resolves, and inside a Scaffold so the batch-action SnackBar has a host.
Widget _buildApp(AppDatabase db, {required AuthState auth}) {
  final router = GoRouter(
    initialLocation: '/jobs',
    routes: [
      GoRoute(
        path: '/jobs',
        builder: (context, state) =>
            const Scaffold(body: JobsPipelineScreen()),
      ),
      GoRoute(
        path: '/jobs/new',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('New Job Screen'))),
      ),
      GoRoute(
        path: '/jobs/:id',
        builder: (context, state) => Scaffold(
          body: Center(child: Text('DETAIL ${state.pathParameters['id']}')),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      jobDaoProvider.overrideWithValue(db.jobDao),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pump the screen and let the JobListNotifier's Drift stream emit its first
/// snapshot (loading → data). NO pumpAndSettle — Drift never settles.
Future<void> _pumpPipeline(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Switch the toolbar's SegmentedButton from Kanban to List view.
Future<void> _switchToListView(WidgetTester tester) async {
  await tester.tap(find.text('List'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmount and flush Drift's zero-duration close timer (MEMORY.md). Call at the
/// END of every test that mounts the real screen.
Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Give tests that render the full list / batch bar a tall surface so cards and
/// the bottom action bar are laid out on-screen and hit-testable.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _seedCompany(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('JobsPipelineScreen E2E', () {
    // ─── 1: kanban groups jobs into the correct pipeline columns ───────────
    testWidgets(
        'kanban renders each job under its pipeline column and excludes Cancelled',
        (tester) async {
      _useTallSurface(tester);
      await _seedOnePerStage(db);

      await tester.pumpWidget(_buildApp(db, auth: _adminAuth()));
      await _pumpPipeline(tester);

      // All five pipeline-stage column headers render (label appears at least
      // once — it also appears as the matching job's status chip).
      for (final label in const [
        'Quote',
        'Scheduled',
        'In Progress',
        'Complete',
        'Invoiced',
      ]) {
        expect(find.text(label), findsAtLeastNWidgets(1),
            reason: 'missing kanban column header: $label');
      }

      // Each non-cancelled job renders in the board.
      expect(find.text(_quoteDesc), findsOneWidget);
      expect(find.text(_scheduledDesc), findsOneWidget);
      expect(find.text(_inProgressDesc), findsOneWidget);
      expect(find.text(_completeDesc), findsOneWidget);
      expect(find.text(_invoicedDesc), findsOneWidget);

      // Cancelled is deliberately excluded from the kanban board.
      expect(find.text(_cancelledDesc), findsNothing);

      // Grouping proof: each of the five columns holds exactly one job, so the
      // count badge '1' renders exactly five times (dates all read "Today", so
      // no other digits leak into the tree).
      expect(find.text('1'), findsNWidgets(5));

      await _drainDriftTimers(tester);
    });

    // ─── 2: empty state ────────────────────────────────────────────────────
    testWidgets('shows the empty state when the company has no jobs',
        (tester) async {
      await tester.pumpWidget(_buildApp(db, auth: _adminAuth()));
      await _pumpPipeline(tester);

      expect(find.text('No jobs yet'), findsOneWidget);
      expect(find.text('Create your first job to get started.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create your first job'),
          findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 3: list view shows everything including Cancelled + filter chips ───
    testWidgets('list view renders all jobs (incl. Cancelled) with filter chips',
        (tester) async {
      _useTallSurface(tester);
      await _seedOnePerStage(db);

      await tester.pumpWidget(_buildApp(db, auth: _adminAuth()));
      await _pumpPipeline(tester);
      await _switchToListView(tester);

      // Status filter chip row is only shown in list view.
      expect(find.widgetWithText(FilterChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Cancelled'), findsOneWidget);

      // The Cancelled job — hidden in kanban — now appears in the list.
      expect(find.text(_cancelledDesc), findsOneWidget);
      expect(find.text(_quoteDesc), findsOneWidget);
      expect(find.text(_invoicedDesc), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 4: status filter narrows the list ─────────────────────────────────
    testWidgets('status filter chip narrows the list to the matching status',
        (tester) async {
      _useTallSurface(tester);
      await _seedOnePerStage(db);

      await tester.pumpWidget(_buildApp(db, auth: _adminAuth()));
      await _pumpPipeline(tester);
      await _switchToListView(tester);

      // Before filtering: both jobs visible.
      expect(find.text(_inProgressDesc), findsOneWidget);
      expect(find.text(_quoteDesc), findsOneWidget);

      // Tap the "In Progress" FilterChip (targets the chip, not a card's chip).
      await tester.tap(find.widgetWithText(FilterChip, 'In Progress'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Only the in_progress job survives the filter.
      expect(find.text(_inProgressDesc), findsOneWidget);
      expect(find.text(_quoteDesc), findsNothing);
      expect(find.text(_completeDesc), findsNothing);
      expect(find.text(_cancelledDesc), findsNothing);

      await _drainDriftTimers(tester);
    });

    // ─── 5: filter that matches nothing → "no jobs match" message ──────────
    testWidgets('status filter with no matches shows the no-match message',
        (tester) async {
      _useTallSurface(tester);
      // Only a single quote job — nothing in the Complete stage.
      await _seedJob(db,
          id: _quoteId, status: 'quote', description: _quoteDesc);

      await tester.pumpWidget(_buildApp(db, auth: _adminAuth()));
      await _pumpPipeline(tester);
      await _switchToListView(tester);

      expect(find.text(_quoteDesc), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Complete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No jobs match the current filters.'), findsOneWidget);
      expect(find.text(_quoteDesc), findsNothing);

      await _drainDriftTimers(tester);
    });

    // ─── 6: tapping a job navigates to its detail route ────────────────────
    testWidgets('tapping a job card navigates to the job detail route',
        (tester) async {
      _useTallSurface(tester);
      await _seedOnePerStage(db);

      await tester.pumpWidget(_buildApp(db, auth: _adminAuth()));
      await _pumpPipeline(tester);
      await _switchToListView(tester);

      // Tap the (top, newest) quote card.
      await tester.tap(find.text(_quoteDesc));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The /jobs/:id detail route received the tapped job's id.
      expect(find.text('DETAIL $_quoteId'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 7: batch mode via long-press → transition SnackBar → cancel ───────
    testWidgets(
        'long-press activates batch mode; Transition Status shows a SnackBar '
        'and Cancel clears the selection', (tester) async {
      _useTallSurface(tester);
      await _seedOnePerStage(db);

      await tester.pumpWidget(_buildApp(db, auth: _adminAuth()));
      await _pumpPipeline(tester);
      await _switchToListView(tester);

      // Long-press the quote card to enter batch mode with it selected.
      await tester.longPress(find.text(_quoteDesc));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Batch action bar appears with the selection count.
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Transition Status'),
          findsOneWidget);

      // Trigger the (stubbed) bulk transition — asserts the SnackBar only.
      await tester.tap(find.widgetWithText(FilledButton, 'Transition Status'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Bulk transition for 1 jobs — pick status'),
          findsOneWidget);

      // Cancel clears the selection and dismisses the action bar.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1 selected'), findsNothing);

      await _drainDriftTimers(tester);
    });

    // ─── 8: no role gating (documents actual behaviour) ────────────────────
    testWidgets('pipeline and New Job action are visible for a contractor role',
        (tester) async {
      _useTallSurface(tester);
      await _seedOnePerStage(db);

      // JobListNotifier scopes by companyId, not by role, so a contractor sees
      // the same company-wide board. The screen gates no action by role.
      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpPipeline(tester);

      expect(find.widgetWithText(FilledButton, 'New Job'), findsOneWidget);
      expect(find.text(_quoteDesc), findsOneWidget);

      await _drainDriftTimers(tester);
    });
  });
}
