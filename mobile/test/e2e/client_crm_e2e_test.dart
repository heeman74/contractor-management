// Client CRM — Flutter E2E widget tests.
//
// Exercises the three "client CRM" screens end-to-end:
//   UI interaction → Riverpod StreamProviders → JobDao (real Drift in-memory DB)
//   → reactive stream → UI update.
//
// ── WHAT THE SOURCE ACTUALLY DOES (differs from a naive spec) ────────────────
//
// The three targets are NOT three variations of one screen — they are a
// placeholder plus a real list/detail pair:
//
//   1. admin/.../client_management_screen.dart  → ClientManagementScreen
//        A STATIC PLACEHOLDER ("Coming in Phase 4"). No providers, no data,
//        StatelessWidget. Superseded by ClientCrmScreen. Light coverage only.
//
//   2. jobs/.../client_crm_screen.dart          → ClientCrmScreen  (PRIMARY)
//        The real CRM hub: searchable/filterable client list of inline
//        expandable ClientCard widgets, a pending-request AppBar badge, an
//        "Add Client" FAB, and empty/error states. Reads three providers, all
//        backed by getIt<JobDao>() over the local Drift DB (offline-first).
//
//   3. jobs/.../client_detail_screen.dart       → ClientDetailScreen (PRIMARY)
//        The drill-down target of a ClientCard's "View Profile" action. A
//        3-tab (Profile / Jobs / Ratings) profile view. Also reads the same
//        JobDao-backed providers.
//
// WRITE PATHS — CRITICAL SOURCE FINDING:
//   NEITHER real screen performs a persistent write. Every "mutation" is a
//   Phase-4 stub:
//     * CRM "Add Client" FAB           → guidance AlertDialog only (no write).
//     * Detail "Save" (admin notes)    → SnackBar "Notes saved locally", the
//                                         setState clears edit mode, but NOTHING
//                                         is written to Drift or Dio.
//     * Detail AppBar edit / "Change"  → "coming soon" SnackBars.
//   Because there is no Dio call and no Drift write in any flow, there is
//   nothing to stub with MockDioClient and nothing new to assert as persisted.
//   We instead assert the ACTUAL stub behaviour (dialog/snackbar shown) AND
//   that the seeded row is UNCHANGED after a "save" — documenting the stub.
//
// PROVIDER KEYING QUIRK (documented, not a test failure):
//   The CRM list card watches job history by profile.userId, while the detail
//   screen watches it by the route id (profile.id). We seed each test's jobs to
//   match the key the screen-under-test actually queries.
//
// Read path is fully real: real AppDatabase(NativeDatabase.memory()), JobDao
// registered in getIt (the providers resolve getIt<JobDao>()), rows seeded
// directly, DB assertions via one-shot .get().
//
// ── Coverage ────────────────────────────────────────────────────────────────
//   Placeholder:
//     1.  ClientManagementScreen renders its static admin-only placeholder.
//   ClientCrmScreen (list):
//     2.  renders seeded clients (identity), tenant-scoped
//     3.  empty state when company has no clients
//     4.  search filters the list by tag/note
//     5.  search with no match shows the "no match" empty state
//     6.  pending-request AppBar badge reflects seeded pending requests
//     7.  "Add Client" FAB opens the guidance dialog (stub — no write)
//     8.  expanding a ClientCard reveals CRM detail + job count (by userId)
//     9.  tenant scoping — another company's client is not shown
//    10.  error state renders "Failed to load clients"
//   ClientDetailScreen (detail / drill-down):
//    11.  Profile tab renders contact, referral, tags, notes, contractor, rating
//    12.  Jobs tab renders the client's job history (keyed by route id)
//    13.  Jobs tab empty state when the client has no jobs
//    14.  unknown client id renders "Client not found"
//    15.  edit admin notes → Save → SnackBar shown AND row NOT persisted (stub)
//    16.  AppBar "Edit Profile" shows the "coming soon" stub SnackBar
//    17.  Ratings tab renders the average rating
//
// Harness rules (CLAUDE.md + MEMORY.md):
//   * Real Drift AppDatabase(NativeDatabase.memory()); JobDao registered in
//     getIt and reset in tearDown.
//   * ProviderScope overrides authNotifierProvider with a fake AuthNotifier.
//   * pump() / pump(Duration(...)) only — never pumpAndSettle (Drift streams
//     never settle). Each screen test drains Drift's close timer at the end.
//   * Error-state override uses ProviderScope(retry: ...) to defeat Riverpod 3
//     auto-retry, which otherwise hangs the test.

import 'dart:convert';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/admin/presentation/screens/client_management_screen.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/domain/client_profile_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/crm_providers.dart';
import 'package:contractorhub/features/jobs/presentation/screens/client_crm_screen.dart';
import 'package:contractorhub/features/jobs/presentation/screens/client_detail_screen.dart';
import 'package:contractorhub/features/jobs/presentation/widgets/client_card.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _otherCompanyId = 'company-002';
const _adminUserId = 'admin-001';

// Client profiles. `id` is the CRM row id (route param used by the detail
// screen). `userId` is the FK to the client User (the key the list card uses
// for job history).
const _aliceProfileId = 'client-profile-alice';
const _aliceUserId = 'alice-user';
const _bobProfileId = 'client-profile-bob';
const _bobUserId = 'bob-user';
const _eveProfileId = 'client-profile-eve';
const _eveUserId = 'eve-user';

// ---------------------------------------------------------------------------
// Auth state helpers
// ---------------------------------------------------------------------------

AuthState _adminAuth() => const AuthState.authenticated(
      userId: _adminUserId,
      companyId: _companyId,
      roles: {UserRole.admin},
    );

// ---------------------------------------------------------------------------
// Fake AuthNotifier — supplies a fixed AuthState (companyId scopes the list)
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

// ---------------------------------------------------------------------------
// Seed helpers — write real rows the JobDao streams will emit
// ---------------------------------------------------------------------------

Future<void> _seedClientProfile(
  AppDatabase db, {
  required String id,
  required String userId,
  required String companyId,
  List<String> tags = const [],
  String? billingAddress,
  String? adminNotes,
  String? referralSource,
  String? preferredContactMethod,
  String? preferredContractorId,
  double? averageRating,
}) async {
  final now = DateTime.now();
  await db.into(db.clientProfiles).insert(
        ClientProfilesCompanion.insert(
          id: Value(id),
          companyId: companyId,
          userId: userId,
          tags: Value(jsonEncode(tags)),
          billingAddress: Value(billingAddress),
          adminNotes: Value(adminNotes),
          referralSource: Value(referralSource),
          preferredContactMethod: Value(preferredContactMethod),
          preferredContractorId: Value(preferredContractorId),
          averageRating: Value(averageRating),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _seedJob(
  AppDatabase db, {
  required String id,
  required String clientId,
  required String companyId,
  required String description,
  String tradeType = 'plumbing',
  String status = 'scheduled',
}) async {
  final now = DateTime.now();
  await db.into(db.jobs).insert(
        JobsCompanion.insert(
          id: Value(id),
          companyId: companyId,
          clientId: Value(clientId),
          description: description,
          tradeType: tradeType,
          status: Value(status),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _seedPendingRequest(
  AppDatabase db, {
  required String id,
  required String companyId,
  required String description,
}) async {
  final now = DateTime.now();
  await db.into(db.jobRequests).insert(
        JobRequestsCompanion.insert(
          id: Value(id),
          companyId: companyId,
          description: description,
          requestStatus: const Value('pending'),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

// One-shot read for DB assertions — avoids opening another watch stream.
Future<ClientProfile?> _profileRow(AppDatabase db, String id) {
  return (db.select(db.clientProfiles)..where((t) => t.id.equals(id)))
      .getSingleOrNull();
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

Future<void> _pumpCrm(
  WidgetTester tester, {
  required AuthState auth,
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      // Defeat Riverpod 3 auto-retry so error-state overrides settle.
      retry: (_, __) => null,
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
        ...extraOverrides,
      ],
      child: const MaterialApp(home: ClientCrmScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required AuthState auth,
  required String clientId,
}) async {
  // Tall surface so the whole Profile ListView (notes, contractor) and the
  // Save button are on-screen — the detail tabs scroll otherwise.
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      ],
      child: MaterialApp(home: ClientDetailScreen(clientId: clientId)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmount and flush the zero-duration Timer Drift schedules when its query
/// streams are cancelled on ProviderScope disposal (MEMORY.md: Drift streams
/// never settle). Call at the END of every test that mounts a data-driven
/// screen.
Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    if (getIt.isRegistered<JobDao>()) {
      getIt.unregister<JobDao>();
    }
    // The CRM providers resolve getIt<JobDao>() — register the real DAO.
    getIt.registerSingleton<JobDao>(db.jobDao);
  });

  tearDown(() async {
    await getIt.reset();
    try {
      await db.close();
    } catch (_) {
      // Some tests close the DB deliberately; tolerate double-close.
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('ClientManagementScreen (legacy placeholder)', () {
    testWidgets('renders the static admin-only placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ClientManagementScreen()),
      );
      await tester.pump();

      // Two matches: the AppBar title and the body heading both read
      // "Client Management".
      expect(find.text('Client Management'), findsNWidgets(2));
      expect(find.text('Admin Only — Coming in Phase 4'), findsOneWidget);
      // Purely static — no data-driven providers, so nothing to drain.
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('ClientCrmScreen (CRM hub list)', () {
    testWidgets('renders seeded clients scoped to the authed company',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId,
          userId: _aliceUserId,
          companyId: _companyId,
          tags: ['vip', 'residential'],
          adminNotes: 'Prefers morning calls',
          referralSource: 'Google',
          averageRating: 4.5);
      await _seedClientProfile(db,
          id: _bobProfileId,
          userId: _bobUserId,
          companyId: _companyId,
          tags: ['commercial']);

      await _pumpCrm(tester, auth: _adminAuth());

      // ClientCard uses profile.userId as the display name (User join pending).
      expect(find.text(_aliceUserId), findsOneWidget);
      expect(find.text(_bobUserId), findsOneWidget);
      expect(find.byType(ClientCard), findsNWidgets(2));

      await _drainDriftTimers(tester);
    });

    testWidgets('shows empty state when the company has no clients',
        (tester) async {
      await _pumpCrm(tester, auth: _adminAuth());

      expect(find.text('No clients yet'), findsOneWidget);
      expect(find.byType(ClientCard), findsNothing);

      await _drainDriftTimers(tester);
    });

    testWidgets('search bar filters the list by tag/note', (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId,
          userId: _aliceUserId,
          companyId: _companyId,
          tags: ['vip']);
      await _seedClientProfile(db,
          id: _bobProfileId,
          userId: _bobUserId,
          companyId: _companyId,
          tags: ['commercial']);

      await _pumpCrm(tester, auth: _adminAuth());
      expect(find.byType(ClientCard), findsNWidgets(2));

      // The SearchBar is the only editable field on the screen.
      await tester.enterText(find.byType(TextField).first, 'vip');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Alice has the 'vip' tag; Bob does not.
      expect(find.text(_aliceUserId), findsOneWidget);
      expect(find.text(_bobUserId), findsNothing);
      expect(find.byType(ClientCard), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('search with no matches shows the search empty state',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId,
          userId: _aliceUserId,
          companyId: _companyId,
          tags: ['vip']);

      await _pumpCrm(tester, auth: _adminAuth());

      await tester.enterText(find.byType(TextField).first, 'zzz-no-match');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No clients match your search'), findsOneWidget);
      expect(find.byType(ClientCard), findsNothing);

      await _drainDriftTimers(tester);
    });

    testWidgets('pending-request AppBar badge reflects seeded pending requests',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId, userId: _aliceUserId, companyId: _companyId);
      await _seedPendingRequest(db,
          id: 'req-1', companyId: _companyId, description: 'Leaky tap');
      await _seedPendingRequest(db,
          id: 'req-2', companyId: _companyId, description: 'New fence');

      await _pumpCrm(tester, auth: _adminAuth());

      // Badge count = 2 pending requests → tooltip encodes the live count.
      expect(find.byTooltip('Pending Requests (2)'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('Add Client FAB opens the guidance dialog (stub, no write)',
        (tester) async {
      await _pumpCrm(tester, auth: _adminAuth());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The dialog is guidance-only — it does NOT create a client.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('invite them via the Team Management screen'),
        findsOneWidget,
      );

      // Dismiss.
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);

      // Nothing persisted.
      final clients = await db.select(db.clientProfiles).get();
      expect(clients, isEmpty);

      await _drainDriftTimers(tester);
    });

    testWidgets(
        'expanding a ClientCard reveals CRM details and the by-userId job count',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId,
          userId: _aliceUserId,
          companyId: _companyId,
          tags: ['vip'],
          adminNotes: 'Prefers morning calls',
          referralSource: 'Google');
      // The list card keys job history by profile.userId.
      await _seedJob(db,
          id: 'job-1',
          clientId: _aliceUserId,
          companyId: _companyId,
          description: 'Bathroom re-pipe');

      await _pumpCrm(tester, auth: _adminAuth());

      // Header shows the by-userId job count.
      expect(find.text('1 job'), findsOneWidget);

      // Tap the card header to expand its inline detail section.
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Prefers morning calls'), findsOneWidget);
      expect(find.text('Google'), findsOneWidget);
      expect(find.text('vip'), findsOneWidget);
      expect(find.text('Bathroom re-pipe'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('client list is tenant-scoped to the authed company',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId, userId: _aliceUserId, companyId: _companyId);
      await _seedClientProfile(db,
          id: _eveProfileId, userId: _eveUserId, companyId: _otherCompanyId);

      await _pumpCrm(tester, auth: _adminAuth());

      expect(find.text(_aliceUserId), findsOneWidget);
      expect(find.text(_eveUserId), findsNothing);
      expect(find.byType(ClientCard), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('renders the error state when the client stream fails',
        (tester) async {
      await _pumpCrm(
        tester,
        auth: _adminAuth(),
        extraOverrides: [
          clientListNotifierProvider(_companyId).overrideWith(
            (ref) => Stream<List<ClientProfileEntity>>.error(
              Exception('DB read failed'),
            ),
          ),
        ],
      );

      expect(find.textContaining('Failed to load clients'), findsOneWidget);
      expect(find.byType(ClientCard), findsNothing);

      await _drainDriftTimers(tester);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('ClientDetailScreen (drill-down)', () {
    testWidgets('Profile tab renders contact, referral, tags, notes, rating',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId,
          userId: _aliceUserId,
          companyId: _companyId,
          tags: ['vip', 'residential'],
          billingAddress: '123 Main St',
          adminNotes: 'Prefers morning calls',
          referralSource: 'Google',
          preferredContactMethod: 'email',
          preferredContractorId: 'contractor-9',
          averageRating: 4.5);

      await _pumpDetail(tester, auth: _adminAuth(), clientId: _aliceProfileId);

      // Profile tab is the default active tab.
      expect(find.text(_aliceUserId), findsOneWidget); // header title
      expect(find.text('123 Main St'), findsOneWidget);
      expect(find.text('email'), findsOneWidget);
      expect(find.text('Google'), findsOneWidget);
      expect(find.text('Prefers morning calls'), findsOneWidget);
      expect(find.text('vip'), findsOneWidget);
      expect(find.text('residential'), findsOneWidget);
      expect(find.text('Contractor ID: contractor-9'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('Jobs tab renders the client job history (keyed by route id)',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId, userId: _aliceUserId, companyId: _companyId);
      // The detail screen keys job history by the route id (profile.id).
      await _seedJob(db,
          id: 'job-a',
          clientId: _aliceProfileId,
          companyId: _companyId,
          description: 'Kitchen remodel',
          status: 'in_progress');
      await _seedJob(db,
          id: 'job-b',
          clientId: _aliceProfileId,
          companyId: _companyId,
          description: 'Roof repair',
          status: 'complete');

      await _pumpDetail(tester, auth: _adminAuth(), clientId: _aliceProfileId);

      // Switch to the Jobs tab.
      await tester.tap(find.text('Jobs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Kitchen remodel'), findsOneWidget);
      expect(find.text('Roof repair'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('Jobs tab shows empty state when the client has no jobs',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId, userId: _aliceUserId, companyId: _companyId);

      await _pumpDetail(tester, auth: _adminAuth(), clientId: _aliceProfileId);

      await tester.tap(find.text('Jobs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No job history for this client'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('unknown client id renders the not-found state',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId, userId: _aliceUserId, companyId: _companyId);

      await _pumpDetail(
        tester,
        auth: _adminAuth(),
        clientId: 'does-not-exist',
      );

      expect(find.text('Client not found'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets(
        'edit admin notes → Save shows SnackBar but does NOT persist (stub)',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId,
          userId: _aliceUserId,
          companyId: _companyId,
          adminNotes: 'Original note');

      await _pumpDetail(tester, auth: _adminAuth(), clientId: _aliceProfileId);

      // Enter edit mode via the Admin Notes section's edit button.
      await tester.tap(find.byTooltip('Edit Notes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Type a replacement note.
      await tester.enterText(find.byType(TextFormField), 'Changed note text');
      await tester.pump();

      // Save — Phase 4 stub: snackbar only.
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Notes saved locally'), findsOneWidget);

      // The stub writes nothing — the seeded row is unchanged.
      final row = await _profileRow(db, _aliceProfileId);
      expect(row, isNotNull);
      expect(row!.adminNotes, 'Original note');

      await _drainDriftTimers(tester);
    });

    testWidgets('AppBar Edit Profile shows the coming-soon stub SnackBar',
        (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId, userId: _aliceUserId, companyId: _companyId);

      await _pumpDetail(tester, auth: _adminAuth(), clientId: _aliceProfileId);

      await tester.tap(find.byTooltip('Edit Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Profile editing — coming soon'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('Ratings tab renders the average rating', (tester) async {
      await _seedClientProfile(db,
          id: _aliceProfileId,
          userId: _aliceUserId,
          companyId: _companyId,
          averageRating: 4.5);

      await _pumpDetail(tester, auth: _adminAuth(), clientId: _aliceProfileId);

      await tester.tap(find.text('Ratings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('Average Client Rating'), findsOneWidget);

      await _drainDriftTimers(tester);
    });
  });
}
