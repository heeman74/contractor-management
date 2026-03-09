import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/jobs/presentation/providers/job_providers.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../providers/calendar_providers.dart';
import '../providers/overdue_providers.dart';
import '../widgets/calendar_day_view.dart';

/// Admin dispatch calendar screen — replaces the Phase 5 placeholder.
///
/// Features:
///   - Day view calendar with contractor lanes, booking cards, travel time blocks
///   - Header navigation: prev/next day arrows, date display, "Today" button
///   - Date picker: tap date label to jump to any date
///   - View mode toggle: Day / Week / Month (week/month show "Coming soon")
///   - Overdue badge: count of overdue jobs, tap to open panel (Plan 04)
///   - Trade type filter: dropdown to narrow visible contractors
///   - Contractor pagination: 5 per page, controlled by CalendarDayView
///   - Pull-to-refresh: triggers SyncEngine.syncNow()
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
///
/// The AppBar is provided by AppShell — this widget does NOT add a Scaffold/AppBar.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(calendarDateProvider);
    final viewMode = ref.watch(calendarViewModeProvider);
    final bookingsAsync = ref.watch(bookingsForDateProvider);
    final contractorsAsync = ref.watch(filteredContractorsProvider);
    final jobsAsync = ref.watch(jobListNotifierProvider);
    final overdueCount = ref.watch(overdueJobCountProvider);
    final tradeFilter = ref.watch(calendarTradeTypeFilterProvider);

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
              // Plan 04: opens overdue jobs panel
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Overdue panel coming in Plan 04'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),

          // ── Calendar content area ────────────────────────────────────────
          Expanded(
            child: switch (viewMode) {
              CalendarViewMode.day => _buildDayView(
                  context,
                  ref,
                  selectedDate,
                  bookingsAsync,
                  contractorsAsync,
                  jobsAsync,
                ),
              CalendarViewMode.week || CalendarViewMode.month => const Center(
                  child: _ComingSoonPlaceholder(),
                ),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayView(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedDate,
    AsyncValue<List<BookingEntity>> bookingsAsync,
    AsyncValue<List<UserEntity>> contractorsAsync,
    AsyncValue<List<JobEntity>> jobsAsync,
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

    return CalendarDayView(
      selectedDate: selectedDate,
      bookings: bookings,
      contractors: contractors,
      jobs: jobMap,
    );
  }
}

// ─── Internal sub-widgets ─────────────────────────────────────────────────────

/// Header bar for the schedule screen.
///
/// Contains:
///   - View mode toggle (Day / Week / Month SegmentedButton)
///   - Date navigation: left arrow, date label (tappable for picker), right arrow
///   - "Today" button
///   - Overdue count badge
///   - Trade type filter dropdown
class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.selectedDate,
    required this.viewMode,
    required this.overdueCount,
    required this.tradeFilter,
    required this.onDateChanged,
    required this.onViewModeChanged,
    required this.onTradeFilterChanged,
    required this.onTapOverdueBadge,
  });

  final DateTime selectedDate;
  final CalendarViewMode viewMode;
  final int overdueCount;
  final String? tradeFilter;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<CalendarViewMode> onViewModeChanged;
  final ValueChanged<String?> onTradeFilterChanged;
  final VoidCallback onTapOverdueBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: View mode toggle + overdue badge
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
              // Overdue badge
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
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Date navigation + Today + trade filter
          Row(
            children: [
              // Previous day arrow
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onDateChanged(
                  selectedDate.subtract(const Duration(days: 1)),
                ),
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
              ),

              // Next day arrow
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => onDateChanged(
                  selectedDate.add(const Duration(days: 1)),
                ),
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

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = weekdays[date.weekday - 1];
    return '$weekday, ${months[date.month - 1]} ${date.day}, ${date.year}';
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

/// Placeholder shown for week and month view modes (coming in Plan 05).
class _ComingSoonPlaceholder extends StatelessWidget {
  const _ComingSoonPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.calendar_view_week_outlined,
          size: 64,
          color: Colors.grey[400],
        ),
        const SizedBox(height: 16),
        Text(
          'Coming soon',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Week and month views will be\navailable in a future update.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
        ),
      ],
    );
  }
}
