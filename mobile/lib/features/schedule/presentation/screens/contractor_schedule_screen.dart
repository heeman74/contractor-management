import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/jobs/presentation/providers/job_providers.dart';
import '../../data/booking_dao.dart';
import '../../domain/booking_entity.dart';
import '../providers/calendar_providers.dart';
import '../widgets/contractor_booking_list.dart';
import '../widgets/contractor_calendar_view.dart';
import '../widgets/contractor_schedule_header.dart';

/// Contractor's personal schedule screen.
///
/// Shown when the logged-in user has the contractor role on the Schedule tab.
/// Provides two views toggled by SegmentedButton:
///
/// **List view** (default):
///   - Date-grouped list: "Today", "Tomorrow", "Wed, Mar 12" for next 7 days
///   - Each card: job description, time range, address, status chip
///   - Overdue jobs: amber/red card with "update status or report a delay" prompt
///   - "Report Delay" button on scheduled/in_progress cards
///
/// **Calendar view**:
///   - Single-lane day view reusing ContractorLane widget
///   - Time axis on left, bookings positioned by time
///   - Date navigation: prev/next day arrows + today button
///
/// Pull-to-refresh triggers SyncEngine.syncNow().
/// Data source: BookingDao.watchBookingsByContractorAndDate scoped to the
/// current user's userId (used as contractorId in the booking table).
class ContractorScheduleScreen extends ConsumerStatefulWidget {
  const ContractorScheduleScreen({super.key});

  @override
  ConsumerState<ContractorScheduleScreen> createState() =>
      _ContractorScheduleScreenState();
}

class _ContractorScheduleScreenState
    extends ConsumerState<ContractorScheduleScreen> {
  ContractorScheduleViewMode _viewMode = ContractorScheduleViewMode.list;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final selectedDate = ref.watch(calendarDateProvider);

    if (authState is! AuthAuthenticated) {
      return const Center(child: CircularProgressIndicator());
    }

    final contractorId = authState.userId;
    final companyId = authState.companyId;

    final normalizedDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final bookingsAsync = ref.watch(
      _contractorBookingsProvider((contractorId: contractorId, date: normalizedDate)),
    );
    final jobsAsync = ref.watch(jobListNotifierProvider);

    return RefreshIndicator(
      onRefresh: () async {
        final syncEngine = getIt<SyncEngine>();
        await syncEngine.syncNow();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── Header: view toggle + date navigation ──────────────────────
          SliverToBoxAdapter(
            child: ContractorScheduleHeader(
              selectedDate: selectedDate,
              viewMode: _viewMode,
              onViewModeChanged: (mode) => setState(() => _viewMode = mode),
              onDateChanged: (date) {
                ref.read(calendarDateProvider.notifier).state = date;
              },
            ),
          ),

          // ── Content area ───────────────────────────────────────────────
          SliverFillRemaining(
            child: bookingsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load schedule',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              data: (bookings) {
                final allJobs = jobsAsync.value ?? [];
                final jobMap = <String, JobEntity>{
                  for (final j in allJobs) j.id: j,
                };

                if (_viewMode == ContractorScheduleViewMode.list) {
                  return ContractorBookingList(
                    bookings: bookings,
                    jobMap: jobMap,
                    contractorId: contractorId,
                    selectedDate: selectedDate,
                  );
                } else {
                  return ContractorCalendarView(
                    contractorId: contractorId,
                    companyId: companyId,
                    selectedDate: selectedDate,
                    bookings: bookings,
                    jobMap: jobMap,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Booking stream provider for contractor ────────────────────────────────────

typedef _ContractorBookingsKey = ({String contractorId, DateTime date});

/// Family provider for a contractor's bookings on a specific date.
///
/// NOTE: GetIt is used to access BookingDao because it is a database accessor
/// registered at startup. This matches the pattern in calendar_providers.dart.
/// (CLAUDE.md: document GetIt<->Riverpod tradeoffs)
final _contractorBookingsProvider = StreamProvider.autoDispose
    .family<List<BookingEntity>, _ContractorBookingsKey>((ref, key) {
  final bookingDao = getIt<BookingDao>();
  return bookingDao.watchBookingsByContractorAndDate(
    key.contractorId,
    key.date,
  );
});
