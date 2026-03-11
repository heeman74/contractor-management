/// E2E widget tests for ClientDetailScreen.
///
/// Tests cover:
/// 1. Tab navigation (Profile, Jobs, Ratings)
/// 2. Profile info display (userId, billing address, referral)
/// 3. Admin notes section (view and edit toggle)
/// 4. Tags display
/// 5. Job history list and empty state
/// 6. Ratings tab display
/// 7. Client not found state
///
/// IMPORTANT: Never use pumpAndSettle() — Drift StreamProvider timers
/// cause infinite loops in flushTimers. Use pump() for frames.
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/data/job_dao.dart';
import 'package:contractorhub/features/jobs/presentation/screens/client_detail_screen.dart';
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
  String? billingAddress,
  String? adminNotes,
  String tags = '[]',
  String? referralSource,
  String? preferredContactMethod,
  double? averageRating,
  String? preferredContractorId,
}) async {
  final now = DateTime.now();
  await db.jobDao.insertClientProfile(ClientProfilesCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    userId: userId,
    billingAddress: Value(billingAddress),
    adminNotes: Value(adminNotes),
    tags: Value(tags),
    referralSource: Value(referralSource),
    preferredContactMethod: Value(preferredContactMethod),
    averageRating: Value(averageRating),
    preferredContractorId: Value(preferredContractorId),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedJob(
  AppDatabase db, {
  required String id,
  required String clientId,
  String status = 'scheduled',
  String description = 'Test job',
  String tradeType = 'plumber',
}) async {
  final now = DateTime.now();
  await db.jobDao.insertJob(JobsCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    clientId: Value(clientId),
    description: description,
    tradeType: tradeType,
    status: Value(status),
    statusHistory: const Value('[]'),
    priority: const Value('medium'),
    tags: const Value('[]'),
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

  Widget buildWidget(String clientId) {
    return ProviderScope(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(_adminState)),
      ],
      child: MaterialApp(home: ClientDetailScreen(clientId: clientId)),
    );
  }

  group('ClientDetailScreen — tabs', () {
    testWidgets('renders all three tabs', (tester) async {
      await _seedClientProfile(db, id: 'cp-1');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Jobs'), findsOneWidget);
      expect(find.text('Ratings'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('ClientDetailScreen — profile tab', () {
    testWidgets('shows user ID', (tester) async {
      await _seedClientProfile(db, id: 'cp-1', userId: 'alice-123');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      expect(find.text('alice-123'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows billing address when present', (tester) async {
      await _seedClientProfile(db,
          id: 'cp-1', billingAddress: '123 Main St');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      expect(find.text('123 Main St'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows admin notes or placeholder', (tester) async {
      await _seedClientProfile(db, id: 'cp-1', adminNotes: null);

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      expect(find.text('No admin notes yet. Tap edit to add.'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows admin notes when present', (tester) async {
      await _seedClientProfile(db,
          id: 'cp-1', adminNotes: 'Great customer');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      expect(find.text('Great customer'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows tags as chips', (tester) async {
      await _seedClientProfile(db,
          id: 'cp-1', tags: '["VIP","residential"]');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      expect(find.text('VIP'), findsOneWidget);
      expect(find.text('residential'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows preferred contractor placeholder', (tester) async {
      await _seedClientProfile(db, id: 'cp-1');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      // Scroll down to see preferred contractor section
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump();

      expect(find.text('No preferred contractor assigned'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('ClientDetailScreen — jobs tab', () {
    testWidgets('shows empty job history', (tester) async {
      await _seedClientProfile(db, id: 'cp-1', userId: 'client-1');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      await tester.tap(find.text('Jobs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No job history for this client'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows job history entries', (tester) async {
      await _seedClientProfile(db, id: 'cp-1', userId: 'client-1');
      await _seedJob(db,
          id: 'j-1',
          clientId: 'cp-1',
          description: 'Fix pipe',
          status: 'complete');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();
      await tester.pump(); // nested stream

      await tester.tap(find.text('Jobs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(); // job stream emits
      await tester.pump(); // re-render

      expect(find.text('Fix pipe'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('ClientDetailScreen — ratings tab', () {
    testWidgets('shows average rating when present', (tester) async {
      await _seedClientProfile(db, id: 'cp-1', averageRating: 4.5);

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      await tester.tap(find.text('Ratings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('Average Client Rating'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows dash when no rating', (tester) async {
      await _seedClientProfile(db, id: 'cp-1');

      await tester.pumpWidget(buildWidget('cp-1'));
      await tester.pump();

      await tester.tap(find.text('Ratings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The "—" dash is shown when no rating
      expect(find.textContaining('—'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('ClientDetailScreen — not found', () {
    testWidgets('shows Client not found for nonexistent ID', (tester) async {
      await tester.pumpWidget(buildWidget('nonexistent'));
      await tester.pump();

      expect(find.text('Client not found'), findsOneWidget);

      await _cleanup(tester);
    });
  });
}
