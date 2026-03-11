/// E2E widget tests for TeamManagementScreen.
///
/// Tests cover:
/// 1. Empty state renders when no users
/// 2. Member cards render with name, email, role chips
/// 3. Search filtering by name and email
/// 4. Add Member bottom sheet validation and submission
/// 5. Assign Role dialog submission
/// 6. Auto-creation of ClientProfile when client role assigned
///
/// IMPORTANT: Never use pumpAndSettle() — Drift StreamProvider timers
/// cause infinite loops in flushTimers. Use pump() for frames, and
/// pump(Duration) ONLY for modal bottom sheet / dialog animations.
/// Never use pump(Duration) with dropdown overlays — use
/// FormFieldState.didChange() instead.
library;

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
// Helpers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;
  @override
  AuthState build() => _fixedState;
}

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _adminState = AuthState.authenticated(
  userId: 'admin-1',
  companyId: 'co-1',
  roles: {UserRole.admin},
);

Future<void> _seedCompany(AppDatabase db) async {
  await db.into(db.companies).insert(CompaniesCompanion.insert(
        id: const Value('co-1'),
        name: 'Test Co',
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

Future<void> _seedUser(
  AppDatabase db, {
  required String id,
  String email = 'user@test.com',
  String? firstName,
  String? lastName,
  String? phone,
}) async {
  final now = DateTime.now();
  await db.userDao.insertUser(UsersCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    email: email,
    firstName: Value(firstName),
    lastName: Value(lastName),
    phone: Value(phone),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedRole(AppDatabase db,
    {required String userId, required String role}) async {
  await db.userDao.assignRole(UserRolesCompanion.insert(
    id: Value('role-$userId-$role'),
    userId: userId,
    companyId: 'co-1',
    role: role,
    createdAt: DateTime.now(),
  ));
}

/// Dispose widget tree so Drift stream timers complete before test ends.
Future<void> _cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

/// Scroll the bottom sheet form down and tap the submit button.
Future<void> _scrollAndTapSubmit(WidgetTester tester) async {
  await tester.drag(
      find.byType(SingleChildScrollView).last, const Offset(0, -500));
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Add Member').last);
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openTestDb();
    await _seedCompany(db);

    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    getIt.registerSingleton<AppDatabase>(db);
  });

  tearDown(() async {
    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    await db.close();
  });

  Widget buildWidget() {
    return ProviderScope(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(_adminState)),
      ],
      child: const MaterialApp(home: TeamManagementScreen()),
    );
  }

  group('TeamManagementScreen — empty state', () {
    testWidgets('shows empty state when no members', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('No team members yet'), findsOneWidget);
      expect(find.text('Add Member'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('TeamManagementScreen — member list', () {
    testWidgets('renders member cards with name, email, and role chips',
        (tester) async {
      await _seedUser(db,
          id: 'u-1',
          email: 'alice@test.com',
          firstName: 'Alice',
          lastName: 'Smith');
      await _seedRole(db, userId: 'u-1', role: 'admin');

      await tester.pumpWidget(buildWidget());
      await tester.pump(); // users stream emits
      await tester.pump(); // nested userRolesProvider emits

      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.text('alice@test.com'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows email as fallback when no name', (tester) async {
      await _seedUser(db, id: 'u-1', email: 'noname@test.com');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('noname@test.com'), findsWidgets);

      await _cleanup(tester);
    });

    testWidgets('shows color-coded role chips', (tester) async {
      await _seedUser(db,
          id: 'u-1', email: 'multi@test.com', firstName: 'Bob');
      await _seedRole(db, userId: 'u-1', role: 'admin');
      await _seedRole(db, userId: 'u-1', role: 'contractor');

      await tester.pumpWidget(buildWidget());
      await tester.pump(); // users stream emits
      await tester.pump(); // nested userRolesProvider emits

      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Contractor'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows phone when present', (tester) async {
      await _seedUser(db,
          id: 'u-1',
          email: 'phone@test.com',
          firstName: 'Carl',
          phone: '555-1234');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('555-1234'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('TeamManagementScreen — search filtering', () {
    testWidgets('filters by name', (tester) async {
      await _seedUser(db,
          id: 'u-1', email: 'alice@test.com', firstName: 'Alice');
      await _seedUser(db,
          id: 'u-2', email: 'bob@test.com', firstName: 'Bob');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'alice');
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);

      await _cleanup(tester);
    });

    testWidgets('filters by email', (tester) async {
      await _seedUser(db,
          id: 'u-1', email: 'alice@test.com', firstName: 'Alice');
      await _seedUser(db,
          id: 'u-2', email: 'bob@other.com', firstName: 'Bob');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.enterText(find.byType(SearchBar), 'other.com');
      await tester.pump();

      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows no-results state when search has no matches',
        (tester) async {
      await _seedUser(db, id: 'u-1', email: 'alice@test.com');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.enterText(find.byType(SearchBar), 'zzzzz');
      await tester.pump();

      expect(find.text('No members match your search'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('clear button resets search', (tester) async {
      await _seedUser(db,
          id: 'u-1', email: 'alice@test.com', firstName: 'Alice');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.enterText(find.byType(SearchBar), 'zzzzz');
      await tester.pump();
      expect(find.text('No members match your search'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('TeamManagementScreen — Add Member', () {
    testWidgets('FAB opens bottom sheet with form fields', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.text('Add Member'));
      await tester.pump();

      expect(find.text('Add Team Member'), findsOneWidget);
      expect(find.text('Email *'), findsOneWidget);
      expect(find.text('First Name'), findsOneWidget);
      expect(find.text('Last Name'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('validates email is required', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.text('Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // bottom sheet animation

      // Scroll to submit and tap without entering email
      await _scrollAndTapSubmit(tester);

      expect(find.text('Email is required'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('validates email format', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.text('Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // bottom sheet animation

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'), 'notanemail');

      await _scrollAndTapSubmit(tester);

      expect(find.text('Enter a valid email address'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('successful submission creates user in Drift DB',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.text('Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // bottom sheet animation

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'), 'new@test.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'First Name'), 'New');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Last Name'), 'User');

      // Invoke submit directly — drag() uses pump(Duration) internally
      // which can hang with Drift stream timers.
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Add Member').last);
      button.onPressed!();
      await tester.pump();
      await tester.pump(); // async DB operations complete

      // Verify user was created in DB (use direct query, not stream)
      final users = await (db.select(db.users)
            ..where((t) => t.companyId.equals('co-1')))
          .get();
      expect(users.any((u) => u.email == 'new@test.com'), isTrue);

      // Verify role was assigned
      final newUser = users.firstWhere((u) => u.email == 'new@test.com');
      final roles = await (db.select(db.userRoles)
            ..where((t) => t.userId.equals(newUser.id)))
          .get();
      expect(roles, hasLength(1));
      expect(roles.first.role, 'contractor'); // Drift stores as String

      await _cleanup(tester);
    });

    testWidgets(
        'adding member with client role auto-creates ClientProfile',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.text('Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // bottom sheet animation

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'), 'client@test.com');

      // Set role via FormFieldState — opening the dropdown overlay would
      // require pump(Duration) which hangs with Drift stream timers.
      final dropdownState = tester.state<FormFieldState<UserRole>>(
          find.byType(DropdownButtonFormField<UserRole>).last);
      dropdownState.didChange(UserRole.client);
      await tester.pump();

      // Invoke submit directly — drag() uses pump(Duration) internally
      // which can hang with Drift stream timers.
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Add Member').last);
      button.onPressed!();
      await tester.pump();
      await tester.pump(); // async DB operations complete

      // Verify ClientProfile was created (use direct query, not stream)
      final profiles = await (db.select(db.clientProfiles)
            ..where((t) => t.companyId.equals('co-1')))
          .get();
      expect(profiles, hasLength(1));

      await _cleanup(tester);
    });

    testWidgets('new member appears in list after submission',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('No team members yet'), findsOneWidget);

      await tester.tap(find.text('Add Member'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // bottom sheet animation

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email *'), 'new@test.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'First Name'), 'Fresh');

      // Invoke submit directly — drag() uses pump(Duration) internally
      // which can hang with Drift stream timers.
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Add Member').last);
      button.onPressed!();
      await tester.pump(); // form submits, DB insert runs
      await tester.pump(); // Drift stream re-emits
      await tester.pump(const Duration(milliseconds: 500)); // bottom sheet dismiss

      // Member should now appear in the list
      expect(find.text('No team members yet'), findsNothing);
      expect(find.text('Fresh'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('TeamManagementScreen — Assign Role', () {
    testWidgets('popup menu shows Assign Role option', (tester) async {
      await _seedUser(db,
          id: 'u-1', email: 'alice@test.com', firstName: 'Alice');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();

      expect(find.text('Assign Role'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('assign role dialog creates role in DB', (tester) async {
      await _seedUser(db,
          id: 'u-1', email: 'alice@test.com', firstName: 'Alice');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // popup open animation

      await tester.tap(find.text('Assign Role'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // popup close
      await tester.pump(); // onSelected → showDialog
      await tester.pump(const Duration(milliseconds: 300)); // dialog animation

      // Dialog should appear
      expect(find.text('Assign'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Submit with default role (contractor) — invoke directly
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Assign'));
      button.onPressed!();
      await tester.pump();
      await tester.pump();

      // Verify role was assigned (direct query, not stream)
      final roles = await (db.select(db.userRoles)
            ..where((t) => t.userId.equals('u-1')))
          .get();
      expect(roles, hasLength(1));
      expect(roles.first.role, 'contractor');

      await _cleanup(tester);
    });

    testWidgets(
        'assigning client role via dialog creates ClientProfile',
        (tester) async {
      await _seedUser(db,
          id: 'u-1', email: 'alice@test.com', firstName: 'Alice');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // popup open animation

      await tester.tap(find.text('Assign Role'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // popup close
      await tester.pump(); // onSelected → showDialog
      await tester.pump(const Duration(milliseconds: 300)); // dialog animation

      // Set dropdown to Client via FormFieldState
      final dropdownState = tester.state<FormFieldState<UserRole>>(
          find.byType(DropdownButtonFormField<UserRole>).last);
      dropdownState.didChange(UserRole.client);
      await tester.pump();

      // Submit via callback — avoid tap/drag with Drift streams
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Assign'));
      button.onPressed!();
      await tester.pump();
      await tester.pump();

      // Verify ClientProfile created (direct query, not stream)
      final profiles = await (db.select(db.clientProfiles)
            ..where((t) => t.companyId.equals('co-1')))
          .get();
      expect(profiles, hasLength(1));
      expect(profiles.first.userId, 'u-1');

      await _cleanup(tester);
    });
  });
}
