import 'package:flutter/material.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import 'booking_card.dart';
import 'calendar_grid_painter.dart';
import 'travel_time_block.dart';

/// Widget rendering one contractor's day schedule as a vertical time column.
///
/// Layout:
///   - Fixed header at top: contractor avatar + name (does not scroll vertically)
///   - Scrollable body (via shared [scrollController]): Stack with:
///     - CalendarGridPainter as background (hour lines, blocked regions, now-line)
///     - BookingCard widgets absolutely positioned by time
///     - TravelTimeBlock widgets positioned between consecutive bookings
///
/// Positioning formula:
///   topY = (booking.timeRangeStart - dayStart).inMinutes * pixelsPerMinute
///
/// Scroll sync: the [scrollController] is shared across all visible lanes and
/// the time axis so scrolling is synchronized.
///
/// Lane width: calculated by the parent [CalendarDayView] as:
///   (screenWidth - timeAxisWidth) / contractorsOnPage  (max 5)
class ContractorLane extends StatelessWidget {
  const ContractorLane({
    required this.contractor,
    required this.dayStart,
    required this.bookings,
    required this.jobs,
    required this.blockedIntervals,
    required this.laneWidth,
    required this.pixelsPerMinute,
    required this.totalDayHeightMinutes,
    required this.scrollController,
    super.key,
    this.showCompleted = false,
  });

  /// The contractor whose schedule is displayed in this lane.
  final UserEntity contractor;

  /// Midnight of the displayed day (used as origin for vertical positioning).
  final DateTime dayStart;

  /// All bookings for this contractor on this day (already filtered).
  final List<BookingEntity> bookings;

  /// Map from jobId → JobEntity for resolving job details for BookingCard.
  final Map<String, JobEntity> jobs;

  /// Blocked intervals for this contractor (working hours, time-off, travel buffers).
  final List<BlockedInterval> blockedIntervals;

  /// Width of this lane in logical pixels.
  final double laneWidth;

  /// Scale factor: logical pixels per minute (2.0 = 120px/hour).
  final double pixelsPerMinute;

  /// Total scrollable height of the lane = 24 * 60 * pixelsPerMinute.
  final double totalDayHeightMinutes;

  /// Shared scroll controller for synchronized vertical scrolling.
  final ScrollController scrollController;

  /// Whether completed/invoiced/cancelled jobs display at full opacity.
  final bool showCompleted;

  @override
  Widget build(BuildContext context) {
    final totalHeight = totalDayHeightMinutes * pixelsPerMinute;

    return SizedBox(
      width: laneWidth,
      child: Column(
        children: [
          // Fixed contractor header (does not scroll with time axis)
          _ContractorHeader(contractor: contractor, laneWidth: laneWidth),

          // Scrollable time body — synchronized with time axis and other lanes
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              physics: const NeverScrollableScrollPhysics(), // Parent handles scroll
              child: SizedBox(
                width: laneWidth,
                height: totalHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Background: grid lines + blocked hour shading + now-line
                    CustomPaint(
                      size: Size(laneWidth, totalHeight),
                      painter: CalendarGridPainter(
                        dayStart: dayStart,
                        pixelsPerMinute: pixelsPerMinute,
                        blockedIntervals: blockedIntervals,
                        laneWidth: laneWidth,
                        currentTime: DateTime.now(),
                      ),
                    ),

                    // Booking cards and travel time blocks
                    ..._buildBookingWidgets(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the positioned booking cards and travel time blocks for this lane.
  ///
  /// Processes bookings in time order to interleave travel time blocks between
  /// consecutive bookings where a 'travel_buffer' interval exists.
  List<Widget> _buildBookingWidgets() {
    final widgets = <Widget>[];
    final sortedBookings = List<BookingEntity>.from(bookings)
      ..sort((a, b) => a.timeRangeStart.compareTo(b.timeRangeStart));

    for (var i = 0; i < sortedBookings.length; i++) {
      final booking = sortedBookings[i];
      final job = jobs[booking.jobId];
      if (job == null) continue; // Skip bookings with no local job data

      final topY =
          booking.timeRangeStart.difference(dayStart).inMinutes * pixelsPerMinute;
      final durationMinutes =
          booking.timeRangeEnd.difference(booking.timeRangeStart).inMinutes;

      // Position the booking card
      widgets.add(
        Positioned(
          top: topY,
          left: 0,
          child: BookingCard(
            job: job,
            durationMinutes: durationMinutes,
            pixelsPerMinute: pixelsPerMinute,
            laneWidth: laneWidth,
            showCompleted: showCompleted,
          ),
        ),
      );

      // Check for a travel buffer after this booking (before the next one)
      if (i < sortedBookings.length - 1) {
        final nextBooking = sortedBookings[i + 1];
        final travelInterval = blockedIntervals.where((interval) {
          return interval.reason == 'travel_buffer' &&
              interval.start.isAtSameMomentAs(booking.timeRangeEnd) &&
              interval.end.isAtSameMomentAs(nextBooking.timeRangeStart);
        }).firstOrNull;

        if (travelInterval != null) {
          final travelTopY =
              travelInterval.start.difference(dayStart).inMinutes *
                  pixelsPerMinute;
          final travelHeight =
              travelInterval.end.difference(travelInterval.start).inMinutes *
                  pixelsPerMinute;

          if (travelHeight > 0) {
            widgets.add(
              Positioned(
                top: travelTopY,
                left: 0,
                child: TravelTimeBlock(
                  height: travelHeight,
                  width: laneWidth,
                ),
              ),
            );
          }
        }
      }
    }

    return widgets;
  }
}

// ─── Internal sub-widget ──────────────────────────────────────────────────────

/// Fixed header showing contractor avatar and name at the top of a lane.
///
/// Does not scroll — remains visible while the time body scrolls vertically.
class _ContractorHeader extends StatelessWidget {
  const _ContractorHeader({
    required this.contractor,
    required this.laneWidth,
  });

  final UserEntity contractor;
  final double laneWidth;

  @override
  Widget build(BuildContext context) {
    final displayName = _contractorName(contractor);
    final initials = _initials(displayName);
    final theme = Theme.of(context);

    return Container(
      width: laneWidth,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _contractorName(UserEntity user) {
    final firstName = user.firstName ?? '';
    final lastName = user.lastName ?? '';
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '$firstName $lastName';
    }
    if (firstName.isNotEmpty) return firstName;
    return user.email.split('@').first;
  }

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
