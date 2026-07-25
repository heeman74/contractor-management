// Team Management — Flutter E2E widget tests.
//
// Exercises the admin Team Management screen end-to-end:
//   UI interaction → Riverpod providers → TeamManagementService →
//   UserDao (real Drift in-memory DB) → reactive stream → UI update.
//
// IMPORTANT — what the SOURCE actually does (differs from a naive spec):
//   * team_management_screen.dart is fully OFFLINE-FIRST. The "Add Member"
//     sheet and "Assign Role" dialog write DIRECTLY to the local Drift DB via
//     TeamManagementService(database: getIt<AppDatabase>()). There is NO Dio /
//     HTTP call in this flow (the sync engine drains the outbox later), so
//     there is nothing to stub with MockDioClient here. We assert on real DB
//     state + reactive UI instead of captured POST paths.
//   * The screen does NOT role-gate the FAB — every authenticated user sees the
//     "Add Member" action. The auth state only supplies companyId, which
//     tenant-scopes the member list. We assert that scoping rather than a
//     non-existent gate.
//
// Coverage:
//   1.  Renders seeded members with names + role chips
//   2.  Empty state when no members
//   3.  Search bar filters members by name
//   4.  Add member happy path → user + role persisted, list updates reactively
//   5.  Validation: empty email shows "Email is required", nothing persisted
//   6.  Validation: malformed email shows "Enter a valid email address"
//   7.  Error path: DB write failure shows "Failed to add member"
//   8.  Assign Role: pick a role in the dialog → role row persisted + chip shown
//   9.  Tenant scoping: members from another company are not shown
//  10.  FAB is visible for a non-admin role (screen does not gate it)
//
// Harness rules (CLAUDE.md + MEMORY.md):
//   * Real Drift AppDatabase(NativeDatabase.memory()) registered in getIt —
//     both the read providers and the write service resolve it from getIt.
//   * ProviderScope overrides authNotifierProvider with a fake AuthNotifier.
//   * pump() / pump(Duration(...)) only — never pumpAndSettle (Drift streams
//     never settle).

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/admin/presentation/screens/team_management_screen.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _companyId = 'company-001';
const _otherCompanyId = 'company-002';
const _adminUserId = 'admin-001';
const _contractorUserId = 'contractor-001';

// ---------------------------------------------------------------------------
// Auth state helpers
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

// ---------------------------------------------------------------------------
// Fake AuthNotifier — supplies a fixed AuthState without hitting getIt<AuthRepository>()
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

// ---------------------------------------------------------------------------
// Seed helpers — write through the real DAO so sync_queue rows are exercised too
// ---------------------------------------------------------------------------

Future<void> _seedCompany(AppDatabase db, String companyId) async {
  final now = DateTime.now();
  await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: Value(companyId),
          name: 'Company $companyId',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _seedMember(
  AppDatabase db, {
  required String id,
  required String email,
  required String companyId,
  String? firstName,
  String? lastName,
  String? role,
}) async {
  final now = DateTime.now();
  await db.userDao.insertUser(
    UsersCompanion.insert(
      id: Value(id),
      companyId: companyId,
      email: email,
      firstName: Value(firstName),
      lastName: Value(lastName),
      createdAt: now,
      updatedAt: now,
    ),
  );
  if (role != null) {
    await db.userDao.assignRole(
      UserRolesCompanion.insert(
        id: Value('role-$id-$role'),
        userId: id,
        companyId: companyId,
        role: role,
        createdAt: now,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget pump helper
// ---------------------------------------------------------------------------

Future<void> _pumpScreen(
  WidgetTester tester, {
  required AuthState auth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier(auth)),
      ],
      child: const MaterialApp(home: TeamManagementScreen()),
    ),
  );
  // Let the Drift StreamProvider emit its first value. NO pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmount the tree and flush the zero-duration Timer that Drift schedules when
/// its query streams are cancelled on ProviderScope disposal. Without this the
/// binding reports "A Timer is still pending even after the widget tree was
/// disposed" (MEMORY.md: Drift streams never settle). Call at the END of every
/// test that mounts the real screen.
Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
}

// Raw one-shot DB reads for assertions. Using .get() (not .watch().first)
// avoids opening yet another Drift stream that would schedule its own close
// timer during the assertion phase.
Future<List<User>> _usersInCompany(AppDatabase db, String companyId) {
  return (db.select(db.users)..where((t) => t.companyId.equals(companyId)))
      .get();
}

Future<List<String>> _roleNamesFor(AppDatabase db, String userId) async {
  final rows =
      await (db.select(db.userRoles)..where((t) => t.userId.equals(userId)))
          .get();
  return rows.map((r) => r.role).toList();
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    if (getIt.isRegistered<AppDatabase>()) {
      getIt.unregister<AppDatabase>();
    }
    getIt.registerSingleton<AppDatabase>(db);
  });

  tearDown(() async {
    await getIt.reset();
    // Some tests close the DB deliberately to force a write failure; closing an
    // already-closed DB throws — tolerate it (test-only cleanup).
    try {
      await db.close();
    } catch (_) {
      // Already closed by the test body.
    }
  });

  group('TeamManagementScreen E2E', () {
    // ─── 1: renders seeded members with names + role chips ─────────────────
    testWidgets('renders the list of existing members with roles',
        (tester) async {
      await _seedCompany(db, _companyId);
      await _seedMember(db,
          id: 'u-admin',
          email: 'ada@team.com',
          firstName: 'Ada',
          lastName: 'Admin',
          companyId: _companyId,
          role: 'admin');
      await _seedMember(db,
          id: 'u-con',
          email: 'carl@team.com',
          firstName: 'Carl',
          lastName: 'Contractor',
          companyId: _companyId,
          role: 'contractor');
      await _seedMember(db,
          id: 'u-cli',
          email: 'cleo@team.com',
          firstName: 'Cleo',
          lastName: 'Client',
          companyId: _companyId,
          role: 'client');

      await _pumpScreen(tester, auth: _adminAuth());

      // Names render
      expect(find.text('Ada Admin'), findsOneWidget);
      expect(find.text('Carl Contractor'), findsOneWidget);
      expect(find.text('Cleo Client'), findsOneWidget);

      // Emails render
      expect(find.text('ada@team.com'), findsOneWidget);

      // Role chips render (displayLabel from UserRole)
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Contractor'), findsOneWidget);
      expect(find.text('Client'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 2: empty state ────────────────────────────────────────────────────
    testWidgets('shows empty state when there are no members', (tester) async {
      await _seedCompany(db, _companyId);

      await _pumpScreen(tester, auth: _adminAuth());

      expect(find.text('No team members yet'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 3: search filters the list ────────────────────────────────────────
    testWidgets('search bar filters members by name', (tester) async {
      await _seedCompany(db, _companyId);
      await _seedMember(db,
          id: 'u-alice',
          email: 'alice@team.com',
          firstName: 'Alice',
          lastName: 'Anderson',
          companyId: _companyId,
          role: 'admin');
      await _seedMember(db,
          id: 'u-bob',
          email: 'bob@team.com',
          firstName: 'Bob',
          lastName: 'Brown',
          companyId: _companyId,
          role: 'contractor');

      await _pumpScreen(tester, auth: _adminAuth());

      expect(find.text('Alice Anderson'), findsOneWidget);
      expect(find.text('Bob Brown'), findsOneWidget);

      // Type into the SearchBar (the only editable field on the screen).
      await tester.enterText(find.byType(TextField).first, 'Alice');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Alice Anderson'), findsOneWidget);
      expect(find.text('Bob Brown'), findsNothing);

      await _drainDriftTimers(tester);
    });

    // ─── 4: add member happy path ──────────────────────────────────────────
    testWidgets(
        'add member: fill form → submit → user + role persisted and list updates',
        (tester) async {
      await _seedCompany(db, _companyId);

      await _pumpScreen(tester, auth: _adminAuth());
      expect(find.text('No team members yet'), findsOneWidget);

      // Open the Add Member bottom sheet via the FAB.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add Team Member'), findsOneWidget);

      // Fill the form (role keeps its default = Contractor).
      await tester.enterText(
          find.widgetWithText(TextField, 'Email *'), 'nadia@team.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'First Name'), 'Nadia');
      await tester.enterText(
          find.widgetWithText(TextField, 'Last Name'), 'Newbie');

      // Submit — the sheet's FilledButton also reads 'Add Member', so target the
      // FilledButton specifically (the FAB shares that label).
      await tester.tap(find.widgetWithText(FilledButton, 'Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Sheet dismissed on success.
      expect(find.text('Add Team Member'), findsNothing);

      // UI assertion: new member card appears in the reactive list.
      expect(find.text('Nadia Newbie'), findsOneWidget);

      // DB assertion: user persisted with the default contractor role.
      final users = await _usersInCompany(db, _companyId);
      expect(users.map((u) => u.email), contains('nadia@team.com'));
      final added = users.firstWhere((u) => u.email == 'nadia@team.com');
      expect(await _roleNamesFor(db, added.id), contains('contractor'));

      await _drainDriftTimers(tester);
    });

    // ─── 5: validation — empty email ───────────────────────────────────────
    testWidgets('add member: empty email shows validation and persists nothing',
        (tester) async {
      await _seedCompany(db, _companyId);

      await _pumpScreen(tester, auth: _adminAuth());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Submit with an empty email.
      await tester.tap(find.widgetWithText(FilledButton, 'Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Email is required'), findsOneWidget);
      // Sheet stays open, nothing written.
      expect(find.text('Add Team Member'), findsOneWidget);
      expect(await _usersInCompany(db, _companyId), isEmpty);

      await _drainDriftTimers(tester);
    });

    // ─── 6: validation — malformed email ───────────────────────────────────
    testWidgets('add member: malformed email shows a format error',
        (tester) async {
      await _seedCompany(db, _companyId);

      await _pumpScreen(tester, auth: _adminAuth());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(
          find.widgetWithText(TextField, 'Email *'), 'not-an-email');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(await _usersInCompany(db, _companyId), isEmpty);

      await _drainDriftTimers(tester);
    });

    // ─── 7: error path — DB write failure ──────────────────────────────────
    testWidgets('add member: write failure surfaces an error message',
        (tester) async {
      await _seedCompany(db, _companyId);

      await _pumpScreen(tester, auth: _adminAuth());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(
          find.widgetWithText(TextField, 'Email *'), 'boom@team.com');

      // Force the underlying write to throw by closing the DB the service will
      // resolve from getIt. The empty member list behind the sheet is unaffected.
      await db.close();

      await tester.tap(find.widgetWithText(FilledButton, 'Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to add member. Please try again.'),
          findsOneWidget);
      // Sheet remains open so the user can retry.
      expect(find.text('Add Team Member'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 8: assign role via the member menu ────────────────────────────────
    testWidgets('assign role: pick a role → role row persisted and chip shown',
        (tester) async {
      await _seedCompany(db, _companyId);
      await _seedMember(db,
          id: 'u-multi',
          email: 'mona@team.com',
          firstName: 'Mona',
          lastName: 'Member',
          companyId: _companyId,
          role: 'contractor');

      await _pumpScreen(tester, auth: _adminAuth());
      expect(find.text('Contractor'), findsOneWidget);

      // Open the row's popup menu and choose "Assign Role".
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Assign Role').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(FilledButton, 'Assign'), findsOneWidget);

      // Select the Admin role from the dropdown (default is Contractor).
      await tester.tap(find.byType(DropdownButtonFormField<UserRole>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Admin').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.widgetWithText(FilledButton, 'Assign'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // DB assertion: the member now holds BOTH contractor and admin roles.
      final roleNames = (await _roleNamesFor(db, 'u-multi')).toSet();
      expect(roleNames, containsAll(<String>{'contractor', 'admin'}));

      // UI assertion: the new Admin chip renders on the member card.
      expect(find.text('Admin'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    // ─── 9: tenant scoping — other company's members hidden ────────────────
    testWidgets('member list is tenant-scoped to the authed company',
        (tester) async {
      await _seedCompany(db, _companyId);
      await _seedCompany(db, _otherCompanyId);
      await _seedMember(db,
          id: 'u-ours',
          email: 'ours@team.com',
          firstName: 'Olive',
          lastName: 'Ours',
          companyId: _companyId,
          role: 'admin');
      await _seedMember(db,
          id: 'u-theirs',
          email: 'theirs@team.com',
          firstName: 'Tara',
          lastName: 'Theirs',
          companyId: _otherCompanyId,
          role: 'admin');

      await _pumpScreen(tester, auth: _adminAuth());

      expect(find.text('Olive Ours'), findsOneWidget);
      expect(find.text('Tara Theirs'), findsNothing);

      await _drainDriftTimers(tester);
    });

    // ─── 10: FAB not role-gated (documents actual behavior) ────────────────
    testWidgets('add-member FAB is visible for a non-admin role',
        (tester) async {
      await _seedCompany(db, _companyId);

      await _pumpScreen(tester, auth: _contractorAuth());

      // The screen intentionally does not gate the primary action by role.
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.widgetWithText(FloatingActionButton, 'Add Member'),
          findsOneWidget);

      await _drainDriftTimers(tester);
    });
  });
}
