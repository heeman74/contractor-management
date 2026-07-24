import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../providers/calendar_providers.dart';
import 'calendar_grid_painter.dart';
import 'contractor_lane.dart';

/// Single-lane contractor calendar view for the selected day.
///
/// Reuses [ContractorLane] and [CalendarGridPainter] from the admin dispatch
/// calendar. Shows only the contractor's own bookings on the time grid.
/// Read-only: DragTarget dropping is not enabled for contractor view.
class ContractorCalendarView extends ConsumerStatefulWidget {
  const ContractorCalendarView({
    required this.contractorId,
    required this.companyId,
    required this.selectedDate,
    required this.bookings,
    required this.jobMap,
    super.key,
  });

  final String contractorId;
  final String companyId;
  final DateTime selectedDate;
  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobMap;

  @override
  ConsumerState<ContractorCalendarView> createState() =>
      _ContractorCalendarViewState();
}

class _ContractorCalendarViewState
    extends ConsumerState<ContractorCalendarView> {
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
