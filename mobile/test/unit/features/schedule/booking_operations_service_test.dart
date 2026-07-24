/// Unit tests for [BookingOperationsService] using a real in-memory Drift DB.
///
/// This logic previously lived in `BookingOperationsNotifier` and had no
/// coverage. Tests exercise the full mutation + undo lifecycle:
/// 1. bookSlot persists a booking and returns a create UndoAction
/// 2. bookSlot auto-transitions a 'quote' job to 'scheduled'
/// 3. reassignBooking moves contractor/time and captures previous state
/// 4. resizeBooking updates the time range
/// 5. bookMultiDay creates child bookings grouped under the parent
/// 6. undo reverses create (soft-delete) and multiDayCreate (all days)
library;

import 'package:contractorhub/core/database/app_database.dart';
import 'package:contractorhub/features/schedule/data/booking_operations_service.dart';
import 'package:contractorhub/features/schedule/domain/booking_operation_models.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _openTestDb() => AppDatabase(NativeDatabase.memory());

const _companyId = 'co-1';
const _contractorId = 'contractor-1';
const _jobId = 'job-1';

Future<void> _seedCompanyAndJob(AppDatabase db, {String status = 'scheduled'}) {
  final now = DateTime.now();
  return db.transaction(() async {
    await db.companyDao.insertCompany(CompaniesCompanion.insert(
      id: const Value(_companyId),
      name: 'Company',
      version: const Value(1),
      createdAt: now,
      updatedAt: now,
    ));
    await db.jobDao.insertJob(JobsCompanion.insert(
      id: const Value(_jobId),
      companyId: _companyId,
      description: 'Test job',
      tradeType: 'plumber',
      status: Value(status),
      createdAt: now,
      updatedAt: now,
    ));
  });
}

Future<Booking?> _bookingById(AppDatabase db, String id) {
  return (db.select(db.bookings)..where((b) => b.id.equals(id)))
      .getSingleOrNull();
}

void main() {
  late AppDatabase db;
  late BookingOperationsService service;

  setUp(() async {
    db = _openTestDb();
    service = BookingOperationsService(bookingDao: db.bookingDao, jobDao: db.jobDao);
  });

  tearDown(() async => db.close());

  DateTime slotStart() => DateTime(2025, 6, 2, 9);

  group('bookSlot', () {
    test('persists a booking and returns a create UndoAction', () async {
      await _seedCompanyAndJob(db);

      final result = await service.bookSlot(
        companyId: _companyId,
        contractorId: _contractorId,
        jobId: _jobId,
        slotStart: slotStart(),
        durationMinutes: 120,
      );

      final booking = await _bookingById(db, result.bookingId);
      expect(booking, isNotNull);
      expect(booking!.contractorId, _contractorId);
      expect(booking.timeRangeEnd.difference(booking.timeRangeStart).inMinutes,
          120);
      expect(result.undo.type, UndoActionType.create);
      expect(result.undo.expectedVersion, 1);
    });

    test('auto-transitions a quote job to scheduled', () async {
      await _seedCompanyAndJob(db, status: 'quote');

      await service.bookSlot(
        companyId: _companyId,
        contractorId: _contractorId,
        jobId: _jobId,
        slotStart: slotStart(),
        durationMinutes: 60,
        jobCurrentStatus: 'quote',
      );

      final job = await db.jobDao.watchJobById(_jobId).first;
      expect(job?.status, 'scheduled');
    });

    test('leaves a non-quote job status unchanged', () async {
      await _seedCompanyAndJob(db);

      await service.bookSlot(
        companyId: _companyId,
        contractorId: _contractorId,
        jobId: _jobId,
        slotStart: slotStart(),
        durationMinutes: 60,
        jobCurrentStatus: 'scheduled',
      );

      final job = await db.jobDao.watchJobById(_jobId).first;
      expect(job?.status, 'scheduled');
    });
  });

  group('reassignBooking', () {
    test('moves contractor/time and captures previous state', () async {
      await _seedCompanyAndJob(db);
      final created = await service.bookSlot(
        companyId: _companyId,
        contractorId: _contractorId,
        jobId: _jobId,
        slotStart: slotStart(),
        durationMinutes: 60,
      );

      final newStart = DateTime(2025, 6, 2, 14);
      final undo = await service.reassignBooking(
        bookingId: created.bookingId,
        newContractorId: 'contractor-2',
        newStart: newStart,
        newEnd: newStart.add(const Duration(hours: 1)),
        previousContractorId: _contractorId,
        previousStart: slotStart(),
        previousEnd: slotStart().add(const Duration(hours: 1)),
        currentVersion: 1,
      );

      final booking = await _bookingById(db, created.bookingId);
      expect(booking!.contractorId, 'contractor-2');
      expect(booking.timeRangeStart, newStart);
      expect(undo.type, UndoActionType.reassign);
      expect(undo.previousContractorId, _contractorId);
      expect(undo.expectedVersion, 2);
    });
  });

  group('resizeBooking', () {
    test('updates the time range', () async {
      await _seedCompanyAndJob(db);
      final created = await service.bookSlot(
        companyId: _companyId,
        contractorId: _contractorId,
        jobId: _jobId,
        slotStart: slotStart(),
        durationMinutes: 60,
      );

      final newEnd = slotStart().add(const Duration(hours: 3));
      final undo = await service.resizeBooking(
        bookingId: created.bookingId,
        newStart: slotStart(),
        newEnd: newEnd,
        previousStart: slotStart(),
        previousEnd: slotStart().add(const Duration(hours: 1)),
        currentVersion: 1,
      );

      final booking = await _bookingById(db, created.bookingId);
      expect(booking!.timeRangeEnd, newEnd);
      expect(undo.type, UndoActionType.resize);
    });
  });

  group('bookMultiDay', () {
    test('creates child bookings grouped under the parent', () async {
      await _seedCompanyAndJob(db);
      final parent = await service.bookSlot(
        companyId: _companyId,
        contractorId: _contractorId,
        jobId: _jobId,
        slotStart: slotStart(),
        durationMinutes: 60,
      );

      final undo = await service.bookMultiDay(
        companyId: _companyId,
        jobId: _jobId,
        parentBookingId: parent.bookingId,
        additionalDays: [
          DayBlock(
            contractorId: _contractorId,
            startTime: DateTime(2025, 6, 3, 9),
            endTime: DateTime(2025, 6, 3, 12),
          ),
          DayBlock(
            contractorId: _contractorId,
            startTime: DateTime(2025, 6, 4, 9),
            endTime: DateTime(2025, 6, 4, 12),
          ),
        ],
      );

      expect(undo.type, UndoActionType.multiDayCreate);
      expect(undo.childBookingIds, hasLength(2));
      for (final childId in undo.childBookingIds) {
        final child = await _bookingById(db, childId);
        expect(child, isNotNull);
        expect(child!.parentBookingId, parent.bookingId);
      }
    });
  });

  group('undo', () {
    test('reverses a create by soft-deleting the booking', () async {
      await _seedCompanyAndJob(db);
      final created = await service.bookSlot(
        companyId: _companyId,
        contractorId: _contractorId,
        jobId: _jobId,
        slotStart: slotStart(),
        durationMinutes: 60,
      );

      await service.undo(created.undo);

      final booking = await _bookingById(db, created.bookingId);
      expect(booking!.deletedAt, isNotNull);
    });

    test('reverses a multiDayCreate by soft-deleting parent and children',
        () async {
      await _seedCompanyAndJob(db);
      final parent = await service.bookSlot(
        companyId: _companyId,
        contractorId: _contractorId,
        jobId: _jobId,
        slotStart: slotStart(),
        durationMinutes: 60,
      );
      final undo = await service.bookMultiDay(
        companyId: _companyId,
        jobId: _jobId,
        parentBookingId: parent.bookingId,
        additionalDays: [
          DayBlock(
            contractorId: _contractorId,
            startTime: DateTime(2025, 6, 3, 9),
            endTime: DateTime(2025, 6, 3, 12),
          ),
        ],
      );

      await service.undo(undo);

      final parentBooking = await _bookingById(db, parent.bookingId);
      expect(parentBooking!.deletedAt, isNotNull);
      for (final childId in undo.childBookingIds) {
        final child = await _bookingById(db, childId);
        expect(child!.deletedAt, isNotNull);
      }
    });
  });
}
