// Job Wizard — Flutter E2E widget tests.
//
// Exercises the multi-step create-job wizard end-to-end:
//   UI interaction → Riverpod providers → JobCreationService → JobDao →
//   Drift (in-memory) persistence + sync-queue outbox → success UI.
//
// Covers (per the ACTUAL screen source — offline-first, no direct POST):
//   1. Wizard renders Step 1 (client selector + description field).
//   2. ONLINE first-frame: no offline banner; review shows the Contractor row.
//   3. OFFLINE gating: offline info banner appears and the Contractor review
//      row is hidden (the documented locked-decision behaviour).
//   4. Validation: a too-short description blocks advancing (stays on Step 1).
//   5. Stepper advances through steps with valid input.
//   6. Contractor step lists seeded contractors and a selection is reflected.
//   7. Empty contractor list edge case (only the placeholder option).
//   8. Create-job happy path: full flow → job persisted to Drift + a CREATE
//      sync item enqueued + "Job created successfully" snackbar.
//
// Harness conventions (CLAUDE.md + MEMORY.md):
//   - Real Drift in-memory DB via NativeDatabase.memory() for the write path.
//   - ProviderScope overrides: fake AuthNotifier (admin), Stream.value() for the
//     client/contractor selector families, real JobDao for jobDaoProvider.
//   - pump() / pump(Duration(...)) — NEVER pumpAndSettle() (Drift never settles;
//     the connectivity check also leaves work pending).
//   - Connectivity is NOT injectable: the screen calls
//     InternetConnection().hasInternetAccess directly in initState. A throwing
//     HttpOverrides makes that check resolve deterministically to OFFLINE; the
//     first rendered frame (before microtasks drain) is ONLINE.

import 'dart:convert';
import 'dart:io';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart';
import 'package:contractorhub/features/jobs/presentation/screens/job_wizard_screen.dart';
import 'package:contractorhub/features/jobs/presentation/widgets/job_wizard_fields.dart';
import 'package:contractorhub/features/users/domain/user_entity.dart';
import 'package:contractorhub/features/users/presentation/providers/user_providers.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _companyId = 'co-1';
const _adminUserId = 'admin-1';
const _contractor1Id = 'con-1';
const _contractor2Id = 'con-2';
const _contractor1Name = 'Carl Builder';
const _contractor2Name = 'Dana Frame';

const _validDescription = 'Replace the leaking kitchen sink and re-seal it';

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

AuthState _adminAuthState() => const AuthState.authenticated(
      userId: _adminUserId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

/// Fake AuthNotifier that returns a fixed authenticated state (no GetIt / IO).
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._fixedState);
  final AuthState _fixedState;

  @override
  AuthState build() => _fixedState;
}

// ---------------------------------------------------------------------------
// Deterministic OFFLINE connectivity.
//
// The wizard calls `InternetConnection().hasInternetAccess` in initState, which
// issues HTTP HEAD requests via dart:io HttpClient. This throwing override makes
// every request fail synchronously → the check resolves to "offline" once the
// microtask queue drains (i.e. after the first pump). The very first rendered
// frame still reflects the initial `_isOffline = false` (online) state.
// ---------------------------------------------------------------------------

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _ThrowingHttpClient();
}

class _ThrowingHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const SocketException('offline (test harness)');
}

// ---------------------------------------------------------------------------
// Test data builders
// ---------------------------------------------------------------------------

UserEntity _contractor({
  required String id,
  required String firstName,
  required String lastName,
}) {
  final now = DateTime.now();
  return UserEntity(
    id: id,
    companyId: _companyId,
    email: '$id@test.com',
    firstName: firstName,
    lastName: lastName,
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

List<UserEntity> _seedContractors() => [
      _contractor(id: _contractor1Id, firstName: 'Carl', lastName: 'Builder'),
      _contractor(id: _contractor2Id, firstName: 'Dana', lastName: 'Frame'),
    ];

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedCompany(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.companies).insert(CompaniesCompanion.insert(
        id: const Value(_companyId),
        name: 'Test Co',
        version: const Value(1),
        createdAt: now,
        updatedAt: now,
      ));
}

// ---------------------------------------------------------------------------
// Widget-tree builders
// ---------------------------------------------------------------------------

List<Override> _baseOverrides(
  AppDatabase db, {
  required List<UserEntity> contractors,
  List<UserEntity> clients = const [],
}) {
  return <Override>[
    authNotifierProvider.overrideWith(() => _FakeAuthNotifier(_adminAuthState())),
    jobDaoProvider.overrideWithValue(db.jobDao),
    companyClientsProvider(_companyId).overrideWith((ref) => Stream.value(clients)),
    companyContractorsProvider(_companyId)
        .overrideWith((ref) => Stream.value(contractors)),
  ];
}

/// Wizard mounted under a plain MaterialApp (no routing needed).
Widget _buildWizard(
  AppDatabase db, {
  List<UserEntity> contractors = const [],
}) {
  return ProviderScope(
    overrides: _baseOverrides(db, contractors: contractors),
    child: const MaterialApp(home: JobWizardScreen()),
  );
}

/// Wizard mounted inside a GoRouter so `context.pop()` on submit works and the
/// success snackbar can be asserted after navigation back to "home".
Widget _buildRoutedWizard(
  AppDatabase db, {
  List<UserEntity> contractors = const [],
}) {
  final router = GoRouter(
    initialLocation: '/wizard',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Home'))),
        routes: [
          GoRoute(
            path: 'wizard',
            builder: (context, state) => const JobWizardScreen(),
          ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: _baseOverrides(db, contractors: contractors),
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Let the initState connectivity check resolve to OFFLINE and rebuild.
Future<void> _resolveOffline(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
}

/// Drain any pending async (connectivity futures/timers) and unmount the tree
/// so the test ends clean.
Future<void> _drainAndDispose(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

int _currentStep(WidgetTester tester) =>
    tester.widget<Stepper>(find.byType(Stepper)).currentStep;

Future<void> _enterDescription(WidgetTester tester, String text) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Job description *'),
    text,
  );
  await tester.pump();
}

/// Tap the "Continue" button of the currently active step, then let the
/// Stepper's cross-fade transition (and any connectivity rebuild) settle so the
/// next step's controls become hit-testable.
Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(find.text('Continue').hitTestable());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Navigate from Step 1 to the contractor step (index 2) with valid input.
Future<void> _advanceToContractorStep(WidgetTester tester) async {
  await _enterDescription(tester, _validDescription);
  await _tapContinue(tester); // Step 1 -> Step 2 (Location & Trade)
  await _tapContinue(tester); // Step 2 -> Step 3 (Contractor & Schedule)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    HttpOverrides.global = _OfflineHttpOverrides();
    dotenv.loadFromString(envString: 'GOOGLE_PLACES_API_KEY=test-key');
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  late AppDatabase db;

  setUp(() async {
    db = _openTestDb();
    await _seedCompany(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Job Wizard — rendering & role-gated data', () {
    testWidgets('renders Step 1 with client selector and description field',
        (tester) async {
      await tester.pumpWidget(_buildWizard(db));
      // First frame — assert before the connectivity microtasks drain.

      expect(find.text('New Job'), findsOneWidget); // AppBar
      expect(find.text('Client & Job'), findsOneWidget); // Step 1 title
      expect(find.text('Job description *'), findsOneWidget);
      expect(find.text('Client (optional)'), findsOneWidget);

      await _drainAndDispose(tester);
    });

    testWidgets(
        'ONLINE first frame shows no offline banner and a Contractor review row',
        (tester) async {
      await tester.pumpWidget(_buildWizard(db, contractors: _seedContractors()));
      // First frame renders with _isOffline == false (online).

      expect(find.byType(OfflineInfoBanner, skipOffstage: false), findsNothing);
      // The Step 4 review "Contractor" row is only built when online.
      expect(find.text('Contractor', skipOffstage: false), findsOneWidget);

      await _drainAndDispose(tester);
    });
  });

  group('Job Wizard — offline gating', () {
    testWidgets(
        'OFFLINE shows the offline info banner and hides the Contractor review row',
        (tester) async {
      await tester.pumpWidget(_buildWizard(db, contractors: _seedContractors()));
      await _resolveOffline(tester);

      // Offline info banner(s) now rendered (Step 3 + Step 4 content).
      expect(find.byType(OfflineInfoBanner, skipOffstage: false),
          findsAtLeastNWidgets(1));
      expect(find.textContaining('You are offline', skipOffstage: false),
          findsAtLeastNWidgets(1));
      // The Step 4 review "Contractor" row is omitted while offline.
      expect(find.text('Contractor', skipOffstage: false), findsNothing);
      // The contractor selector itself is still present (only gated by a banner).
      expect(find.text('Assign contractor (optional)', skipOffstage: false),
          findsOneWidget);

      await _drainAndDispose(tester);
    });
  });

  group('Job Wizard — validation & navigation', () {
    testWidgets('too-short description blocks advancing past Step 1',
        (tester) async {
      await tester.pumpWidget(_buildWizard(db));
      await tester.pump();

      await _enterDescription(tester, 'Short');
      await _tapContinue(tester);

      expect(find.text('Description must be at least 10 characters.'),
          findsAtLeastNWidgets(1));
      expect(_currentStep(tester), 0);

      await _drainAndDispose(tester);
    });

    testWidgets('advances through steps with valid input', (tester) async {
      await tester.pumpWidget(_buildWizard(db, contractors: _seedContractors()));
      await tester.pump();

      expect(_currentStep(tester), 0);
      await _enterDescription(tester, _validDescription);
      await _tapContinue(tester);
      expect(_currentStep(tester), 1); // Location & Trade
      await _tapContinue(tester);
      expect(_currentStep(tester), 2); // Contractor & Schedule

      await _drainAndDispose(tester);
    });
  });

  group('Job Wizard — contractor assignment', () {
    testWidgets('contractor step lists seeded contractors and reflects selection',
        (tester) async {
      await tester.pumpWidget(_buildWizard(db, contractors: _seedContractors()));
      await tester.pump();

      await _advanceToContractorStep(tester);
      expect(_currentStep(tester), 2);

      // Open the contractor dropdown (currently showing the placeholder).
      await tester.tap(find.text('No contractor assigned yet').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Both seeded contractors are offered.
      expect(find.text(_contractor1Name), findsAtLeastNWidgets(1));
      expect(find.text(_contractor2Name), findsAtLeastNWidgets(1));

      // Pick the first contractor.
      await tester.tap(find.text(_contractor1Name).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The dropdown field now reflects the selection.
      expect(find.text(_contractor1Name), findsOneWidget);
      expect(find.text(_contractor2Name), findsNothing);

      await _drainAndDispose(tester);
    });

    testWidgets('empty contractor list shows only the placeholder option',
        (tester) async {
      await tester.pumpWidget(_buildWizard(db)); // no contractors seeded
      await tester.pump();

      await _advanceToContractorStep(tester);
      expect(_currentStep(tester), 2);

      await tester.tap(find.text('No contractor assigned yet').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No contractor assigned yet'), findsAtLeastNWidgets(1));
      expect(find.text(_contractor1Name), findsNothing);
      expect(find.text(_contractor2Name), findsNothing);

      await _drainAndDispose(tester);
    });
  });

  group('Job Wizard — create-job happy path (offline-first persistence)', () {
    testWidgets(
        'completing the wizard persists the job to Drift, enqueues a CREATE '
        'sync item, and shows the success snackbar', (tester) async {
      // Tall surface so the (offline) Step 3 controls stay on-screen / tappable.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester
          .pumpWidget(_buildRoutedWizard(db, contractors: _seedContractors()));
      await tester.pump();

      // Step 1 → Step 3 (contractor step).
      await _advanceToContractorStep(tester);
      expect(_currentStep(tester), 2);

      // Assign a contractor.
      await tester.tap(find.text('No contractor assigned yet').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(_contractor1Name).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Step 3 → Step 4 (Review & Submit).
      await _tapContinue(tester);
      expect(_currentStep(tester), 3);

      // Submit. The Drift write completes on the microtask queue (drained by
      // pump); avoid runAsync here — it deadlocks with the in-memory DB.
      await tester.tap(find.text('Create Job').hitTestable());
      await tester.pump(); // start _submit / _isSubmitting = true
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400)); // pop + snackbar

      // --- Assert Drift persistence (one-shot .get(), not a watch stream) --
      final jobs = await db.select(db.jobs).get();
      expect(jobs, hasLength(1));
      final job = jobs.first;
      expect(job.description, _validDescription);
      expect(job.contractorId, _contractor1Id);
      expect(job.status, 'quote');
      expect(job.priority, 'medium');
      expect(job.companyId, _companyId);

      // --- Assert sync-queue outbox (CREATE) ----------------------------
      final queue = await db.select(db.syncQueue).get();
      expect(queue, hasLength(1));
      expect(queue.first.entityType, 'job');
      expect(queue.first.operation, 'CREATE');
      final payload = jsonDecode(queue.first.payload) as Map<String, dynamic>;
      expect(payload['id'], job.id);
      expect(payload['contractor_id'], _contractor1Id);
      expect(payload['description'], _validDescription);
      expect(payload['status'], 'quote');

      // --- Assert success UI + navigation back --------------------------
      expect(find.text('Job created successfully'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);

      await _drainAndDispose(tester);
    });
  });
}
