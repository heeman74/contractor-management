import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/jobs/data/job_dao.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/jobs/presentation/providers/job_providers.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../data/booking_dao.dart';
import '../../domain/booking_entity.dart';
import '../../domain/overdue_service.dart';
import '../providers/calendar_providers.dart';
import '../widgets/calendar_grid_painter.dart';
import '../widgets/contractor_lane.dart';
import '../widgets/delay_justification_dialog.dart';

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

/// View mode for contractor's personal schedule (list vs calendar).
enum _ContractorViewMode { list, calendar }

class _ContractorScheduleScreenState
    extends ConsumerState<ContractorScheduleScreen> {
  _ContractorViewMode _viewMode = _ContractorViewMode.list;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final selectedDate = ref.watch(calendarDateProvider);

    if (authState is! AuthAuthenticated) {
      return const Center(child: CircularProgressIndicator());
    }

    final contractorId = authState.userId;
    final companyId = authState.companyId;

    final bookingsAsync = ref.watch(
      _contractorBookingsProvider((contractorId: contractorId, date: selectedDate)),
    );
    final jobsAsync = ref.watch(jobListNotifierProvider);

    return RefreshIndicator(
      onRefresh: () async {
        final syncEngine = getIt<SyncEngine>();
        await syncEngine.syncNow();
      },
      child: Column(
        children: [
          // ── Header: view toggle + date navigation ──────────────────────
          _ContractorScheduleHeader(
            selectedDate: selectedDate,
            viewMode: _viewMode,
            onViewModeChanged: (mode) => setState(() => _viewMode = mode),
            onDateChanged: (date) {
              ref.read(calendarDateProvider.notifier).state = date;
            },
          ),

          // ── Content area ───────────────────────────────────────────────
          Expanded(
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

                if (_viewMode == _ContractorViewMode.list) {
                  return _ContractorListView(
                    bookings: bookings,
                    jobMap: jobMap,
                    contractorId: contractorId,
                    selectedDate: selectedDate,
                  );
                } else {
                  return _ContractorCalendarView(
                    contractorId: contractorId,
                    companyId: companyId,
                    selectedDate: selectedDate,
                    bookings: bookings,
                    jobMap: jobMap,
                    scrollController: _scrollController,
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

// ─── Header ───────────────────────────────────────────────────────────────────

class _ContractorScheduleHeader extends StatelessWidget {
  const _ContractorScheduleHeader({
    required this.selectedDate,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final _ContractorViewMode viewMode;
  final ValueChanged<_ContractorViewMode> onViewModeChanged;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // List / Calendar toggle
          SegmentedButton<_ContractorViewMode>(
            segments: const [
              ButtonSegment<_ContractorViewMode>(
                value: _ContractorViewMode.list,
                label: Text('List'),
                icon: Icon(Icons.list, size: 16),
              ),
              ButtonSegment<_ContractorViewMode>(
                value: _ContractorViewMode.calendar,
                label: Text('Calendar'),
                icon: Icon(Icons.calendar_today, size: 16),
              ),
            ],
            selected: {viewMode},
            onSelectionChanged: (modes) {
              if (modes.isNotEmpty) onViewModeChanged(modes.first);
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 6),

          // Date navigation (only shown in calendar mode, but useful in list too)
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onDateChanged(
                  selectedDate.subtract(const Duration(days: 1)),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) onDateChanged(picked);
                  },
                  child: Text(
                    _formatDate(selectedDate),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => onDateChanged(
                  selectedDate.add(const Duration(days: 1)),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
              ),
              TextButton(
                onPressed: () => onDateChanged(DateTime.now()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Today', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
}

// ─── List view ────────────────────────────────────────────────────────────────

/// Date-grouped list of the contractor's bookings.
///
/// Groups by date with headers: "Today", "Tomorrow", "Wed, Mar 12" etc.
/// Shows bookings only for the selected date (uses watchBookingsByContractorAndDate
/// which is single-day scoped). For the multi-day list, a future enhancement
/// can extend to watchBookingsByContractorAndDate with a date range.
class _ContractorListView extends StatelessWidget {
  const _ContractorListView({
    required this.bookings,
    required this.jobMap,
    required this.contractorId,
    required this.selectedDate,
  });

  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobMap;
  final String contractorId;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No jobs scheduled',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              _dateSectionHeader(selectedDate),
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: bookings.length + 1, // +1 for section header
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              _dateSectionHeader(selectedDate),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
          );
        }

        final booking = bookings[index - 1];
        final job = jobMap[booking.jobId];

        return _BookingListCard(
          booking: booking,
          job: job,
          contractorId: contractorId,
        );
      },
    );
  }

  String _dateSectionHeader(DateTime date) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final selectedDateNormalized =
        DateTime(date.year, date.month, date.day);

    final diffDays =
        selectedDateNormalized.difference(todayDate).inDays;

    if (diffDays == 0) return 'TODAY';
    if (diffDays == 1) return 'TOMORROW';
    if (diffDays == -1) return 'YESTERDAY';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1].toUpperCase()}, ${months[date.month - 1]} ${date.day}';
  }
}

// ─── Booking list card ─────────────────────────────────────────────────────────

/// Card for a single booking in the contractor list view.
///
/// Overdue jobs get amber/red background with prompt message.
/// "Report Delay" button shown for scheduled/in_progress status.
class _BookingListCard extends ConsumerWidget {
  const _BookingListCard({
    required this.booking,
    required this.job,
    required this.contractorId,
  });

  final BookingEntity booking;
  final JobEntity? job;
  final String contractorId;

  static const _activeStatuses = {'scheduled', 'in_progress'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final currentUserId = authState is AuthAuthenticated ? authState.userId : '';

    final status = job?.status ?? 'scheduled';
    final severity = job != null
        ? OverdueService.computeSeverity(job!.scheduledCompletionDate)
        : OverdueSeverity.none;

    final isOverdue = severity != OverdueSeverity.none;
    final canReportDelay = _activeStatuses.contains(status);

    Color cardColor = theme.colorScheme.surfaceContainerLow;
    if (severity == OverdueSeverity.critical) {
      cardColor = Colors.red.withValues(alpha: 0.08);
    } else if (severity == OverdueSeverity.warning) {
      cardColor = Colors.amber.withValues(alpha: 0.08);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isOverdue
              ? (severity == OverdueSeverity.critical
                  ? Colors.red.withValues(alpha: 0.5)
                  : Colors.amber.withValues(alpha: 0.5))
              : theme.dividerColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Job description + status chip
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    job?.description ?? 'Job',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: status),
              ],
            ),

            const SizedBox(height: 6),

            // Time range
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  _formatTimeRange(booking.timeRangeStart, booking.timeRangeEnd),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),

            // Overdue prompt
            if (isOverdue) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: severity == OverdueSeverity.critical
                        ? Colors.red
                        : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'This job is past its scheduled completion — '
                      'update status or report a delay',
                      style: TextStyle(
                        fontSize: 11,
                        color: severity == OverdueSeverity.critical
                            ? Colors.red[700]
                            : Colors.orange[800],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Report Delay button
            if (canReportDelay && job != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final jobDao = getIt<JobDao>();
                    final reported = await DelayJustificationDialog.show(
                      context: context,
                      jobDao: jobDao,
                      job: job!,
                      currentUserId: currentUserId,
                    );
                    if (reported && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Delay reported successfully'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.schedule_send, size: 14),
                  label: const Text('Report Delay',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, 30),
                    side: BorderSide(
                      color: isOverdue ? Colors.orange : Colors.grey[400]!,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimeRange(DateTime start, DateTime end) {
    return '${_formatTime(start)} - ${_formatTime(end)}';
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h:$minute $period';
  }
}

// ─── Status chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColorMap[status] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Calendar view ────────────────────────────────────────────────────────────

/// Single-lane contractor calendar view for the selected day.
///
/// Reuses [ContractorLane] and [CalendarGridPainter] from the admin dispatch
/// calendar. Shows only the contractor's own bookings on the time grid.
/// Read-only: DragTarget dropping is not enabled for contractor view.
class _ContractorCalendarView extends ConsumerStatefulWidget {
  const _ContractorCalendarView({
    required this.contractorId,
    required this.companyId,
    required this.selectedDate,
    required this.bookings,
    required this.jobMap,
    required this.scrollController,
  });

  final String contractorId;
  final String companyId;
  final DateTime selectedDate;
  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobMap;
  final ScrollController scrollController;

  @override
  ConsumerState<_ContractorCalendarView> createState() =>
      _ContractorCalendarViewState();
}

class _ContractorCalendarViewState
    extends ConsumerState<_ContractorCalendarView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToWorkingHoursStart();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToWorkingHoursStart() {
    if (!_scrollController.hasClients) return;
    const workingHoursStartMinutes = 6 * 60;
    const targetOffset = workingHoursStartMinutes * pixelsPerMinute;
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dayStart = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );
    const totalDayMinutes = 24 * 60;
    const totalHeight = totalDayMinutes * pixelsPerMinute;
    const timeAxisWidth = 44.0;

    // Build a minimal UserEntity from auth state for the lane widget header.
    // The lane widget uses this for avatar/name display only.
    final authState = ref.read(authNotifierProvider);
    final now = DateTime.now();
    final contractorUser = UserEntity(
      id: widget.contractorId,
      companyId: widget.companyId,
      email: authState is AuthAuthenticated ? '' : widget.contractorId,
      firstName: 'My',
      lastName: 'Schedule',
      version: 1,
      createdAt: now,
      updatedAt: now,
    );

    // Blocked intervals (default working hours 06:00 - 18:00)
    final blockedIntervals = [
      BlockedInterval(
        start: dayStart,
        end: dayStart.add(const Duration(hours: 6)),
        reason: 'outside_working_hours',
      ),
      BlockedInterval(
        start: dayStart.add(const Duration(hours: 18)),
        end: dayStart.add(const Duration(days: 1)),
        reason: 'outside_working_hours',
      ),
    ];

    return Column(
      children: [
        // Contractor header row (self-sizing, no fixed height)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: timeAxisWidth),
              Expanded(
                child: ContractorLaneHeader(
                  contractor: contractorUser,
                  laneWidth: double.infinity,
                ),
              ),
            ],
          ),
        ),

        // Scroll area: single scroll surface for time axis + lane body
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final laneWidth = constraints.maxWidth - timeAxisWidth;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time axis (scrolls with lane)
                    SizedBox(
                      width: timeAxisWidth,
                      height: totalHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (var hour = 0; hour < 24; hour++)
                            Positioned(
                              top: hour * 60 * pixelsPerMinute - 7,
                              left: 0,
                              right: 0,
                              child: Text(
                                '${hour.toString().padLeft(2, '0')}:00',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF9E9E9E),
                                  height: 1.0,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Contractor lane body (header rendered above)
                    ContractorLane(
                      contractor: contractorUser,
                      dayStart: dayStart,
                      bookings: widget.bookings,
                      jobs: widget.jobMap,
                      blockedIntervals: blockedIntervals,
                      laneWidth: laneWidth > 0 ? laneWidth : 200,
                      pixelsPerMinute: pixelsPerMinute,
                      totalDayHeightMinutes: totalDayMinutes.toDouble(),
                      showHeader: false,
                      companyId: widget.companyId,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
