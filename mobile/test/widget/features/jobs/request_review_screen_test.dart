/// E2E widget tests for RequestReviewScreen.
///
/// Tests cover:
/// 1. Empty state when no pending requests
/// 2. Request cards render with description, client, urgency badge
/// 3. Accept/Decline/Request Info buttons are present
/// 4. Trade type and budget chips render
///
/// IMPORTANT: Never use pumpAndSettle() — Drift StreamProvider timers
/// cause infinite loops in flushTimers. Use pump() for frames.
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/data/job_dao.dart';
import 'package:contractorhub/features/jobs/presentation/screens/request_review_screen.dart';
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

Future<void> _seedRequest(
  AppDatabase db, {
  required String id,
  String description = 'Fix my roof',
  String urgency = 'normal',
  String? tradeType,
  String? submittedName,
  double? budgetMin,
  double? budgetMax,
  DateTime? createdAt,
}) async {
  final now = createdAt ?? DateTime.now();
  await db.jobDao.insertJobRequest(JobRequestsCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    clientId: const Value('client-1'),
    description: description,
    tradeType: Value(tradeType),
    urgency: Value(urgency),
    budgetMin: Value(budgetMin),
    budgetMax: Value(budgetMax),
    photos: const Value('[]'),
    requestStatus: const Value('pending'),
    submittedName: Value(submittedName),
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
      child: const MaterialApp(home: RequestReviewScreen()),
    );
  }

  group('RequestReviewScreen — empty state', () {
    testWidgets('shows empty state when no pending requests',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump(); // stream emits

      expect(find.text('No pending requests'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('RequestReviewScreen — request cards', () {
    testWidgets('renders request card with description and client name',
        (tester) async {
      await _seedRequest(db,
          id: 'req-1',
          description: 'Fix my leaking roof',
          submittedName: 'Jane Doe');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('Fix my leaking roof'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows URGENT badge for urgent requests', (tester) async {
      await _seedRequest(db,
          id: 'req-1', urgency: 'urgent', description: 'Emergency fix');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('URGENT'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('does not show URGENT badge for normal requests',
        (tester) async {
      await _seedRequest(db,
          id: 'req-1', urgency: 'normal', description: 'Regular job');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('URGENT'), findsNothing);

      await _cleanup(tester);
    });

    testWidgets('shows trade type chip when present', (tester) async {
      await _seedRequest(db,
          id: 'req-1', tradeType: 'plumber', description: 'Pipe work');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('plumber'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows budget range when present', (tester) async {
      await _seedRequest(db,
          id: 'req-1', budgetMin: 500, budgetMax: 1500);

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.textContaining('\$500'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows Accept, Decline, and Request Info buttons',
        (tester) async {
      await _seedRequest(db, id: 'req-1');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('Request Info'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('RequestReviewScreen — action dialogs', () {
    testWidgets('Accept button opens confirmation dialog', (tester) async {
      await _seedRequest(db,
          id: 'req-1', submittedName: 'Jane');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog animation

      expect(find.text('Accept Request'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('Decline button opens decline dialog with reason dropdown',
        (tester) async {
      await _seedRequest(db, id: 'req-1');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.text('Decline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog animation

      expect(find.text('Decline Request'), findsOneWidget);
      expect(find.text('Reason for declining:'), findsOneWidget);
      expect(find.text('Outside service area'), findsOneWidget); // default

      await _cleanup(tester);
    });

    testWidgets('Request Info button opens info dialog', (tester) async {
      await _seedRequest(db, id: 'req-1');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.text('Request Info'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Request More Information'), findsOneWidget);
      expect(find.text('Message to client'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('RequestReviewScreen — sorting', () {
    testWidgets('older requests appear first (highest priority)',
        (tester) async {
      final older = DateTime.now().subtract(const Duration(days: 5));
      final newer = DateTime.now();

      await _seedRequest(db,
          id: 'req-old',
          description: 'Old request',
          createdAt: older);
      await _seedRequest(db,
          id: 'req-new',
          description: 'New request',
          createdAt: newer);

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      // Both should be visible
      expect(find.text('Old request'), findsOneWidget);
      expect(find.text('New request'), findsOneWidget);

      // Old request should appear first (lower index in widget tree)
      final oldPos = tester.getTopLeft(find.text('Old request'));
      final newPos = tester.getTopLeft(find.text('New request'));
      expect(oldPos.dy, lessThan(newPos.dy));

      await _cleanup(tester);
    });
  });
}
