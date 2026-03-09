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

/// Streams all active users for the current company.
///
/// The schedule screen uses this to find contractors (filtered by role in
/// [filteredContractorsProvider]). Uses AsyncNotifier for consistent stream
/// lifecycle management.
class ContractorsNotifier extends AsyncNotifier<List<UserEntity>> {
  @override
  Future<List<UserEntity>> build() async {
    final authState = ref.watch(authNotifierProvider);
    if (authState is! AuthAuthenticated) return [];

    final db = ref.watch(appDatabaseProvider);
    final companyId = authState.companyId;

    final stream = db.userDao.watchUsersByCompany(companyId);

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
