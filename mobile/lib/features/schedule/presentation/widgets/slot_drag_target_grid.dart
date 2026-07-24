import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/jobs/domain/job_entity.dart';
import '../../../../features/users/domain/user_entity.dart';
import '../../domain/booking_entity.dart';
import '../../domain/schedule_constants.dart';
import '../../domain/schedule_time_format.dart';
import '../providers/calendar_providers.dart';
import 'multi_day_wizard_dialog.dart';
import 'tap_to_schedule_sheet.dart';

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
class DragTargetGrid extends ConsumerWidget {
  const DragTargetGrid({
    required this.contractor,
    required this.companyId,
    required this.dayStart,
    required this.bookings,
    required this.jobs,
    required this.laneWidth,
    required this.pixelsPerMinute,
    super.key,
    this.onBookingCreated,
    this.onBookingReassigned,
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
    final slotHeight = ScheduleConstants.slotMinutes * pixelsPerMinute;
    const totalSlotsStart = ScheduleConstants.workingHoursStart *
        ScheduleConstants.minutesPerHour ~/
        ScheduleConstants.slotMinutes;
    const totalSlotsEnd = ScheduleConstants.workingHoursEnd *
        ScheduleConstants.minutesPerHour ~/
        ScheduleConstants.slotMinutes;
    const slotCount = totalSlotsEnd - totalSlotsStart;

    return Stack(
      children: List.generate(slotCount, (index) {
        final slotIndex = totalSlotsStart + index;
        final slotStartMinutesFromMidnight =
            slotIndex * ScheduleConstants.slotMinutes;
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
          final timeRange = ScheduleTimeFormat.range(
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
          // Reassign existing booking to this lane/time.
          // Use drag data for previous start/end/version — the source booking
          // may not exist in THIS lane's bookings list (cross-lane drag).
          await ref
              .read(bookingOperationsProvider.notifier)
              .reassignBooking(
                bookingId: dragData.existingBookingId!,
                newContractorId: contractor.id,
                newStart: slotStart,
                newEnd: slotEnd,
                previousContractorId:
                    dragData.sourceContractorId ?? contractor.id,
                previousStart: dragData.previousStart ?? slotStart,
                previousEnd: dragData.previousEnd ?? slotEnd,
                currentVersion: dragData.previousVersion ?? 1,
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

          if ((job?.estimatedDurationMinutes ?? 0) >
              ScheduleConstants.multiDayThresholdMinutes) {
            if (context.mounted) {
              _openMultiDayWizard(context, ref, bookingId: bookingId, job: job);
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
            slotStart
                .add(const Duration(minutes: ScheduleConstants.slotMinutes))
                .isAfter(b.timeRangeStart));

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
      builder: (sheetContext) => TapToScheduleSheet(
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
                    durationMinutes: job.estimatedDurationMinutes ??
                        ScheduleConstants.defaultBookingMinutes,
                    jobCurrentStatus: job.status,
                    jobCurrentVersion: job.version,
                    jobStatusHistory: job.statusHistory,
                  );

          if ((job.estimatedDurationMinutes ?? 0) >
                  ScheduleConstants.multiDayThresholdMinutes &&
              context.mounted) {
            _openMultiDayWizard(context, ref, bookingId: bookingId, job: job);
          } else {
            onBookingCreated?.call(bookingId);
          }
        },
      ),
    );
  }

  /// Opens the multi-day scheduling wizard for a freshly created [bookingId].
  ///
  /// Unifies the drag-drop and tap-to-schedule flows. When [job] is null
  /// (job details not available locally) sensible fallbacks are used.
  void _openMultiDayWizard(
    BuildContext context,
    WidgetRef ref, {
    required String bookingId,
    required JobEntity? job,
  }) {
    final durationMinutes =
        job?.estimatedDurationMinutes ?? ScheduleConstants.defaultBookingMinutes;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => MultiDayWizardDialog(
        parentBookingId: bookingId,
        jobDescription: job?.description ?? 'Job',
        firstDayContractorName: contractor.email.split('@').first,
        firstDayStart: slotStart,
        firstDayEnd: slotStart.add(Duration(minutes: durationMinutes)),
        companyId: companyId,
        defaultContractorId: contractor.id,
        onConfirmed: (additionalDays) async {
          await ref.read(bookingOperationsProvider.notifier).bookMultiDay(
                companyId: companyId,
                jobId: job?.id ?? '',
                parentBookingId: bookingId,
                additionalDays: additionalDays,
              );
          onBookingCreated?.call(bookingId);
        },
        onCancelled: () async {
          await ref.read(bookingOperationsProvider.notifier).undoLastBooking();
        },
      ),
    );
  }
}
