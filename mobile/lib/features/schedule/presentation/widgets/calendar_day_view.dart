import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../providers/calendar_providers.dart';
import 'calendar_grid_painter.dart';
import 'contractor_lane.dart';

/// Width of the fixed time axis label column on the left.
const double _timeAxisWidth = 44.0;

/// Height of each contractor lane header (avatar + name row).
const double _laneHeaderHeight = 52.0;

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
    const totalHeight = _totalDayMinutes * pixelsPerMinute;

    return Column(
      children: [
        // ── Content area: time axis + contractor lanes ──────────────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: fixed-width time axis (scrolls with lanes)
              SizedBox(
                width: _timeAxisWidth,
                child: Column(
                  children: [
                    // Spacer to align with lane header height
                    const SizedBox(height: _laneHeaderHeight),
                    // Time labels scroll area
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: const _TimeAxisColumn(
                          totalHeight: _totalDayMinutes * pixelsPerMinute,
                          pixelsPerMinute: pixelsPerMinute,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Right: paginated contractor lanes
              Expanded(
                child: widget.contractors.isEmpty
                    ? _EmptyLanesPlaceholder(dayStart: dayStart)
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          // Sync lane scroll to time axis
                          if (notification.metrics.axis == Axis.vertical) {
                            if (_scrollController.hasClients &&
                                notification.metrics.pixels !=
                                    _scrollController.offset) {
                              _scrollController.jumpTo(
                                notification.metrics.pixels,
                              );
                            }
                          }
                          return false;
                        },
                        child: _LanePage(
                          contractors: widget.contractors,
                          dayStart: dayStart,
                          bookings: widget.bookings,
                          jobs: widget.jobs,
                          laneWidth: _calcLaneWidth(context),
                          pixelsPerMinute: pixelsPerMinute,
                          totalHeight: totalHeight,
                          scrollController: _scrollController,
                          showCompleted: showCompleted,
                          companyId: widget.companyId,
                          onBookingMutated: widget.onBookingMutated,
                        ),
                      ),
              ),
            ],
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

/// Row of ContractorLane widgets for the current page.
///
/// Uses a single shared [scrollController] so all lanes scroll in sync.
class _LanePage extends StatelessWidget {
  const _LanePage({
    required this.contractors,
    required this.dayStart,
    required this.bookings,
    required this.jobs,
    required this.laneWidth,
    required this.pixelsPerMinute,
    required this.totalHeight,
    required this.scrollController,
    required this.showCompleted,
    required this.companyId,
    this.onBookingMutated,
  });

  final List<UserEntity> contractors;
  final DateTime dayStart;
  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobs;
  final double laneWidth;
  final double pixelsPerMinute;
  final double totalHeight;
  final ScrollController scrollController;
  final bool showCompleted;
  final String companyId;
  final VoidCallback? onBookingMutated;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: contractors.map((contractor) {
        // Filter bookings for this contractor
        final contractorBookings = bookings
            .where((b) => b.contractorId == contractor.id)
            .toList();

        // Build blocked intervals for outside-working-hours shading.
        // For now we use a default working hours window (06:00 – 18:00).
        // Plan 03 will wire actual contractor schedule data here.
        final blockedIntervals = _buildDefaultBlockedIntervals(dayStart);

        return ContractorLane(
          contractor: contractor,
          dayStart: dayStart,
          bookings: contractorBookings,
          jobs: jobs,
          blockedIntervals: blockedIntervals,
          laneWidth: laneWidth,
          pixelsPerMinute: pixelsPerMinute,
          totalDayHeightMinutes: _totalDayMinutes,
          scrollController: scrollController,
          showCompleted: showCompleted,
          companyId: companyId,
          onBookingCreated: (_) => onBookingMutated?.call(),
          onBookingReassigned: (_) => onBookingMutated?.call(),
        );
      }).toList(),
    );
  }

  /// Builds default blocked intervals for outside working hours (06:00–18:00).
  ///
  /// Plan 03 will replace this with actual contractor schedule data from the
  /// scheduling engine (ContractorWeeklySchedule + overrides).
  List<BlockedInterval> _buildDefaultBlockedIntervals(DateTime dayStart) {
    final workStart = dayStart.add(const Duration(hours: 6));
    final workEnd = dayStart.add(const Duration(hours: 18));

    return [
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
  }
}

/// Empty state shown when no contractors are available for the current filter.
class _EmptyLanesPlaceholder extends StatelessWidget {
  const _EmptyLanesPlaceholder({required this.dayStart});

  final DateTime dayStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            'No contractors found',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adjust the trade type filter to see contractors.',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
