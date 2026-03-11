/// E2E widget tests for ContractorJobsScreen.
///
/// Tests cover:
/// 1. Empty state when no jobs assigned
/// 2. Job cards render with status badges, description, trade type
/// 3. Section headers (Today/Upcoming/Completed) with counts
/// 4. Start Work button for scheduled jobs
/// 5. Mark Complete button for in-progress jobs
/// 6. Status transitions write to Drift DB
///
/// IMPORTANT: Never use pumpAndSettle() — Drift StreamProvider timers
/// cause infinite loops in flushTimers. Use pump() for frames.
library;

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/core/sync/sync_engine.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/data/job_dao.dart';
import 'package:contractorhub/features/jobs/presentation/screens/contractor_jobs_screen.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AuthState _fixedState;
  @override
  AuthState build() => _fixedState;
}

class _MockSyncEngine extends Mock implements SyncEngine {}

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _contractorState = AuthState.authenticated(
  userId: 'contractor-1',
  companyId: 'co-1',
  roles: {UserRole.contractor},
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

Future<void> _seedJob(
  AppDatabase db, {
  required String id,
  required String status,
  String description = 'Test job',
  String tradeType = 'plumber',
  String contractorId = 'contractor-1',
  String priority = 'medium',
  DateTime? scheduledCompletion,
}) async {
  final now = DateTime.now();
  await db.jobDao.insertJob(JobsCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    contractorId: Value(contractorId),
    description: description,
    tradeType: tradeType,
    status: Value(status),
    statusHistory: Value('[{"status":"$status","timestamp":"${now.toIso8601String()}"}]'),
    priority: Value(priority),
    tags: const Value('[]'),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
    scheduledCompletionDate: Value(scheduledCompletion),
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

    final mockSync = _MockSyncEngine();
    when(() => mockSync.syncNow()).thenAnswer((_) async {});
    if (getIt.isRegistered<SyncEngine>()) getIt.unregister<SyncEngine>();
    getIt.registerSingleton<SyncEngine>(mockSync);
  });

  tearDown(() async {
    if (getIt.isRegistered<SyncEngine>()) getIt.unregister<SyncEngine>();
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    await db.close();
  });

  Widget buildWidget() {
    return ProviderScope(
      overrides: [
        authNotifierProvider
            .overrideWith(() => _StubAuthNotifier(_contractorState)),
      ],
      child: const MaterialApp(home: ContractorJobsScreen()),
    );
  }

  group('ContractorJobsScreen — empty state', () {
    testWidgets('shows empty state when no jobs assigned', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump(); // stream emits

      expect(find.text('No jobs assigned to you'), findsOneWidget);
      expect(find.textContaining('Pull down to sync'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('ContractorJobsScreen — job cards', () {
    testWidgets('renders scheduled job with Start Work button',
        (tester) async {
      await _seedJob(db,
          id: 'j-1',
          status: 'scheduled',
          description: 'Fix pipe',
          tradeType: 'plumber');

      await tester.pumpWidget(buildWidget());
      await tester.pump(); // stream emits

      expect(find.text('Fix pipe'), findsOneWidget);
      expect(find.text('plumber'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Start Work'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('renders in-progress job with Mark Complete button',
        (tester) async {
      await _seedJob(db,
          id: 'j-2',
          status: 'in_progress',
          description: 'Wire kitchen');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Wire kitchen'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Mark Complete'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('completed job has no action button', (tester) async {
      await _seedJob(db,
          id: 'j-3', status: 'complete', description: 'Paint walls');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Paint walls'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Start Work'), findsNothing);
      expect(find.text('Mark Complete'), findsNothing);

      await _cleanup(tester);
    });

    testWidgets('shows priority label', (tester) async {
      await _seedJob(db,
          id: 'j-4', status: 'scheduled', priority: 'high');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('HIGH'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('ContractorJobsScreen — status transitions', () {
    testWidgets('Start Work transitions scheduled to in_progress',
        (tester) async {
      await _seedJob(db, id: 'j-1', status: 'scheduled');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      // Invoke Start Work button directly
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Start Work'));
      button.onPressed!();
      await tester.pump();
      await tester.pump(); // DB write completes

      // Verify status changed in DB
      final jobs = await (db.select(db.jobs)
            ..where((t) => t.id.equals('j-1')))
          .get();
      expect(jobs.first.status, 'in_progress');

      await _cleanup(tester);
    });

    testWidgets('Mark Complete transitions in_progress to complete',
        (tester) async {
      await _seedJob(db, id: 'j-2', status: 'in_progress');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Mark Complete'));
      button.onPressed!();
      await tester.pump();
      await tester.pump();

      final jobs = await (db.select(db.jobs)
            ..where((t) => t.id.equals('j-2')))
          .get();
      expect(jobs.first.status, 'complete');

      await _cleanup(tester);
    });
  });

  group('ContractorJobsScreen — section headers', () {
    testWidgets('shows Completed section header for completed jobs',
        (tester) async {
      await _seedJob(db, id: 'j-1', status: 'complete');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Completed'), findsOneWidget);

      await _cleanup(tester);
    });
  });
}
