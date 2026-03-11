import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/time_entries.dart';
import '../../../core/database/tables/sync_queue.dart';

part 'time_entry_dao.g.dart';

/// Drift DAO for TimeEntry CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Key invariant: at most ONE active session per contractor at any time.
/// [clockIn] enforces this by auto-closing any existing open session before
/// creating the new entry.
///
/// Every mutating method uses [db.transaction] to atomically write to BOTH
/// the time_entries table AND sync_queue outbox. If either write fails, both
/// are rolled back — no orphaned queue items, no untracked mutations.
@DriftAccessor(
  tables: [TimeEntries, SyncQueue],
)
class TimeEntryDao extends DatabaseAccessor<AppDatabase>
    with _$TimeEntryDaoMixin {
  TimeEntryDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Time entry streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of the active session for a contractor.
  ///
  /// Returns a stream of at most one [TimeEntry] — the open session where
  /// [clockedOutAt] is null. Returns null if no active session exists.
  Stream<TimeEntry?> watchActiveSession(String contractorId) {
    return (select(timeEntries)
          ..where(
            (tbl) =>
                tbl.contractorId.equals(contractorId) &
                tbl.clockedOutAt.isNull() &
                tbl.deletedAt.isNull(),
          )
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Reactive stream of time entries for a job.
  ///
  /// Ordered newest-first for the time tracking list view.
  Stream<List<TimeEntry>> watchEntriesForJob(String jobId) {
    return (select(timeEntries)
          ..where(
            (tbl) => tbl.jobId.equals(jobId) & tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.clockedInAt)]))
        .watch();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Clock in / Clock out mutations
  // ────────────────────────────────────────────────────────────────────────

  /// Clock in a contractor to a job.
  ///
  /// Enforces one-active-session-per-contractor invariant:
  /// 1. Queries for any active session (clockedOutAt is null) for this contractor.
  /// 2. If found, auto-clocks-out the existing session (computes duration, sets
  ///    status='completed', enqueues UPDATE to sync_queue).
  /// 3. Inserts the new time entry with clockedInAt=now, enqueues CREATE.
  ///
  /// All writes in a single transaction — no partial state is ever committed.
  /// Returns the new entry's UUID.
  Future<String> clockIn({
    required String companyId,
    required String jobId,
    required String contractorId,
  }) async {
    final now = DateTime.now();
    final newEntryId = const Uuid().v4();

    await db.transaction(() async {
      // Auto-close any existing active session for this contractor
      final activeSession = await (select(timeEntries)
            ..where(
              (tbl) =>
                  tbl.contractorId.equals(contractorId) &
                  tbl.clockedOutAt.isNull() &
                  tbl.deletedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();

      if (activeSession != null) {
        final duration =
            now.difference(activeSession.clockedInAt).inSeconds;
        final newVersion = activeSession.version + 1;

        // Auto-clock-out the existing active session
        await (update(timeEntries)
              ..where((tbl) => tbl.id.equals(activeSession.id)))
            .write(
          TimeEntriesCompanion(
            clockedOutAt: Value(now),
            durationSeconds: Value(duration),
            sessionStatus: const Value('completed'),
            version: Value(newVersion),
            updatedAt: Value(now),
          ),
        );

        // Enqueue UPDATE for auto-closed session
        await into(syncQueue).insert(
          _buildQueueEntry(
            entityType: 'time_entry',
            entityId: activeSession.id,
            operation: 'UPDATE',
            payload: {
              'id': activeSession.id,
              'job_id': activeSession.jobId,
              'clocked_out_at': now.toIso8601String(),
              'duration_seconds': duration,
              'session_status': 'completed',
              'version': newVersion,
              'updated_at': now.toIso8601String(),
            },
          ),
        );
      }

      // Insert the new time entry
      await into(timeEntries).insert(
        TimeEntriesCompanion.insert(
          id: Value(newEntryId),
          companyId: companyId,
          jobId: jobId,
          contractorId: contractorId,
          clockedInAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Enqueue CREATE for new entry
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'time_entry',
          entityId: newEntryId,
          operation: 'CREATE',
          payload: {
            'id': newEntryId,
            'company_id': companyId,
            'job_id': jobId,
            'contractor_id': contractorId,
            'clocked_in_at': now.toIso8601String(),
            'session_status': 'active',
            'adjustment_log': '[]',
            'version': 1,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
        ),
      );
    });

    return newEntryId;
  }

  /// Clock out a contractor from a specific time entry.
  ///
  /// Updates [clockedOutAt] = now, computes [durationSeconds],
  /// sets [sessionStatus] = 'completed', enqueues UPDATE to sync_queue.
  ///
  /// All writes in a single transaction.
  Future<void> clockOut(String entryId) async {
    final now = DateTime.now();

    await db.transaction(() async {
      // Fetch current entry to compute duration
      final entry = await (select(timeEntries)
            ..where((tbl) => tbl.id.equals(entryId)))
          .getSingleOrNull();

      if (entry == null) return;

      final duration = now.difference(entry.clockedInAt).inSeconds;
      final newVersion = entry.version + 1;

      await (update(timeEntries)..where((tbl) => tbl.id.equals(entryId)))
          .write(
        TimeEntriesCompanion(
          clockedOutAt: Value(now),
          durationSeconds: Value(duration),
          sessionStatus: const Value('completed'),
          version: Value(newVersion),
          updatedAt: Value(now),
        ),
      );

      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'time_entry',
          entityId: entryId,
          operation: 'UPDATE',
          payload: {
            'id': entryId,
            'job_id': entry.jobId,
            'clocked_out_at': now.toIso8601String(),
            'duration_seconds': duration,
            'session_status': 'completed',
            'version': newVersion,
            'updated_at': now.toIso8601String(),
          },
        ),
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // Sync pull upsert
  // ────────────────────────────────────────────────────────────────────────

  /// Upsert a time entry from a sync pull response (server-wins on conflict).
  ///
  /// No sync_queue entry — this IS the sync; writing to the queue would
  /// cause an infinite sync loop.
  Future<void> upsertFromSync(Map<String, dynamic> data) async {
    final deletedAt = data['deleted_at'] != null
        ? DateTime.parse(data['deleted_at'] as String)
        : null;
    final clockedOutAt = data['clocked_out_at'] != null
        ? DateTime.parse(data['clocked_out_at'] as String)
        : null;

    final companion = TimeEntriesCompanion(
      id: Value(data['id'] as String),
      companyId: Value(data['company_id'] as String),
      jobId: Value(data['job_id'] as String),
      contractorId: Value(data['contractor_id'] as String),
      clockedInAt: Value(DateTime.parse(data['clocked_in_at'] as String)),
      clockedOutAt: Value(clockedOutAt),
      durationSeconds: Value(data['duration_seconds'] as int?),
      sessionStatus: Value(data['session_status'] is String ? data['session_status'] as String : 'active'),
      adjustmentLog: Value(data['adjustment_log'] is String ? data['adjustment_log'] as String : '[]'),
      version: data['version'] != null
          ? Value(data['version'] as int)
          : const Value.absent(),
      createdAt: data['created_at'] != null
          ? Value(DateTime.parse(data['created_at'] as String))
          : const Value.absent(),
      updatedAt: data['updated_at'] != null
          ? Value(DateTime.parse(data['updated_at'] as String))
          : const Value.absent(),
      deletedAt: Value(deletedAt),
    );

    await into(timeEntries).insertOnConflictUpdate(companion);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Internal helpers
  // ────────────────────────────────────────────────────────────────────────

  /// Build a [SyncQueueCompanion] outbox entry for the given mutation.
  SyncQueueCompanion _buildQueueEntry({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) {
    return SyncQueueCompanion.insert(
      id: Value(const Uuid().v4()),
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: jsonEncode(payload),
      status: const Value('pending'),
      attemptCount: const Value(0),
      createdAt: DateTime.now(),
    );
  }
}
