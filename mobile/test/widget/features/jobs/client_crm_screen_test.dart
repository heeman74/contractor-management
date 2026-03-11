/// E2E widget tests for ClientCrmScreen.
///
/// Tests cover:
/// 1. Empty state when no clients
/// 2. Search bar filters clients
/// 3. Client cards render
/// 4. FAB opens Add Client guidance dialog
/// 5. Search clear button resets
/// 6. No-match search state
///
/// IMPORTANT: Never use pumpAndSettle() — Drift StreamProvider timers
/// cause infinite loops in flushTimers. Use pump() for frames.
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/data/job_dao.dart';
import 'package:contractorhub/features/jobs/presentation/screens/client_crm_screen.dart';
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

Future<void> _seedClientProfile(
  AppDatabase db, {
  required String id,
  String userId = 'client-user-1',
  String? adminNotes,
  String tags = '[]',
  String? referralSource,
  String? billingAddress,
}) async {
  final now = DateTime.now();
  await db.jobDao.insertClientProfile(ClientProfilesCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    userId: userId,
    adminNotes: Value(adminNotes),
    tags: Value(tags),
    referralSource: Value(referralSource),
    billingAddress: Value(billingAddress),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
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

    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    getIt.registerSingleton<JobDao>(db.jobDao);
  });

  tearDown(() async {
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    await db.close();
  });

  Widget buildWidget() {
    return ProviderScope(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(_adminState)),
      ],
      child: const MaterialApp(home: ClientCrmScreen()),
    );
  }

  group('ClientCrmScreen — empty state', () {
    testWidgets('shows empty state when no clients', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump(); // stream emits

      expect(find.text('No clients yet'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('ClientCrmScreen — client list', () {
    testWidgets('renders client cards', (tester) async {
      await _seedClientProfile(db,
          id: 'cp-1', userId: 'alice-client');

      await tester.pumpWidget(buildWidget());
      await tester.pump(); // clients stream
      await tester.pump(); // nested job history stream

      // ClientCard shows the userId as display name
      expect(find.text('alice-client'), findsWidgets);

      await _cleanup(tester);
    });
  });

  group('ClientCrmScreen — search', () {
    testWidgets('search filters by admin notes', (tester) async {
      await _seedClientProfile(db,
          id: 'cp-1',
          userId: 'user-a',
          adminNotes: 'VIP customer');
      await _seedClientProfile(db,
          id: 'cp-2', userId: 'user-b', adminNotes: 'Regular');

      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump();

      // Both visible initially
      expect(find.text('user-a'), findsWidgets);
      expect(find.text('user-b'), findsWidgets);

      // Search for VIP
      await tester.enterText(find.byType(SearchBar), 'VIP');
      await tester.pump();

      expect(find.text('user-a'), findsWidgets);
      expect(find.text('user-b'), findsNothing);

      await _cleanup(tester);
    });

    testWidgets('search filters by tags', (tester) async {
      await _seedClientProfile(db,
          id: 'cp-1',
          userId: 'user-tagged',
          tags: '["premium","residential"]');

      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(SearchBar), 'premium');
      await tester.pump();

      expect(find.text('user-tagged'), findsWidgets);

      await _cleanup(tester);
    });

    testWidgets('shows no-match state for search with no results',
        (tester) async {
      await _seedClientProfile(db, id: 'cp-1', userId: 'user-a');

      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(SearchBar), 'zzzznonexistent');
      await tester.pump();

      expect(find.text('No clients match your search'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('clear button resets search', (tester) async {
      await _seedClientProfile(db, id: 'cp-1', userId: 'user-a');

      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(SearchBar), 'zzzzz');
      await tester.pump();
      expect(find.text('No clients match your search'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(find.text('user-a'), findsWidgets);

      await _cleanup(tester);
    });
  });

  group('ClientCrmScreen — FAB', () {
    testWidgets('Add Client FAB opens guidance dialog', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Add Client'), findsOneWidget);

      await tester.tap(find.text('Add Client'));
      await tester.pump();
      await tester.pump(); // dialog frame

      // Dialog title "Add Client" appears as dialog heading
      expect(find.text('OK'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('ClientCrmScreen — AppBar', () {
    testWidgets('shows Clients title', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Clients'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows search bar hint text', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(
          find.text('Search clients by name, tag, or note…'), findsOneWidget);

      await _cleanup(tester);
    });
  });
}
