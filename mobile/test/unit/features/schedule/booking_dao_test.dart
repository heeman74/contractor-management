/// Unit tests for BookingDao — Drift DAO for Booking CRUD with transactional outbox.
///
/// Uses Drift in-memory database (NativeDatabase.memory()) to test actual
/// SQL queries without mocking. Import pattern from MEMORY.md:
///   import 'package:drift/drift.dart' hide isNotNull, isNull;
///
/// Tests cover:
/// 1. insertBooking creates booking + sync queue CREATE entry (outbox dual-write)
/// 2. watchBookingsByContractorAndDate filters by contractor + date correctly
/// 3. softDeleteBooking sets deletedAt and excludes from watch queries
/// 4. updateBookingTime changes time range, bumps version, and creates UPDATE sync entry
/// 5. upsertBookingFromSync creates a new booking without sync queue entry
/// 6. upsertBookingFromSync updates an existing booking without sync queue entry
/// 7. watchUnscheduledJobs excludes jobs that have bookings (LEFT JOIN)
library;

import 'dart:convert';

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/core/sync/sync_queue_dao.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

AppDatabase openTestDatabase() {
  return AppDatabase(NativeDatabase.memory());
}

const _uuid = Uuid();

/// Build a minimal BookingsCompanion with required fields.
BookingsCompanion makeBooking({
  String? id,
  String companyId = 'co-1',
  String contractorId = 'user-1',
  String jobId = 'job-1',
  DateTime? timeRangeStart,
  DateTime? timeRangeEnd,
}) {
  final now = DateTime.now();
  final start = timeRangeStart ?? now;
  final end = timeRangeEnd ?? now.add(const Duration(hours: 2));
  return BookingsCompanion.insert(
    id: Value(id ?? _uuid.v4()),
    companyId: companyId,
    contractorId: contractorId,
    jobId: jobId,
    timeRangeStart: start,
    timeRangeEnd: end,
    createdAt: now,
    updatedAt: now,
  );
}

/// Build a minimal JobsCompanion for testing watchUnscheduledJobs.
JobsCompanion makeJob({
  String? id,
  String companyId = 'co-1',
  String status = 'quote',
}) {
  final now = DateTime.now();
  return JobsCompanion.insert(
    id: Value(id ?? _uuid.v4()),
    companyId: companyId,
    description: 'Test job description',
    tradeType: 'plumber',
    status: Value(status),
    createdAt: now,
    updatedAt: now,
  );
}

/// Build a minimal CompaniesCompanion (required by Jobs.companyId FK).
CompaniesCompanion makeCompany({String id = 'co-1'}) {
  final now = DateTime.now();
  return CompaniesCompanion.insert(
    id: Value(id),
    name: 'Test Company',
    version: const Value(1),
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('BookingDao', () {
    late AppDatabase db;

    setUp(() async {
      db = openTestDatabase();
      // Insert a company row (required for Jobs.companyId FK in watchUnscheduledJobs tests)
      await db.companyDao.insertCompany(makeCompany());
    });

    tearDown(() async {
      await db.close();
    });

    // ────────────────────────────────────────────────────────────────────────
    // Test 1: insertBooking creates booking AND sync queue CREATE entry
    // ────────────────────────────────────────────────────────────────────────

    test(
      'insertBooking creates booking and sync queue entry with operation CREATE',
      () async {
        final bookingId = _uuid.v4();
        final companion = makeBooking(id: bookingId);
        await db.bookingDao.insertBooking(companion);

        // Verify booking was persisted
        final rows = await (db.select(db.bookings)
              ..where((tbl) => tbl.id.equals(bookingId)))
            .get();
        expect(rows, hasLength(1));
        expect(rows.first.id, equals(bookingId));

        // Verify sync queue CREATE entry was created
        final queueItems = await db.syncQueueDao.getAllItems();
        final bookingItems = queueItems
            .where((item) =>
                item.entityType == 'booking' && item.entityId == bookingId)
            .toList();
        expect(bookingItems, hasLength(1));
        expect(bookingItems.first.operation, equals('CREATE'));

        // Verify payload contains the booking ID
        final payload =
            jsonDecode(bookingItems.first.payload) as Map<String, dynamic>;
        expect(payload['id'], equals(bookingId));
      },
    );

    // ────────────────────────────────────────────────────────────────────────
    // Test 2: watchBookingsByContractorAndDate filters correctly
    // ────────────────────────────────────────────────────────────────────────

    test(
      'watchBookingsByContractorAndDate filters by contractor and date',
      () async {
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day, 9);
        final tomorrow = todayStart.add(const Duration(days: 1));

        // Booking for contractor-1 on today
        await db.bookingDao.insertBooking(makeBooking(
          id: 'b-c1-today',
          contractorId: 'contractor-1',
          timeRangeStart: todayStart,
          timeRangeEnd: todayStart.add(const Duration(hours: 2)),
        ));

        // Booking for contractor-2 on today (different contractor)
        await db.bookingDao.insertBooking(makeBooking(
          id: 'b-c2-today',
          contractorId: 'contractor-2',
          timeRangeStart: todayStart,
          timeRangeEnd: todayStart.add(const Duration(hours: 2)),
        ));

        // Booking for contractor-1 on tomorrow (different date)
        await db.bookingDao.insertBooking(makeBooking(
          id: 'b-c1-tomorrow',
          contractorId: 'contractor-1',
          timeRangeStart: tomorrow.add(const Duration(hours: 9)),
          timeRangeEnd: tomorrow.add(const Duration(hours: 11)),
        ));

        // Watch contractor-1's bookings on today
        final bookings = await db.bookingDao
            .watchBookingsByContractorAndDate('contractor-1', today)
            .first;

        // Only the contractor-1/today booking should appear
        final ids = bookings.map((b) => b.id).toList();
        expect(ids, contains('b-c1-today'));
        expect(ids, isNot(contains('b-c2-today')));
        expect(ids, isNot(contains('b-c1-tomorrow')));
      },
    );

    // ────────────────────────────────────────────────────────────────────────
    // Test 3: softDeleteBooking sets deletedAt, excludes from watch
    // ────────────────────────────────────────────────────────────────────────

    test(
      'softDeleteBooking sets deletedAt and excludes booking from watch queries',
      () async {
        final bookingId = _uuid.v4();
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day, 9);

        await db.bookingDao.insertBooking(makeBooking(
          id: bookingId,
          contractorId: 'contractor-1',
          timeRangeStart: todayStart,
          timeRangeEnd: todayStart.add(const Duration(hours: 2)),
        ));

        // Confirm it appears in watch query
        final before = await db.bookingDao
            .watchBookingsByContractorAndDate('contractor-1', today)
            .first;
        expect(before.map((b) => b.id), contains(bookingId));

        // Soft-delete the booking
        await db.bookingDao.softDeleteBooking(bookingId, 1);

        // Verify deletedAt is set in raw DB
        final rawRow = await (db.select(db.bookings)
              ..where((tbl) => tbl.id.equals(bookingId)))
            .getSingleOrNull();
        expect(rawRow, isNotNull);
        expect(rawRow!.deletedAt, isNotNull);

        // Verify it no longer appears in watch query (deletedAt.isNull filter)
        final after = await db.bookingDao
            .watchBookingsByContractorAndDate('contractor-1', today)
            .first;
        expect(after.map((b) => b.id), isNot(contains(bookingId)));
      },
    );

    // ────────────────────────────────────────────────────────────────────────
    // Test 4: updateBookingTime changes range and bumps version
    // ────────────────────────────────────────────────────────────────────────

    test(
      'updateBookingTime updates time range, bumps version, and creates UPDATE sync entry',
      () async {
        final bookingId = _uuid.v4();
        final today = DateTime.now();
        final originalStart =
            DateTime(today.year, today.month, today.day, 9);
        final originalEnd = originalStart.add(const Duration(hours: 2));
        final newStart = DateTime(today.year, today.month, today.day, 11);
        final newEnd = newStart.add(const Duration(hours: 3));

        await db.bookingDao.insertBooking(makeBooking(
          id: bookingId,
          timeRangeStart: originalStart,
          timeRangeEnd: originalEnd,
        ));

        // Record queue length before update
        final queueBefore = await db.syncQueueDao.getAllItems();
        final countBefore = queueBefore.length;

        // Update the booking's time range
        await db.bookingDao.updateBookingTime(bookingId, newStart, newEnd, 1);

        // Verify new time range in DB
        final row = await (db.select(db.bookings)
              ..where((tbl) => tbl.id.equals(bookingId)))
            .getSingleOrNull();
        expect(row, isNotNull);
        expect(row!.timeRangeStart, equals(newStart));
        expect(row.timeRangeEnd, equals(newEnd));
        // Version bumped: 1 (insert default) + 1 (update) = 2
        expect(row.version, equals(2));

        // Verify UPDATE sync entry was created
        final queueAfter = await db.syncQueueDao.getAllItems();
        expect(queueAfter.length, equals(countBefore + 1));

        final updateItems = queueAfter
            .where((item) =>
                item.entityType == 'booking' &&
                item.entityId == bookingId &&
                item.operation == 'UPDATE')
            .toList();
        expect(updateItems, hasLength(1));
      },
    );

    // ────────────────────────────────────────────────────────────────────────
    // Test 5: upsertBookingFromSync creates new booking WITHOUT sync queue entry
    // ────────────────────────────────────────────────────────────────────────

    test(
      'upsertBookingFromSync creates new booking without adding sync queue entry',
      () async {
        final bookingId = _uuid.v4();
        final now = DateTime.now();

        final companion = BookingsCompanion.insert(
          id: Value(bookingId),
          companyId: 'co-1',
          contractorId: 'contractor-1',
          jobId: 'job-1',
          timeRangeStart: now,
          timeRangeEnd: now.add(const Duration(hours: 2)),
          createdAt: now,
          updatedAt: now,
        );

        // Capture queue state before upsert
        final queueBefore = await db.syncQueueDao.getAllItems();
        final countBefore = queueBefore.length;

        await db.bookingDao.upsertBookingFromSync(companion);

        // Booking should be in DB
        final row = await (db.select(db.bookings)
              ..where((tbl) => tbl.id.equals(bookingId)))
            .getSingleOrNull();
        expect(row, isNotNull);

        // No new sync queue entries (sync pull must NOT re-queue)
        final queueAfter = await db.syncQueueDao.getAllItems();
        expect(queueAfter.length, equals(countBefore));
      },
    );

    // ────────────────────────────────────────────────────────────────────────
    // Test 6: upsertBookingFromSync updates existing WITHOUT sync queue entry
    // ────────────────────────────────────────────────────────────────────────

    test(
      'upsertBookingFromSync updates existing booking without adding sync queue entry',
      () async {
        final bookingId = _uuid.v4();
        final now = DateTime.now();
        final originalStart = DateTime(now.year, now.month, now.day, 9);
        final newStart = DateTime(now.year, now.month, now.day, 14);

        // Insert original via insertBooking (creates a CREATE sync entry)
        await db.bookingDao.insertBooking(makeBooking(
          id: bookingId,
          timeRangeStart: originalStart,
          timeRangeEnd: originalStart.add(const Duration(hours: 2)),
        ));

        final queueAfterInsert = await db.syncQueueDao.getAllItems();
        final countAfterInsert = queueAfterInsert.length;

        // Upsert with updated start time (simulating a sync pull)
        final updatedCompanion = BookingsCompanion.insert(
          id: Value(bookingId),
          companyId: 'co-1',
          contractorId: 'contractor-1',
          jobId: 'job-1',
          timeRangeStart: newStart,
          timeRangeEnd: newStart.add(const Duration(hours: 3)),
          createdAt: now,
          updatedAt: now.add(const Duration(minutes: 5)),
        );

        await db.bookingDao.upsertBookingFromSync(updatedCompanion);

        // Verify updated fields
        final row = await (db.select(db.bookings)
              ..where((tbl) => tbl.id.equals(bookingId)))
            .getSingleOrNull();
        expect(row, isNotNull);
        expect(row!.timeRangeStart, equals(newStart));

        // No additional sync queue entry (sync pull must NOT re-queue)
        final queueAfterUpsert = await db.syncQueueDao.getAllItems();
        expect(queueAfterUpsert.length, equals(countAfterInsert));
      },
    );

    // ────────────────────────────────────────────────────────────────────────
    // Test 7: watchUnscheduledJobs excludes jobs with bookings
    // ────────────────────────────────────────────────────────────────────────

    test(
      'watchUnscheduledJobs excludes jobs that have active bookings on the given date',
      () async {
        final today = DateTime.now();
        final todayStart = DateTime(today.year, today.month, today.day, 9);

        // Insert two jobs via raw DB (company row inserted in setUp)
        final jobWithBookingId = _uuid.v4();
        final jobWithoutBookingId = _uuid.v4();

        // default status is 'quote'
        await db.into(db.jobs).insert(makeJob(
              id: jobWithBookingId,
            ));
        await db.into(db.jobs).insert(makeJob(
              id: jobWithoutBookingId,
            ));

        // Create a booking for the first job on today
        await db.bookingDao.insertBooking(BookingsCompanion.insert(
          id: Value(_uuid.v4()),
          companyId: 'co-1',
          contractorId: 'contractor-1',
          jobId: jobWithBookingId,
          timeRangeStart: todayStart,
          timeRangeEnd: todayStart.add(const Duration(hours: 2)),
          createdAt: todayStart,
          updatedAt: todayStart,
        ));

        // Watch unscheduled jobs for today
        final unscheduledJobs = await db.bookingDao
            .watchUnscheduledJobs('co-1', today)
            .first;

        final ids = unscheduledJobs.map((j) => j.id).toList();

        // Job with booking should NOT appear
        expect(ids, isNot(contains(jobWithBookingId)));

        // Job without booking SHOULD appear
        expect(ids, contains(jobWithoutBookingId));
      },
    );
  });
}
