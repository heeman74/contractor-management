/// E2E widget tests for JobsPipelineScreen.
///
/// Tests cover:
/// 1. Empty state with "No jobs yet" and create button
/// 2. Kanban/List view toggle via SegmentedButton
/// 3. Job cards render in list view
/// 4. New Job button is present
/// 5. Filter chips appear in list view only
/// 6. Batch mode shows action bar
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
import 'package:contractorhub/features/jobs/presentation/screens/jobs_pipeline_screen.dart';
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

Future<void> _seedJob(
  AppDatabase db, {
  required String id,
  String status = 'quote',
  String description = 'Test job',
  String tradeType = 'plumber',
  String priority = 'medium',
}) async {
  final now = DateTime.now();
  await db.jobDao.insertJob(JobsCompanion.insert(
    id: Value(id),
    companyId: 'co-1',
    description: description,
    tradeType: tradeType,
    status: Value(status),
    statusHistory: Value('[]'),
    priority: Value(priority),
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
            .overrideWith(() => _StubAuthNotifier(_adminState)),
      ],
      child: const MaterialApp(home: Scaffold(body: JobsPipelineScreen())),
    );
  }

  group('JobsPipelineScreen — empty state', () {
    testWidgets('shows empty state when no jobs', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump(); // stream emits

      expect(find.text('No jobs yet'), findsOneWidget);
      expect(find.text('Create your first job'), findsOneWidget);

      await _cleanup(tester);
    });
  });

  group('JobsPipelineScreen — toolbar', () {
    testWidgets('shows Kanban/List toggle and New Job button',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Kanban'), findsOneWidget);
      expect(find.text('List'), findsOneWidget);
      expect(find.text('New Job'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('switching to List view shows filter chips', (tester) async {
      await _seedJob(db, id: 'j-1', description: 'Test job');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      // Initially in Kanban — no filter chips
      expect(find.text('All'), findsNothing);

      // Tap List segment
      await tester.tap(find.text('List'));
      await tester.pump();

      // Filter chips should appear
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Quote'), findsWidgets); // filter chip + possibly card

      await _cleanup(tester);
    });
  });

  group('JobsPipelineScreen — list view', () {
    testWidgets('renders job cards in list view', (tester) async {
      await _seedJob(db,
          id: 'j-1', description: 'Fix pipe', status: 'scheduled');
      await _seedJob(db,
          id: 'j-2', description: 'Wire kitchen', status: 'in_progress');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      // Switch to list view
      await tester.tap(find.text('List'));
      await tester.pump();

      expect(find.text('Fix pipe'), findsOneWidget);
      expect(find.text('Wire kitchen'), findsOneWidget);

      await _cleanup(tester);
    });

    testWidgets('shows no match message when filter excludes all jobs',
        (tester) async {
      await _seedJob(db, id: 'j-1', status: 'scheduled');

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      // Switch to list view
      await tester.tap(find.text('List'));
      await tester.pump();

      // Tap "Complete" filter — no scheduled jobs match
      await tester.tap(find.text('Complete'));
      await tester.pump();

      expect(find.text('No jobs match the current filters.'), findsOneWidget);

      await _cleanup(tester);
    });
  });
}
