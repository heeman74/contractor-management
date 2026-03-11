import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to legacy in Riverpod 3 — explicitly imported.
// ignore: depend_on_referenced_packages
import 'package:riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/schedule/domain/booking_entity.dart';
import '../../../../features/users/domain/user_entity.dart';

// ────────────────────────────────────────────────────────────────────────────
// View mode enum
// ────────────────────────────────────────────────────────────────────────────

/// Calendar display mode. Week and month views are planned for Plan 05.
enum CalendarViewMode {
  day,
  week,
  month;

  String get label => switch (this) {
        CalendarViewMode.day => 'Day',
        CalendarViewMode.week => 'Week',
        CalendarViewMode.month => 'Month',
      };
}

// ────────────────────────────────────────────────────────────────────────────
// Status color map
// ────────────────────────────────────────────────────────────────────────────

/// Color coding for job lifecycle statuses on booking cards.
///
/// Used by [BookingCard] to set background fill + border color.
const Map<String, Color> statusColorMap = {
  'quote': Colors.grey,
  'scheduled': Colors.blue,
  'in_progress': Colors.orange,
  'complete': Colors.green,
  'invoiced': Colors.purple,
  'cancelled': Colors.red,
};

/// Pixels per minute scale factor for the time axis and booking card sizing.
/// 2.0 px/min = 120px/hour — readable density on mobile without excessive scrolling.
const double pixelsPerMinute = 2.0;

// ────────────────────────────────────────────────────────────────────────────
// Calendar state providers (UI state, no async)
// ────────────────────────────────────────────────────────────────────────────

/// Currently selected date for the day view calendar.
///
/// Defaults to today. Changed by date navigation arrows, "Today" button,
/// and the date picker dialog in ScheduleScreen.
final calendarDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Current calendar display mode (day / week / month).
///
/// Week and month modes show "Coming soon" until Plan 05 implements them.
final calendarViewModeProvider =
    StateProvider<CalendarViewMode>((ref) => CalendarViewMode.day);

/// Current page index for paginated contractor lanes.
///
/// Each page shows up to 5 contractors. Prev/next pagination buttons in
/// CalendarDayView update this provider.
final contractorPageIndexProvider = StateProvider<int>((ref) => 0);

/// Whether completed/invoiced/cancelled bookings are shown on the calendar.
///
/// When false (default), terminal-status bookings are dimmed at 0.4 opacity.
/// When true, all bookings display at full opacity.
final showCompletedJobsProvider = StateProvider<bool>((ref) => false);

/// Trade type filter for contractor lane visibility.
///
/// null = show all contractors. A trade type string (e.g., 'electrician')
/// narrows visible contractor lanes to those matching the trade.
final calendarTradeTypeFilterProvider = StateProvider<String?>((ref) => null);

// ────────────────────────────────────────────────────────────────────────────
// DAO providers
// ────────────────────────────────────────────────────────────────────────────

/// Provider exposing the [BookingDao] singleton from GetIt.
///
/// NOTE: GetIt is used because BookingDao is a database accessor registered
/// at startup in service_locator.dart. Riverpod providers read it via this
/// provider — dependency is explicit and testable via ProviderScope overrides.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final bookingDaoProvider = Provider<BookingDao>((ref) {
  return getIt<BookingDao>();
});

/// Provider exposing the [AppDatabase] singleton from GetIt for UserDao access.
///
/// UserDao is accessed via AppDatabase.userDao (not registered directly in
/// GetIt). This matches the pattern in user_providers.dart.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return getIt<AppDatabase>();
});

// ────────────────────────────────────────────────────────────────────────────
// Bookings for selected date
// ────────────────────────────────────────────────────────────────────────────

/// Streams bookings for the currently selected calendar date.
///
/// Watches [BookingDao.watchBookingsByCompanyAndDateRange] scoped to the
/// currently selected date (dayStart → dayStart + 1 day).
///
/// Uses [AsyncNotifier] because [build()] must await the auth state before
/// setting up the stream subscription. The stream stays live for the lifetime
/// of the provider, re-emitting on every Drift DB change.
class BookingsForDateNotifier extends AsyncNotifier<List<BookingEntity>> {
  @override
  Future<List<BookingEntity>> build() async {
    final authState = ref.watch(authNotifierProvider);
    if (authState is! AuthAuthenticated) return [];

    final selectedDate = ref.watch(calendarDateProvider);
    final dao = ref.watch(bookingDaoProvider);
    final companyId = authState.companyId;

    final dayStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));

    final stream = dao.watchBookingsByCompanyAndDateRange(
      companyId,
      dayStart,
      dayEnd,
    );

    // Keep the provider alive while the stream emits; propagate errors.
    final sub = stream.listen(
      (bookings) => state = AsyncData(bookings),
      onError: (Object e, StackTrace st) => state = AsyncError(e, st),
    );
    ref.onDispose(sub.cancel);

    return await stream.first;
  }
}

/// Provider for [BookingsForDateNotifier].
final bookingsForDateProvider =
    AsyncNotifierProvider<BookingsForDateNotifier, List<BookingEntity>>(
  BookingsForDateNotifier.new,
);

// ────────────────────────────────────────────────────────────────────────────
// Contractor list providers
// ────────────────────────────────────────────────────────────────────────────

/// Streams users with the 'contractor' role for the current company.
///
/// The schedule screen displays these as contractor lanes. Previously this
/// loaded ALL users (admin, client, contractor), making the schedule confusing
/// and scheduling non-functional for non-contractor users.
class ContractorsNotifier extends AsyncNotifier<List<UserEntity>> {
  @override
  Future<List<UserEntity>> build() async {
    final authState = ref.watch(authNotifierProvider);
    if (authState is! AuthAuthenticated) return [];

    final db = ref.watch(appDatabaseProvider);
    final companyId = authState.companyId;

    final stream = db.userDao.watchUsersByRole(companyId, 'contractor');

    final sub = stream.listen(
      (users) => state = AsyncData(users),
      onError: (Object e, StackTrace st) => state = AsyncError(e, st),
    );
    ref.onDispose(sub.cancel);

    return await stream.first;
  }
}

/// Provider for [ContractorsNotifier].
///
/// Returns all active users for the current company. Filter by contractor role
/// is applied downstream in [filteredContractorsProvider].
final contractorsProvider =
    AsyncNotifierProvider<ContractorsNotifier, List<UserEntity>>(
  ContractorsNotifier.new,
);

/// Derived provider: applies trade type filter and paginates to 5 per page.
///
/// Filters [contractorsProvider] results:
///   1. If [calendarTradeTypeFilterProvider] is non-null, only returns users
///      whose [tradeType] field contains the selected trade type.
///   2. Paginates to 5 per page using [contractorPageIndexProvider].
///
/// Note: UserEntity does not have a tradeType field (users table stores trade
/// types as a separate relation in the backend). For now we paginate the full
/// list — trade type filter will be applied when trade type data is available
/// on UserEntity.
final filteredContractorsProvider = Provider<AsyncValue<List<UserEntity>>>(
  (ref) {
    final contractorsAsync = ref.watch(contractorsProvider);
    final tradeFilter = ref.watch(calendarTradeTypeFilterProvider);
    final pageIndex = ref.watch(contractorPageIndexProvider);

    return contractorsAsync.whenData((users) {
      // Apply trade type filter when available.
      // UserEntity currently lacks tradeType — this hook is ready for Plan 05
      // when user profiles include trade specialization.
      var filtered = users;
      if (tradeFilter != null) {
        // Placeholder: filter would be applied here when UserEntity has tradeType.
        // For now all users pass through the filter.
        filtered = users;
      }

      // Paginate: 5 contractors per page.
      const perPage = 5;
      final start = pageIndex * perPage;
      if (start >= filtered.length) return <UserEntity>[];
      final end =
          (start + perPage < filtered.length) ? start + perPage : filtered.length;
      return filtered.sublist(start, end);
    });
  },
);

/// Total number of contractor pages for the current filter.
///
/// Used by pagination controls in CalendarDayView to render dots/prev/next.
final contractorPageCountProvider = Provider<int>((ref) {
  final contractorsAsync = ref.watch(contractorsProvider);
  return contractorsAsync.maybeWhen(
    data: (users) => (users.length / 5).ceil().clamp(1, 999),
    orElse: () => 1,
  );
});

// ────────────────────────────────────────────────────────────────────────────
// Drag-and-drop data model
// ────────────────────────────────────────────────────────────────────────────

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
  });

  /// The job being scheduled or reassigned.
  final String jobId;

  /// Estimated or actual booking duration in minutes.
  final int durationMinutes;

  /// Non-null when dragging an existing booking (reassign/move operation).
  final String? existingBookingId;

  /// Non-null when dragging an existing booking from another contractor's lane.
  final String? sourceContractorId;
}

// ────────────────────────────────────────────────────────────────────────────
// Conflict info model and provider
// ────────────────────────────────────────────────────────────────────────────

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

  /// Human-readable time range of the conflicting booking, e.g. "9:00 AM - 11:30 AM".
  final String conflictingTimeRange;
}

/// Holds conflict information detected during a drag operation.
///
/// Written by DragTarget.onWillAcceptWithDetails in ContractorLane when a
/// conflict is detected. Reset to null after the conflict snackbar is shown.
/// (StateProvider from riverpod/legacy.dart — Riverpod 3 moved it out of main export.)
final conflictInfoProvider = StateProvider<ConflictInfo?>((ref) => null);

// ────────────────────────────────────────────────────────────────────────────
// Overdue panel toggle provider
// ────────────────────────────────────────────────────────────────────────────

/// Controls visibility of the overdue jobs panel.
///
/// Toggled by tapping the overdue badge count in the calendar header.
/// Plan 04 creates the actual OverduePanel widget; this plan wires the toggle.
final showOverduePanelProvider = StateProvider<bool>((ref) => false);

// ────────────────────────────────────────────────────────────────────────────
// Undo stack model
// ────────────────────────────────────────────────────────────────────────────

/// Type of booking mutation for undo tracking.
enum UndoActionType { create, reassign, resize, multiDayCreate }

/// Snapshot of a booking state before a mutation, enabling undo.
class UndoAction {
  const UndoAction({
    required this.type,
    required this.bookingId,
    this.previousContractorId,
    this.previousStart,
    this.previousEnd,
    this.childBookingIds = const [],
  });

  final UndoActionType type;
  final String bookingId;

  /// Original contractorId before a reassign operation.
  final String? previousContractorId;

  /// Original start time before a reassign or resize operation.
  final DateTime? previousStart;

  /// Original end time before a reassign or resize operation.
  final DateTime? previousEnd;

  /// Child booking IDs for multi-day creates (all removed on undo).
  final List<String> childBookingIds;
}

/// Stack of undoable booking operations (max depth 10).
///
/// Pushed on every booking mutation. Popped by undoLastBooking().
final undoStackProvider = StateProvider<List<UndoAction>>((ref) => []);

// ────────────────────────────────────────────────────────────────────────────
// Booking operations notifier
// ────────────────────────────────────────────────────────────────────────────

/// Provides booking mutation methods for the dispatch calendar.
///
/// Methods: bookSlot, reassignBooking, resizeBooking, undoLastBooking,
/// bookMultiDay.
///
/// All mutations write to Drift + sync queue (offline-first). The undo stack
/// captures enough state to reverse each operation.
///
/// NOTE: GetIt is used to access BookingDao and JobDao because they are
/// database accessors registered at startup. This is the established pattern
/// for schedule providers (see bookingDaoProvider). (CLAUDE.md: document
/// GetIt<->Riverpod tradeoffs)
class BookingOperationsNotifier extends Notifier<void> {
  // Fire-and-forget async pattern: build() is sync because this notifier
  // exposes imperative methods, not reactive state. Methods are called by UI
  // and return Futures directly.
  @override
  void build() {}

  /// Create a new booking at [slotStart] for [contractorId] on [jobId].
  ///
  /// Steps:
  ///   1. Insert booking into Drift via BookingDao (offline-first).
  ///   2. If job status is 'quote', auto-transition to 'scheduled' via JobDao.
  ///   3. Push CREATE to undo stack.
  Future<String> bookSlot({
    required String companyId,
    required String contractorId,
    required String jobId,
    required DateTime slotStart,
    required int durationMinutes,
    String? jobCurrentStatus,
    int jobCurrentVersion = 1,
    List<Map<String, dynamic>>? jobStatusHistory,
  }) async {
    final bookingId = const Uuid().v4();
    final now = DateTime.now();
    final slotEnd = slotStart.add(Duration(minutes: durationMinutes));

    final bookingDao = getIt<BookingDao>();
    final jobDao = getIt<JobDao>();

    await bookingDao.createBooking(
      id: bookingId,
      companyId: companyId,
      contractorId: contractorId,
      jobId: jobId,
      timeRangeStart: slotStart,
      timeRangeEnd: slotEnd,
    );

    // Auto-transition quote -> scheduled when booking is created.
    if (jobCurrentStatus == 'quote') {
      final history = List<Map<String, dynamic>>.from(jobStatusHistory ?? []);
      history.add({
        'status': 'scheduled',
        'timestamp': now.toIso8601String(),
        'userId': 'system',
        'reason': 'booking_created',
      });
      await jobDao.updateJobStatus(
        jobId,
        'scheduled',
        jsonEncode(history),
        jobCurrentVersion + 1,
      );
    }

    // Push to undo stack (max 10 items).
    _pushUndo(UndoAction(
      type: UndoActionType.create,
      bookingId: bookingId,
    ));

    return bookingId;
  }

  /// Reassign an existing booking to a new contractor and/or time slot.
  ///
  /// Steps:
  ///   1. Update booking in Drift (contractorId + time) via BookingDao.
  ///   2. Push REASSIGN to undo stack with previous state.
  Future<void> reassignBooking({
    required String bookingId,
    required String newContractorId,
    required DateTime newStart,
    required DateTime newEnd,
    required String previousContractorId,
    required DateTime previousStart,
    required DateTime previousEnd,
    required int currentVersion,
  }) async {
    final bookingDao = getIt<BookingDao>();

    await bookingDao.updateBookingContractorAndTime(
      bookingId,
      newContractorId,
      newStart,
      newEnd,
      currentVersion,
    );

    _pushUndo(UndoAction(
      type: UndoActionType.reassign,
      bookingId: bookingId,
      previousContractorId: previousContractorId,
      previousStart: previousStart,
      previousEnd: previousEnd,
    ));
  }

  /// Resize a booking's time range.
  ///
  /// Steps:
  ///   1. Update booking time in Drift via BookingDao.
  ///   2. Push RESIZE to undo stack with previous times.
  Future<void> resizeBooking({
    required String bookingId,
    required DateTime newStart,
    required DateTime newEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
    required int currentVersion,
  }) async {
    final bookingDao = getIt<BookingDao>();

    await bookingDao.updateBookingTime(
      bookingId,
      newStart,
      newEnd,
      currentVersion,
    );

    _pushUndo(UndoAction(
      type: UndoActionType.resize,
      bookingId: bookingId,
      previousStart: previousStart,
      previousEnd: previousEnd,
    ));
  }

  /// Create multiple additional day bookings for a multi-day job.
  ///
  /// [parentBookingId] is the first day's booking (already created via bookSlot).
  /// Each [DayBlock] in [additionalDays] creates a child booking with dayIndex
  /// and parentBookingId linking back to the first booking.
  Future<void> bookMultiDay({
    required String companyId,
    required String jobId,
    required String parentBookingId,
    required List<DayBlock> additionalDays,
  }) async {
    final bookingDao = getIt<BookingDao>();
    final childIds = <String>[];

    for (var i = 0; i < additionalDays.length; i++) {
      final day = additionalDays[i];
      final childId = const Uuid().v4();
      childIds.add(childId);

      await bookingDao.createBooking(
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

    // Update undo stack: replace the CREATE action for parentBookingId with
    // a multiDayCreate that includes all child IDs for group undo.
    final stack = ref.read(undoStackProvider);
    final parentIdx = stack.indexWhere(
      (a) => a.bookingId == parentBookingId && a.type == UndoActionType.create,
    );
    if (parentIdx >= 0) {
      final updated = List<UndoAction>.from(stack);
      updated[parentIdx] = UndoAction(
        type: UndoActionType.multiDayCreate,
        bookingId: parentBookingId,
        childBookingIds: childIds,
      );
      ref.read(undoStackProvider.notifier).state = updated;
    }
  }

  /// Undo the last booking operation.
  ///
  /// Pops from the undo stack and reverses the operation:
  ///   - create: soft-delete the booking
  ///   - reassign: restore original contractorId + time
  ///   - resize: restore original start/end times
  ///   - multiDayCreate: soft-delete parent + all child bookings
  Future<void> undoLastBooking() async {
    final stack = ref.read(undoStackProvider);
    if (stack.isEmpty) return;

    final action = stack.last;
    final newStack = stack.sublist(0, stack.length - 1);
    ref.read(undoStackProvider.notifier).state = newStack;

    final bookingDao = getIt<BookingDao>();

    switch (action.type) {
      case UndoActionType.create:
        await bookingDao.softDeleteBooking(action.bookingId, 1);

      case UndoActionType.reassign:
        if (action.previousContractorId != null &&
            action.previousStart != null &&
            action.previousEnd != null) {
          await bookingDao.updateBookingContractorAndTime(
            action.bookingId,
            action.previousContractorId!,
            action.previousStart!,
            action.previousEnd!,
            1, // version — incrementing is handled inside updateBookingContractorAndTime
          );
        }

      case UndoActionType.resize:
        if (action.previousStart != null && action.previousEnd != null) {
          await bookingDao.updateBookingTime(
            action.bookingId,
            action.previousStart!,
            action.previousEnd!,
            1,
          );
        }

      case UndoActionType.multiDayCreate:
        // Undo all child bookings first, then the parent.
        for (final childId in action.childBookingIds) {
          await bookingDao.softDeleteBooking(childId, 1);
        }
        await bookingDao.softDeleteBooking(action.bookingId, 1);
    }
  }

  /// Push an undo action, capping the stack at 10 items.
  void _pushUndo(UndoAction action) {
    final stack = ref.read(undoStackProvider);
    final newStack = [...stack, action];
    // Cap at 10 items — oldest item dropped if over limit.
    final capped =
        newStack.length > 10 ? newStack.sublist(newStack.length - 10) : newStack;
    ref.read(undoStackProvider.notifier).state = capped;
  }
}

/// Provider for [BookingOperationsNotifier].
final bookingOperationsProvider =
    NotifierProvider<BookingOperationsNotifier, void>(
  BookingOperationsNotifier.new,
);

// ────────────────────────────────────────────────────────────────────────────
// Multi-day booking data model
// ────────────────────────────────────────────────────────────────────────────

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

// ────────────────────────────────────────────────────────────────────────────
// JobDao provider
// ────────────────────────────────────────────────────────────────────────────

/// Provider exposing the [JobDao] singleton from GetIt.
///
/// Used by CalendarOperationsNotifier for job status auto-transition.
/// Follows the same pattern as bookingDaoProvider.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final jobDaoProvider = Provider<JobDao>((ref) {
  return getIt<JobDao>();
});
