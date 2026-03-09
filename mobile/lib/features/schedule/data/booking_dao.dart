import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/bookings.dart';
import '../../../core/database/tables/jobs.dart';
import '../../../core/database/tables/sync_queue.dart';
import '../domain/booking_entity.dart';

part 'booking_dao.g.dart';

/// Drift DAO for Booking CRUD with transactional outbox dual-write.
///
/// All read methods return [Stream] — offline-first, reactive to local DB changes.
///
/// Every mutating method (insert/update/softDelete) uses [db.transaction] to
/// atomically write to BOTH the bookings table AND sync_queue outbox. If either
/// write fails, both are rolled back — no orphaned queue items, no untracked
/// mutations.
///
/// [upsertBookingFromSync] is the sync-pull path and does NOT write to the
/// sync_queue — this IS the sync, writing to the queue would create an infinite loop.
///
/// Payload serialization: manually build Map<String, dynamic> from Companion
/// fields — [toColumns()] returns Map<String, Expression> which cannot be
/// JSON-encoded (Phase 2 decision).
@DriftAccessor(
  tables: [Bookings, Jobs, SyncQueue],
)
class BookingDao extends DatabaseAccessor<AppDatabase> with _$BookingDaoMixin {
  BookingDao(super.db);

  // ────────────────────────────────────────────────────────────────────────
  // Booking streams
  // ────────────────────────────────────────────────────────────────────────

  /// Reactive stream of bookings for a contractor on a specific date.
  ///
  /// Filters by contractorId, date range [dayStart, dayStart + 1 day),
  /// and excludes soft-deleted rows. Used by contractor calendar day view.
  Stream<List<BookingEntity>> watchBookingsByContractorAndDate(
    String contractorId,
    DateTime date,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    return (select(bookings)
          ..where(
            (tbl) =>
                tbl.contractorId.equals(contractorId) &
                tbl.timeRangeStart.isBiggerOrEqualValue(dayStart) &
                tbl.timeRangeStart.isSmallerThanValue(dayEnd) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.timeRangeStart)]))
        .watch()
        .map((rows) => rows.map(_rowToEntity).toList());
  }

  /// Reactive stream of bookings for a company across a date range.
  ///
  /// Used by admin calendar views spanning multiple days (week/month view).
  /// Filters by companyId and the date range [start, end), excludes soft-deleted.
  Stream<List<BookingEntity>> watchBookingsByCompanyAndDateRange(
    String companyId,
    DateTime start,
    DateTime end,
  ) {
    return (select(bookings)
          ..where(
            (tbl) =>
                tbl.companyId.equals(companyId) &
                tbl.timeRangeStart.isBiggerOrEqualValue(start) &
                tbl.timeRangeStart.isSmallerThanValue(end) &
                tbl.deletedAt.isNull(),
          )
          ..orderBy([
            (tbl) => OrderingTerm.asc(tbl.timeRangeStart),
          ]))
        .watch()
        .map((rows) => rows.map(_rowToEntity).toList());
  }

  /// Reactive stream of unscheduled jobs for a company on a given date.
  ///
  /// Returns active jobs (non-deleted, status in 'quote'/'scheduled') that
  /// have NO active booking for the given date. Uses LEFT JOIN to find
  /// unmatched jobs — the dispatch drawer uses this to show draggable jobs.
  ///
  /// Implementation: SELECT jobs LEFT JOIN bookings ON jobs.id = bookings.job_id
  ///   AND bookings.deleted_at IS NULL
  ///   AND bookings.time_range_start >= dayStart
  ///   AND bookings.time_range_start < dayStart + 1 day
  /// WHERE bookings.id IS NULL
  ///   AND jobs.company_id = companyId
  ///   AND jobs.deleted_at IS NULL
  ///   AND jobs.status IN ('quote', 'scheduled')
  Stream<List<Job>> watchUnscheduledJobs(String companyId, DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final query = select(jobs).join([
      leftOuterJoin(
        bookings,
        bookings.jobId.equalsExp(jobs.id) &
            bookings.deletedAt.isNull() &
            bookings.timeRangeStart.isBiggerOrEqualValue(dayStart) &
            bookings.timeRangeStart.isSmallerThanValue(dayEnd),
      ),
    ])
      ..where(
        bookings.id.isNull() &
            jobs.companyId.equals(companyId) &
            jobs.deletedAt.isNull() &
            (jobs.status.equals('quote') | jobs.status.equals('scheduled')),
      )
      ..orderBy([OrderingTerm.desc(jobs.createdAt)]);

    return query.watch().map(
          (rows) => rows.map((row) => row.readTable(jobs)).toList(),
        );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Booking mutations (transactional outbox pattern)
  // ────────────────────────────────────────────────────────────────────────

  /// Insert a new booking and atomically enqueue a CREATE sync item.
  ///
  /// Both the entity write and sync_queue insert happen in a single
  /// transaction — if either fails, both are rolled back.
  Future<void> insertBooking(BookingsCompanion entry) async {
    await db.transaction(() async {
      await into(bookings).insert(entry);
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'booking',
          entityId: entry.id.value,
          operation: 'CREATE',
          payload: _bookingPayload(entry),
        ),
      );
    });
  }

  /// Update booking time range and atomically enqueue an UPDATE sync item.
  ///
  /// Bumps the version for optimistic locking. The sync payload includes
  /// the new time range and current version for server-side conflict detection.
  Future<void> updateBookingTime(
    String id,
    DateTime newStart,
    DateTime newEnd,
    int currentVersion,
  ) async {
    final now = DateTime.now();
    final newVersion = currentVersion + 1;
    await db.transaction(() async {
      await (update(bookings)..where((tbl) => tbl.id.equals(id))).write(
        BookingsCompanion(
          timeRangeStart: Value(newStart),
          timeRangeEnd: Value(newEnd),
          version: Value(newVersion),
          updatedAt: Value(now),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'booking',
          entityId: id,
          operation: 'UPDATE',
          payload: {
            'id': id,
            'time_range_start': newStart.toIso8601String(),
            'time_range_end': newEnd.toIso8601String(),
            'version': newVersion,
            'updated_at': now.toIso8601String(),
          },
        ),
      );
    });
  }

  /// Soft-delete a booking and atomically enqueue a DELETE sync item.
  ///
  /// The booking remains in the local DB as a tombstone — sync propagates
  /// the deletedAt timestamp to other devices and the backend.
  Future<void> softDeleteBooking(String id, int currentVersion) async {
    final now = DateTime.now();
    final newVersion = currentVersion + 1;
    await db.transaction(() async {
      await (update(bookings)..where((tbl) => tbl.id.equals(id))).write(
        BookingsCompanion(
          deletedAt: Value(now),
          version: Value(newVersion),
          updatedAt: Value(now),
        ),
      );
      await into(syncQueue).insert(
        _buildQueueEntry(
          entityType: 'booking',
          entityId: id,
          operation: 'DELETE',
          payload: {
            'id': id,
            'deleted_at': now.toIso8601String(),
            'version': newVersion,
          },
        ),
      );
    });
  }

  /// Upsert a booking from a sync pull response (server-wins on conflict).
  ///
  /// No sync_queue entry — this IS the sync; writing to the queue would
  /// cause an infinite sync loop.
  Future<void> upsertBookingFromSync(BookingsCompanion entry) async {
    await into(bookings).insertOnConflictUpdate(entry);
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

  /// Build a JSON-serializable payload from a [BookingsCompanion] (for CREATE).
  Map<String, dynamic> _bookingPayload(BookingsCompanion entry) {
    return {
      'id': entry.id.value,
      'company_id': entry.companyId.value,
      'contractor_id': entry.contractorId.value,
      'job_id': entry.jobId.value,
      if (entry.jobSiteId.present && entry.jobSiteId.value != null)
        'job_site_id': entry.jobSiteId.value,
      'time_range_start': entry.timeRangeStart.value.toIso8601String(),
      'time_range_end': entry.timeRangeEnd.value.toIso8601String(),
      if (entry.dayIndex.present && entry.dayIndex.value != null)
        'day_index': entry.dayIndex.value,
      if (entry.parentBookingId.present && entry.parentBookingId.value != null)
        'parent_booking_id': entry.parentBookingId.value,
      if (entry.notes.present && entry.notes.value != null)
        'notes': entry.notes.value,
      'version': entry.version.present ? entry.version.value : 1,
      if (entry.createdAt.present)
        'created_at': entry.createdAt.value.toIso8601String(),
      if (entry.updatedAt.present)
        'updated_at': entry.updatedAt.value.toIso8601String(),
    };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Row to entity mapper
  // ────────────────────────────────────────────────────────────────────────

  /// Map a Drift [Booking] row to a [BookingEntity] domain object.
  BookingEntity _rowToEntity(Booking row) {
    return BookingEntity(
      id: row.id,
      companyId: row.companyId,
      contractorId: row.contractorId,
      jobId: row.jobId,
      jobSiteId: row.jobSiteId,
      timeRangeStart: row.timeRangeStart,
      timeRangeEnd: row.timeRangeEnd,
      dayIndex: row.dayIndex,
      parentBookingId: row.parentBookingId,
      notes: row.notes,
      version: row.version,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deletedAt: row.deletedAt,
    );
  }
}
