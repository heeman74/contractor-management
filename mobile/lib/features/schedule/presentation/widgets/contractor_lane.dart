import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../../domain/schedule_constants.dart';
import '../providers/calendar_providers.dart';
import 'booking_card.dart';
import 'calendar_grid_painter.dart';
import 'contractor_lane_header.dart';
import 'slot_drag_target_grid.dart';
import 'travel_time_block.dart';

export 'contractor_lane_header.dart' show ContractorLaneHeader;

/// Widget rendering one contractor's day schedule as a vertical time column.
///
/// Layout:
///   - Fixed header at top: contractor avatar + name (does not scroll vertically)
///   - Scrollable body (via shared [scrollController]): Stack with:
///     - CalendarGridPainter as background (hour lines, blocked regions, now-line)
///     - DragTarget grid strips for 15-minute slots (working hours only)
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
///
/// DragTarget strips:
///   Only rendered for working hours (06:00–20:00) to keep widget count low
///   (~56 strips per lane, NOT 96 for full 24h).
class ContractorLane extends ConsumerWidget {
  const ContractorLane({
    required this.contractor,
    required this.dayStart,
    required this.bookings,
    required this.jobs,
    required this.blockedIntervals,
    required this.laneWidth,
    required this.pixelsPerMinute,
    required this.totalDayHeightMinutes,
    required this.companyId,
    super.key,
    this.currentTime,
    this.showHeader = true,
    this.showCompleted = false,
    this.onBookingCreated,
    this.onBookingReassigned,
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

  /// Company ID for booking creation (tenant scope).
  final String companyId;

  /// Current time for the "now" line. Passed from a stateful parent that
  /// updates it periodically (e.g., every minute) to avoid creating a new
  /// DateTime.now() on every rebuild, which would force the CustomPainter
  /// to repaint unnecessarily.
  final DateTime? currentTime;

  /// Whether to show the contractor name/avatar header above the lane.
  /// Set to `false` when headers are rendered separately by the parent.
  final bool showHeader;

  /// Whether completed/invoiced/cancelled jobs display at full opacity.
  final bool showCompleted;

  /// Callback fired after a new booking is successfully created.
  /// Provides the bookingId for undo snackbar display.
  final void Function(String bookingId)? onBookingCreated;

  /// Callback fired after a booking is reassigned to this lane.
  final void Function(String bookingId)? onBookingReassigned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalHeight = totalDayHeightMinutes * pixelsPerMinute;

    // The lane body — parent SingleChildScrollView handles scrolling.
    final body = SizedBox(
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
              currentTime: currentTime ?? DateTime.now(),
            ),
          ),

          // DragTarget strips for working hours slots
          // Only 15-min slots from 06:00–20:00 = ~56 strips (not 96 for 24h)
          DragTargetGrid(
            contractor: contractor,
            companyId: companyId,
            dayStart: dayStart,
            bookings: bookings,
            jobs: jobs,
            laneWidth: laneWidth,
            pixelsPerMinute: pixelsPerMinute,
            onBookingCreated: onBookingCreated,
            onBookingReassigned: onBookingReassigned,
          ),

          // Booking cards and travel time blocks (rendered on top of DragTargets)
          ..._buildBookingWidgets(ref),
        ],
      ),
    );

    if (showHeader) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ContractorLaneHeader(contractor: contractor, laneWidth: laneWidth),
          body,
        ],
      );
    }

    return body;
  }

  /// Builds the positioned booking cards and travel time blocks for this lane.
  ///
  /// Processes bookings in time order to interleave travel time blocks between
  /// consecutive bookings where a 'travel_buffer' interval exists.
  List<Widget> _buildBookingWidgets(WidgetRef ref) {
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
            booking: booking,
            job: job,
            durationMinutes: durationMinutes,
            pixelsPerMinute: pixelsPerMinute,
            laneWidth: laneWidth,
            showCompleted: showCompleted,
            onResized: (newStart, newEnd) async {
              await ref.read(bookingOperationsProvider.notifier).resizeBooking(
                    bookingId: booking.id,
                    newStart: newStart,
                    newEnd: newEnd,
                    previousStart: booking.timeRangeStart,
                    previousEnd: booking.timeRangeEnd,
                    currentVersion: booking.version,
                  );
            },
          ),
        ),
      );

      // Check for a travel buffer after this booking (before the next one)
      if (i < sortedBookings.length - 1) {
        final nextBooking = sortedBookings[i + 1];
        final travelInterval = blockedIntervals.where((interval) {
          return interval.reason == BlockedIntervalReason.travelBuffer &&
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
