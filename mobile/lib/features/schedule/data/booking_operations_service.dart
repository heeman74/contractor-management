import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../jobs/data/job_dao.dart';
import '../../jobs/domain/job_status.dart';
import '../domain/booking_operation_models.dart';
import 'booking_dao.dart';

/// Encapsulates all booking mutation logic for the dispatch calendar.
///
/// Each mutation writes to Drift (offline-first, via the DAOs) and returns the
/// [UndoAction] needed to reverse it. Undo-stack state itself lives in the
/// presentation layer (Riverpod), keeping this service free of framework
/// dependencies and unit-testable with a real in-memory database.
class BookingOperationsService {
  BookingOperationsService({
    required BookingDao bookingDao,
    required JobDao jobDao,
    Uuid uuid = const Uuid(),
  })  : _bookingDao = bookingDao,
        _jobDao = jobDao,
        _uuid = uuid;

  final BookingDao _bookingDao;
  final JobDao _jobDao;
  final Uuid _uuid;

  static const int _initialVersion = 1;
  static const String _systemUserId = 'system';
  static const String _bookingCreatedReason = 'booking_created';

  /// Creates a booking at [slotStart]; auto-transitions a 'quote' job to
  /// 'scheduled'. Returns the new booking id and the create [UndoAction].
  Future<({String bookingId, UndoAction undo})> bookSlot({
    required String companyId,
    required String contractorId,
    required String jobId,
    required DateTime slotStart,
    required int durationMinutes,
    String? jobCurrentStatus,
    int jobCurrentVersion = _initialVersion,
    List<Map<String, dynamic>>? jobStatusHistory,
  }) async {
    final bookingId = _uuid.v4();
    final slotEnd = slotStart.add(Duration(minutes: durationMinutes));

    await _bookingDao.createBooking(
      id: bookingId,
      companyId: companyId,
      contractorId: contractorId,
      jobId: jobId,
      timeRangeStart: slotStart,
      timeRangeEnd: slotEnd,
    );

    await _autoScheduleQuote(
      jobId: jobId,
      currentStatus: jobCurrentStatus,
      currentVersion: jobCurrentVersion,
      statusHistory: jobStatusHistory,
    );

    return (
      bookingId: bookingId,
      undo: UndoAction(
        type: UndoActionType.create,
        bookingId: bookingId,
        expectedVersion: _initialVersion,
      ),
    );
  }

  Future<void> _autoScheduleQuote({
    required String jobId,
    required String? currentStatus,
    required int currentVersion,
    required List<Map<String, dynamic>>? statusHistory,
  }) async {
    if (currentStatus != JobStatus.quote.backendValue) return;

    final history = List<Map<String, dynamic>>.from(statusHistory ?? []);
    history.add({
      'status': JobStatus.scheduled.backendValue,
      'timestamp': DateTime.now().toIso8601String(),
      'userId': _systemUserId,
      'reason': _bookingCreatedReason,
    });
    await _jobDao.updateJobStatus(
      jobId,
      JobStatus.scheduled.backendValue,
      jsonEncode(history),
      currentVersion + 1,
    );
  }

  /// Reassigns a booking to a new contractor and/or time. Returns the
  /// reassign [UndoAction] capturing the previous state.
  Future<UndoAction> reassignBooking({
    required String bookingId,
    required String newContractorId,
    required DateTime newStart,
    required DateTime newEnd,
    required String previousContractorId,
    required DateTime previousStart,
    required DateTime previousEnd,
    required int currentVersion,
  }) async {
    await _bookingDao.updateBookingContractorAndTime(
      bookingId,
      newContractorId,
      newStart,
      newEnd,
      currentVersion,
    );

    return UndoAction(
      type: UndoActionType.reassign,
      bookingId: bookingId,
      expectedVersion: currentVersion + 1,
      previousContractorId: previousContractorId,
      previousStart: previousStart,
      previousEnd: previousEnd,
    );
  }

  /// Resizes a booking's time range. Returns the resize [UndoAction].
  Future<UndoAction> resizeBooking({
    required String bookingId,
    required DateTime newStart,
    required DateTime newEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
    required int currentVersion,
  }) async {
    await _bookingDao.updateBookingTime(
      bookingId,
      newStart,
      newEnd,
      currentVersion,
    );

    return UndoAction(
      type: UndoActionType.resize,
      bookingId: bookingId,
      expectedVersion: currentVersion + 1,
      previousStart: previousStart,
      previousEnd: previousEnd,
    );
  }

  /// Creates the additional day bookings for a multi-day job. Returns a
  /// multiDayCreate [UndoAction] that groups the parent and all children.
  Future<UndoAction> bookMultiDay({
    required String companyId,
    required String jobId,
    required String parentBookingId,
    required List<DayBlock> additionalDays,
  }) async {
    final childIds = <String>[];

    for (var i = 0; i < additionalDays.length; i++) {
      final day = additionalDays[i];
      final childId = _uuid.v4();
      childIds.add(childId);

      await _bookingDao.createBooking(
        id: childId,
        companyId: companyId,
        contractorId: day.contractorId,
        jobId: jobId,
        timeRangeStart: day.startTime,
        timeRangeEnd: day.endTime,
        dayIndex: i + 1, // 0 = parent, 1+ = additional days
        parentBookingId: parentBookingId,
      );
    }

    return UndoAction(
      type: UndoActionType.multiDayCreate,
      bookingId: parentBookingId,
      expectedVersion: _initialVersion,
      childBookingIds: childIds,
      childExpectedVersions: List.filled(childIds.length, _initialVersion),
    );
  }

  /// Reverses a previously applied [action].
  Future<void> undo(UndoAction action) async {
    switch (action.type) {
      case UndoActionType.create:
        await _bookingDao.softDeleteBooking(
            action.bookingId, action.expectedVersion);

      case UndoActionType.reassign:
        if (action.previousContractorId != null &&
            action.previousStart != null &&
            action.previousEnd != null) {
          await _bookingDao.updateBookingContractorAndTime(
            action.bookingId,
            action.previousContractorId!,
            action.previousStart!,
            action.previousEnd!,
            action.expectedVersion,
          );
        }

      case UndoActionType.resize:
        if (action.previousStart != null && action.previousEnd != null) {
          await _bookingDao.updateBookingTime(
            action.bookingId,
            action.previousStart!,
            action.previousEnd!,
            action.expectedVersion,
          );
        }

      case UndoActionType.multiDayCreate:
        for (var i = 0; i < action.childBookingIds.length; i++) {
          final childVersion = i < action.childExpectedVersions.length
              ? action.childExpectedVersions[i]
              : action.expectedVersion;
          await _bookingDao.softDeleteBooking(
              action.childBookingIds[i], childVersion);
        }
        await _bookingDao.softDeleteBooking(
            action.bookingId, action.expectedVersion);
    }
  }
}
