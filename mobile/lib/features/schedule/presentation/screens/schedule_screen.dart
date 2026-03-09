import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/jobs/presentation/providers/job_providers.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../providers/calendar_providers.dart';
import '../providers/overdue_providers.dart';
import '../widgets/calendar_day_view.dart';
import '../widgets/calendar_month_view.dart';
import '../widgets/calendar_week_view.dart';
import '../widgets/unscheduled_jobs_drawer.dart';

/// Admin dispatch calendar screen — replaces the Phase 5 placeholder.
///
/// Features:
///   - Day view calendar with contractor lanes, booking cards, travel time blocks
///   - Header navigation: prev/next day arrows, date display, "Today" button
///   - Date picker: tap date label to jump to any date
///   - View mode toggle: Day / Week / Month (week/month show "Coming soon")
///   - Overdue badge: count of overdue jobs, tap to toggle overdue panel
///   - Trade type filter: dropdown to narrow visible contractors
///   - Contractor pagination: 5 per page, controlled by CalendarDayView
///   - Pull-to-refresh: triggers SyncEngine.syncNow()
///   - Unscheduled jobs drawer: slide-in sidebar with draggable job cards
///   - Drag-and-drop scheduling: drag from drawer onto contractor lanes
///   - Undo snackbar: 5-second dismissable snackbar after every booking op
///   - Conflict snackbar: shows conflicting job name + time range on rejected drag
///   - Overdue panel toggle: badge tap toggles showOverduePanelProvider
///
/// ConsumerWidget watching:
///   - calendarDateProvider — selected date
///   - calendarViewModeProvider — day/week/month
///   - bookingsForDateProvider — date-scoped booking stream
///   - filteredContractorsProvider — paginated + filtered contractor list
///   - jobListNotifierProvider — all company jobs (for job detail lookup)
///   - overdueJobCountProvider — overdue badge count
///   - showCompletedJobsProvider — toggle for terminal-status bookings
///   - calendarTradeTypeFilterProvider — trade type filter
///   - conflictInfoProvider — conflict info from DragTarget, shown on dragEnd
///   - showOverduePanelProvider — overdue panel visibility toggle
///
/// The AppBar is provided by AppShell — this widget does NOT add a Scaffold/AppBar.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  bool _drawerOpen = false;

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(calendarDateProvider);
    final viewMode = ref.watch(calendarViewModeProvider);
    final bookingsAsync = ref.watch(bookingsForDateProvider);
    final contractorsAsync = ref.watch(filteredContractorsProvider);
    final jobsAsync = ref.watch(jobListNotifierProvider);
    final overdueCount = ref.watch(overdueJobCountProvider);
    final tradeFilter = ref.watch(calendarTradeTypeFilterProvider);
    final showOverduePanel = ref.watch(showOverduePanelProvider);
    final authState = ref.watch(authNotifierProvider);
    final companyId = authState is AuthAuthenticated ? authState.companyId : '';

    return RefreshIndicator(
      onRefresh: () async {
        final syncEngine = getIt<SyncEngine>();
        await syncEngine.syncNow();
      },
      child: Column(
        children: [
          // ── Header bar ──────────────────────────────────────────────────
          _CalendarHeader(
            selectedDate: selectedDate,
            viewMode: viewMode,
            overdueCount: overdueCount,
            tradeFilter: tradeFilter,
            drawerOpen: _drawerOpen,
            onDateChanged: (date) {
              ref.read(calendarDateProvider.notifier).state = date;
            },
            onViewModeChanged: (mode) {
              ref.read(calendarViewModeProvider.notifier).state = mode;
            },
            onTradeFilterChanged: (filter) {
              ref.read(calendarTradeTypeFilterProvider.notifier).state = filter;
              // Reset to page 0 when filter changes
              ref.read(contractorPageIndexProvider.notifier).state = 0;
            },
            onTapOverdueBadge: () {
              // Toggle overdue panel — wired per plan 03 requirement.
              // Plan 04 will replace the placeholder with the real OverduePanel.
              ref.read(showOverduePanelProvider.notifier).state =
                  !showOverduePanel;
            },
            onToggleDrawer: () {
              setState(() => _drawerOpen = !_drawerOpen);
            },
          ),

          // ── Overdue panel placeholder (Plan 04 replaces with real widget) ──
          if (showOverduePanel)
            Container(
              color: Colors.orange.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Overdue panel loading...',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => ref
                        .read(showOverduePanelProvider.notifier)
                        .state = false,
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),

          // ── Calendar content area + unscheduled drawer ───────────────────
          Expanded(
            child: Stack(
              children: [
                // Main calendar content
                _buildCalendarContent(
                  context,
                  ref,
                  selectedDate,
                  viewMode,
                  bookingsAsync,
                  contractorsAsync,
                  jobsAsync,
                  companyId,
                ),

                // Unscheduled jobs drawer overlay (slides in from right)
                if (_drawerOpen)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: UnscheduledJobsDrawer(
                      laneWidth: _calcDrawerFeedbackWidth(context),
                      pixelsPerMinute: pixelsPerMinute,
                      onClose: () => setState(() => _drawerOpen = false),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarContent(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedDate,
    CalendarViewMode viewMode,
    AsyncValue<List<BookingEntity>> bookingsAsync,
    AsyncValue<List<UserEntity>> contractorsAsync,
    AsyncValue<List<JobEntity>> jobsAsync,
    String companyId,
  ) {
    return switch (viewMode) {
      CalendarViewMode.day => _buildDayView(
          context,
          ref,
          selectedDate,
          bookingsAsync,
          contractorsAsync,
          jobsAsync,
          companyId,
        ),
      CalendarViewMode.week => _buildWeekView(
          ref,
          selectedDate,
          bookingsAsync,
          contractorsAsync,
          jobsAsync,
        ),
      CalendarViewMode.month => _buildMonthView(
          bookingsAsync,
        ),
    };
  }

  Widget _buildDayView(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedDate,
    AsyncValue<List<BookingEntity>> bookingsAsync,
    AsyncValue<List<UserEntity>> contractorsAsync,
    AsyncValue<List<JobEntity>> jobsAsync,
    String companyId,
  ) {
    // Show loading while any of the three streams are loading
    if (bookingsAsync is AsyncLoading ||
        contractorsAsync is AsyncLoading ||
        jobsAsync is AsyncLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show error if any stream failed
    final bookingError = bookingsAsync.error;
    final contractorError = contractorsAsync.error;
    final jobError = jobsAsync.error;

    if (bookingError != null || contractorError != null || jobError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load calendar data',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final bookings = bookingsAsync.value ?? [];
    final contractors = contractorsAsync.value ?? [];
    final allJobs = jobsAsync.value ?? [];

    // Build job lookup map for O(1) access in booking cards
    final jobMap = <String, JobEntity>{
      for (final job in allJobs) job.id: job,
    };

    // Wrap in a LongPressDraggable listener for conflict snackbar detection.
    // When drag ends with wasAccepted=false and conflictInfoProvider is set,
    // show the conflict snackbar then reset conflictInfoProvider.
    return Listener(
      onPointerUp: (_) => _checkAndShowConflictSnackbar(ref),
      child: CalendarDayView(
        selectedDate: selectedDate,
        bookings: bookings,
        contractors: contractors,
        jobs: jobMap,
        companyId: companyId,
        onBookingMutated: () => _showUndoSnackbar(ref),
      ),
    );
  }

  Widget _buildWeekView(
    WidgetRef ref,
    DateTime selectedDate,
    AsyncValue<List<BookingEntity>> bookingsAsync,
    AsyncValue<List<UserEntity>> contractorsAsync,
    AsyncValue<List<JobEntity>> jobsAsync,
  ) {
    if (bookingsAsync is AsyncLoading ||
        contractorsAsync is AsyncLoading ||
        jobsAsync is AsyncLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bookingError = bookingsAsync.error;
    final contractorError = contractorsAsync.error;
    if (bookingError != null || contractorError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load week data',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Compute 7-day range for week — week view needs the full 7 days.
    // bookingsForDateProvider only covers one day; for week view we need
    // all bookings in the week range. We use the full booking stream from
    // bookingsForDateProvider as a fallback — the parent screen will wire
    // a week-range provider in a future enhancement. For now, show all
    // bookings from the month's loaded data.
    final allJobs = jobsAsync.value ?? [];
    final jobMap = <String, JobEntity>{
      for (final job in allJobs) job.id: job,
    };

    return CalendarWeekView(
      bookings: bookingsAsync.value ?? [],
      contractors: contractorsAsync.value ?? [],
      jobs: jobMap,
    );
  }

  Widget _buildMonthView(
    AsyncValue<List<BookingEntity>> bookingsAsync,
  ) {
    if (bookingsAsync is AsyncLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CalendarMonthView(
      bookings: bookingsAsync.value ?? [],
    );
  }

  /// Show undo snackbar after every booking operation.
  ///
  /// explicit duration: 5 seconds — required in Flutter 3.29+ where SnackBar
  /// with an action does NOT auto-dismiss.
  void _showUndoSnackbar(WidgetRef ref) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Booking updated'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await ref.read(bookingOperationsProvider.notifier).undoLastBooking();
          },
        ),
      ),
    );
  }

  /// Check if a conflict was detected during the last drag and show snackbar.
  ///
  /// Called from a Listener.onPointerUp so it fires when the user releases
  /// the drag. If conflictInfoProvider has data and drag was rejected, show
  /// the conflict message.
  void _checkAndShowConflictSnackbar(WidgetRef ref) {
    final conflictInfo = ref.read(conflictInfoProvider);
    if (conflictInfo != null) {
      // Reset immediately before showing snackbar (prevent double-show)
      ref.read(conflictInfoProvider.notifier).state = null;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Conflict: ${conflictInfo.conflictingJobDescription} '
            'at ${conflictInfo.conflictingTimeRange}',
          ),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  double _calcDrawerFeedbackWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Use roughly 1/3 of screen width for drag feedback sizing
    return (screenWidth / 3).clamp(80.0, 180.0);
  }
}

// ─── Internal sub-widgets ─────────────────────────────────────────────────────

/// Header bar for the schedule screen.
///
/// Contains:
///   - View mode toggle (Day / Week / Month SegmentedButton)
///   - Date navigation: left arrow, date label (tappable for picker), right arrow
///   - "Today" button
///   - Overdue count badge (tap toggles overdue panel)
///   - Trade type filter dropdown
///   - Unscheduled drawer toggle button
class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.selectedDate,
    required this.viewMode,
    required this.overdueCount,
    required this.tradeFilter,
    required this.drawerOpen,
    required this.onDateChanged,
    required this.onViewModeChanged,
    required this.onTradeFilterChanged,
    required this.onTapOverdueBadge,
    required this.onToggleDrawer,
  });

  final DateTime selectedDate;
  final CalendarViewMode viewMode;
  final int overdueCount;
  final String? tradeFilter;
  final bool drawerOpen;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<CalendarViewMode> onViewModeChanged;
  final ValueChanged<String?> onTradeFilterChanged;
  final VoidCallback onTapOverdueBadge;
  final VoidCallback onToggleDrawer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: View mode toggle + overdue badge + drawer toggle
          Row(
            children: [
              // View mode segmented button
              Expanded(
                child: SegmentedButton<CalendarViewMode>(
                  segments: CalendarViewMode.values
                      .map(
                        (mode) => ButtonSegment<CalendarViewMode>(
                          value: mode,
                          label: Text(mode.label),
                        ),
                      )
                      .toList(),
                  selected: {viewMode},
                  onSelectionChanged: (modes) {
                    if (modes.isNotEmpty) onViewModeChanged(modes.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Overdue badge — tap toggles overdue panel
              GestureDetector(
                onTap: onTapOverdueBadge,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: overdueCount > 0
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: overdueCount > 0 ? Colors.red : Colors.grey,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: overdueCount > 0 ? Colors.red : Colors.grey,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$overdueCount',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: overdueCount > 0 ? Colors.red : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Unscheduled jobs drawer toggle
              IconButton(
                icon: Icon(
                  drawerOpen ? Icons.close : Icons.format_list_bulleted,
                  size: 18,
                ),
                onPressed: onToggleDrawer,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: drawerOpen ? 'Close job queue' : 'Open job queue',
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Date navigation + Today + trade filter
          Row(
            children: [
              // Previous arrow — step depends on view mode
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onDateChanged(_stepDate(selectedDate, viewMode, -1)),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
              ),

              // Date display — tappable for date picker
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _formatDateForMode(selectedDate, viewMode),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ),
                ),
              ),

              // Next arrow — step depends on view mode
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => onDateChanged(_stepDate(selectedDate, viewMode, 1)),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
              ),

              // Today button
              TextButton(
                onPressed: () => onDateChanged(DateTime.now()),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(48, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Today', style: TextStyle(fontSize: 12)),
              ),

              // Trade type filter dropdown
              _TradeFilterDropdown(
                currentFilter: tradeFilter,
                onChanged: onTradeFilterChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Format the date label based on the current view mode.
  ///
  /// Day:   "Mon, Mar 10"
  /// Week:  "Mar 10 - 16"
  /// Month: "March 2026"
  String _formatDateForMode(DateTime date, CalendarViewMode mode) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const fullMonths = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return switch (mode) {
      CalendarViewMode.day => '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}',
      CalendarViewMode.week => () {
          final monday = date.subtract(Duration(days: date.weekday - 1));
          final sunday = monday.add(const Duration(days: 6));
          if (monday.month == sunday.month) {
            return '${months[monday.month - 1]} ${monday.day} - ${sunday.day}';
          }
          return '${months[monday.month - 1]} ${monday.day} - ${months[sunday.month - 1]} ${sunday.day}';
        }(),
      CalendarViewMode.month => '${fullMonths[date.month - 1]} ${date.year}',
    };
  }

  /// Compute the next date step for the given view mode and direction.
  ///
  /// Day:   ±1 day
  /// Week:  ±7 days
  /// Month: ±1 month (preserves day, clamped to last day of new month)
  DateTime _stepDate(DateTime date, CalendarViewMode mode, int direction) {
    return switch (mode) {
      CalendarViewMode.day =>
        date.add(Duration(days: direction)),
      CalendarViewMode.week =>
        date.add(Duration(days: 7 * direction)),
      CalendarViewMode.month => () {
          var newMonth = date.month + direction;
          var newYear = date.year;
          if (newMonth > 12) {
            newMonth = 1;
            newYear++;
          } else if (newMonth < 1) {
            newMonth = 12;
            newYear--;
          }
          final daysInMonth = DateTime(newYear, newMonth + 1, 0).day;
          return DateTime(newYear, newMonth, date.day.clamp(1, daysInMonth));
        }(),
    };
  }
}

/// Compact dropdown for filtering contractor lanes by trade type.
class _TradeFilterDropdown extends StatelessWidget {
  const _TradeFilterDropdown({
    required this.currentFilter,
    required this.onChanged,
  });

  final String? currentFilter;
  final ValueChanged<String?> onChanged;

  static const _tradeTypes = [
    'builder',
    'electrician',
    'plumber',
    'hvac',
    'painter',
    'carpenter',
    'roofer',
    'landscaper',
    'general',
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: currentFilter,
      hint: const Text('Trade', style: TextStyle(fontSize: 11)),
      isDense: true,
      underline: const SizedBox.shrink(),
      items: [
        const DropdownMenuItem<String?>(
          child: Text('All trades', style: TextStyle(fontSize: 12)),
        ),
        ..._tradeTypes.map(
          (trade) => DropdownMenuItem<String?>(
            value: trade,
            child: Text(
              trade[0].toUpperCase() + trade.substring(1),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

