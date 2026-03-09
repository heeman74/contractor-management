import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../../../shared/models/user_role.dart';
import '../../domain/booking_entity.dart';
import '../providers/calendar_providers.dart';
import 'booking_card.dart';
import 'calendar_grid_painter.dart';
import 'multi_day_wizard_dialog.dart';
import 'travel_time_block.dart';
import 'unscheduled_jobs_drawer.dart';

/// First visible working hour (slots rendered only for this range).
const int _workingHoursStart = 6; // 06:00
const int _workingHoursEnd = 20; // 20:00
const int _slotMinutes = 15; // 15-minute slots

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
    required this.scrollController,
    required this.companyId,
    super.key,
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

  /// Shared scroll controller for synchronized vertical scrolling.
  final ScrollController scrollController;

  /// Company ID for booking creation (tenant scope).
  final String companyId;

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

                    // DragTarget strips for working hours slots
                    // Only 15-min slots from 06:00–20:00 = ~56 strips (not 96 for 24h)
                    _DragTargetGrid(
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

// ─── DragTarget grid overlay ──────────────────────────────────────────────────

/// Grid of 15-minute DragTarget strips covering the working hours range.
///
/// Each strip:
///   - onWillAcceptWithDetails: checks local bookings for time overlap (OFFLINE ONLY).
///     If conflict detected, writes ConflictInfo to conflictInfoProvider.
///   - builder: green highlight if can accept, red if rejected.
///   - onAcceptWithDetails: calls bookSlot() or reassignBooking() on the provider.
///
/// Non-working hours are NOT covered by DragTargets — dropping outside
/// working hours is rejected.
///
/// Total widgets: ~56 per lane for 06:00–20:00 range (14h × 4 slots/h).
class _DragTargetGrid extends ConsumerWidget {
  const _DragTargetGrid({
    required this.contractor,
    required this.companyId,
    required this.dayStart,
    required this.bookings,
    required this.jobs,
    required this.laneWidth,
    required this.pixelsPerMinute,
    this.onBookingCreated,
    this.onBookingReassigned,
    super.key,
  });

  final UserEntity contractor;
  final String companyId;
  final DateTime dayStart;
  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobs;
  final double laneWidth;
  final double pixelsPerMinute;
  final void Function(String bookingId)? onBookingCreated;
  final void Function(String bookingId)? onBookingReassigned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotHeight = _slotMinutes * pixelsPerMinute;
    const totalSlotsStart = _workingHoursStart * 60 ~/ _slotMinutes;
    const totalSlotsEnd = _workingHoursEnd * 60 ~/ _slotMinutes;
    final slotCount = totalSlotsEnd - totalSlotsStart;

    return Stack(
      children: List.generate(slotCount, (index) {
        final slotIndex = totalSlotsStart + index;
        final slotStartMinutesFromMidnight = slotIndex * _slotMinutes;
        final slotStart = dayStart.add(
          Duration(minutes: slotStartMinutesFromMidnight),
        );
        final topY = slotStartMinutesFromMidnight * pixelsPerMinute;

        return Positioned(
          top: topY,
          left: 0,
          width: laneWidth,
          height: slotHeight,
          child: _SlotDragTarget(
            contractor: contractor,
            companyId: companyId,
            slotStart: slotStart,
            slotHeight: slotHeight,
            laneWidth: laneWidth,
            bookings: bookings,
            jobs: jobs,
            pixelsPerMinute: pixelsPerMinute,
            onBookingCreated: onBookingCreated,
            onBookingReassigned: onBookingReassigned,
          ),
        );
      }),
    );
  }
}

/// A single 15-minute slot DragTarget.
///
/// Handles conflict detection locally (no HTTP) — reads [bookings] list
/// which is already synced from Drift stream.
class _SlotDragTarget extends ConsumerWidget {
  const _SlotDragTarget({
    required this.contractor,
    required this.companyId,
    required this.slotStart,
    required this.slotHeight,
    required this.laneWidth,
    required this.bookings,
    required this.jobs,
    required this.pixelsPerMinute,
    this.onBookingCreated,
    this.onBookingReassigned,
    super.key,
  });

  final UserEntity contractor;
  final String companyId;
  final DateTime slotStart;
  final double slotHeight;
  final double laneWidth;
  final List<BookingEntity> bookings;
  final Map<String, JobEntity> jobs;
  final double pixelsPerMinute;
  final void Function(String bookingId)? onBookingCreated;
  final void Function(String bookingId)? onBookingReassigned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<BookingDragData>(
      onWillAcceptWithDetails: (details) {
        final dragData = details.data;
        final slotEnd =
            slotStart.add(Duration(minutes: dragData.durationMinutes));

        // Conflict check: LOCAL ONLY — instant, no HTTP, works offline.
        // Skip conflict check for the booking being dragged (it overlaps itself).
        final conflictingBooking = bookings.where((b) {
          if (b.id == dragData.existingBookingId) return false;
          // Check time overlap: [slotStart, slotEnd) overlaps [b.start, b.end)
          return slotStart.isBefore(b.timeRangeEnd) &&
              slotEnd.isAfter(b.timeRangeStart);
        }).firstOrNull;

        if (conflictingBooking != null) {
          // Write conflict info so schedule_screen can display the snackbar.
          final conflictJob = jobs[conflictingBooking.jobId];
          final description = conflictJob?.description ?? 'Unknown job';
          final timeRange = _formatTimeRange(
            conflictingBooking.timeRangeStart,
            conflictingBooking.timeRangeEnd,
          );
          ref.read(conflictInfoProvider.notifier).state = ConflictInfo(
            conflictingJobDescription: description,
            conflictingTimeRange: timeRange,
          );
          return false;
        }

        return true;
      },
      onAcceptWithDetails: (details) async {
        final dragData = details.data;
        final slotEnd =
            slotStart.add(Duration(minutes: dragData.durationMinutes));

        if (dragData.existingBookingId != null) {
          // Reassign existing booking to this lane/time
          final existingBooking = bookings.firstWhere(
            (b) => b.id == dragData.existingBookingId,
            orElse: () => throw StateError('Booking not found'),
          );
          await ref
              .read(bookingOperationsProvider.notifier)
              .reassignBooking(
                bookingId: dragData.existingBookingId!,
                newContractorId: contractor.id,
                newStart: slotStart,
                newEnd: slotEnd,
                previousContractorId:
                    dragData.sourceContractorId ?? contractor.id,
                previousStart: existingBooking.timeRangeStart,
                previousEnd: existingBooking.timeRangeEnd,
                currentVersion: existingBooking.version,
              );
          onBookingReassigned?.call(dragData.existingBookingId!);
        } else {
          // Create new booking from unscheduled job
          final job = jobs[dragData.jobId];
          final bookingId =
              await ref.read(bookingOperationsProvider.notifier).bookSlot(
                    companyId: companyId,
                    contractorId: contractor.id,
                    jobId: dragData.jobId,
                    slotStart: slotStart,
                    durationMinutes: dragData.durationMinutes,
                    jobCurrentStatus: job?.status,
                    jobCurrentVersion: job?.version ?? 1,
                    jobStatusHistory: job?.statusHistory,
                  );

          // Check if multi-day wizard should open (> 480 min = 8 hours)
          if ((job?.estimatedDurationMinutes ?? 0) > 480) {
            if (context.mounted) {
              _showMultiDayWizard(context, ref, bookingId, dragData.jobId,
                  companyId, contractor.id);
            }
          } else {
            onBookingCreated?.call(bookingId);
          }
        }
      },
      builder: (context, candidateData, rejectedData) {
        Color? overlayColor;
        if (candidateData.isNotEmpty) {
          overlayColor = Colors.green.withValues(alpha: 0.2);
        } else if (rejectedData.isNotEmpty) {
          overlayColor = Colors.red.withValues(alpha: 0.2);
        }

        // When no drag is in progress (no candidateData), allow tap to schedule.
        // Tap opens the bottom sheet job picker only when slot is empty.
        final isSlotOccupied = bookings.any((b) =>
            slotStart.isBefore(b.timeRangeEnd) &&
            slotStart.add(const Duration(minutes: 15)).isAfter(b.timeRangeStart));

        final child = overlayColor != null
            ? Container(
                width: laneWidth,
                height: slotHeight,
                color: overlayColor,
              )
            : const SizedBox.shrink();

        // Wrap with GestureDetector for tap-to-schedule only when not occupied
        if (candidateData.isEmpty && !isSlotOccupied) {
          return GestureDetector(
            onTap: () => _showTapToScheduleSheet(context, ref),
            child: child,
          );
        }

        return child;
      },
    );
  }

  /// Shows a bottom sheet with a filterable job list for tap-to-schedule.
  ///
  /// Admin taps an empty time slot → bottom sheet appears → selects a job →
  /// booking is created at the tapped slot.
  void _showTapToScheduleSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _TapToScheduleSheet(
        slotStart: slotStart,
        contractor: contractor,
        companyId: companyId,
        jobs: jobs,
        existingBookings: bookings,
        onJobSelected: (job) async {
          Navigator.of(sheetContext).pop();
          final bookingId =
              await ref.read(bookingOperationsProvider.notifier).bookSlot(
                    companyId: companyId,
                    contractorId: contractor.id,
                    jobId: job.id,
                    slotStart: slotStart,
                    durationMinutes: job.estimatedDurationMinutes ?? 60,
                    jobCurrentStatus: job.status,
                    jobCurrentVersion: job.version,
                    jobStatusHistory: job.statusHistory,
                  );

          if ((job.estimatedDurationMinutes ?? 0) > 480 &&
              context.mounted) {
            _showMultiDayWizardForTap(
                context, ref, bookingId, job, companyId, contractor.id);
          } else {
            onBookingCreated?.call(bookingId);
          }
        },
      ),
    );
  }

  void _showMultiDayWizardForTap(
    BuildContext context,
    WidgetRef ref,
    String bookingId,
    JobEntity job,
    String companyId,
    String contractorId,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => MultiDayWizardDialog(
        parentBookingId: bookingId,
        jobDescription: job.description,
        firstDayContractorName: contractor.email.split('@').first,
        firstDayStart: slotStart,
        firstDayEnd: slotStart.add(Duration(minutes: job.estimatedDurationMinutes ?? 60)),
        companyId: companyId,
        defaultContractorId: contractorId,
        onConfirmed: (additionalDays) async {
          await ref.read(bookingOperationsProvider.notifier).bookMultiDay(
                companyId: companyId,
                jobId: job.id,
                parentBookingId: bookingId,
                additionalDays: additionalDays,
              );
          onBookingCreated?.call(bookingId);
        },
        onCancelled: () async {
          await ref
              .read(bookingOperationsProvider.notifier)
              .undoLastBooking();
        },
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

  void _showMultiDayWizard(
    BuildContext context,
    WidgetRef ref,
    String bookingId,
    String jobId,
    String companyId,
    String contractorId,
  ) {
    final job = jobs[jobId];
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => MultiDayWizardDialog(
        parentBookingId: bookingId,
        jobDescription: job?.description ?? 'Job',
        firstDayContractorName: contractor.email.split('@').first,
        firstDayStart: slotStart,
        firstDayEnd: slotStart.add(
          Duration(minutes: job?.estimatedDurationMinutes ?? 60),
        ),
        companyId: companyId,
        defaultContractorId: contractorId,
        onConfirmed: (additionalDays) async {
          await ref.read(bookingOperationsProvider.notifier).bookMultiDay(
                companyId: companyId,
                jobId: jobId,
                parentBookingId: bookingId,
                additionalDays: additionalDays,
              );
          onBookingCreated?.call(bookingId);
        },
        onCancelled: () async {
          await ref
              .read(bookingOperationsProvider.notifier)
              .undoLastBooking();
        },
      ),
    );
  }
}

// ─── Tap-to-schedule bottom sheet ─────────────────────────────────────────────

/// Filterable job list bottom sheet for tap-to-schedule.
///
/// Shows jobs without bookings for the current date. Admin selects a job
/// to schedule it at the tapped time slot.
class _TapToScheduleSheet extends ConsumerStatefulWidget {
  const _TapToScheduleSheet({
    required this.slotStart,
    required this.contractor,
    required this.companyId,
    required this.jobs,
    required this.existingBookings,
    required this.onJobSelected,
  });

  final DateTime slotStart;
  final UserEntity contractor;
  final String companyId;
  final Map<String, JobEntity> jobs;
  final List<BookingEntity> existingBookings;
  final Future<void> Function(JobEntity job) onJobSelected;

  @override
  ConsumerState<_TapToScheduleSheet> createState() =>
      _TapToScheduleSheetState();
}

class _TapToScheduleSheetState
    extends ConsumerState<_TapToScheduleSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unscheduledJobsAsync = ref.watch(unscheduledJobsProvider);
    final searchText = _searchController.text.toLowerCase();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Schedule at ${_formatTime(widget.slotStart)}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search jobs...',
                  prefixIcon: Icon(Icons.search, size: 16),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),

            const Divider(height: 1),

            // Job list
            Expanded(
              child: unscheduledJobsAsync.when(
                data: (unscheduledJobs) {
                  // Filter by search text
                  final filtered = unscheduledJobs.where((j) {
                    if (searchText.isEmpty) return true;
                    return j.description.toLowerCase().contains(searchText) ||
                        (j.clientId?.toLowerCase().contains(searchText) ??
                            false);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 36, color: Colors.green),
                          const SizedBox(height: 8),
                          Text(
                            'All jobs scheduled',
                            style:
                                TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final driftJob = filtered[index];
                      // Try to find matching JobEntity for full details
                      final jobEntity = widget.jobs[driftJob.id];

                      return ListTile(
                        dense: true,
                        title: Text(
                          driftJob.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${driftJob.tradeType}'
                          '${driftJob.estimatedDurationMinutes != null ? '  •  ${_formatDuration(driftJob.estimatedDurationMinutes!)}' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            driftJob.status,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onTap: () {
                          if (jobEntity != null) {
                            widget.onJobSelected(jobEntity);
                          }
                        },
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Error loading jobs',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h:$minute $period';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// ─── Internal lane sub-widget ──────────────────────────────────────────────────

/// Fixed header showing contractor avatar and name at the top of a lane.
///
/// Does not scroll — remains visible while the time body scrolls vertically.
///
/// Admin long-press: wrap the header in a [GestureDetector] that opens
/// schedule settings for the contractor. Per CONTEXT.md locked decision:
/// "Contractor schedule management: both inline quick actions from calendar
/// (long-press for day off, adjust hours) AND a separate settings screen".
class _ContractorHeader extends ConsumerWidget {
  const _ContractorHeader({
    required this.contractor,
    required this.laneWidth,
  });

  final UserEntity contractor;
  final double laneWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = _contractorName(contractor);
    final initials = _initials(displayName);
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState is AuthAuthenticated &&
        authState.roles.contains(UserRole.admin);

    final headerContent = Container(
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
          // Admin-only hint: shows tooltip on long-press
          if (isAdmin)
            const Icon(Icons.more_horiz, size: 10, color: Colors.grey),
        ],
      ),
    );

    // Admin users: long-press opens schedule settings for this contractor.
    // Contractors: no long-press action (they use the gear icon in their own screen).
    if (isAdmin) {
      return GestureDetector(
        onLongPress: () {
          context.push(
            RouteNames.scheduleSettings,
            extra: contractor.id,
          );
        },
        child: Tooltip(
          message: 'Long press to manage schedule',
          child: headerContent,
        ),
      );
    }

    return headerContent;
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
