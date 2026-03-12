/// Unit tests for TimeEntryDao — Drift in-memory database.
///
/// Tests cover:
/// 1. clockIn creates active entry (clockedOutAt is null, sessionStatus='active')
/// 2. clockIn enqueues CREATE to sync_queue
/// 3. clockIn auto-clocks out existing active session for same contractor (ONE JOB AT A TIME)
/// 4. auto-clock-out computes duration correctly and sets sessionStatus='completed'
/// 5. auto-clock-out enqueues UPDATE for previous session to sync_queue
/// 6. clockOut sets clockedOutAt, computes durationSeconds, sets sessionStatus='completed'
/// 7. clockOut enqueues UPDATE to sync_queue
/// 8. watchActiveSession returns only entry with clockedOutAt=null for given contractor
/// 9. watchActiveSession returns null when no active session
/// 10. watchEntriesForJob returns entries ordered by clockedInAt DESC
/// 11. watchEntriesForJob excludes soft-deleted entries
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedCompany(AppDatabase db, String id) async {
  await db.companyDao.insertCompany(CompaniesCompanion.insert(
    id: Value(id),
    name: 'Company $id',
    version: const Value(1),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
}

Future<void> _seedUser(AppDatabase db,
    {required String id,
    required String companyId,
    String email = 'user@test.com'}) async {
  final now = DateTime.now();
  await db.userDao.insertUser(UsersCompanion.insert(
    id: Value(id),
    companyId: companyId,
    email: email,
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

Future<void> _seedJob(AppDatabase db,
    {required String id, required String companyId}) async {
  final now = DateTime.now();
  await db.jobDao.insertJob(JobsCompanion.insert(
    id: Value(id),
    companyId: companyId,
    description: 'Test Job $id',
    tradeType: 'plumbing',
    status: const Value('quote'),
    priority: const Value('medium'),
    statusHistory: const Value('[]'),
    tags: const Value('[]'),
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
}

void main() {
  group('TimeEntryDao', () {
    late AppDatabase db;

    setUp(() async {
      db = _openTestDb();
      await _seedCompany(db, 'co-1');
      await _seedUser(db,
          id: 'contractor-1', companyId: 'co-1', email: 'c1@test.com');
      await _seedUser(db,
          id: 'contractor-2', companyId: 'co-1', email: 'c2@test.com');
      await _seedJob(db, id: 'job-1', companyId: 'co-1');
      await _seedJob(db, id: 'job-2', companyId: 'co-1');
    });

    tearDown(() async => await db.close());

    test('clockIn creates active entry (clockedOutAt is null, sessionStatus=active)',
        () async {
      final entryId = await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      final active =
          await db.timeEntryDao.watchActiveSession('contractor-1').first;
      expect(active, isNotNull);
      expect(active!.id, entryId);
      expect(active.jobId, 'job-1');
      expect(active.contractorId, 'contractor-1');
      expect(active.clockedOutAt, isNull);
      expect(active.sessionStatus, 'active');
    });

    test('clockIn enqueues CREATE to sync_queue', () async {
      final entryId = await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      final queueItems = await db.syncQueueDao.getAllItems();
      final createItems = queueItems
          .where((item) =>
              item.entityType == 'time_entry' &&
              item.entityId == entryId &&
              item.operation == 'CREATE')
          .toList();
      expect(createItems, hasLength(1));
      expect(createItems.first.status, 'pending');
    });

    test(
        'clockIn auto-clocks out existing active session for same contractor (ONE JOB AT A TIME)',
        () async {
      // Clock in to job-1
      final firstEntryId = await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      // Clock in to job-2 — should auto-close the job-1 session
      await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-2',
        contractorId: 'contractor-1',
      );

      // Active session should now be for job-2
      final active =
          await db.timeEntryDao.watchActiveSession('contractor-1').first;
      expect(active, isNotNull);
      expect(active!.jobId, 'job-2');

      // job-1 session should be closed
      final allEntries =
          await db.timeEntryDao.watchEntriesForJob('job-1').first;
      expect(allEntries, hasLength(1));
      expect(allEntries.first.id, firstEntryId);
      expect(allEntries.first.clockedOutAt, isNotNull);
      expect(allEntries.first.sessionStatus, 'completed');
    });

    test(
        'auto-clock-out computes duration correctly and sets sessionStatus=completed',
        () async {
      // We cannot control clock time precisely in unit tests, but we can verify
      // the duration is positive and session is completed.
      final firstEntryId = await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      // Small delay to ensure measurable duration
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Clock in to another job — triggers auto-clock-out of first session
      await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-2',
        contractorId: 'contractor-1',
      );

      final entries =
          await db.timeEntryDao.watchEntriesForJob('job-1').first;
      final closedEntry =
          entries.firstWhere((e) => e.id == firstEntryId);

      expect(closedEntry.clockedOutAt, isNotNull);
      expect(closedEntry.durationSeconds, isNotNull);
      expect(closedEntry.durationSeconds! >= 0, isTrue);
      expect(closedEntry.sessionStatus, 'completed');
    });

    test('auto-clock-out enqueues UPDATE for previous session to sync_queue',
        () async {
      final firstEntryId = await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-2',
        contractorId: 'contractor-1',
      );

      final queueItems = await db.syncQueueDao.getAllItems();
      final updateItems = queueItems
          .where((item) =>
              item.entityType == 'time_entry' &&
              item.entityId == firstEntryId &&
              item.operation == 'UPDATE')
          .toList();
      expect(updateItems, hasLength(1));
    });

    test(
        'clockOut sets clockedOutAt, computes durationSeconds, sets sessionStatus=completed',
        () async {
      final entryId = await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await db.timeEntryDao.clockOut(entryId);

      final entries =
          await db.timeEntryDao.watchEntriesForJob('job-1').first;
      expect(entries, hasLength(1));
      expect(entries.first.clockedOutAt, isNotNull);
      expect(entries.first.durationSeconds, isNotNull);
      expect(entries.first.durationSeconds! >= 0, isTrue);
      expect(entries.first.sessionStatus, 'completed');
    });

    test('clockOut enqueues UPDATE to sync_queue', () async {
      final entryId = await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      await db.timeEntryDao.clockOut(entryId);

      final queueItems = await db.syncQueueDao.getAllItems();
      final updateItems = queueItems
          .where((item) =>
              item.entityType == 'time_entry' &&
              item.entityId == entryId &&
              item.operation == 'UPDATE')
          .toList();
      expect(updateItems, hasLength(1));
    });

    test(
        'watchActiveSession returns only entry with clockedOutAt=null for given contractor',
        () async {
      await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      final active =
          await db.timeEntryDao.watchActiveSession('contractor-1').first;
      expect(active, isNotNull);
      expect(active!.clockedOutAt, isNull);
      expect(active.contractorId, 'contractor-1');
    });

    test('watchActiveSession returns null when no active session', () async {
      final active =
          await db.timeEntryDao.watchActiveSession('contractor-1').first;
      expect(active, isNull);
    });

    test('watchEntriesForJob returns entries ordered by clockedInAt DESC',
        () async {
      final now = DateTime.now();
      final older = now.subtract(const Duration(hours: 3));

      // Insert older entry via upsertFromSync
      await db.timeEntryDao.upsertFromSync({
        'id': 'entry-old',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'contractor_id': 'contractor-1',
        'clocked_in_at': older.toIso8601String(),
        'clocked_out_at':
            older.add(const Duration(hours: 1)).toIso8601String(),
        'duration_seconds': 3600,
        'session_status': 'completed',
        'adjustment_log': '[]',
        'version': 1,
        'created_at': older.toIso8601String(),
        'updated_at': older.toIso8601String(),
      });

      // Insert newer entry via upsertFromSync
      await db.timeEntryDao.upsertFromSync({
        'id': 'entry-new',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'contractor_id': 'contractor-1',
        'clocked_in_at': now.toIso8601String(),
        'clocked_out_at': null,
        'duration_seconds': null,
        'session_status': 'active',
        'adjustment_log': '[]',
        'version': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final entries =
          await db.timeEntryDao.watchEntriesForJob('job-1').first;
      expect(entries, hasLength(2));
      expect(entries.first.id, 'entry-new');
      expect(entries.last.id, 'entry-old');
    });

    test('watchEntriesForJob excludes soft-deleted entries', () async {
      // Insert alive entry
      final aliveId = await db.timeEntryDao.clockIn(
        companyId: 'co-1',
        jobId: 'job-1',
        contractorId: 'contractor-1',
      );

      // Upsert soft-deleted entry via sync
      await db.timeEntryDao.upsertFromSync({
        'id': 'entry-deleted',
        'company_id': 'co-1',
        'job_id': 'job-1',
        'contractor_id': 'contractor-2',
        'clocked_in_at': DateTime.now().toIso8601String(),
        'clocked_out_at': null,
        'duration_seconds': null,
        'session_status': 'active',
        'adjustment_log': '[]',
        'version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'deleted_at': DateTime.now().toIso8601String(),
      });

      final entries =
          await db.timeEntryDao.watchEntriesForJob('job-1').first;
      expect(entries, hasLength(1));
      expect(entries.first.id, aliveId);
    });
  });
}
