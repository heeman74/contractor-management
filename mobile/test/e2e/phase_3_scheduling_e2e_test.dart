// Phase 3 E2E: Scheduling Engine
//
// Covers BookingDao CRUD with transactional sync queue dual-write,
// unscheduled jobs query, sync integration (upsertBookingFromSync),
// OverdueService severity computation, and version bumping.
//
// Strategy: Real Drift in-memory DB for DAO-level tests, pure Dart for
// OverdueService. Do NOT use pumpAndSettle() — Drift streams never settle.

import 'dart:convert';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/features/schedule/data/booking_dao.dart';
import 'package:contractorhub/features/schedule/domain/overdue_service.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

Future<void> _seedCompany(AppDatabase db) async {
  await db.into(db.companies).insert(CompaniesCompanion.insert(
        id: const Value('co-1'),
        name: 'Test Co',
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

Future<void> _seedUser(AppDatabase db, String id, String email) async {
  await db.into(db.users).insert(UsersCompanion.insert(
        id: Value(id),
        companyId: 'co-1',
        email: email,
        firstName: const Value('Test'),
        lastName: const Value('User'),
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

Future<void> _seedJob(
    AppDatabase db, String id, String desc, {String status = 'scheduled'}) async {
  await db.into(db.jobs).insert(JobsCompanion.insert(
        id: Value(id),
        companyId: 'co-1',
        description: desc,
        tradeType: 'plumber',
        status: Value(status),
        statusHistory: const Value('[]'),
        priority: const Value('medium'),
        tags: const Value('[]'),
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

/// Helper to read all sync queue entries ordered by createdAt (FIFO).
Future<List<SyncQueueData>> _readSyncQueue(AppDatabase db) async {
  return (db.select(db.syncQueue)
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .get();
}

/// Helper to read a single booking row by id (including soft-deleted).
Future<Booking?> _readBookingById(AppDatabase db, String id) async {
  final rows = await (db.select(db.bookings)
        ..where((t) => t.id.equals(id)))
      .get();
  return rows.isEmpty ? null : rows.first;
}

void main() {
  // ──────────────────────────────────────────────────────────────────────
  // 1. BookingDao CRUD E2E
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3 E2E: BookingDao CRUD', () {
    late AppDatabase db;
    late BookingDao dao;

    setUp(() async {
      db = _openTestDb();
      dao = BookingDao(db);
      await _seedCompany(db);
      await _seedUser(db, 'contractor-1', 'c1@test.com');
      await _seedUser(db, 'contractor-2', 'c2@test.com');
      await _seedJob(db, 'job-1', 'Fix pipe');
      await _seedJob(db, 'job-2', 'Paint wall');
    });

    tearDown(() => db.close());

    test('createBooking inserts booking + sync queue CREATE entry atomically',
        () async {
      final start = DateTime(2026, 3, 11, 9, 0);
      final end = DateTime(2026, 3, 11, 11, 0);

      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: start,
        timeRangeEnd: end,
      );

      // Verify booking exists
      final booking = await _readBookingById(db, 'bk-1');
      expect(booking, isNotNull);
      expect(booking!.companyId, 'co-1');
      expect(booking.contractorId, 'contractor-1');
      expect(booking.jobId, 'job-1');
      expect(booking.timeRangeStart, start);
      expect(booking.timeRangeEnd, end);
      expect(booking.version, 1);

      // Verify sync queue CREATE entry
      final queue = await _readSyncQueue(db);
      expect(queue, hasLength(1));
      expect(queue.first.entityType, 'booking');
      expect(queue.first.entityId, 'bk-1');
      expect(queue.first.operation, 'CREATE');
      expect(queue.first.status, 'pending');

      final payload = jsonDecode(queue.first.payload) as Map<String, dynamic>;
      expect(payload['id'], 'bk-1');
      expect(payload['company_id'], 'co-1');
      expect(payload['contractor_id'], 'contractor-1');
      expect(payload['job_id'], 'job-1');
    });

    test('watchBookingsByContractorAndDate streams bookings for correct contractor/date',
        () async {
      final date = DateTime(2026, 3, 11);
      final start1 = DateTime(2026, 3, 11, 9, 0);
      final end1 = DateTime(2026, 3, 11, 11, 0);
      final start2 = DateTime(2026, 3, 11, 13, 0);
      final end2 = DateTime(2026, 3, 11, 15, 0);

      // Booking for contractor-1 on Mar 11
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: start1,
        timeRangeEnd: end1,
      );

      // Booking for contractor-2 on Mar 11 (should NOT appear)
      await dao.createBooking(
        id: 'bk-2',
        companyId: 'co-1',
        contractorId: 'contractor-2',
        jobId: 'job-2',
        timeRangeStart: start2,
        timeRangeEnd: end2,
      );

      final stream = dao.watchBookingsByContractorAndDate('contractor-1', date);
      final first = await stream.first;

      expect(first, hasLength(1));
      expect(first.first.id, 'bk-1');
      expect(first.first.contractorId, 'contractor-1');
    });

    test('watchBookingsByCompanyAndDateRange streams bookings in date range',
        () async {
      final rangeStart = DateTime(2026, 3, 10);
      final rangeEnd = DateTime(2026, 3, 13);

      // Inside range
      await dao.createBooking(
        id: 'bk-in-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      // Inside range, different day
      await dao.createBooking(
        id: 'bk-in-2',
        companyId: 'co-1',
        contractorId: 'contractor-2',
        jobId: 'job-2',
        timeRangeStart: DateTime(2026, 3, 12, 10, 0),
        timeRangeEnd: DateTime(2026, 3, 12, 12, 0),
      );

      // Outside range (Mar 13 is excluded since range is [start, end))
      await dao.createBooking(
        id: 'bk-out',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 13, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 13, 11, 0),
      );

      final stream =
          dao.watchBookingsByCompanyAndDateRange('co-1', rangeStart, rangeEnd);
      final first = await stream.first;

      expect(first, hasLength(2));
      expect(first.map((b) => b.id).toList(), containsAll(['bk-in-1', 'bk-in-2']));
    });

    test('updateBookingTime bumps version + creates UPDATE sync entry',
        () async {
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      final newStart = DateTime(2026, 3, 11, 10, 0);
      final newEnd = DateTime(2026, 3, 11, 12, 0);
      await dao.updateBookingTime('bk-1', newStart, newEnd, 1);

      // Verify booking updated
      final booking = await _readBookingById(db, 'bk-1');
      expect(booking!.timeRangeStart, newStart);
      expect(booking.timeRangeEnd, newEnd);
      expect(booking.version, 2);

      // Verify sync queue has CREATE + UPDATE
      final queue = await _readSyncQueue(db);
      expect(queue, hasLength(2));
      expect(queue[0].operation, 'CREATE');
      expect(queue[1].operation, 'UPDATE');
      expect(queue[1].entityId, 'bk-1');

      final payload = jsonDecode(queue[1].payload) as Map<String, dynamic>;
      expect(payload['version'], 2);
    });

    test('updateBookingContractorAndTime changes contractor + time + version',
        () async {
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      final newStart = DateTime(2026, 3, 11, 14, 0);
      final newEnd = DateTime(2026, 3, 11, 16, 0);
      await dao.updateBookingContractorAndTime(
          'bk-1', 'contractor-2', newStart, newEnd, 1);

      final booking = await _readBookingById(db, 'bk-1');
      expect(booking!.contractorId, 'contractor-2');
      expect(booking.timeRangeStart, newStart);
      expect(booking.timeRangeEnd, newEnd);
      expect(booking.version, 2);

      // Verify sync queue UPDATE entry
      final queue = await _readSyncQueue(db);
      expect(queue, hasLength(2)); // CREATE + UPDATE
      expect(queue[1].operation, 'UPDATE');

      final payload = jsonDecode(queue[1].payload) as Map<String, dynamic>;
      expect(payload['contractor_id'], 'contractor-2');
    });

    test('softDeleteBooking sets deletedAt, excluded from watches', () async {
      final date = DateTime(2026, 3, 11);
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      await dao.softDeleteBooking('bk-1', 1);

      // Row still exists but has deletedAt set
      final booking = await _readBookingById(db, 'bk-1');
      expect(booking, isNotNull);
      expect(booking!.deletedAt, isNotNull);
      expect(booking.version, 2);

      // Verify sync queue DELETE entry
      final queue = await _readSyncQueue(db);
      expect(queue, hasLength(2)); // CREATE + DELETE
      expect(queue[1].operation, 'DELETE');
    });

    test('soft-deleted booking NOT returned by watchBookingsByContractorAndDate',
        () async {
      final date = DateTime(2026, 3, 11);

      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      // Also create a non-deleted booking
      await dao.createBooking(
        id: 'bk-2',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-2',
        timeRangeStart: DateTime(2026, 3, 11, 13, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 15, 0),
      );

      await dao.softDeleteBooking('bk-1', 1);

      final stream = dao.watchBookingsByContractorAndDate('contractor-1', date);
      final result = await stream.first;

      expect(result, hasLength(1));
      expect(result.first.id, 'bk-2');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 2. Unscheduled Jobs E2E
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3 E2E: Unscheduled Jobs', () {
    late AppDatabase db;
    late BookingDao dao;

    setUp(() async {
      db = _openTestDb();
      dao = BookingDao(db);
      await _seedCompany(db);
      await _seedUser(db, 'contractor-1', 'c1@test.com');
      await _seedJob(db, 'job-1', 'Fix pipe');
      await _seedJob(db, 'job-2', 'Paint wall');
      await _seedJob(db, 'job-3', 'Install fixture');
    });

    tearDown(() => db.close());

    test('watchUnscheduledJobs returns jobs with no bookings for the date',
        () async {
      final date = DateTime(2026, 3, 11);

      final stream = dao.watchUnscheduledJobs('co-1', date);
      final result = await stream.first;

      // All 3 jobs are unscheduled
      expect(result, hasLength(3));
      expect(result.map((j) => j.id).toSet(),
          {'job-1', 'job-2', 'job-3'});
    });

    test('job with booking on selected date excluded from unscheduled',
        () async {
      final date = DateTime(2026, 3, 11);

      // Book job-1 on Mar 11
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      final stream = dao.watchUnscheduledJobs('co-1', date);
      final result = await stream.first;

      expect(result, hasLength(2));
      expect(result.map((j) => j.id).toSet(), {'job-2', 'job-3'});
    });

    test('job with booking on different date still appears as unscheduled for selected date',
        () async {
      final selectedDate = DateTime(2026, 3, 11);

      // Book job-1 on Mar 12 (different day)
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 12, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 12, 11, 0),
      );

      final stream = dao.watchUnscheduledJobs('co-1', selectedDate);
      final result = await stream.first;

      // All 3 jobs should appear as unscheduled for Mar 11
      expect(result, hasLength(3));
      expect(result.map((j) => j.id).toSet(),
          {'job-1', 'job-2', 'job-3'});
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 3. Sync Integration E2E
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3 E2E: Sync Integration', () {
    late AppDatabase db;
    late BookingDao dao;

    setUp(() async {
      db = _openTestDb();
      dao = BookingDao(db);
      await _seedCompany(db);
      await _seedUser(db, 'contractor-1', 'c1@test.com');
      await _seedJob(db, 'job-1', 'Fix pipe');
    });

    tearDown(() => db.close());

    test('upsertBookingFromSync inserts without sync queue entry', () async {
      final now = DateTime.now();
      await dao.upsertBookingFromSync(BookingsCompanion.insert(
        id: const Value('bk-sync-1'),
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
        version: const Value(5),
        createdAt: now,
        updatedAt: now,
      ));

      // Booking should exist
      final booking = await _readBookingById(db, 'bk-sync-1');
      expect(booking, isNotNull);
      expect(booking!.version, 5);

      // Sync queue should be EMPTY — no outbox entry for sync pulls
      final queue = await _readSyncQueue(db);
      expect(queue, isEmpty);
    });

    test('upsertBookingFromSync updates existing booking (server-wins)',
        () async {
      final now = DateTime.now();

      // Insert initial booking via sync
      await dao.upsertBookingFromSync(BookingsCompanion.insert(
        id: const Value('bk-sync-1'),
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
        version: const Value(1),
        createdAt: now,
        updatedAt: now,
      ));

      // Server sends updated version with new time
      final updatedStart = DateTime(2026, 3, 11, 14, 0);
      final updatedEnd = DateTime(2026, 3, 11, 16, 0);
      await dao.upsertBookingFromSync(BookingsCompanion.insert(
        id: const Value('bk-sync-1'),
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: updatedStart,
        timeRangeEnd: updatedEnd,
        version: const Value(3),
        createdAt: now,
        updatedAt: DateTime.now(),
      ));

      final booking = await _readBookingById(db, 'bk-sync-1');
      expect(booking!.timeRangeStart, updatedStart);
      expect(booking.timeRangeEnd, updatedEnd);
      expect(booking.version, 3);

      // Still no sync queue entries
      final queue = await _readSyncQueue(db);
      expect(queue, isEmpty);
    });

    test('sync queue correctly tracks all local mutations (CREATE, UPDATE, DELETE)',
        () async {
      // CREATE
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      // UPDATE
      await dao.updateBookingTime(
        'bk-1',
        DateTime(2026, 3, 11, 10, 0),
        DateTime(2026, 3, 11, 12, 0),
        1,
      );

      // DELETE
      await dao.softDeleteBooking('bk-1', 2);

      final queue = await _readSyncQueue(db);
      expect(queue, hasLength(3));
      expect(queue[0].operation, 'CREATE');
      expect(queue[1].operation, 'UPDATE');
      expect(queue[2].operation, 'DELETE');

      // All reference the same entity
      expect(queue.map((q) => q.entityId).toSet(), {'bk-1'});
      expect(queue.every((q) => q.entityType == 'booking'), isTrue);
    });

    test('FIFO ordering preserved in sync queue', () async {
      await _seedJob(db, 'job-2', 'Paint wall');

      // Create two bookings in sequence
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      await dao.createBooking(
        id: 'bk-2',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-2',
        timeRangeStart: DateTime(2026, 3, 11, 13, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 15, 0),
      );

      // Update first booking
      await dao.updateBookingTime(
        'bk-1',
        DateTime(2026, 3, 11, 10, 0),
        DateTime(2026, 3, 11, 12, 0),
        1,
      );

      final queue = await _readSyncQueue(db);
      expect(queue, hasLength(3));

      // FIFO: CREATE bk-1, CREATE bk-2, UPDATE bk-1
      expect(queue[0].entityId, 'bk-1');
      expect(queue[0].operation, 'CREATE');
      expect(queue[1].entityId, 'bk-2');
      expect(queue[1].operation, 'CREATE');
      expect(queue[2].entityId, 'bk-1');
      expect(queue[2].operation, 'UPDATE');

      // Timestamps should be non-decreasing
      for (var i = 1; i < queue.length; i++) {
        expect(
          queue[i].createdAt.millisecondsSinceEpoch,
          greaterThanOrEqualTo(queue[i - 1].createdAt.millisecondsSinceEpoch),
        );
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 4. OverdueService E2E
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3 E2E: OverdueService', () {
    test('computeSeverity: null date returns none', () {
      expect(OverdueService.computeSeverity(null), OverdueSeverity.none);
    });

    test('computeSeverity: future date returns none', () {
      final futureDate = DateTime.now().add(const Duration(days: 7));
      expect(OverdueService.computeSeverity(futureDate), OverdueSeverity.none);
    });

    test('computeSeverity: today returns none (not yet overdue)', () {
      final today = DateTime.now();
      expect(OverdueService.computeSeverity(today), OverdueSeverity.none);
    });

    test('computeSeverity: 1 day ago returns warning', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(
          OverdueService.computeSeverity(yesterday), OverdueSeverity.warning);
    });

    test('computeSeverity: 3 days ago returns warning', () {
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      expect(OverdueService.computeSeverity(threeDaysAgo),
          OverdueSeverity.warning);
    });

    test('computeSeverity: 4+ days ago returns critical', () {
      // Use calendar-day arithmetic to avoid hour-boundary edge cases
      final now = DateTime.now();
      final fiveDaysAgo = DateTime(now.year, now.month, now.day - 5);
      expect(OverdueService.computeSeverity(fiveDaysAgo),
          OverdueSeverity.critical);
    });

    test('computeSeverity: 30 days ago returns critical', () {
      final longOverdue = DateTime.now().subtract(const Duration(days: 30));
      expect(OverdueService.computeSeverity(longOverdue),
          OverdueSeverity.critical);
    });

    test('isOverdue: scheduled status with past date is overdue', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 2));
      expect(OverdueService.isOverdue('scheduled', pastDate), isTrue);
    });

    test('isOverdue: in_progress status with past date is overdue', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 2));
      expect(OverdueService.isOverdue('in_progress', pastDate), isTrue);
    });

    test('isOverdue: complete status never overdue', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 10));
      expect(OverdueService.isOverdue('complete', pastDate), isFalse);
    });

    test('isOverdue: invoiced status never overdue', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 10));
      expect(OverdueService.isOverdue('invoiced', pastDate), isFalse);
    });

    test('isOverdue: cancelled status never overdue', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 10));
      expect(OverdueService.isOverdue('cancelled', pastDate), isFalse);
    });

    test('isOverdue: scheduled status with future date is not overdue', () {
      final futureDate = DateTime.now().add(const Duration(days: 5));
      expect(OverdueService.isOverdue('scheduled', futureDate), isFalse);
    });

    test('isOverdue: null date is never overdue regardless of status', () {
      expect(OverdueService.isOverdue('scheduled', null), isFalse);
      expect(OverdueService.isOverdue('in_progress', null), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 5. Version Bumping E2E
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 3 E2E: Version Bumping', () {
    late AppDatabase db;
    late BookingDao dao;

    setUp(() async {
      db = _openTestDb();
      dao = BookingDao(db);
      await _seedCompany(db);
      await _seedUser(db, 'contractor-1', 'c1@test.com');
      await _seedUser(db, 'contractor-2', 'c2@test.com');
      await _seedJob(db, 'job-1', 'Fix pipe');
    });

    tearDown(() => db.close());

    test('each mutation increments version', () async {
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      var booking = await _readBookingById(db, 'bk-1');
      expect(booking!.version, 1);

      // First update: version 1 -> 2
      await dao.updateBookingTime(
        'bk-1',
        DateTime(2026, 3, 11, 10, 0),
        DateTime(2026, 3, 11, 12, 0),
        1,
      );
      booking = await _readBookingById(db, 'bk-1');
      expect(booking!.version, 2);

      // Second update: version 2 -> 3
      await dao.updateBookingContractorAndTime(
        'bk-1',
        'contractor-2',
        DateTime(2026, 3, 11, 14, 0),
        DateTime(2026, 3, 11, 16, 0),
        2,
      );
      booking = await _readBookingById(db, 'bk-1');
      expect(booking!.version, 3);

      // Soft delete: version 3 -> 4
      await dao.softDeleteBooking('bk-1', 3);
      booking = await _readBookingById(db, 'bk-1');
      expect(booking!.version, 4);
      expect(booking.deletedAt, isNotNull);
    });

    test('multiple updates accumulate version correctly', () async {
      await dao.createBooking(
        id: 'bk-1',
        companyId: 'co-1',
        contractorId: 'contractor-1',
        jobId: 'job-1',
        timeRangeStart: DateTime(2026, 3, 11, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 11, 11, 0),
      );

      // 5 consecutive time updates: version goes 1 -> 2 -> 3 -> 4 -> 5 -> 6
      for (var v = 1; v <= 5; v++) {
        await dao.updateBookingTime(
          'bk-1',
          DateTime(2026, 3, 11, 9 + v, 0),
          DateTime(2026, 3, 11, 11 + v, 0),
          v,
        );
      }

      final booking = await _readBookingById(db, 'bk-1');
      expect(booking!.version, 6);

      // Sync queue should have 1 CREATE + 5 UPDATE entries
      final queue = await _readSyncQueue(db);
      expect(queue, hasLength(6));
      expect(queue[0].operation, 'CREATE');
      for (var i = 1; i <= 5; i++) {
        expect(queue[i].operation, 'UPDATE');
        final payload =
            jsonDecode(queue[i].payload) as Map<String, dynamic>;
        expect(payload['version'], i + 1);
      }
    });
  });
}
