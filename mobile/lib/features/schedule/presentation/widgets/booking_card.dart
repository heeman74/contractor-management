import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_names.dart';
import '../../../../features/jobs/domain/job_entity.dart';
import '../../domain/booking_entity.dart';
import '../../domain/overdue_service.dart';
import '../providers/calendar_providers.dart';

/// Height of the resize handle strips at top and bottom edges of a booking card.
const double _resizeHandleHeight = 8.0;

/// Minimum booking duration in minutes (prevents resize to zero).
const int _minBookingMinutes = 15;

/// Stateful widget displaying a single booking on the day view calendar.
///
/// Visual features:
///   - Sized by booking duration × [pixelsPerMinute]
///   - Background: [statusColorMap] color at 0.15 opacity + 4px solid left border
///   - Content: job description (max 2 lines) + client name
///   - Overdue indicator: yellow/orange border for warning (1-3d), red + icon for critical (4+d)
///   - Delay badge: clock icon if status_history contains a 'delay' entry
///   - Opacity dimming (0.4) for completed/invoiced/cancelled when [showCompleted] is false
///   - Tap navigates to job detail screen via go_router
///
/// Resize handles:
///   - 8px strip at top edge: drag up/down adjusts timeRangeStart (snaps to 15-min)
///   - 8px strip at bottom edge: drag up/down adjusts timeRangeEnd (snaps to 15-min)
///   - Resize gesture is independent from LongPressDraggable (uses vertical drag)
///
/// Drag-and-drop (cross-lane reassignment):
///   - Wrapped in [LongPressDraggable<BookingDragData>]
///   - data includes existingBookingId + sourceContractorId for reassignment logic
///   - feedback: Material-elevated card matching booking dimensions
///   - childWhenDragging: 0.3 opacity ghost
///
/// Leaf widget — no dependency on ContractorLane, CalendarDayView, or providers.
class BookingCard extends StatefulWidget {
  const BookingCard({
    required this.booking,
    required this.job,
    required this.durationMinutes,
    required this.pixelsPerMinute,
    required this.laneWidth,
    super.key,
    this.showCompleted = false,
    this.onResized,
  });

  /// The booking entity (provides id, contractorId, times for drag/resize).
  final BookingEntity booking;

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

  /// Called when user finishes a resize drag with the new start/end times.
  ///
  /// The caller (ContractorLane) handles the actual Drift update + undo push.
  final Future<void> Function(DateTime newStart, DateTime newEnd)? onResized;

  @override
  State<BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<BookingCard> {
  /// Whether top or bottom resize is in progress.
  bool _isResizing = false;

  /// Delta minutes accumulated during resize drag.
  double _resizeDeltaMinutes = 0;

  /// Which edge is being resized: 'top' or 'bottom'.
  String? _resizingEdge;

  @override
  Widget build(BuildContext context) {
    final baseDuration = widget.durationMinutes;
    final effectiveDuration =
        _isResizing ? _effectiveResizedDuration(baseDuration) : baseDuration;

    final cardHeight =
        (effectiveDuration * widget.pixelsPerMinute).clamp(36.0, double.infinity);
    final status = widget.job.status;
    final statusColor = statusColorMap[status] ?? Colors.grey;
    final severity =
        OverdueService.computeSeverity(widget.job.scheduledCompletionDate);
    final hasDelayEntry = _hasDelayEntry(widget.job.statusHistory);
    final isTerminalStatus = _isTerminalStatus(status);

    // Dim terminal-status bookings when showCompleted is false.
    final opacity = (!widget.showCompleted && isTerminalStatus) ? 0.4 : 1.0;

    // Overdue border color overrides status border when job is overdue.
    final borderColor = switch (severity) {
      OverdueSeverity.critical => Colors.red,
      OverdueSeverity.warning => Colors.orange,
      OverdueSeverity.none => statusColor,
    };

    final criticalBorderSide = severity == OverdueSeverity.critical
        ? const BorderSide(color: Colors.red)
        : BorderSide.none;

    final cardContent = _BookingCardContent(
      job: widget.job,
      cardHeight: cardHeight,
      statusColor: statusColor,
      borderColor: borderColor,
      criticalBorderSide: criticalBorderSide,
      hasDelayEntry: hasDelayEntry,
      severity: severity,
      opacity: opacity,
      laneWidth: widget.laneWidth,
    );

    // Show resize time overlay during drag
    if (_isResizing) {
      final newStart = _resizingEdge == 'top'
          ? widget.booking.timeRangeStart
              .add(Duration(minutes: _resizeDeltaMinutes.round()))
          : widget.booking.timeRangeStart;
      final newEnd = _resizingEdge == 'bottom'
          ? widget.booking.timeRangeEnd
              .add(Duration(minutes: _resizeDeltaMinutes.round()))
          : widget.booking.timeRangeEnd;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          _buildDraggableCard(cardContent, cardHeight),
          // Resize indicator overlay
          Positioned(
            top: -24,
            left: 0,
            right: 0,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(4),
              color: statusColor.withValues(alpha: 0.9),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  '${_formatTime(newStart)} - ${_formatTime(newEnd)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return _buildDraggableCard(cardContent, cardHeight);
  }

  Widget _buildDraggableCard(Widget cardContent, double cardHeight) {
    // Build BookingDragData for cross-lane reassignment.
    final dragData = BookingDragData(
      jobId: widget.job.id,
      durationMinutes: widget.durationMinutes,
      existingBookingId: widget.booking.id,
      sourceContractorId: widget.booking.contractorId,
    );

    return SizedBox(
      width: widget.laneWidth,
      height: cardHeight,
      child: Stack(
        children: [
          // Main booking card + navigation (middle area)
          LongPressDraggable<BookingDragData>(
            data: dragData,
            feedback: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(4),
              child: Opacity(
                opacity: 0.85,
                child: SizedBox(
                  width: widget.laneWidth,
                  height: cardHeight,
                  child: cardContent,
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.3,
              child: cardContent,
            ),
            child: GestureDetector(
              onTap: () => context.push(RouteNames.jobDetailPath(widget.job.id)),
              child: cardContent,
            ),
          ),

          // TOP resize handle — 8px strip at top edge.
          // Vertical drag gesture is distinct from LongPressDraggable (which
          // requires long press). Flutter gesture arena resolves naturally.
          if (cardHeight >= 32)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _resizeHandleHeight,
              child: GestureDetector(
                onVerticalDragStart: (_) => _startResize('top'),
                onVerticalDragUpdate: (details) =>
                    _updateResize(details.delta.dy),
                onVerticalDragEnd: (_) => _endResize(),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.01),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(0),
                        topRight: Radius.circular(4),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // BOTTOM resize handle — 8px strip at bottom edge.
          if (cardHeight >= 32)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: _resizeHandleHeight,
              child: GestureDetector(
                onVerticalDragStart: (_) => _startResize('bottom'),
                onVerticalDragUpdate: (details) =>
                    _updateResize(details.delta.dy),
                onVerticalDragEnd: (_) => _endResize(),
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.01),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(0),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _startResize(String edge) {
    setState(() {
      _isResizing = true;
      _resizingEdge = edge;
      _resizeDeltaMinutes = 0;
    });
  }

  void _updateResize(double dyPixels) {
    if (!_isResizing) return;
    final deltaMinutes = dyPixels / widget.pixelsPerMinute;
    setState(() {
      _resizeDeltaMinutes += deltaMinutes;
    });
  }

  void _endResize() {
    if (!_isResizing) return;

    // Snap delta to 15-minute increments
    final snappedDelta =
        (_resizeDeltaMinutes / _minBookingMinutes).round() * _minBookingMinutes;

    DateTime newStart = widget.booking.timeRangeStart;
    DateTime newEnd = widget.booking.timeRangeEnd;

    if (_resizingEdge == 'top') {
      newStart = widget.booking.timeRangeStart
          .add(Duration(minutes: snappedDelta));
    } else if (_resizingEdge == 'bottom') {
      newEnd = widget.booking.timeRangeEnd
          .add(Duration(minutes: snappedDelta));
    }

    // Enforce minimum duration
    final newDuration = newEnd.difference(newStart).inMinutes;
    if (newDuration >= _minBookingMinutes) {
      widget.onResized?.call(newStart, newEnd);
    }

    setState(() {
      _isResizing = false;
      _resizingEdge = null;
      _resizeDeltaMinutes = 0;
    });
  }

  int _effectiveResizedDuration(int baseDuration) {
    final snappedDelta =
        (_resizeDeltaMinutes / _minBookingMinutes).round() * _minBookingMinutes;
    if (_resizingEdge == 'top') {
      // Top resize: start moves, duration changes inversely
      return (baseDuration - snappedDelta).clamp(
        _minBookingMinutes,
        baseDuration * 3,
      );
    } else {
      // Bottom resize: end moves, duration changes directly
      return (baseDuration + snappedDelta).clamp(
        _minBookingMinutes,
        baseDuration * 3,
      );
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? 'AM' : 'PM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$h:$minute $period';
  }

  /// Returns true if the job's status history contains a delay entry.
  bool _hasDelayEntry(List<Map<String, dynamic>> statusHistory) {
    return statusHistory.any((entry) => entry['type'] == 'delay');
  }

  /// Returns true for terminal job statuses that should be dimmed.
  bool _isTerminalStatus(String status) {
    const terminalStatuses = {'complete', 'invoiced', 'cancelled'};
    return terminalStatuses.contains(status);
  }
}

// ─── Pure visual widget ───────────────────────────────────────────────────────

/// The visual card content — no state, no gestures.
///
/// Separated so it can be reused as both the main card body and the
/// drag feedback widget without duplication.
class _BookingCardContent extends StatelessWidget {
  const _BookingCardContent({
    required this.job,
    required this.cardHeight,
    required this.statusColor,
    required this.borderColor,
    required this.criticalBorderSide,
    required this.hasDelayEntry,
    required this.severity,
    required this.opacity,
    required this.laneWidth,
  });

  final JobEntity job;
  final double cardHeight;
  final Color statusColor;
  final Color borderColor;
  final BorderSide criticalBorderSide;
  final bool hasDelayEntry;
  final OverdueSeverity severity;
  final double opacity;
  final double laneWidth;

  @override
  Widget build(BuildContext context) {
    return Opacity(
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
  }
}
