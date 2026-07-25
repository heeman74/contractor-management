// Contractor Jobs — Flutter E2E widget tests.
//
// Exercises the contractor's OWN job list (the field dashboard) end-to-end:
//   Drift (in-memory) seeded jobs → jobDaoProvider → ContractorJobsNotifier
//   (reactive AsyncNotifier stream, scoped by contractorId) →
//   ContractorJobsScreen → grouped section UI (Active / Today / Upcoming /
//   Completed), ContractorJobCard rendering, in-card status transitions, and
//   job-detail navigation.
//
// What the SOURCE actually does (verified by reading the screen + providers +
// DAO + card widget — differs from a naive spec):
//   * SCOPING is by contractor, not company. ContractorJobsNotifier streams
//     `dao.watchJobsByContractor(authState.userId)`, whose SQL is
//     `contractorId == <me> AND deletedAt IS NULL`. Jobs assigned to other
//     contractors, and unassigned jobs (contractorId == null), are NEVER shown.
//     This is THE key behaviour under test.
//   * There is NO status filter / tab UI on this screen (unlike the admin
//     JobsPipelineScreen). Instead the list is GROUPED into ordered sections:
//     the clocked-in "Active" job pinned first, then "Today", "Upcoming",
//     "Completed". A section header only renders when its group is non-empty,
//     and carries a count badge. Grouping is the organisational interaction we
//     exercise in lieu of a filter.
//       - Group assignment: completed/invoiced/cancelled → "Completed".
//         Otherwise reference = scheduledCompletionDate ?? createdAt; within
//         [todayStart, todayEnd) → "Today", else → "Upcoming".
//   * The screen is OFFLINE-FIRST and streams straight from Drift — no Dio/HTTP
//     here, so nothing to stub with MockDioClient; we seed real Drift rows and
//     assert on the rendered UI.
//   * CONTRACTOR ACTIONS live on ContractorJobCard, not the screen:
//       - Long-press the status badge opens a transition menu. Scheduled offers
//         "Start Work" (→ in_progress); In Progress offers "Mark Complete"
//         (→ complete). Selecting writes via `dao.updateJobStatus(...)` (Drift +
//         sync-queue dual write) and shows a "Job started"/"Job completed"
//         SnackBar. Completed/invoiced/cancelled cards have NO transition menu.
//       - Tapping the card body navigates to `/jobs/:id`.
//       - Add Note / Camera / Clock In-Out are also on the card but reach into
//         getIt<NoteDao>/<AttachmentDao> or push the timer route; they are out
//         of scope here and deliberately not tapped.
//   * The screen watches timerNotifierProvider (to pin the active job). That
//     provider reads timeEntryDaoProvider → getIt<TimeEntryDao>(), so we MUST
//     override timeEntryDaoProvider too, else the widget throws on getIt.
//   * Pull-to-refresh calls getIt<SyncEngine>().syncNow(); we never trigger it.
//
// Coverage:
//   1. Scoping — only jobs whose contractorId == the logged-in contractor are
//      rendered; another contractor's job and an unassigned job are hidden.
//   2. Job card fields — description, trade type, status label, priority.
//   3. Empty state — contractor with no jobs shows the "No jobs assigned" view.
//   4. Grouping (the interaction) — Today / Upcoming / Completed section headers
//      render for jobs that fall into each group.
//   5. Navigation — tapping a job card pushes `/jobs/:id` with the tapped id.
//   6. Contractor action: Start Work — long-press a Scheduled badge → "Start
//      Work" → status becomes in_progress in the UI AND in Drift, with SnackBar.
//   7. Contractor action: Mark Complete — long-press an In Progress badge →
//      "Mark Complete" → status becomes complete in Drift + SnackBar.
//   8. Completed jobs expose NO transition menu (long-press is a no-op).
//   9. Active job — an open TimeEntry pins its job under the "Active" header and
//      swaps the Clock In button for Clock Out.
//
// Harness rules (CLAUDE.md + MEMORY.md):
//   * Real Drift AppDatabase(NativeDatabase.memory()); a Company row is seeded
//     for the jobs FK. jobDaoProvider + timeEntryDaoProvider overridden with the
//     real DAOs — no getIt registration needed for reads.
//   * ProviderScope overrides authNotifierProvider with a fake AuthNotifier
//     supplying an AuthState.authenticated(roles: {contractor}).
//   * pump() / pump(Duration(...)) only — never pumpAndSettle (Drift streams and
//     the live timer never settle). Each test ends by unmounting to a SizedBox
//     to drain the zero-duration Drift close timer + cancel the timer ticker.

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart';
import 'package:contractorhub/features/jobs/presentation/providers/timer_providers.dart';
import 'package:contractorhub/features/jobs/presentation/screens/contractor_jobs_screen.dart';
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
const _meId = 'contractor-001'; // the logged-in contractor (the actor)
const _otherContractorId = 'contractor-002';

// Job ids
const _myScheduledId = 'job-my-scheduled';
const _myInProgressId = 'job-my-inprogress';
const _myUpcomingId = 'job-my-upcoming';
const _myCompletedId = 'job-my-completed';
const _otherId = 'job-other-contractor';
const _unassignedId = 'job-unassigned';

// Job descriptions (unique — used as find.text targets)
const _myScheduledDesc = 'Fix the leaking bathroom sink';
const _myInProgressDesc = 'Install the kitchen ceiling fan';
const _myUpcomingDesc = 'Replace the fence posts next week';
const _myCompletedDesc = 'Paint the garage door';
const _otherDesc = 'Repaint the hallway (other contractor)';
const _unassignedDesc = 'Unassigned quote — nobody yet';

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _meId,
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

/// Insert a job row directly. [minutesAgo] controls newest-first ordering.
Future<void> _seedJob(
  AppDatabase db, {
  required String id,
  required String status,
  required String description,
  String? contractorId,
  int minutesAgo = 0,
  String tradeType = 'Plumbing',
  String priority = 'medium',
  DateTime? scheduledCompletionDate,
}) async {
  final createdAt = DateTime.now().subtract(Duration(minutes: minutesAgo));
  await db.into(db.jobs).insert(
        JobsCompanion.insert(
          id: Value(id),
          companyId: _companyId,
          contractorId: Value(contractorId),
          description: description,
          tradeType: tradeType,
          status: Value(status),
          priority: Value(priority),
          scheduledCompletionDate: Value(scheduledCompletionDate),
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
}

/// Insert an OPEN (clocked-in) time entry so timerNotifier restores it and the
/// screen pins the matching job under the "Active" header.
Future<void> _seedActiveSession(
  AppDatabase db, {
  required String jobId,
}) async {
  final now = DateTime.now();
  await db.into(db.timeEntries).insert(
        TimeEntriesCompanion.insert(
          companyId: _companyId,
          jobId: jobId,
          contractorId: _meId,
          clockedInAt: now.subtract(const Duration(minutes: 12)),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

/// One-shot DB read of a job's current status.
Future<String> _statusOf(AppDatabase db, String jobId) async {
  final row = await (db.select(db.jobs)
        ..where((tbl) => tbl.id.equals(jobId)))
      .getSingle();
  return row.status;
}

// ---------------------------------------------------------------------------
// Widget-tree builder
// ---------------------------------------------------------------------------

/// Mount the contractor jobs screen inside a GoRouter so `context.push` (job
/// detail) resolves.
Widget _buildApp(AppDatabase db, {required AuthState auth}) {
  final router = GoRouter(
    initialLocation: '/contractor/jobs',
    routes: [
      GoRoute(
        path: '/contractor/jobs',
        builder: (context, state) => const ContractorJobsScreen(),
      ),
      GoRoute(
        path: '/jobs/:id',
        builder: (context, state) => Scaffold(
          body: Center(child: Text('DETAIL ${state.pathParameters['id']}')),
        ),
      ),
      GoRoute(
        path: '/timer/:jobId',
        builder: (context, state) => Scaffold(
          body: Center(child: Text('TIMER ${state.pathParameters['jobId']}')),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      jobDaoProvider.overrideWithValue(db.jobDao),
      timeEntryDaoProvider.overrideWithValue(db.timeEntryDao),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pump the screen and let the Drift stream emit its first snapshot
/// (loading → data). NO pumpAndSettle — Drift never settles.
Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmount and flush Drift's zero-duration close timer + cancel the timer
/// ticker (MEMORY.md). Call at the END of every test that mounts the screen.
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Give tests a tall surface so cards + action bars lay out on-screen and are
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
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await _seedCompany(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ContractorJobsScreen E2E', () {
    // ─── 1: scoping — only my jobs render ──────────────────────────────────
    testWidgets(
        'renders only jobs assigned to the logged-in contractor; hides other '
        "contractors' and unassigned jobs", (tester) async {
      _useTallSurface(tester);
      // Mine (two of them).
      await _seedJob(db,
          id: _myScheduledId,
          status: 'scheduled',
          description: _myScheduledDesc,
          contractorId: _meId,
          minutesAgo: 1);
      await _seedJob(db,
          id: _myInProgressId,
          status: 'in_progress',
          description: _myInProgressDesc,
          contractorId: _meId,
          minutesAgo: 2);
      // Another contractor's job.
      await _seedJob(db,
          id: _otherId,
          status: 'scheduled',
          description: _otherDesc,
          contractorId: _otherContractorId,
          minutesAgo: 3);
      // Unassigned job (contractorId defaults to null — nobody assigned).
      await _seedJob(db,
          id: _unassignedId,
          status: 'quote',
          description: _unassignedDesc,
          minutesAgo: 4);

      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpScreen(tester);

      // Only my jobs appear.
      expect(find.text(_myScheduledDesc), findsOneWidget);
      expect(find.text(_myInProgressDesc), findsOneWidget);

      // Other contractor's + unassigned jobs are excluded by the DAO scope.
      expect(find.text(_otherDesc), findsNothing);
      expect(find.text(_unassignedDesc), findsNothing);

      await _drainTimers(tester);
    });

    // ─── 2: job card fields ────────────────────────────────────────────────
    testWidgets('job card shows description, trade type, status label, priority',
        (tester) async {
      _useTallSurface(tester);
      await _seedJob(db,
          id: _myScheduledId,
          status: 'scheduled',
          description: _myScheduledDesc,
          contractorId: _meId,
          tradeType: 'Electrical',
          priority: 'high');

      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpScreen(tester);

      expect(find.text(_myScheduledDesc), findsOneWidget);
      expect(find.text('Electrical'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget); // status badge label
      expect(find.text('HIGH'), findsOneWidget); // priority, upper-cased

      await _drainTimers(tester);
    });

    // ─── 3: empty state ────────────────────────────────────────────────────
    testWidgets('shows the empty state when the contractor has no jobs',
        (tester) async {
      // No jobs seeded for anyone.
      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpScreen(tester);

      expect(find.text('No jobs assigned to you'), findsOneWidget);
      expect(
        find.text(
            'Jobs assigned by your admin will appear here.\nPull down to sync.'),
        findsOneWidget,
      );

      await _drainTimers(tester);
    });

    // ─── 4: grouping into Today / Upcoming / Completed sections ────────────
    testWidgets('groups jobs into Today, Upcoming and Completed sections',
        (tester) async {
      _useTallSurface(tester);
      // Today: created now, no scheduled date → reference = createdAt (today).
      await _seedJob(db,
          id: _myScheduledId,
          status: 'scheduled',
          description: _myScheduledDesc,
          contractorId: _meId,
          minutesAgo: 1);
      // Upcoming: scheduled 5 days out → reference is after today window.
      await _seedJob(db,
          id: _myUpcomingId,
          status: 'scheduled',
          description: _myUpcomingDesc,
          contractorId: _meId,
          minutesAgo: 2,
          scheduledCompletionDate:
              DateTime.now().add(const Duration(days: 5)));
      // Completed: terminal status → Completed section regardless of dates.
      await _seedJob(db,
          id: _myCompletedId,
          status: 'complete',
          description: _myCompletedDesc,
          contractorId: _meId,
          minutesAgo: 3);

      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpScreen(tester);

      // All three section headers render.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // Each job is on-screen under its section.
      expect(find.text(_myScheduledDesc), findsOneWidget);
      expect(find.text(_myUpcomingDesc), findsOneWidget);
      expect(find.text(_myCompletedDesc), findsOneWidget);

      await _drainTimers(tester);
    });

    // ─── 5: tapping a job navigates to its detail route ────────────────────
    testWidgets('tapping a job card navigates to the job detail route',
        (tester) async {
      _useTallSurface(tester);
      await _seedJob(db,
          id: _myScheduledId,
          status: 'scheduled',
          description: _myScheduledDesc,
          contractorId: _meId);

      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpScreen(tester);

      await tester.tap(find.text(_myScheduledDesc));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('DETAIL $_myScheduledId'), findsOneWidget);

      await _drainTimers(tester);
    });

    // ─── 6: contractor action — Start Work (scheduled → in_progress) ───────
    testWidgets(
        'long-press badge → Start Work transitions a scheduled job to '
        'in_progress in the UI and in Drift', (tester) async {
      _useTallSurface(tester);
      await _seedJob(db,
          id: _myScheduledId,
          status: 'scheduled',
          description: _myScheduledDesc,
          contractorId: _meId);

      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpScreen(tester);

      expect(find.text('Scheduled'), findsOneWidget);

      // Long-press the status badge to open the transition menu.
      await tester.longPress(find.text('Scheduled'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Menu offers "Start Work" (scheduled → in_progress).
      expect(find.text('Start Work'), findsOneWidget);

      await tester.tap(find.text('Start Work'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Drift row transitioned.
      expect(await _statusOf(db, _myScheduledId), 'in_progress');

      // UI reflects the new status + shows the confirmation SnackBar.
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Job started'), findsOneWidget);

      await _drainTimers(tester);
    });

    // ─── 7: contractor action — Mark Complete (in_progress → complete) ─────
    testWidgets(
        'long-press badge → Mark Complete transitions an in_progress job to '
        'complete in Drift with a SnackBar', (tester) async {
      _useTallSurface(tester);
      await _seedJob(db,
          id: _myInProgressId,
          status: 'in_progress',
          description: _myInProgressDesc,
          contractorId: _meId);

      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpScreen(tester);

      await tester.longPress(find.text('In Progress'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Mark Complete'), findsOneWidget);

      await tester.tap(find.text('Mark Complete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(await _statusOf(db, _myInProgressId), 'complete');
      expect(find.text('Job completed'), findsOneWidget);

      await _drainTimers(tester);
    });

    // ─── 8: completed jobs expose no transition menu ───────────────────────
    testWidgets('a completed job offers no status transition menu on long-press',
        (tester) async {
      _useTallSurface(tester);
      await _seedJob(db,
          id: _myCompletedId,
          status: 'complete',
          description: _myCompletedDesc,
          contractorId: _meId);

      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      await _pumpScreen(tester);

      // The completed badge renders (label 'Complete') but long-press is a no-op.
      await tester.longPress(find.text('Complete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // No transition menu items appear.
      expect(find.text('Start Work'), findsNothing);
      expect(find.text('Mark Complete'), findsNothing);

      await _drainTimers(tester);
    });

    // ─── 9: active (clocked-in) job pinned under the Active header ──────────
    testWidgets(
        'an open time entry pins its job under the Active header and shows '
        'Clock Out', (tester) async {
      _useTallSurface(tester);
      await _seedJob(db,
          id: _myInProgressId,
          status: 'in_progress',
          description: _myInProgressDesc,
          contractorId: _meId,
          minutesAgo: 1);
      await _seedJob(db,
          id: _myScheduledId,
          status: 'scheduled',
          description: _myScheduledDesc,
          contractorId: _meId,
          minutesAgo: 2);
      // Clock in to the in_progress job.
      await _seedActiveSession(db, jobId: _myInProgressId);

      await tester.pumpWidget(_buildApp(db, auth: _contractorAuth()));
      // timerNotifier.build() restores the open session over the Drift
      // active-session stream, which needs a REAL async gap (not fake pump
      // time) before it flips the screen from Clock In → Active/Clock Out.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The Active section header is present and pins the clocked-in job.
      expect(find.text('Active'), findsOneWidget);
      expect(find.text(_myInProgressDesc), findsOneWidget);

      // The active card swaps Clock In for Clock Out; the non-active card keeps
      // Clock In.
      expect(find.text('Clock Out'), findsOneWidget);
      expect(find.text('Clock In'), findsOneWidget);

      await _drainTimers(tester);
    });
  });
}
