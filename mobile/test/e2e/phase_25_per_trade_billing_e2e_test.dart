// Phase 25 — Per-Trade Billing: Flutter E2E widget tests.
//
// Covers BILL-01 through BILL-05:
//   BILL-01-01: test_trade_scope_billing_section_visible
//   BILL-01-02: test_create_quote_button_present
//   BILL-01-03: test_billing_section_hidden_for_contractor
//   BILL-03-01: test_generate_invoice_button_present_with_completed_tasks
//   BILL-03-02: test_generate_invoice_button_absent_without_completed_tasks
//   BILL-02-01: test_project_quote_summary_renders
//   BILL-02-02: test_project_quote_summary_empty_state
//   BILL-04-01: test_project_invoice_summary_renders
//   BILL-04-02: test_project_invoice_summary_empty_state
//   BILL-05-01: test_milestone_list_renders
//   BILL-05-02: test_invoiced_milestone_shows_badge
//   BILL-05-03: test_invoiced_milestone_no_generate_button
//   BILL-05-04: test_non_invoiced_milestone_has_generate_button
//   BILL-05-05: test_empty_milestones_shows_empty_state
//   BILL-05-06: test_create_milestone_sheet_validation
//   BILL-05-07: test_create_milestone_sheet_percentage_validation
//   BILL-05-08: test_create_milestone_sheet_title_visible
//   BONUS-01:   test_project_detail_shows_billing_summaries
//
// Patterns:
//   - ProviderScope.overrideWith for Riverpod providers
//   - pump() NOT pumpAndSettle() — Drift streams never settle (MEMORY.md)
//   - Stream.value() for fake DAO providers to avoid pending timer errors
//   - No GetIt initialization needed — all DAOs overridden via ProviderScope

import 'package:contractorhub/core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/billing_milestones/domain/billing_milestone_entity.dart';
import 'package:contractorhub/features/billing_milestones/presentation/providers/billing_milestone_providers.dart';
import 'package:contractorhub/features/billing_milestones/presentation/widgets/create_milestone_sheet.dart';
import 'package:contractorhub/features/billing_milestones/presentation/widgets/milestone_list_card.dart';
import 'package:contractorhub/features/projects/presentation/providers/billing_summary_providers.dart';
import 'package:contractorhub/features/projects/presentation/providers/project_providers.dart';
import 'package:contractorhub/features/projects/presentation/screens/project_detail_screen.dart';
import 'package:contractorhub/features/projects/presentation/screens/trade_scope_detail_screen.dart';
import 'package:contractorhub/features/projects/presentation/widgets/billing_summary_card.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'company-e2e-001';
const _userId = 'user-e2e-001';
const _projectId = 'project-e2e-001';
const _scopeId = 'scope-e2e-001';

// ---------------------------------------------------------------------------
// Auth state helpers
// ---------------------------------------------------------------------------

AuthState _adminAuth() => const AuthState.authenticated(
      userId: _userId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

AuthState _contractorAuth() => const AuthState.authenticated(
      userId: _userId,
      companyId: _companyId,
      roles: {UserRole.contractor},
    );

// ---------------------------------------------------------------------------
// Data builder helpers
// ---------------------------------------------------------------------------

TradeScope _makeScope({String id = _scopeId}) {
  final now = DateTime.now();
  return TradeScope(
    id: id,
    companyId: _companyId,
    projectId: _projectId,
    tradeName: 'Plumbing',
    tradeColor: '#2196F3',
    status: 'active',
    statusOverride: false,
    sortOrder: 0,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectTask _makeTask({
  String id = 'task-001',
  String status = 'complete',
}) {
  final now = DateTime.now();
  return ProjectTask(
    id: id,
    companyId: _companyId,
    tradeScopeId: _scopeId,
    title: 'Install pipes',
    status: status,
    sortOrder: 0,
    priority: 'medium',
    photoRequired: false,
    materialsNeeded: '',
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

BillingMilestoneEntity _makeMilestone({
  String id = 'ms-001',
  String name = 'Mobilisation',
  double percentage = 40.0,
  bool isInvoiced = false,
}) {
  final now = DateTime.now();
  return BillingMilestoneEntity(
    id: id,
    companyId: _companyId,
    tradeScopeId: _scopeId,
    name: name,
    percentage: percentage,
    isInvoiced: isInvoiced,
    sortOrder: 0,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

Project _makeProject({String id = _projectId}) {
  final now = DateTime.now();
  return Project(
    id: id,
    companyId: _companyId,
    name: 'Test Build',
    status: 'active',
    statusHistory: '[]',
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Fake auth notifier — sync Notifier to match AuthNotifier.build() signature
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  _FakeAuthNotifier(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Fake project list notifier
// ---------------------------------------------------------------------------

class _FakeProjectListNotifier extends AsyncNotifier<List<Project>>
    implements ProjectListNotifier {
  _FakeProjectListNotifier(this._projects);
  final List<Project> _projects;

  @override
  Future<List<Project>> build() async => _projects;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Widget wrappers
// ---------------------------------------------------------------------------

/// Wraps a widget in a minimal app with provider overrides.
Widget _wrapWithProviders(
  Widget child, {
  AuthState? authState,
  List<Override> overrides = const [],
}) {
  final auth = authState ?? _adminAuth();
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      ...overrides,
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

/// Wraps TradeScopeDetailScreen with all required providers.
Widget _wrapScopeDetailScreen({
  AuthState? authState,
  List<TradeScope> scopes = const [],
  List<ProjectTask> tasks = const [],
  List<PunchListItem> punchItems = const [],
  List<BillingMilestoneEntity> milestones = const [],
}) {
  final auth = authState ?? _adminAuth();
  return ProviderScope(
    overrides: [
      authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      tradeScopesProvider(_projectId).overrideWith(
        (ref) => Stream.value(scopes),
      ),
      tasksProvider(_scopeId).overrideWith(
        (ref) => Stream.value(tasks),
      ),
      punchItemsByScopeProvider(_scopeId).overrideWith(
        (ref) => Stream.value(punchItems),
      ),
      billingMilestonesByScope(_scopeId).overrideWith(
        (ref) => Stream.value(milestones),
      ),
    ],
    child: const MaterialApp(
      home: TradeScopeDetailScreen(
        projectId: _projectId,
        scopeId: _scopeId,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ────────────────────────────────────────────────────────────────────────
  // BILL-01: Trade-scope-level quotes — billing section visibility
  // ────────────────────────────────────────────────────────────────────────

  group('BILL-01: Trade scope billing section', () {
    testWidgets(
        'test_trade_scope_billing_section_visible: Billing section present for admin',
        (tester) async {
      await tester.pumpWidget(_wrapScopeDetailScreen(
        scopes: [_makeScope()],
        tasks: [_makeTask()],
      ));
      await tester.pump();

      // Billing section header visible for GC/admin
      expect(find.text('Billing'), findsWidgets);
    });

    testWidgets(
        'test_create_quote_button_present: Create Quote button visible for admin',
        (tester) async {
      await tester.pumpWidget(_wrapScopeDetailScreen(
        scopes: [_makeScope()],
        tasks: [_makeTask()],
      ));
      await tester.pump();

      expect(find.text('Create Quote'), findsOneWidget);
    });

    testWidgets(
        'test_billing_section_hidden_for_contractor: non-admin does not see billing',
        (tester) async {
      await tester.pumpWidget(_wrapScopeDetailScreen(
        authState: _contractorAuth(),
        scopes: [_makeScope()],
        tasks: [_makeTask()],
      ));
      await tester.pump();

      // No billing section for contractors
      expect(find.text('Create Quote'), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // BILL-03: Generate Invoice button presence
  // ────────────────────────────────────────────────────────────────────────

  group('BILL-03: Generate Invoice button', () {
    testWidgets(
        'test_generate_invoice_button_present_with_completed_tasks: button visible when tasks complete',
        (tester) async {
      await tester.pumpWidget(_wrapScopeDetailScreen(
        scopes: [_makeScope()],
        // _BillingActionButtons checks status == 'completed' or 'approved'
        tasks: [_makeTask(status: 'completed')],
      ));
      await tester.pump();

      expect(find.text('Generate Invoice'), findsOneWidget);
    });

    testWidgets(
        'test_generate_invoice_button_absent_without_completed_tasks: button hidden when no tasks complete',
        (tester) async {
      await tester.pumpWidget(_wrapScopeDetailScreen(
        scopes: [_makeScope()],
        tasks: [_makeTask(status: 'in_progress')],
      ));
      await tester.pump();

      expect(find.text('Generate Invoice'), findsNothing);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // BILL-05: Billing milestone list
  // ────────────────────────────────────────────────────────────────────────

  group('BILL-05: MilestoneListCard', () {
    testWidgets(
        'test_milestone_list_renders: both milestone names visible',
        (tester) async {
      final milestones = [
        _makeMilestone(id: 'ms-1'),
        _makeMilestone(id: 'ms-2', name: 'Completion', percentage: 60.0),
      ];

      await tester.pumpWidget(_wrapWithProviders(
        const MilestoneListCard(scopeId: _scopeId),
        overrides: [
          billingMilestonesByScope(_scopeId).overrideWith(
            (ref) => Stream.value(milestones),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Mobilisation'), findsOneWidget);
      expect(find.text('Completion'), findsOneWidget);
    });

    testWidgets(
        'test_invoiced_milestone_shows_badge: Invoiced chip visible for is_invoiced=true',
        (tester) async {
      final milestones = [
        _makeMilestone(id: 'ms-inv', name: 'Invoiced MS', isInvoiced: true),
      ];

      await tester.pumpWidget(_wrapWithProviders(
        const MilestoneListCard(scopeId: _scopeId),
        overrides: [
          billingMilestonesByScope(_scopeId).overrideWith(
            (ref) => Stream.value(milestones),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Invoiced'), findsOneWidget);
    });

    testWidgets(
        'test_invoiced_milestone_no_generate_button: no Generate Invoice button for invoiced milestone',
        (tester) async {
      final milestones = [
        _makeMilestone(id: 'ms-inv2', name: 'Already Invoiced', isInvoiced: true),
      ];

      await tester.pumpWidget(_wrapWithProviders(
        const MilestoneListCard(scopeId: _scopeId),
        overrides: [
          billingMilestonesByScope(_scopeId).overrideWith(
            (ref) => Stream.value(milestones),
          ),
        ],
      ));
      await tester.pump();

      // "Generate Invoice" TextButton should NOT be present for invoiced milestones
      expect(find.text('Generate Invoice'), findsNothing);
      // But the Invoiced chip should be present
      expect(find.text('Invoiced'), findsOneWidget);
    });

    testWidgets(
        'test_non_invoiced_milestone_has_generate_button: Generate Invoice button shown for non-invoiced',
        (tester) async {
      final milestones = [
        _makeMilestone(id: 'ms-noninv', name: 'Not Yet'),
      ];

      await tester.pumpWidget(_wrapWithProviders(
        const MilestoneListCard(scopeId: _scopeId),
        overrides: [
          billingMilestonesByScope(_scopeId).overrideWith(
            (ref) => Stream.value(milestones),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('Generate Invoice'), findsOneWidget);
      expect(find.text('Invoiced'), findsNothing);
    });

    testWidgets(
        'test_empty_milestones_shows_empty_state',
        (tester) async {
      await tester.pumpWidget(_wrapWithProviders(
        const MilestoneListCard(scopeId: _scopeId),
        overrides: [
          billingMilestonesByScope(_scopeId).overrideWith(
            (ref) => Stream.value([]),
          ),
        ],
      ));
      await tester.pump();

      expect(find.text('No milestones yet. Tap + to add one.'), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // BILL-05: CreateMilestoneSheet validation
  // ────────────────────────────────────────────────────────────────────────

  group('BILL-05: CreateMilestoneSheet', () {
    testWidgets(
        'test_create_milestone_sheet_title_visible: sheet header present',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuth()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CreateMilestoneSheet(scopeId: _scopeId, existingCount: 2),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Add Billing Milestone'), findsOneWidget);
    });

    testWidgets(
        'test_create_milestone_sheet_validation: submitting empty form shows required errors',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuth()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CreateMilestoneSheet(scopeId: _scopeId, existingCount: 0),
          ),
        ),
      ));
      await tester.pump();

      // Tap the Add Milestone button without filling in form
      await tester.tap(find.text('Add Milestone'));
      await tester.pump();

      // Validation errors should appear
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Percentage is required'), findsOneWidget);
    });

    testWidgets(
        'test_create_milestone_sheet_percentage_validation: 0 rejected',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuth()),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CreateMilestoneSheet(scopeId: _scopeId, existingCount: 0),
          ),
        ),
      ));
      await tester.pump();

      // Fill name but use invalid percentage (0)
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Milestone Name'),
        'Test MS',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Percentage (%)'),
        '0',
      );
      await tester.tap(find.text('Add Milestone'));
      await tester.pump();

      expect(find.text('Must be between 0 and 100 (exclusive)'), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // BILL-02: Project quote summary card
  // ────────────────────────────────────────────────────────────────────────

  group('BILL-02: BillingSummaryCard (quote)', () {
    testWidgets(
        'test_project_quote_summary_renders: per-trade rows and grand total visible',
        (tester) async {
      final fakeSummary = {
        'scopes': [
          {'trade_name': 'Plumbing', 'quote_count': 2, 'subtotal': 5000.0},
          {'trade_name': 'Electrical', 'quote_count': 1, 'subtotal': 3000.0},
        ],
        'grand_total': 8000.0,
      };

      await tester.pumpWidget(ProviderScope(
        overrides: [
          projectQuoteSummaryProvider(_projectId).overrideWith(
            (ref) async => fakeSummary,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BillingSummaryCard(
              projectId: _projectId,
              type: BillingSummaryType.quote,
            ),
          ),
        ),
      ));
      await tester.pump();
      // FutureProvider needs one more pump to resolve
      await tester.pump();

      // Card header
      expect(find.text('Quote Summary'), findsOneWidget);
      // Per-trade rows
      expect(find.text('Plumbing'), findsOneWidget);
      expect(find.text('Electrical'), findsOneWidget);
      // Grand total
      expect(find.text('Grand Total'), findsOneWidget);
      expect(find.text('\$8000.00'), findsOneWidget);
    });

    testWidgets(
        'test_project_quote_summary_empty_state: no quotes message shown',
        (tester) async {
      final fakeSummary = {
        'scopes': <dynamic>[],
        'grand_total': 0.0,
      };

      await tester.pumpWidget(ProviderScope(
        overrides: [
          projectQuoteSummaryProvider(_projectId).overrideWith(
            (ref) async => fakeSummary,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BillingSummaryCard(
              projectId: _projectId,
              type: BillingSummaryType.quote,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('No quotes yet for this project.'), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // BILL-04: Project invoice summary card
  // ────────────────────────────────────────────────────────────────────────

  group('BILL-04: BillingSummaryCard (invoice)', () {
    testWidgets(
        'test_project_invoice_summary_renders: billed/paid/outstanding columns visible',
        (tester) async {
      final fakeSummary = {
        'scopes': [
          {
            'trade_name': 'Plumbing',
            'billed': 5000.0,
            'paid': 2500.0,
            'outstanding': 2500.0,
          },
        ],
        'grand_total': {
          'billed': 5000.0,
          'paid': 2500.0,
          'outstanding': 2500.0,
        },
      };

      await tester.pumpWidget(ProviderScope(
        overrides: [
          projectInvoiceSummaryProvider(_projectId).overrideWith(
            (ref) async => fakeSummary,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BillingSummaryCard(
              projectId: _projectId,
              type: BillingSummaryType.invoice,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      // Card header
      expect(find.text('Invoice Summary'), findsOneWidget);
      // Column headers
      expect(find.text('Billed'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Owed'), findsOneWidget);
      // Trade name row
      expect(find.text('Plumbing'), findsOneWidget);
      // Grand total row
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets(
        'test_project_invoice_summary_empty_state: no invoices message shown',
        (tester) async {
      final fakeSummary = {
        'scopes': <dynamic>[],
        'grand_total': {'billed': 0.0, 'paid': 0.0, 'outstanding': 0.0},
      };

      await tester.pumpWidget(ProviderScope(
        overrides: [
          projectInvoiceSummaryProvider(_projectId).overrideWith(
            (ref) async => fakeSummary,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: BillingSummaryCard(
              projectId: _projectId,
              type: BillingSummaryType.invoice,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('No invoices yet for this project.'), findsOneWidget);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // BONUS: ProjectDetailScreen shows both billing summary cards
  // ────────────────────────────────────────────────────────────────────────

  group('ProjectDetailScreen billing cards', () {
    testWidgets(
        'test_project_detail_shows_billing_summaries: both BillingSummaryCards present for admin',
        (tester) async {
      final fakeQuoteSummary = {
        'scopes': <dynamic>[],
        'grand_total': 0.0,
      };
      final fakeInvoiceSummary = {
        'scopes': <dynamic>[],
        'grand_total': {'billed': 0.0, 'paid': 0.0, 'outstanding': 0.0},
      };

      await tester.pumpWidget(ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(
            () => _FakeAuthNotifier(_adminAuth()),
          ),
          projectListProvider.overrideWith(
            () => _FakeProjectListNotifier([_makeProject()]),
          ),
          tradeScopesProvider(_projectId).overrideWith(
            (ref) => Stream.value([_makeScope()]),
          ),
          flagsForProjectProvider(_projectId).overrideWith(
            (ref) => Stream.value([]),
          ),
          projectProgressProvider(_projectId).overrideWith(
            (ref) => Stream.value(const ProjectProgress()),
          ),
          projectQuoteSummaryProvider(_projectId).overrideWith(
            (ref) async => fakeQuoteSummary,
          ),
          projectInvoiceSummaryProvider(_projectId).overrideWith(
            (ref) async => fakeInvoiceSummary,
          ),
        ],
        child: const MaterialApp(
          home: ProjectDetailScreen(projectId: _projectId),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Quote Summary'), findsOneWidget);
      expect(find.text('Invoice Summary'), findsOneWidget);
    });
  });
}
