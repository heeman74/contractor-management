// Phase 6 E2E: Time Tracking + Clock In/Out flow
//
// Covers VERIFICATION.md human_verification item #4:
// "Clock in to Job A, then clock in to Job B → Job A auto-clocks out,
// Job B becomes the active pinned card with elapsed timer."
//
// Strategy: Use real Drift in-memory DB for TimeEntryDao, stub TimerNotifier
// for widget tests. Test the full DAO-level clock in/out logic with real DB,
// and test the UI rendering with provider overrides.
// Do NOT use pumpAndSettle() — timer animations never settle.

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/di/service_locator.dart';
import 'package:contractorhub/features/auth/domain/auth_state.dart';
import 'package:contractorhub/features/auth/presentation/providers/auth_provider.dart';
import 'package:contractorhub/features/jobs/data/job_dao.dart';
import 'package:contractorhub/features/jobs/data/time_entry_dao.dart';
import 'package:contractorhub/features/jobs/domain/job_entity.dart';
import 'package:contractorhub/features/jobs/presentation/providers/timer_providers.dart';
import 'package:contractorhub/features/jobs/presentation/screens/timer_screen.dart';
import 'package:contractorhub/features/jobs/presentation/widgets/contractor_job_card.dart';
import 'package:contractorhub/features/jobs/presentation/providers/job_providers.dart';
import 'package:contractorhub/shared/models/user_role.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _contractorAuth = AuthState.authenticated(
  userId: 'contractor-1',
  companyId: 'co-1',
  roles: {UserRole.contractor},
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => _contractorAuth;
}

Future<void> _seedCompany(AppDatabase db) async {
  await db.into(db.companies).insert(CompaniesCompanion.insert(
        id: const Value('co-1'),
        name: 'Test Co',
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

Future<void> _seedJob(AppDatabase db, String id, String desc) async {
  await db.into(db.jobs).insert(JobsCompanion.insert(
        id: Value(id),
        companyId: 'co-1',
        description: desc,
        tradeType: 'plumber',
        status: const Value('scheduled'),
        statusHistory: const Value('[]'),
        priority: const Value('medium'),
        tags: const Value('[]'),
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

JobEntity _makeJob({
  required String id,
  required String description,
  String status = 'scheduled',
}) {
  final now = DateTime.now();
  return JobEntity(
    id: id,
    companyId: 'co-1',
    description: description,
    tradeType: 'plumber',
    status: status,
    statusHistory: const [],
    priority: 'medium',
    tags: const [],
    version: 1,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late AppDatabase db;
  late TimeEntryDao timeEntryDao;
  late JobDao jobDao;

  setUp(() async {
    db = _openTestDb();
    timeEntryDao = TimeEntryDao(db);
    jobDao = JobDao(db);

    await _seedCompany(db);
    await _seedJob(db, 'job-a', 'Fix water heater');
    await _seedJob(db, 'job-b', 'Replace faucet');

    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    getIt.registerSingleton<AppDatabase>(db);
    if (getIt.isRegistered<TimeEntryDao>()) {
      getIt.unregister<TimeEntryDao>();
    }
    getIt.registerSingleton<TimeEntryDao>(timeEntryDao);
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    getIt.registerSingleton<JobDao>(jobDao);
  });

  tearDown(() async {
    if (getIt.isRegistered<TimeEntryDao>()) {
      getIt.unregister<TimeEntryDao>();
    }
    if (getIt.isRegistered<JobDao>()) getIt.unregister<JobDao>();
    if (getIt.isRegistered<AppDatabase>()) getIt.unregister<AppDatabase>();
    await db.close();
  });

  group('Phase 6 E2E: Clock In/Out DAO logic', () {
    test('clockIn creates time entry with null clockedOutAt', () async {
      final entryId = await timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-a',
        contractorId: 'contractor-1',
      );
      expect(entryId, isNotEmpty);

      // Active session should exist
      final active =
          await timeEntryDao.watchActiveSession('contractor-1').first;
      expect(active, isNotNull);
      expect(active!.jobId, equals('job-a'));
      expect(active.clockedOutAt, isNull);
    });

    test('clockOut sets clockedOutAt and duration', () async {
      final entryId = await timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-a',
        contractorId: 'contractor-1',
      );

      await timeEntryDao.clockOut(entryId);

      final active =
          await timeEntryDao.watchActiveSession('contractor-1').first;
      expect(active, isNull); // No active session

      // Verify the entry was completed
      final entries =
          await timeEntryDao.watchEntriesForJob('job-a').first;
      expect(entries.length, equals(1));
      expect(entries.first.clockedOutAt, isNotNull);
      expect(entries.first.durationSeconds, isNotNull);
      expect(entries.first.durationSeconds!, greaterThanOrEqualTo(0));
    });

    test('clockIn to job B auto-clocks-out job A', () async {
      // Clock in to job A
      await timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-a',
        contractorId: 'contractor-1',
      );

      // Verify active on job A
      var active =
          await timeEntryDao.watchActiveSession('contractor-1').first;
      expect(active!.jobId, equals('job-a'));

      // Clock in to job B — should auto-close job A
      await timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-b',
        contractorId: 'contractor-1',
      );

      // Active should now be job B
      active = await timeEntryDao.watchActiveSession('contractor-1').first;
      expect(active, isNotNull);
      expect(active!.jobId, equals('job-b'));

      // Job A entry should be completed
      final jobAEntries =
          await timeEntryDao.watchEntriesForJob('job-a').first;
      expect(jobAEntries.length, equals(1));
      expect(jobAEntries.first.clockedOutAt, isNotNull);
    });

    test('sync queue entries created for clock in and clock out', () async {
      final entryId = await timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-a',
        contractorId: 'contractor-1',
      );

      await timeEntryDao.clockOut(entryId);

      // Check sync queue has time_entry entries
      final syncEntries = await db.select(db.syncQueue).get();
      final timeEntrySyncs =
          syncEntries.where((e) => e.entityType == 'time_entry').toList();
      // At least 2: one CREATE for clock-in, one UPDATE for clock-out
      expect(timeEntrySyncs.length, greaterThanOrEqualTo(2));
    });

    test('multiple sessions for same job accumulate', () async {
      // Session 1
      final id1 = await timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-a',
        contractorId: 'contractor-1',
      );
      await timeEntryDao.clockOut(id1);

      // Session 2
      final id2 = await timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-a',
        contractorId: 'contractor-1',
      );
      await timeEntryDao.clockOut(id2);

      final entries =
          await timeEntryDao.watchEntriesForJob('job-a').first;
      expect(entries.length, equals(2));
    });
  });

  group('Phase 6 E2E: Timer Screen UI', () {
    // Stub TimerNotifier for UI-only tests
    Widget buildTimerScreen({required TimerState timerState}) {
      return ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
          timerNotifierProvider.overrideWith(
            () => _StubTimerNotifier(timerState),
          ),
          timeEntryDaoProvider.overrideWithValue(timeEntryDao),
          timeEntriesForJobProvider.overrideWith(
            (ref, jobId) => Stream.value(<TimeEntry>[]),
          ),
          jobDetailNotifierProvider.overrideWith(
            (ref, jobId) => Stream.value(_makeJob(
              id: jobId,
              description: 'Fix water heater',
            )),
          ),
        ],
        child: const MaterialApp(
          home: TimerScreen(jobId: 'job-a'),
        ),
      );
    }

    testWidgets('idle state shows 00:00:00 and Clock In button',
        (tester) async {
      await tester.pumpWidget(buildTimerScreen(
        timerState: const TimerState(),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('00:00:00'), findsOneWidget);
      expect(find.text('Clock In'), findsOneWidget);
    });

    testWidgets('active state shows elapsed time and Clock Out',
        (tester) async {
      final now = DateTime.now();
      final activeEntry = TimeEntry(
        id: 'entry-1',
        companyId: 'co-1',
        jobId: 'job-a',
        contractorId: 'contractor-1',
        clockedInAt: now.subtract(const Duration(hours: 1)),
        clockedOutAt: null,
        durationSeconds: null,
        sessionStatus: 'active',
        adjustmentLog: '',
        version: 1,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      );

      await tester.pumpWidget(buildTimerScreen(
        timerState: TimerState(
          activeEntry: activeEntry,
          elapsedSeconds: 3661, // 1h 1m 1s
          activeJobId: 'job-a',
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('01:01:01'), findsOneWidget);
      expect(find.text('Clock Out'), findsOneWidget);
      expect(find.text('Recording time'), findsOneWidget);
    });

    testWidgets('active on different job shows warning', (tester) async {
      final now = DateTime.now();
      final activeEntry = TimeEntry(
        id: 'entry-1',
        companyId: 'co-1',
        jobId: 'job-b',
        contractorId: 'contractor-1',
        clockedInAt: now,
        clockedOutAt: null,
        durationSeconds: null,
        sessionStatus: 'active',
        adjustmentLog: '',
        version: 1,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      );

      await tester.pumpWidget(buildTimerScreen(
        timerState: TimerState(
          activeEntry: activeEntry,
          elapsedSeconds: 300,
          activeJobId: 'job-b', // Different from job-a being viewed
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('currently clocked in to another job'),
        findsOneWidget,
      );
      expect(
        find.textContaining('will auto-clock you out'),
        findsOneWidget,
      );
    });

    testWidgets('empty session history shows prompt', (tester) async {
      await tester.pumpWidget(buildTimerScreen(
        timerState: const TimerState(),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('No time sessions yet'), findsOneWidget);
    });
  });

  group('Phase 6 E2E: Contractor Job Card', () {
    Widget buildJobCard({
      required JobEntity job,
      required TimerState timerState,
    }) {
      return ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => _StubAuthNotifier()),
          timerNotifierProvider.overrideWith(
            () => _StubTimerNotifier(timerState),
          ),
          timeEntryDaoProvider.overrideWithValue(timeEntryDao),
          timeEntriesForJobProvider.overrideWith(
            (ref, jobId) => Stream.value(<TimeEntry>[]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContractorJobCard(job: job),
          ),
        ),
      );
    }

    testWidgets('scheduled job shows Clock In button', (tester) async {
      final job = _makeJob(id: 'job-a', description: 'Fix water heater');
      await tester.pumpWidget(buildJobCard(
        job: job,
        timerState: const TimerState(),
      ));
      await tester.pump();

      expect(find.text('Fix water heater'), findsOneWidget);
      expect(find.text('Clock In'), findsOneWidget);
      expect(find.text('Add Note'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
    });

    testWidgets('active job shows highlighted card with Clock Out',
        (tester) async {
      final job = _makeJob(
        id: 'job-a',
        description: 'Fix water heater',
        status: 'in_progress',
      );

      final now = DateTime.now();
      final activeEntry = TimeEntry(
        id: 'entry-1',
        companyId: 'co-1',
        jobId: 'job-a',
        contractorId: 'contractor-1',
        clockedInAt: now,
        clockedOutAt: null,
        durationSeconds: null,
        sessionStatus: 'active',
        adjustmentLog: '',
        version: 1,
        createdAt: now,
        updatedAt: now,
        deletedAt: null,
      );

      await tester.pumpWidget(buildJobCard(
        job: job,
        timerState: TimerState(
          activeEntry: activeEntry,
          elapsedSeconds: 125,
          activeJobId: 'job-a',
        ),
      ));
      await tester.pump();

      expect(find.text('Clock Out'), findsOneWidget);
      // Elapsed time displayed in card
      expect(find.text('00:02:05'), findsOneWidget);
    });

    testWidgets('completed job is dimmed with no action bar', (tester) async {
      final job = _makeJob(
        id: 'job-a',
        description: 'Fix water heater',
        status: 'complete',
      );
      await tester.pumpWidget(buildJobCard(
        job: job,
        timerState: const TimerState(),
      ));
      await tester.pump();

      // Should have Opacity wrapper (dimmed)
      expect(find.byType(Opacity), findsWidgets);

      // No action bar
      expect(find.text('Clock In'), findsNothing);
      expect(find.text('Add Note'), findsNothing);
    });
  });
}

// ─── Stub notifiers for UI tests ──────────────────────────────────────────────

class _StubTimerNotifier extends TimerNotifier {
  _StubTimerNotifier(this._fixedState);
  final TimerState _fixedState;

  @override
  Future<TimerState> build() async => _fixedState;
}

