/// Data models for calendar drag/drop and booking mutation/undo tracking.
///
/// Extracted from `calendar_providers.dart` so the presentation layer holds
/// providers, not data structures (SRP).
library;

/// Data payload carried by LongPressDraggable for scheduling drag operations.
///
/// Used by both the unscheduled jobs drawer (new booking) and existing booking
/// cards (reassign/move). When [existingBookingId] is non-null, the drag
/// represents a reassignment rather than a new booking creation.
class BookingDragData {
  const BookingDragData({
    required this.jobId,
    required this.durationMinutes,
    this.existingBookingId,
    this.sourceContractorId,
    this.previousStart,
    this.previousEnd,
    this.previousVersion,
  });

  /// The job being scheduled or reassigned.
  final String jobId;

  /// Estimated or actual booking duration in minutes.
  final int durationMinutes;

  /// Non-null when dragging an existing booking (reassign/move operation).
  final String? existingBookingId;

  /// Non-null when dragging an existing booking from another contractor's lane.
  final String? sourceContractorId;

  /// Original start time of the booking being dragged (cross-lane reassignment).
  final DateTime? previousStart;

  /// Original end time of the booking being dragged (cross-lane reassignment).
  final DateTime? previousEnd;

  /// Version of the booking being dragged (for optimistic concurrency).
  final int? previousVersion;
}

/// Information about a detected scheduling conflict.
///
/// Written by ContractorLane's DragTarget.onWillAcceptWithDetails when a
/// conflict is detected during drag. Read by schedule_screen.dart in
/// LongPressDraggable.onDragEnd(wasAccepted: false) to show a snackbar.
class ConflictInfo {
  const ConflictInfo({
    required this.conflictingJobDescription,
    required this.conflictingTimeRange,
  });

  /// Description of the job that already occupies the target slot.
  final String conflictingJobDescription;

  /// Human-readable time range of the conflicting booking.
  final String conflictingTimeRange;
}

/// Type of booking mutation for undo tracking.
enum UndoActionType { create, reassign, resize, multiDayCreate }

/// Snapshot of a booking state before a mutation, enabling undo.
class UndoAction {
  const UndoAction({
    required this.type,
    required this.bookingId,
    required this.expectedVersion,
    this.previousContractorId,
    this.previousStart,
    this.previousEnd,
    this.childBookingIds = const [],
    this.childExpectedVersions = const [],
  });

  final UndoActionType type;
  final String bookingId;

  /// The version the booking will be at after the forward mutation.
  ///
  /// Used by undo as the currentVersion for the reverse operation.
  /// - For creates: 1 (booking starts at version 1).
  /// - For reassign/resize: currentVersion+1 (version after forward mutation).
  /// - For multiDayCreate: 1 for all child bookings.
  final int expectedVersion;

  /// Original contractorId before a reassign operation.
  final String? previousContractorId;

  /// Original start time before a reassign or resize operation.
  final DateTime? previousStart;

  /// Original end time before a reassign or resize operation.
  final DateTime? previousEnd;

  /// Child booking IDs for multi-day creates (all removed on undo).
  final List<String> childBookingIds;

  /// Expected versions for child bookings (parallel to [childBookingIds]).
  final List<int> childExpectedVersions;
}

/// Represents a single day block in a multi-day booking wizard.
class DayBlock {
  const DayBlock({
    required this.contractorId,
    required this.startTime,
    required this.endTime,
  });

  final String contractorId;
  final DateTime startTime;
  final DateTime endTime;
}
