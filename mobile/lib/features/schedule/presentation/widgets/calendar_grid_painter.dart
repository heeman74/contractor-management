import 'package:flutter/material.dart';

/// A blocked time interval for a contractor's day.
///
/// Used by [CalendarGridPainter] to shade non-working-hour regions and
/// draw travel time gaps between consecutive bookings.
class BlockedInterval {
  const BlockedInterval({
    required this.start,
    required this.end,
    required this.reason,
  });

  /// Start of the blocked interval (UTC).
  final DateTime start;

  /// End of the blocked interval (UTC).
  final DateTime end;

  /// Reason for the block:
  ///   - 'outside_working_hours' — before work start or after work end
  ///   - 'time_off' — contractor unavailability override (holiday/sick)
  ///   - 'travel_buffer' — buffer between consecutive bookings (for TravelTimeBlock)
  final String reason;
}

/// [CustomPainter] that renders the time-axis background grid for a single
/// contractor lane.
///
/// Draws:
///   - Hourly horizontal lines across the full lane width
///   - Non-working-hour shaded regions (grey fill for before/after hours)
///   - "Day off" / "Holiday" text labels centered in 'time_off' blocked regions
///   - Red "now" line at the current time position
///
/// Leaf widget — no dependency on ContractorLane, CalendarDayView, or providers.
///
/// Callers pass:
///   - [dayStart]: midnight of the displayed date (local time)
///   - [pixelsPerMinute]: scale factor (2.0 = 120px/hour)
///   - [blockedIntervals]: non-working blocks to shade grey
///   - [currentTime]: DateTime for the "now" line; null hides the line
///   - [laneWidth]: total width of the lane in logical pixels
class CalendarGridPainter extends CustomPainter {
  const CalendarGridPainter({
    required this.dayStart,
    required this.pixelsPerMinute,
    required this.blockedIntervals,
    required this.laneWidth,
    this.currentTime,
  });

  final DateTime dayStart;
  final double pixelsPerMinute;
  final List<BlockedInterval> blockedIntervals;
  final DateTime? currentTime;
  final double laneWidth;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBlockedRegions(canvas, size);
    _paintHourLines(canvas, size);
    _paintNowLine(canvas, size);
  }

  /// Paints the shaded background for blocked intervals.
  ///
  /// - 'outside_working_hours': light grey fill
  /// - 'time_off': slightly darker grey + centered label text
  void _paintBlockedRegions(Canvas canvas, Size size) {
    final outsideHoursPaint = Paint()
      ..color = const Color(0xFFF0F0F0) // very light grey
      ..style = PaintingStyle.fill;

    final timeOffPaint = Paint()
      ..color = const Color(0xFFE0E0E0) // slightly darker grey
      ..style = PaintingStyle.fill;

    const textStyle = TextStyle(
      color: Color(0xFF9E9E9E),
      fontSize: 11,
      fontWeight: FontWeight.w500,
    );

    for (final interval in blockedIntervals) {
      // Travel buffers are rendered by TravelTimeBlock, not here.
      if (interval.reason == 'travel_buffer') continue;

      final topY = _minutesFromDayStart(interval.start) * pixelsPerMinute;
      final bottomY = _minutesFromDayStart(interval.end) * pixelsPerMinute;

      if (bottomY <= topY) continue; // Skip zero-height or inverted intervals

      final rect = Rect.fromLTWH(0, topY, laneWidth, bottomY - topY);
      final paint = interval.reason == 'time_off' ? timeOffPaint : outsideHoursPaint;
      canvas.drawRect(rect, paint);

      // For time_off blocks, draw a centered "Day off" label.
      if (interval.reason == 'time_off') {
        _paintCenteredText(
          canvas,
          'Day off',
          textStyle,
          rect,
        );
      }
    }
  }

  /// Paints horizontal lines at each whole hour (00:00–23:00).
  void _paintHourLines(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final halfHourPaint = Paint()
      ..color = const Color(0xFFEEEEEE)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (var hour = 0; hour < 24; hour++) {
      final y = hour * 60 * pixelsPerMinute;
      canvas.drawLine(Offset(0, y), Offset(laneWidth, y), linePaint);

      // Half-hour tick
      final halfHourY = y + 30 * pixelsPerMinute;
      canvas.drawLine(
        Offset(0, halfHourY),
        Offset(laneWidth, halfHourY),
        halfHourPaint,
      );
    }
  }

  /// Paints a red horizontal line at the current time position.
  ///
  /// Only rendered if [currentTime] is on the same calendar day as [dayStart].
  void _paintNowLine(Canvas canvas, Size size) {
    final now = currentTime;
    if (now == null) return;

    // Only show "now" line if today matches the rendered day.
    final today = DateTime.now();
    final isToday = today.year == dayStart.year &&
        today.month == dayStart.month &&
        today.day == dayStart.day;
    if (!isToday) return;

    final nowY = _minutesFromDayStart(now) * pixelsPerMinute;

    final linePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw the line
    canvas.drawLine(Offset(0, nowY), Offset(laneWidth, nowY), linePaint);

    // Draw a small circle at the left edge
    final circlePaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(0, nowY), 4, circlePaint);
  }

  /// Returns the number of minutes elapsed since [dayStart] for a given [time].
  double _minutesFromDayStart(DateTime time) {
    return time.difference(dayStart).inMinutes.toDouble();
  }

  /// Draws centered text inside a [rect] using the given [style].
  void _paintCenteredText(
    Canvas canvas,
    String text,
    TextStyle style,
    Rect rect,
  ) {
    // Only render if the block is tall enough to show text.
    if (rect.height < 20) return;

    final span = TextSpan(text: text, style: style);
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )
      ..layout(maxWidth: rect.width);
    final offset = Offset(
      rect.left + (rect.width - painter.width) / 2,
      rect.top + (rect.height - painter.height) / 2,
    );
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(CalendarGridPainter oldDelegate) {
    if (oldDelegate.laneWidth != laneWidth) return true;
    if (oldDelegate.pixelsPerMinute != pixelsPerMinute) return true;
    if (oldDelegate.dayStart != dayStart) return true;

    // Repaint if "now" line minute changes.
    final oldMinute = oldDelegate.currentTime?.minute;
    final newMinute = currentTime?.minute;
    if (oldMinute != newMinute) return true;

    // Repaint if blocked intervals list length or content changes.
    if (oldDelegate.blockedIntervals.length != blockedIntervals.length) {
      return true;
    }
    for (var i = 0; i < blockedIntervals.length; i++) {
      final o = oldDelegate.blockedIntervals[i];
      final n = blockedIntervals[i];
      if (o.start != n.start || o.end != n.end || o.reason != n.reason) {
        return true;
      }
    }
    return false;
  }
}
