import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to legacy in Riverpod 3 — explicitly imported.
// ignore: depend_on_referenced_packages
import 'package:riverpod/legacy.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/schedule/domain/booking_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../data/booking_operations_service.dart';
import '../../domain/booking_operation_models.dart';
import '../../domain/schedule_constants.dart';

// Re-export models so existing importers keep a single import site.
export '../../domain/booking_operation_models.dart'
    show BookingDragData, ConflictInfo, UndoAction, UndoActionType, DayBlock;

/// Subscribes [state] to [stream], propagating data/errors and cancelling on
/// dispose. Returns the first emission for the AsyncNotifier's initial value.
Future<List<T>> _bindStream<T>(
  Ref ref,
  void Function(AsyncValue<List<T>>) setState,
  Stream<List<T>> stream,
) async {
  final subscription = stream.listen(
    (items) => setState(AsyncData(items)),
    onError: (Object error, StackTrace st) => setState(AsyncError(error, st)),
  );
  ref.onDispose(subscription.cancel);
  return stream.first;
}

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
///
/// Alias for [ScheduleConstants.pixelsPerMinute] kept for existing importers.
const double pixelsPerMinute = ScheduleConstants.pixelsPerMinute;

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

    return _bindStream(
      ref,
      (value) => state = value,
      dao.watchBookingsByCompanyAndDateRange(companyId, dayStart, dayEnd),
    );
  }
}

/// Provider for [BookingsForDateNotifier].
final bookingsForDateProvider =
    AsyncNotifierProvider<BookingsForDateNotifier, List<BookingEntity>>(
  BookingsForDateNotifier.new,
);

// ────────────────────────────────────────────────────────────────────────────
// Bookings for selected week (Mon–Sun)
// ────────────────────────────────────────────────────────────────────────────

/// Streams bookings for the full week (Monday–Sunday) of the selected date.
///
/// Uses [BookingDao.watchBookingsByCompanyAndDateRange] with a 7-day range.
/// Required by week view which needs all 7 days of bookings, not just one day.
class BookingsForWeekNotifier extends AsyncNotifier<List<BookingEntity>> {
  @override
  Future<List<BookingEntity>> build() async {
    final authState = ref.watch(authNotifierProvider);
    if (authState is! AuthAuthenticated) return [];

    final selectedDate = ref.watch(calendarDateProvider);
    final dao = ref.watch(bookingDaoProvider);
    final companyId = authState.companyId;

    // Compute Monday of the selected week
    final monday = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    ).subtract(Duration(days: selectedDate.weekday - 1));
    // Sunday end = Monday + 7 days
    final sundayEnd = monday.add(const Duration(days: 7));

    return _bindStream(
      ref,
      (value) => state = value,
      dao.watchBookingsByCompanyAndDateRange(companyId, monday, sundayEnd),
    );
  }
}

/// Provider for [BookingsForWeekNotifier].
final bookingsForWeekProvider =
    AsyncNotifierProvider<BookingsForWeekNotifier, List<BookingEntity>>(
  BookingsForWeekNotifier.new,
);

// ────────────────────────────────────────────────────────────────────────────
// Bookings for selected month (1st–last day)
// ────────────────────────────────────────────────────────────────────────────

/// Streams bookings for the full month of the selected date.
///
/// Uses [BookingDao.watchBookingsByCompanyAndDateRange] with a range from
/// the first day to the last day of the month. Required by month view which
/// needs all days of the month, not just one day.
class BookingsForMonthNotifier extends AsyncNotifier<List<BookingEntity>> {
  @override
  Future<List<BookingEntity>> build() async {
    final authState = ref.watch(authNotifierProvider);
    if (authState is! AuthAuthenticated) return [];

    final selectedDate = ref.watch(calendarDateProvider);
    final dao = ref.watch(bookingDaoProvider);
    final companyId = authState.companyId;

    // First day of the month at midnight
    final monthStart = DateTime(selectedDate.year, selectedDate.month);
    // First day of the next month (exclusive end)
    final monthEnd = DateTime(selectedDate.year, selectedDate.month + 1);

    return _bindStream(
      ref,
      (value) => state = value,
      dao.watchBookingsByCompanyAndDateRange(companyId, monthStart, monthEnd),
    );
  }
}

/// Provider for [BookingsForMonthNotifier].
final bookingsForMonthProvider =
    AsyncNotifierProvider<BookingsForMonthNotifier, List<BookingEntity>>(
  BookingsForMonthNotifier.new,
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

    return _bindStream(
      ref,
      (value) => state = value,
      db.userDao.watchUsersByRole(companyId, 'contractor'),
    );
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
        // TODO(schedule): Trade filter is a no-op — UserEntity does not yet have
        // a tradeType field. The dropdown is visible but non-functional. Implement
        // filtering when UserEntity trade type support is added (Plan 05+).
        // Until then, all contractors pass through regardless of filter selection.
        filtered = users;
      }

      const perPage = ScheduleConstants.contractorsPerPage;
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
    data: (users) => (users.length / ScheduleConstants.contractorsPerPage)
        .ceil()
        .clamp(1, 999),
    orElse: () => 1,
  );
});

// ────────────────────────────────────────────────────────────────────────────
// Conflict info provider
// ────────────────────────────────────────────────────────────────────────────

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
// Undo stack + booking operations
// ────────────────────────────────────────────────────────────────────────────

/// Stack of undoable booking operations (max [ScheduleConstants.maxUndoDepth]).
///
/// Pushed on every booking mutation. Popped by
/// [BookingOperationsNotifier.undoLastBooking].
final undoStackProvider = StateProvider<List<UndoAction>>((ref) => []);

/// Provides the [BookingOperationsService], wiring the booking and job DAOs.
///
/// NOTE: GetIt is used because BookingDao and JobDao are database accessors
/// registered at startup. This matches the pattern for schedule providers.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final bookingOperationsServiceProvider =
    Provider<BookingOperationsService>((ref) {
  return BookingOperationsService(
    bookingDao: getIt<BookingDao>(),
    jobDao: getIt<JobDao>(),
  );
});

/// Exposes booking mutation commands for the dispatch calendar.
///
/// Delegates all persistence to [BookingOperationsService] and owns only the
/// Riverpod undo-stack state — keeping business logic out of the UI layer.
class BookingOperationsNotifier extends Notifier<void> {
  // build() is sync: this notifier exposes imperative commands, not reactive
  // state. Methods are called by the UI and return Futures directly.
  @override
  void build() {}

  BookingOperationsService get _service =>
      ref.read(bookingOperationsServiceProvider);

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
    final result = await _service.bookSlot(
      companyId: companyId,
      contractorId: contractorId,
      jobId: jobId,
      slotStart: slotStart,
      durationMinutes: durationMinutes,
      jobCurrentStatus: jobCurrentStatus,
      jobCurrentVersion: jobCurrentVersion,
      jobStatusHistory: jobStatusHistory,
    );
    _pushUndo(result.undo);
    return result.bookingId;
  }

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
    final undo = await _service.reassignBooking(
      bookingId: bookingId,
      newContractorId: newContractorId,
      newStart: newStart,
      newEnd: newEnd,
      previousContractorId: previousContractorId,
      previousStart: previousStart,
      previousEnd: previousEnd,
      currentVersion: currentVersion,
    );
    _pushUndo(undo);
  }

  Future<void> resizeBooking({
    required String bookingId,
    required DateTime newStart,
    required DateTime newEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
    required int currentVersion,
  }) async {
    final undo = await _service.resizeBooking(
      bookingId: bookingId,
      newStart: newStart,
      newEnd: newEnd,
      previousStart: previousStart,
      previousEnd: previousEnd,
      currentVersion: currentVersion,
    );
    _pushUndo(undo);
  }

  Future<void> bookMultiDay({
    required String companyId,
    required String jobId,
    required String parentBookingId,
    required List<DayBlock> additionalDays,
  }) async {
    final undo = await _service.bookMultiDay(
      companyId: companyId,
      jobId: jobId,
      parentBookingId: parentBookingId,
      additionalDays: additionalDays,
    );
    _replaceParentCreateWithMultiDay(parentBookingId, undo);
  }

  Future<void> undoLastBooking() async {
    final stack = ref.read(undoStackProvider);
    if (stack.isEmpty) return;

    final action = stack.last;
    ref.read(undoStackProvider.notifier).state =
        stack.sublist(0, stack.length - 1);
    await _service.undo(action);
  }

  /// Replaces the parent booking's CREATE undo entry with a grouped
  /// multiDayCreate entry so a single undo removes all days.
  void _replaceParentCreateWithMultiDay(
    String parentBookingId,
    UndoAction multiDayUndo,
  ) {
    final stack = ref.read(undoStackProvider);
    final parentIndex = stack.indexWhere(
      (action) =>
          action.bookingId == parentBookingId &&
          action.type == UndoActionType.create,
    );
    if (parentIndex < 0) return;

    final updated = List<UndoAction>.from(stack);
    updated[parentIndex] = multiDayUndo;
    ref.read(undoStackProvider.notifier).state = updated;
  }

  /// Pushes an undo action, capping the stack at [ScheduleConstants.maxUndoDepth].
  void _pushUndo(UndoAction action) {
    final stack = [...ref.read(undoStackProvider), action];
    final capped = stack.length > ScheduleConstants.maxUndoDepth
        ? stack.sublist(stack.length - ScheduleConstants.maxUndoDepth)
        : stack;
    ref.read(undoStackProvider.notifier).state = capped;
  }
}

/// Provider for [BookingOperationsNotifier].
final bookingOperationsProvider =
    NotifierProvider<BookingOperationsNotifier, void>(
  BookingOperationsNotifier.new,
);
