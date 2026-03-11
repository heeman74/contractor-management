import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../providers/calendar_providers.dart';
import 'calendar_grid_painter.dart';
import 'contractor_lane.dart';

/// Width of the fixed time axis label column on the left.
const double _timeAxisWidth = 44.0;

/// Total scrollable day height in minutes (midnight to midnight).
const double _totalDayMinutes = 24 * 60;

/// The main day view widget — the primary dispatch calendar interface.
///
/// Layout:
///   - Left: fixed time axis (06:00–23:00 labels) that scrolls vertically
///   - Right: PageView of contractor lanes (5 per page)
///   - Each page: Row of ContractorLane widgets sharing a ScrollController
///   - Contractor name headers fixed at top (outside scroll area)
///   - Pagination controls at bottom
///
/// Features:
///   - Synchronized vertical scrolling across time axis + all lanes
///   - Auto-scroll to working hours start (06:00) on initial load
///   - "Now" line painted by CalendarGridPainter
///   - Pagination: prev/next buttons + page indicator
///   - DragTarget grid on each ContractorLane for scheduling operations
///
/// Consumes providers: bookingsForDateProvider, filteredContractorsProvider,
/// contractorPageIndexProvider, contractorPageCountProvider, showCompletedJobsProvider.
class CalendarDayView extends ConsumerStatefulWidget {
  const CalendarDayView({
    required this.selectedDate,
    required this.bookings,
    required this.contractors,
    required this.jobs,
    required this.companyId,
    super.key,
    this.totalContractorCount = 0,
    this.onBookingMutated,
  });

  /// The date being displayed.
  final DateTime selectedDate;

  /// All bookings for the selected date (company-scoped).
  final List<BookingEntity> bookings;

  /// Contractors to display as lanes (already filtered + paginated).
  final List<UserEntity> contractors;

  /// Map of jobId → JobEntity for resolving booking details.
  final Map<String, JobEntity> jobs;

  /// Company ID for booking creation tenant scope.
  final String companyId;

  /// Total unfiltered contractor count (before trade filter + pagination).
  /// Used by the empty state to distinguish "no contractors at all" from
  /// "trade filter hid them all".
  final int totalContractorCount;

  /// Called after any booking mutation (create/reassign/resize) to trigger
  /// the undo snackbar in the parent screen.
  final VoidCallback? onBookingMutated;

  @override
  ConsumerState<CalendarDayView> createState() => _CalendarDayViewState();
}

class _CalendarDayViewState extends ConsumerState<CalendarDayView> {
  late final ScrollController _scrollController;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _pageController = PageController();

    // Auto-scroll to working hours start (06:00) after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToWorkingHoursStart();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Scrolls to 06:00 (360 minutes from midnight) on initial load.
  void _scrollToWorkingHoursStart() {
    if (!_scrollController.hasClients) return;
    const workingHoursStartMinutes = 6 * 60; // 06:00
    const targetOffset = workingHoursStartMinutes * pixelsPerMinute;
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showCompleted = ref.watch(showCompletedJobsProvider);
    final pageCount = ref.watch(contractorPageCountProvider);

    final dayStart = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
    );
    final laneWidth = _calcLaneWidth(context);

    return Column(
      children: [
        // ── Contractor headers row (self-sizing, no fixed height) ─────────
        if (widget.contractors.isNotEmpty)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Empty space above the time axis column
                const SizedBox(width: _timeAxisWidth),
                // One header per contractor lane
                ...widget.contractors.map((c) => ContractorLaneHeader(
                      contractor: c,
                      laneWidth: laneWidth,
                    )),
              ],
            ),
          ),

        // ── Scroll area: time axis + lane bodies (single scroll surface) ──
        Expanded(
          child: widget.contractors.isEmpty
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: _timeAxisWidth),
                    Expanded(
                      child: _EmptyLanesPlaceholder(
                        dayStart: dayStart,
                        totalContractorCount: widget.totalContractorCount,
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  controller: _scrollController,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: fixed-width time axis (scrolls with lanes)
                      const SizedBox(
                        width: _timeAxisWidth,
                        child: _TimeAxisColumn(
                          totalHeight: _totalDayMinutes * pixelsPerMinute,
                          pixelsPerMinute: pixelsPerMinute,
                        ),
                      ),

                      // Right: contractor lane bodies
                      ..._buildLaneWidgets(
                        dayStart: dayStart,
                        laneWidth: laneWidth,
                        showCompleted: showCompleted,
                      ),
                    ],
                  ),
                ),
        ),

        // ── Pagination controls ─────────────────────────────────────────────
        if (pageCount > 1)
          _PaginationControls(
            pageCount: pageCount,
            onPrevious: _onPreviousPage,
            onNext: _onNextPage,
          ),
      ],
    );
  }

  /// Calculates the width available for each contractor lane on the current page.
  double _calcLaneWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - _timeAxisWidth;
    final contractorCount = widget.contractors.length.clamp(1, 5);
    return availableWidth / contractorCount;
  }

  /// Builds contractor lane widgets for the current page (used inside the
  /// single parent SingleChildScrollView — no per-lane scroll views).
  List<Widget> _buildLaneWidgets({
    required DateTime dayStart,
    required double laneWidth,
    required bool showCompleted,
  }) {
    return widget.contractors.map((contractor) {
      final contractorBookings = widget.bookings
          .where((b) => b.contractorId == contractor.id)
          .toList();

      final workStart = dayStart.add(const Duration(hours: 6));
      final workEnd = dayStart.add(const Duration(hours: 18));
      final blockedIntervals = [
        BlockedInterval(
          start: dayStart,
          end: workStart,
          reason: 'outside_working_hours',
        ),
        BlockedInterval(
          start: workEnd,
          end: dayStart.add(const Duration(days: 1)),
          reason: 'outside_working_hours',
        ),
      ];

      return ContractorLane(
        contractor: contractor,
        dayStart: dayStart,
        bookings: contractorBookings,
        jobs: widget.jobs,
        blockedIntervals: blockedIntervals,
        laneWidth: laneWidth,
        pixelsPerMinute: pixelsPerMinute,
        totalDayHeightMinutes: _totalDayMinutes,
        showHeader: false,
        showCompleted: showCompleted,
        companyId: widget.companyId,
        onBookingCreated: (_) => widget.onBookingMutated?.call(),
        onBookingReassigned: (_) => widget.onBookingMutated?.call(),
      );
    }).toList();
  }

  void _onPreviousPage() {
    final current = ref.read(contractorPageIndexProvider);
    if (current > 0) {
      ref.read(contractorPageIndexProvider.notifier).state = current - 1;
    }
  }

  void _onNextPage() {
    final current = ref.read(contractorPageIndexProvider);
    final pageCount = ref.read(contractorPageCountProvider);
    if (current < pageCount - 1) {
      ref.read(contractorPageIndexProvider.notifier).state = current + 1;
    }
  }
}

// ─── Internal sub-widgets ──────────────────────────────────────────────────────

/// Fixed left column displaying hourly time labels from 00:00 to 23:00.
class _TimeAxisColumn extends StatelessWidget {
  const _TimeAxisColumn({
    required this.totalHeight,
    required this.pixelsPerMinute,
  });

  final double totalHeight;
  final double pixelsPerMinute;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
                _formatHour(hour),
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
    );
  }

  String _formatHour(int hour) {
    final h = hour.toString().padLeft(2, '0');
    return '$h:00';
  }
}

// _LanePage removed — lane widgets now built inline by _buildLaneWidgets()
// and placed directly inside the single parent SingleChildScrollView.

/// Empty state shown when no contractors are available for the current filter.
///
/// Shows different messaging based on whether the empty state is caused by
/// the trade type filter or by having no contractor-role users at all.
class _EmptyLanesPlaceholder extends StatelessWidget {
  const _EmptyLanesPlaceholder({
    required this.dayStart,
    required this.totalContractorCount,
  });

  final DateTime dayStart;

  /// Total unfiltered contractor count. When 0, the issue is that no users
  /// have the 'contractor' role — not a filter problem.
  final int totalContractorCount;

  @override
  Widget build(BuildContext context) {
    final isFilterIssue = totalContractorCount > 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFilterIssue ? Icons.filter_alt_outlined : Icons.people_outline,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              isFilterIssue
                  ? 'No contractors match this filter'
                  : 'No contractors found',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isFilterIssue
                  ? 'Adjust the trade type filter to see contractors.'
                  : 'Assign the contractor role to team members\nso they appear on the schedule.',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isFilterIssue) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => context.push(RouteNames.adminTeam),
                icon: const Icon(Icons.group_add, size: 18),
                label: const Text('Team Management'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pagination controls: previous / page indicator / next.
class _PaginationControls extends StatelessWidget {
  const _PaginationControls({
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int pageCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final pageIndex = ref.watch(contractorPageIndexProvider);

        return Container(
          height: 40,
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: pageIndex > 0 ? onPrevious : null,
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              Text(
                'Page ${pageIndex + 1} of $pageCount',
                style: const TextStyle(fontSize: 12),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: pageIndex < pageCount - 1 ? onNext : null,
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
