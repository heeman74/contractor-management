// Phase 5 E2E: Calendar and Dispatch UI
//
// Covers Phase 5 features: Delay Justification, Overdue Panel, Multi-Day Wizard,
// SyncStatus subtitle rendering, and combined booking+delay flows.
//
// Strategy: Real Drift in-memory DB for DAO-level tests. Pure Dart for
// OverdueService and SyncStatus. No pumpAndSettle() — Drift streams never settle.

import 'dart:convert';

import 'package:contractorhub/core/database/app_database.dart' hide UserRole;
import 'package:contractorhub/core/sync/sync_engine.dart';
import 'package:contractorhub/features/jobs/data/job_dao.dart';
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

Future<void> _seedJob(
  AppDatabase db,
  String id,
  String desc, {
  DateTime? scheduledCompletion,
  String status = 'scheduled',
}) async {
  await db.into(db.jobs).insert(JobsCompanion.insert(
        id: Value(id),
        companyId: 'co-1',
        description: desc,
        tradeType: 'plumber',
        status: Value(status),
        statusHistory: const Value('[]'),
        priority: const Value('medium'),
        tags: const Value('[]'),
        scheduledCompletionDate: Value(scheduledCompletion),
        version: const Value(1),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
}

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // Group 1: Delay Justification DAO E2E
  // ──────────────────────────────────────────────────────────────────────────
  group('Phase 5 E2E: Delay Justification DAO', () {
    late AppDatabase db;
    late JobDao jobDao;

    setUp(() async {
      db = _openTestDb();
      jobDao = JobDao(db);
      await _seedCompany(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('reportDelay appends entry to job statusHistory JSON', () async {
      await _seedJob(db, 'job-1', 'Fix leak');

      final newEta = DateTime(2026, 4, 15);
      await jobDao.reportDelay(
        jobId: 'job-1',
        reason: 'Parts delayed',
        newEta: newEta,
        currentUserId: 'user-1',
        currentVersion: 1,
      );

      final job = await (db.select(db.jobs)
            ..where((t) => t.id.equals('job-1')))
          .getSingle();
      final history = jsonDecode(job.statusHistory) as List<dynamic>;

      expect(history, hasLength(1));
      final entry = history[0] as Map<String, dynamic>;
      expect(entry['type'], 'delay');
      expect(entry['reason'], 'Parts delayed');
      expect(entry['new_eta'], '2026-04-15');
      expect(entry['user_id'], 'user-1');
      expect(entry.containsKey('timestamp'), isTrue);
    });

    test('reportDelay updates scheduledCompletionDate to new ETA', () async {
      final originalDate = DateTime(2026, 3, 10);
      await _seedJob(db, 'job-1', 'Fix leak',
          scheduledCompletion: originalDate);

      final newEta = DateTime(2026, 4, 20);
      await jobDao.reportDelay(
        jobId: 'job-1',
        reason: 'Weather delay',
        newEta: newEta,
        currentUserId: 'user-1',
        currentVersion: 1,
      );

      final job = await (db.select(db.jobs)
            ..where((t) => t.id.equals('job-1')))
          .getSingle();

      // Drift stores epoch millis; reading back gives local time.
      // Convert to UTC to compare against the UTC value written by reportDelay.
      final scd = job.scheduledCompletionDate!.toUtc();
      expect(scd, DateTime.utc(2026, 4, 20));
    });

    test('reportDelay bumps version + creates sync queue UPDATE entry',
        () async {
      await _seedJob(db, 'job-1', 'Fix leak');

      await jobDao.reportDelay(
        jobId: 'job-1',
        reason: 'Supply chain',
        newEta: DateTime(2026, 5, 1),
        currentUserId: 'user-1',
        currentVersion: 1,
      );

      // Version bumped from 1 to 2
      final job = await (db.select(db.jobs)
            ..where((t) => t.id.equals('job-1')))
          .getSingle();
      expect(job.version, 2);

      // Sync queue has UPDATE entry
      final queueItems = await (db.select(db.syncQueue)
            ..where((t) =>
                t.entityId.equals('job-1') & t.operation.equals('UPDATE')))
          .get();
      expect(queueItems, hasLength(1));
      expect(queueItems.first.entityType, 'job');

      final payload =
          jsonDecode(queueItems.first.payload) as Map<String, dynamic>;
      expect(payload['id'], 'job-1');
      expect(payload['version'], 2);
      expect(payload.containsKey('scheduled_completion_date'), isTrue);
      expect(payload.containsKey('status_history'), isTrue);
    });

    test('multiple delays per job accumulate in statusHistory', () async {
      await _seedJob(db, 'job-1', 'Large project');

      // First delay
      await jobDao.reportDelay(
        jobId: 'job-1',
        reason: 'Permit delay',
        newEta: DateTime(2026, 4, 10),
        currentUserId: 'user-1',
        currentVersion: 1,
      );

      // Second delay
      await jobDao.reportDelay(
        jobId: 'job-1',
        reason: 'Material shortage',
        newEta: DateTime(2026, 5, 5),
        currentUserId: 'user-1',
        currentVersion: 2,
      );

      // Third delay
      await jobDao.reportDelay(
        jobId: 'job-1',
        reason: 'Weather',
        newEta: DateTime(2026, 5, 20),
        currentUserId: 'user-2',
        currentVersion: 3,
      );

      final job = await (db.select(db.jobs)
            ..where((t) => t.id.equals('job-1')))
          .getSingle();
      final history = jsonDecode(job.statusHistory) as List<dynamic>;

      expect(history, hasLength(3));
      expect((history[0] as Map)['reason'], 'Permit delay');
      expect((history[1] as Map)['reason'], 'Material shortage');
      expect((history[2] as Map)['reason'], 'Weather');

      // Version bumped 3 times: 1 → 2 → 3 → 4
      expect(job.version, 4);

      // Latest ETA is the last one reported — convert to UTC for comparison
      final scd = job.scheduledCompletionDate!.toUtc();
      expect(scd, DateTime.utc(2026, 5, 20));
    });

    test('delay entry has correct structure (type, reason, new_eta, timestamp, user_id)',
        () async {
      await _seedJob(db, 'job-1', 'Inspection');

      final newEta = DateTime(2026, 6, 1);
      await jobDao.reportDelay(
        jobId: 'job-1',
        reason: 'Inspector unavailable',
        newEta: newEta,
        currentUserId: 'user-42',
        currentVersion: 1,
      );

      final job = await (db.select(db.jobs)
            ..where((t) => t.id.equals('job-1')))
          .getSingle();
      final history = jsonDecode(job.statusHistory) as List<dynamic>;
      final entry = history[0] as Map<String, dynamic>;

      // Verify all required fields exist and have correct types
      expect(entry['type'], isA<String>());
      expect(entry['type'], 'delay');
      expect(entry['reason'], isA<String>());
      expect(entry['reason'], 'Inspector unavailable');
      expect(entry['new_eta'], isA<String>());
      expect(entry['new_eta'], '2026-06-01');
      expect(entry['timestamp'], isA<String>());
      // Timestamp should be valid ISO 8601 UTC
      final ts = DateTime.parse(entry['timestamp'] as String);
      expect(ts.isUtc, isTrue);
      expect(entry['user_id'], isA<String>());
      expect(entry['user_id'], 'user-42');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 2: Overdue Detection E2E
  // ──────────────────────────────────────────────────────────────────────────
  group('Phase 5 E2E: Overdue Detection', () {
    test('job 2 days past due → isOverdue true, severity warning', () {
      final twoDaysAgo =
          DateTime.now().subtract(const Duration(days: 2));

      expect(OverdueService.isOverdue('scheduled', twoDaysAgo), isTrue);
      expect(
        OverdueService.computeSeverity(twoDaysAgo),
        OverdueSeverity.warning,
      );
    });

    test('job 5 days past due → isOverdue true, severity critical', () {
      final fiveDaysAgo =
          DateTime.now().subtract(const Duration(days: 5));

      expect(OverdueService.isOverdue('in_progress', fiveDaysAgo), isTrue);
      expect(
        OverdueService.computeSeverity(fiveDaysAgo),
        OverdueSeverity.critical,
      );
    });

    test('job with future due date → isOverdue false, severity none', () {
      final futureDate =
          DateTime.now().add(const Duration(days: 10));

      expect(OverdueService.isOverdue('scheduled', futureDate), isFalse);
      expect(
        OverdueService.computeSeverity(futureDate),
        OverdueSeverity.none,
      );
    });

    test('completed job never overdue regardless of date', () {
      final wayPastDue =
          DateTime.now().subtract(const Duration(days: 30));

      expect(OverdueService.isOverdue('completed', wayPastDue), isFalse);
    });

    test('job with no scheduled date → not overdue', () {
      expect(OverdueService.isOverdue('scheduled', null), isFalse);
      expect(
        OverdueService.computeSeverity(null),
        OverdueSeverity.none,
      );
    });

    test('job 1 day past due → severity warning (boundary)', () {
      final yesterday =
          DateTime.now().subtract(const Duration(days: 1));

      expect(OverdueService.isOverdue('scheduled', yesterday), isTrue);
      expect(
        OverdueService.computeSeverity(yesterday),
        OverdueSeverity.warning,
      );
    });

    test('job 3 days past due → severity warning (upper boundary)', () {
      final threeDaysAgo =
          DateTime.now().subtract(const Duration(days: 3));

      expect(
        OverdueService.computeSeverity(threeDaysAgo),
        OverdueSeverity.warning,
      );
    });

    test('job 4 days past due → severity critical (lower boundary)', () {
      // Use midnight-aligned date to avoid time-of-day rounding issues
      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final fourDaysAgo = todayMidnight.subtract(const Duration(days: 4));

      expect(
        OverdueService.computeSeverity(fourDaysAgo),
        OverdueSeverity.critical,
      );
    });

    test('invoiced job never overdue', () {
      final pastDue =
          DateTime.now().subtract(const Duration(days: 10));
      expect(OverdueService.isOverdue('invoiced', pastDue), isFalse);
    });

    test('cancelled job never overdue', () {
      final pastDue =
          DateTime.now().subtract(const Duration(days: 10));
      expect(OverdueService.isOverdue('cancelled', pastDue), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 3: Multi-Day Booking E2E
  // ──────────────────────────────────────────────────────────────────────────
  group('Phase 5 E2E: Multi-Day Booking', () {
    late AppDatabase db;
    late BookingDao bookingDao;

    setUp(() async {
      db = _openTestDb();
      bookingDao = BookingDao(db);
      await _seedCompany(db);
      await _seedJob(db, 'job-multi', 'Large renovation');
    });

    tearDown(() async {
      await db.close();
    });

    test('create first-day booking + additional day bookings with dayIndex',
        () async {
      final day0Start = DateTime(2026, 4, 1, 8, 0);
      final day0End = DateTime(2026, 4, 1, 17, 0);

      // Day 0 — parent booking
      await bookingDao.createBooking(
        id: 'bk-day0',
        companyId: 'co-1',
        contractorId: 'ctr-1',
        jobId: 'job-multi',
        timeRangeStart: day0Start,
        timeRangeEnd: day0End,
        dayIndex: 0,
        parentBookingId: null,
      );

      // Day 1
      await bookingDao.createBooking(
        id: 'bk-day1',
        companyId: 'co-1',
        contractorId: 'ctr-1',
        jobId: 'job-multi',
        timeRangeStart: DateTime(2026, 4, 2, 8, 0),
        timeRangeEnd: DateTime(2026, 4, 2, 17, 0),
        dayIndex: 1,
        parentBookingId: 'bk-day0',
      );

      // Day 2
      await bookingDao.createBooking(
        id: 'bk-day2',
        companyId: 'co-1',
        contractorId: 'ctr-1',
        jobId: 'job-multi',
        timeRangeStart: DateTime(2026, 4, 3, 8, 0),
        timeRangeEnd: DateTime(2026, 4, 3, 17, 0),
        dayIndex: 2,
        parentBookingId: 'bk-day0',
      );

      // Verify all 3 bookings exist
      final allBookings = await db.select(db.bookings).get();
      expect(allBookings, hasLength(3));
    });

    test('all day bookings share same parentBookingId', () async {
      // Create parent (day 0)
      await bookingDao.createBooking(
        id: 'bk-p0',
        companyId: 'co-1',
        contractorId: 'ctr-1',
        jobId: 'job-multi',
        timeRangeStart: DateTime(2026, 4, 1, 8, 0),
        timeRangeEnd: DateTime(2026, 4, 1, 17, 0),
        dayIndex: 0,
        parentBookingId: null,
      );

      // Create children (day 1, day 2)
      await bookingDao.createBooking(
        id: 'bk-p1',
        companyId: 'co-1',
        contractorId: 'ctr-1',
        jobId: 'job-multi',
        timeRangeStart: DateTime(2026, 4, 2, 8, 0),
        timeRangeEnd: DateTime(2026, 4, 2, 17, 0),
        dayIndex: 1,
        parentBookingId: 'bk-p0',
      );

      await bookingDao.createBooking(
        id: 'bk-p2',
        companyId: 'co-1',
        contractorId: 'ctr-1',
        jobId: 'job-multi',
        timeRangeStart: DateTime(2026, 4, 3, 8, 0),
        timeRangeEnd: DateTime(2026, 4, 3, 17, 0),
        dayIndex: 2,
        parentBookingId: 'bk-p0',
      );

      // Verify parentBookingId on children
      final bk1 = await (db.select(db.bookings)
            ..where((t) => t.id.equals('bk-p1')))
          .getSingle();
      final bk2 = await (db.select(db.bookings)
            ..where((t) => t.id.equals('bk-p2')))
          .getSingle();

      expect(bk1.parentBookingId, 'bk-p0');
      expect(bk2.parentBookingId, 'bk-p0');

      // Parent has no parentBookingId
      final bk0 = await (db.select(db.bookings)
            ..where((t) => t.id.equals('bk-p0')))
          .getSingle();
      expect(bk0.parentBookingId, isNull);
    });

    test('each booking has correct dayIndex (0, 1, 2)', () async {
      for (var i = 0; i < 3; i++) {
        await bookingDao.createBooking(
          id: 'bk-idx-$i',
          companyId: 'co-1',
          contractorId: 'ctr-1',
          jobId: 'job-multi',
          timeRangeStart: DateTime(2026, 4, 1 + i, 8, 0),
          timeRangeEnd: DateTime(2026, 4, 1 + i, 17, 0),
          dayIndex: i,
          parentBookingId: i == 0 ? null : 'bk-idx-0',
        );
      }

      for (var i = 0; i < 3; i++) {
        final bk = await (db.select(db.bookings)
              ..where((t) => t.id.equals('bk-idx-$i')))
            .getSingle();
        expect(bk.dayIndex, i);
      }
    });

    test('sync queue has CREATE entry for each day booking', () async {
      for (var i = 0; i < 3; i++) {
        await bookingDao.createBooking(
          id: 'bk-sq-$i',
          companyId: 'co-1',
          contractorId: 'ctr-1',
          jobId: 'job-multi',
          timeRangeStart: DateTime(2026, 4, 1 + i, 8, 0),
          timeRangeEnd: DateTime(2026, 4, 1 + i, 17, 0),
          dayIndex: i,
          parentBookingId: i == 0 ? null : 'bk-sq-0',
        );
      }

      // Verify 3 CREATE entries in sync queue for booking entity type
      final queueItems = await (db.select(db.syncQueue)
            ..where((t) =>
                t.entityType.equals('booking') &
                t.operation.equals('CREATE')))
          .get();
      expect(queueItems, hasLength(3));

      // Verify each queue item references correct booking
      final entityIds = queueItems.map((q) => q.entityId).toSet();
      expect(entityIds, containsAll(['bk-sq-0', 'bk-sq-1', 'bk-sq-2']));

      // Verify payload contains dayIndex for child bookings
      for (final item in queueItems) {
        final payload =
            jsonDecode(item.payload) as Map<String, dynamic>;
        if (item.entityId == 'bk-sq-1' || item.entityId == 'bk-sq-2') {
          expect(payload['day_index'], isNotNull);
          expect(payload['parent_booking_id'], 'bk-sq-0');
        }
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 4: SyncStatus Subtitle Rendering E2E
  // ──────────────────────────────────────────────────────────────────────────
  group('Phase 5 E2E: SyncStatus Subtitle Rendering', () {
    test('offline → "Offline"', () {
      const status = SyncStatus(SyncState.offline, 0);
      expect(status.subtitle, 'Offline');
    });

    test('allSynced → "All synced"', () {
      const status = SyncStatus(SyncState.allSynced, 0);
      expect(status.subtitle, 'All synced');
    });

    test('pending with 3 items → "3 item(s) pending"', () {
      const status = SyncStatus(SyncState.pending, 3);
      expect(status.subtitle, '3 item(s) pending');
    });

    test('syncing 2 of 5 → "Syncing 2 of 5..."', () {
      const status = SyncStatus(SyncState.syncing, 5, syncingOf: 2);
      expect(status.subtitle, 'Syncing 2 of 5...');
    });

    test('SyncStatus with upload progress shows combined message', () {
      const status = SyncStatus(
        SyncState.allSynced,
        4,
        uploadTotal: 5,
        uploadCompleted: 2,
      );
      expect(
        status.subtitle,
        '4 item(s) synced, 5 photos uploading (2/5)',
      );
    });

    test('offline with upload progress still shows "Offline"', () {
      const status = SyncStatus(
        SyncState.offline,
        0,
        uploadTotal: 3,
        uploadCompleted: 1,
      );
      // Offline takes priority over upload progress
      expect(status.subtitle, 'Offline');
    });

    test('pending with 1 item → "1 item(s) pending"', () {
      const status = SyncStatus(SyncState.pending, 1);
      expect(status.subtitle, '1 item(s) pending');
    });

    test('withUploadProgress creates correct copy', () {
      const original = SyncStatus(SyncState.allSynced, 3);
      final updated = original.withUploadProgress(
        uploadTotal: 10,
        uploadCompleted: 4,
      );
      expect(updated.state, SyncState.allSynced);
      expect(updated.pendingCount, 3);
      expect(updated.uploadTotal, 10);
      expect(updated.uploadCompleted, 4);
      expect(
        updated.subtitle,
        '3 item(s) synced, 10 photos uploading (4/10)',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 5: Booking + Delay Combined Flow E2E
  // ──────────────────────────────────────────────────────────────────────────
  group('Phase 5 E2E: Booking + Delay Combined Flow', () {
    late AppDatabase db;
    late JobDao jobDao;
    late BookingDao bookingDao;

    setUp(() async {
      db = _openTestDb();
      jobDao = JobDao(db);
      bookingDao = BookingDao(db);
      await _seedCompany(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'create booking for job → report delay → verify both booking and delay recorded',
        () async {
      final originalDue = DateTime(2026, 3, 15);
      await _seedJob(db, 'job-combo', 'Bathroom remodel',
          scheduledCompletion: originalDue);

      // Create a booking for the job
      await bookingDao.createBooking(
        id: 'bk-combo',
        companyId: 'co-1',
        contractorId: 'ctr-1',
        jobId: 'job-combo',
        timeRangeStart: DateTime(2026, 3, 14, 9, 0),
        timeRangeEnd: DateTime(2026, 3, 14, 17, 0),
      );

      // Verify booking exists
      final allBookings = await db.select(db.bookings).get();
      expect(allBookings, hasLength(1));
      expect(allBookings.first.jobId, 'job-combo');

      // Report a delay on the same job
      await jobDao.reportDelay(
        jobId: 'job-combo',
        reason: 'Tile supplier delayed shipment',
        newEta: DateTime(2026, 4, 1),
        currentUserId: 'user-1',
        currentVersion: 1,
      );

      // Verify delay recorded in statusHistory
      final job = await (db.select(db.jobs)
            ..where((t) => t.id.equals('job-combo')))
          .getSingle();
      final history = jsonDecode(job.statusHistory) as List<dynamic>;
      expect(history, hasLength(1));
      expect((history[0] as Map)['type'], 'delay');
      expect((history[0] as Map)['reason'], 'Tile supplier delayed shipment');

      // Booking still exists and is unaffected
      final booking = await (db.select(db.bookings)
            ..where((t) => t.id.equals('bk-combo')))
          .getSingle();
      expect(booking.jobId, 'job-combo');

      // Sync queue has both CREATE (booking) and UPDATE (delay) entries
      final queueItems = await db.select(db.syncQueue).get();
      final bookingCreates = queueItems
          .where((q) =>
              q.entityType == 'booking' && q.operation == 'CREATE')
          .toList();
      final jobUpdates = queueItems
          .where(
              (q) => q.entityType == 'job' && q.operation == 'UPDATE')
          .toList();
      expect(bookingCreates, hasLength(1));
      expect(jobUpdates, hasLength(1));
    });

    test(
        'delayed job scheduledCompletionDate updated → overdue severity recalculated',
        () async {
      // Job due 2 days ago (warning severity)
      final twoDaysAgo =
          DateTime.now().subtract(const Duration(days: 2));
      await _seedJob(db, 'job-overdue', 'Roof repair',
          scheduledCompletion: twoDaysAgo);

      // Confirm it is currently overdue (warning)
      expect(OverdueService.isOverdue('scheduled', twoDaysAgo), isTrue);
      expect(
        OverdueService.computeSeverity(twoDaysAgo),
        OverdueSeverity.warning,
      );

      // Report delay with new ETA far in the future
      final futureEta =
          DateTime.now().add(const Duration(days: 30));
      await jobDao.reportDelay(
        jobId: 'job-overdue',
        reason: 'Material backorder resolved',
        newEta: futureEta,
        currentUserId: 'user-1',
        currentVersion: 1,
      );

      // Read updated job
      final updatedJob = await (db.select(db.jobs)
            ..where((t) => t.id.equals('job-overdue')))
          .getSingle();

      // After delay update, the new scheduledCompletionDate is in the future
      expect(
        OverdueService.isOverdue(
            updatedJob.status, updatedJob.scheduledCompletionDate),
        isFalse,
      );
      expect(
        OverdueService.computeSeverity(updatedJob.scheduledCompletionDate),
        OverdueSeverity.none,
      );
    });

    test('multiple delays then booking creation → all data coexists',
        () async {
      await _seedJob(db, 'job-multi-delay', 'Kitchen remodel',
          scheduledCompletion: DateTime(2026, 3, 10));

      // Two delays
      await jobDao.reportDelay(
        jobId: 'job-multi-delay',
        reason: 'Countertop backorder',
        newEta: DateTime(2026, 3, 25),
        currentUserId: 'user-1',
        currentVersion: 1,
      );
      await jobDao.reportDelay(
        jobId: 'job-multi-delay',
        reason: 'Plumber schedule conflict',
        newEta: DateTime(2026, 4, 5),
        currentUserId: 'user-1',
        currentVersion: 2,
      );

      // Create booking after delays
      await bookingDao.createBooking(
        id: 'bk-after-delay',
        companyId: 'co-1',
        contractorId: 'ctr-1',
        jobId: 'job-multi-delay',
        timeRangeStart: DateTime(2026, 4, 4, 9, 0),
        timeRangeEnd: DateTime(2026, 4, 4, 17, 0),
      );

      // Verify 2 delays in history
      final job = await (db.select(db.jobs)
            ..where((t) => t.id.equals('job-multi-delay')))
          .getSingle();
      final history = jsonDecode(job.statusHistory) as List<dynamic>;
      expect(history, hasLength(2));

      // Verify booking exists
      final booking = await (db.select(db.bookings)
            ..where((t) => t.id.equals('bk-after-delay')))
          .getSingle();
      expect(booking.jobId, 'job-multi-delay');

      // Sync queue has 2 UPDATE (delays) + 1 CREATE (booking)
      final queueItems = await db.select(db.syncQueue).get();
      expect(queueItems.length, greaterThanOrEqualTo(3));
    });
  });
}
