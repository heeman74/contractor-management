import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../domain/overdue_service.dart';
import '../providers/calendar_providers.dart';

/// Stateless widget displaying a single booking on the day view calendar.
///
/// Visual features:
///   - Sized by booking duration × [pixelsPerMinute]
///   - Background: [statusColorMap] color at 0.15 opacity + 4px solid left border
///   - Content: job description (max 2 lines) + client name
///   - Overdue indicator: yellow/orange border for warning (1-3d), red + icon for critical (4+d)
///   - Delay badge: clock icon if status_history contains a 'delay' entry
///   - Opacity dimming (0.4) for completed/invoiced/cancelled when [showCompleted] is false
///   - Tap navigates to job detail screen via go_router
///   - Wrapped in [LongPressDraggable] for Plan 03 drag-and-drop (data param is placeholder)
///
/// Leaf widget — no dependency on ContractorLane, CalendarDayView, or providers.
class BookingCard extends StatelessWidget {
  const BookingCard({
    required this.job,
    required this.durationMinutes,
    required this.pixelsPerMinute,
    required this.laneWidth,
    super.key,
    this.showCompleted = false,
  });

  /// The job associated with this booking (provides description, status, etc.).
  final JobEntity job;

  /// Duration of the booking in minutes (timeRangeEnd - timeRangeStart).
  final int durationMinutes;

  /// Scale factor: logical pixels per minute (typically [pixelsPerMinute] = 2.0).
  final double pixelsPerMinute;

  /// Width of the parent contractor lane in logical pixels.
  final double laneWidth;

  /// Whether completed/invoiced/cancelled jobs should display at full opacity.
  ///
  /// When false (default), terminal-status bookings are dimmed to 0.4 opacity.
  final bool showCompleted;

  @override
  Widget build(BuildContext context) {
    final cardHeight =
        (durationMinutes * pixelsPerMinute).clamp(24.0, double.infinity);
    final status = job.status;
    final statusColor = statusColorMap[status] ?? Colors.grey;
    final severity = OverdueService.computeSeverity(job.scheduledCompletionDate);
    final hasDelayEntry = _hasDelayEntry(job.statusHistory);
    final isTerminalStatus = _isTerminalStatus(status);

    // Dim terminal-status bookings when showCompleted is false.
    final opacity = (!showCompleted && isTerminalStatus) ? 0.4 : 1.0;

    // Overdue border color overrides status border when job is overdue.
    final borderColor = switch (severity) {
      OverdueSeverity.critical => Colors.red,
      OverdueSeverity.warning => Colors.orange,
      OverdueSeverity.none => statusColor,
    };

    final criticalBorderSide = severity == OverdueSeverity.critical
        ? BorderSide(color: Colors.red.withValues(alpha: 0.6))
        : BorderSide.none;

    final card = Opacity(
      opacity: opacity,
      child: Container(
        width: laneWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          border: Border(
            left: BorderSide(color: borderColor, width: 4),
            top: criticalBorderSide,
            right: criticalBorderSide,
            bottom: criticalBorderSide,
          ),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: ClipRect(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 3, 4, 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: description + badges
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        job.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor.withValues(alpha: 0.9),
                          height: 1.2,
                        ),
                      ),
                    ),
                    // Badge row: delay icon + overdue critical icon
                    if (hasDelayEntry || severity == OverdueSeverity.critical)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasDelayEntry)
                            Icon(
                              Icons.schedule,
                              size: 12,
                              color: Colors.orange[700],
                            ),
                          if (severity == OverdueSeverity.critical)
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 12,
                              color: Colors.red,
                            ),
                        ],
                      ),
                  ],
                ),

                // Client name — show only if card is tall enough
                if (cardHeight >= 36 && job.clientId != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    'Client ${job.clientId!.substring(0, 8)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // Wrap in LongPressDraggable for Plan 03 drag-and-drop.
    // The feedback and DragTarget implementations are added in Plan 03.
    // For now, 'data' is the jobId placeholder — drag has no visual effect yet.
    return LongPressDraggable<String>(
      data: job.id, // Plan 03 will use this for scheduling drag-and-drop
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(
            width: laneWidth,
            height: cardHeight,
            child: card,
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: card,
      ),
      child: GestureDetector(
        onTap: () => context.push(RouteNames.jobDetailPath(job.id)),
        child: card,
      ),
    );
  }

  /// Returns true if the job's status history contains a delay entry.
  ///
  /// Delay entries are added by PATCH /jobs/{id}/delay (Plan 01 backend).
  /// Each entry has: {type: 'delay', reason: ..., new_eta: ..., timestamp: ...}
  bool _hasDelayEntry(List<Map<String, dynamic>> statusHistory) {
    return statusHistory.any((entry) => entry['type'] == 'delay');
  }

  /// Returns true for terminal job statuses that should be dimmed.
  bool _isTerminalStatus(String status) {
    const terminalStatuses = {'complete', 'invoiced', 'cancelled'};
    return terminalStatuses.contains(status);
  }
}
