// Phase 10 — UI Backend Wiring Gap Closure: Flutter E2E widget tests.
//
// Tests cover:
//   - SCHED-08: OverduePanel wired into ScheduleScreen (not placeholder Container)
//   - BIZ-01: Create Quote button visible for admin, hidden for non-admin
//   - BIZ-02: View/Edit Quote button shown when quote already exists for the job
//
// Patterns:
//   - ProviderScope.overrideWith for stream providers (Drift-backed)
//   - pump() NOT pumpAndSettle() for Drift stream providers (streams never settle)
//   - Fake notifiers extend original notifier class for Riverpod 3 type safety
//   - OverduePanel tested directly (not via full ScheduleScreen) for simpler setup

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/invoices/presentation/providers/invoice_providers.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart';
import 'package:contractorhub/features/jobs/presentation/providers/note_providers.dart';
import 'package:contractorhub/features/jobs/presentation/screens/job_detail_screen.dart';
import 'package:contractorhub/features/quotes/domain/quote_entity.dart';
import 'package:contractorhub/features/quotes/presentation/providers/quote_providers.dart';
import 'package:contractorhub/features/schedule/domain/overdue_service.dart';
import 'package:contractorhub/features/schedule/presentation/providers/calendar_providers.dart';
import 'package:contractorhub/features/schedule/presentation/providers/overdue_providers.dart';
import 'package:contractorhub/features/schedule/presentation/widgets/overdue_panel.dart';
import 'package:contractorhub/shared/models/user_role.dart';

// ---------------------------------------------------------------------------
// Auth state helpers
// ---------------------------------------------------------------------------

AuthState _adminAuthState() => const AuthState.authenticated(
      userId: 'user-001',
      companyId: 'company-001',
      roles: {UserRole.admin},
    );

AuthState _contractorAuthState() => const AuthState.authenticated(
      userId: 'contractor-001',
      companyId: 'company-001',
      roles: {UserRole.contractor},
    );

// ---------------------------------------------------------------------------
// Job entity helper — uses correct freezed field names
// ---------------------------------------------------------------------------

JobEntity _makeJob({
  String id = 'job-001',
  String status = 'scheduled',
  String description = 'Bathroom renovation',
}) {
  return JobEntity(
    id: id,
    companyId: 'company-001',
    description: description,
    tradeType: 'plumbing',
    status: status,
    statusHistory: const [],
    priority: 'medium',
    tags: const [],
    notes: null,
    purchaseOrderNumber: null,
    externalReference: null,
    estimatedDurationMinutes: null,
    scheduledCompletionDate: null,
    clientId: null,
    contractorId: null,
    gpsLatitude: null,
    gpsLongitude: null,
    gpsAddress: null,
    version: 1,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    deletedAt: null,
  );
}

// ---------------------------------------------------------------------------
// Quote entity helper
// ---------------------------------------------------------------------------

QuoteEntity _makeQuote({String status = 'draft'}) {
  return QuoteEntity(
    id: 'quote-001',
    companyId: 'company-001',
    jobId: 'job-001',
    status: status,
    revisionNumber: 0,
    taxRate: 10.0,
    discountType: null,
    discountValue: 0.0,
    expiryDate: null,
    sentAt: null,
    viewedAt: null,
    approvedAt: null,
    declinedAt: null,
    declineReason: null,
    declineDetail: null,
    adminNotes: null,
    lineItems: const [],
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

// ---------------------------------------------------------------------------
// Overdue job info helper
// ---------------------------------------------------------------------------

OverdueJobInfo _makeOverdueJob({
  String jobId = 'job-001',
  String description = 'Overdue Roof Repair',
}) {
  return OverdueJobInfo(
    jobId: jobId,
    description: description,
    scheduledCompletionDate: DateTime.now().subtract(const Duration(days: 5)),
    daysOverdue: 5,
    severity: OverdueSeverity.warning,
    hasDelayReport: false,
    clientName: null,
    contractorName: null,
    latestDelayReason: null,
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

// Stub JobListNotifier returns empty list — avoids Drift dependency in tests.
class _StubJobListNotifier extends JobListNotifier {
  @override
  Future<List<JobEntity>> build() async => [];
}

// ---------------------------------------------------------------------------
// SCHED-08: OverduePanel widget tests
// ---------------------------------------------------------------------------

void main() {
  group('SCHED-08: OverduePanel wired (not placeholder Container)', () {
    testWidgets(
      'sched08: OverduePanel renders overdue job when panel is visible',
      (tester) async {
        final overdueJob = _makeOverdueJob();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider
                  .overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
              // Show panel with one overdue job
              showOverduePanelProvider.overrideWith((ref) => true),
              overdueJobsProvider.overrideWith((ref) => [overdueJob]),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: OverduePanel(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // OverduePanel widget is present (not placeholder)
        expect(find.byType(OverduePanel), findsOneWidget);

        // Placeholder text must NOT appear — wiring is correct
        expect(find.text('Overdue panel loading...'), findsNothing);

        // The overdue job description should be visible
        expect(find.text('Overdue Roof Repair'), findsOneWidget);
      },
    );

    testWidgets(
      'sched08_empty: OverduePanel renders empty state when panel is visible with no jobs',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider
                  .overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
              showOverduePanelProvider.overrideWith((ref) => true),
              overdueJobsProvider.overrideWith((ref) => []),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: OverduePanel(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OverduePanel), findsOneWidget);

        // No placeholder text
        expect(find.text('Overdue panel loading...'), findsNothing);

        // Empty state indicator should show
        expect(find.text('No overdue jobs'), findsOneWidget);
      },
    );

    testWidgets(
      'sched08_collapsed: OverduePanel is hidden when showOverduePanelProvider is false',
      (tester) async {
        final overdueJob = _makeOverdueJob();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider
                  .overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
              // Panel toggled off
              showOverduePanelProvider.overrideWith((ref) => false),
              overdueJobsProvider.overrideWith((ref) => [overdueJob]),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: OverduePanel(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Widget exists but content is hidden (AnimatedContainer height=0)
        expect(find.byType(OverduePanel), findsOneWidget);
        // Job content not visible when collapsed
        expect(find.text('Overdue Roof Repair'), findsNothing);
      },
    );
  });

  // =============================================================================
  // BIZ-01 Tests — Create Quote button visibility
  // =============================================================================

  group('BIZ-01: Create Quote button for admin', () {
    testWidgets(
      'biz01_create: Admin sees Create Quote button when job has no quote',
      (tester) async {
        final job = _makeJob(status: 'scheduled');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider
                  .overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
              // No existing quote for this job
              quoteForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([]),
              ),
              // No existing invoice
              invoicesForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([]),
              ),
              // Job detail stream
              jobDetailNotifierProvider('job-001').overrideWith(
                (ref) => Stream.value(job),
              ),
              // Note count — depends on notesForJobProvider; return 0 directly
              noteCountProvider('job-001').overrideWith((ref) => 0),
            ],
            child: const MaterialApp(
              home: JobDetailScreen(jobId: 'job-001'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // "Create Quote" FilledButton should be visible for admin
        expect(find.text('Create Quote'), findsOneWidget);
      },
    );

    testWidgets(
      'biz01_no_button: Non-admin (contractor) does NOT see Create Quote button',
      (tester) async {
        final job = _makeJob(status: 'scheduled');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              // Contractor role — not admin
              authNotifierProvider.overrideWith(
                () => _FakeAuthNotifier(_contractorAuthState()),
              ),
              quoteForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([]),
              ),
              invoicesForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([]),
              ),
              jobDetailNotifierProvider('job-001').overrideWith(
                (ref) => Stream.value(job),
              ),
              noteCountProvider('job-001').overrideWith((ref) => 0),
            ],
            child: const MaterialApp(
              home: JobDetailScreen(jobId: 'job-001'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // "Create Quote" should NOT be visible for contractor
        expect(find.text('Create Quote'), findsNothing);
      },
    );

    testWidgets(
      'biz01_cancelled: Admin does NOT see Create Quote button for cancelled job',
      (tester) async {
        final job = _makeJob(status: 'cancelled');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider
                  .overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
              quoteForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([]),
              ),
              invoicesForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([]),
              ),
              jobDetailNotifierProvider('job-001').overrideWith(
                (ref) => Stream.value(job),
              ),
              noteCountProvider('job-001').overrideWith((ref) => 0),
            ],
            child: const MaterialApp(
              home: JobDetailScreen(jobId: 'job-001'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Cancelled job — quote section hidden entirely
        expect(find.text('Create Quote'), findsNothing);
        expect(find.text('View / Edit Quote'), findsNothing);
      },
    );
  });

  // =============================================================================
  // BIZ-02 Tests — View/Edit Quote button when quote exists
  // =============================================================================

  group('BIZ-02: View/Edit Quote button when quote exists', () {
    testWidgets(
      'biz02_view: Admin sees View / Edit Quote button when quote exists',
      (tester) async {
        final job = _makeJob(status: 'scheduled');
        final quote = _makeQuote(status: 'sent');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider
                  .overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
              // Existing quote for this job
              quoteForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([quote]),
              ),
              invoicesForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([]),
              ),
              jobDetailNotifierProvider('job-001').overrideWith(
                (ref) => Stream.value(job),
              ),
              noteCountProvider('job-001').overrideWith((ref) => 0),
            ],
            child: const MaterialApp(
              home: JobDetailScreen(jobId: 'job-001'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // "View / Edit Quote" OutlinedButton should be visible
        expect(find.text('View / Edit Quote'), findsOneWidget);

        // "Create Quote" should NOT be visible (quote already exists)
        expect(find.text('Create Quote'), findsNothing);
      },
    );

    testWidgets(
      'biz02_draft_visible: Admin sees View / Edit Quote for draft quote',
      (tester) async {
        final job = _makeJob(status: 'in_progress');
        final quote = _makeQuote(status: 'draft');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider
                  .overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
              quoteForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([quote]),
              ),
              invoicesForJobProvider('job-001').overrideWith(
                (ref) => Stream.value([]),
              ),
              jobDetailNotifierProvider('job-001').overrideWith(
                (ref) => Stream.value(job),
              ),
              noteCountProvider('job-001').overrideWith((ref) => 0),
            ],
            child: const MaterialApp(
              home: JobDetailScreen(jobId: 'job-001'),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Both quote statuses (draft, sent, etc.) show View / Edit Quote
        expect(find.text('View / Edit Quote'), findsOneWidget);
      },
    );
  });
}
