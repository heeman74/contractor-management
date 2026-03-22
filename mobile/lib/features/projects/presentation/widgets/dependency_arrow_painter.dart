import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart' show TaskDependency;

/// CustomPainter overlay that draws bezier dependency arrows between task bars.
///
/// Renders on top of the [GanttPainter] layer. Each dependency is drawn as a
/// cubic bezier curve from the right edge of the predecessor bar to the left
/// edge of the successor bar. Arrows involved in cycles are drawn in red.
///
/// Ghost arrow: during a drag-to-connect gesture, a dashed line is drawn
/// from [dragStart] to [dragEnd].
class DependencyArrowPainter extends CustomPainter {
  final List<TaskDependency> dependencies;

  /// Task bar rects built by [GanttPainter] — used to position arrow endpoints.
  final Map<String, Rect> taskBarRects;

  /// Task IDs that form a cycle. Arrows involving these IDs are drawn red.
  final Set<String> cycleInvolvedIds;

  /// Start point for drag-to-connect ghost arrow (null = not dragging).
  final Offset? dragStart;

  /// Current drag end position for ghost arrow (null = not dragging).
  final Offset? dragEnd;

  const DependencyArrowPainter({
    required this.dependencies,
    required this.taskBarRects,
    this.cycleInvolvedIds = const {},
    this.dragStart,
    this.dragEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final dep in dependencies) {
      final from = taskBarRects[dep.predecessorTaskId];
      final to = taskBarRects[dep.successorTaskId];
      if (from == null || to == null) continue;

      final isCycle = cycleInvolvedIds.contains(dep.predecessorTaskId) ||
          cycleInvolvedIds.contains(dep.successorTaskId);

      final paint = Paint()
        ..color = isCycle
            ? const Color(0xFFEF4444) // red-500 for cycle
            : const Color(0xFF374151) // gray-700 normal
        ..strokeWidth = isCycle ? 2.0 : 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Bezier from right-center of predecessor to left-center of successor
      final startPoint = Offset(from.right, from.center.dy);
      final endPoint = Offset(to.left, to.center.dy);

      // Control points for smooth horizontal curve
      final dx = (endPoint.dx - startPoint.dx).abs().clamp(20.0, 60.0);
      final ctrl1 = Offset(startPoint.dx + dx, startPoint.dy);
      final ctrl2 = Offset(endPoint.dx - dx, endPoint.dy);

      final path = Path()
        ..moveTo(startPoint.dx, startPoint.dy)
        ..cubicTo(
          ctrl1.dx,
          ctrl1.dy,
          ctrl2.dx,
          ctrl2.dy,
          endPoint.dx,
          endPoint.dy,
        );
      canvas.drawPath(path, paint);

      // Draw arrowhead at endPoint pointing left-to-right
      _drawArrowhead(canvas, ctrl2, endPoint, paint);

      // Draw dependency type label chip for non-FS types
      if (dep.dependencyType != 'FS') {
        _drawTypeLabel(canvas, startPoint, endPoint, dep.dependencyType);
      }

      // Draw lag/lead label if non-zero
      if (dep.lagDays != 0) {
        _drawLagLabel(canvas, startPoint, endPoint, dep.lagDays);
      }
    }

    // Draw ghost arrow during drag-to-connect
    if (dragStart != null && dragEnd != null) {
      _drawGhostArrow(canvas, dragStart!, dragEnd!);
    }
  }

  void _drawArrowhead(
      Canvas canvas, Offset direction, Offset tip, Paint paint) {
    const arrowSize = 8.0;
    const arrowAngle = 0.4; // radians, ~23 degrees

    // Compute angle of the arrow direction
    final angle = math.atan2(
      tip.dy - direction.dy,
      tip.dx - direction.dx,
    );

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - arrowSize * math.cos(angle - arrowAngle),
        tip.dy - arrowSize * math.sin(angle - arrowAngle),
      )
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - arrowSize * math.cos(angle + arrowAngle),
        tip.dy - arrowSize * math.sin(angle + arrowAngle),
      );

    canvas.drawPath(path, paint);
  }

  void _drawTypeLabel(
    Canvas canvas,
    Offset start,
    Offset end,
    String type,
  ) {
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2 - 12);

    // Background pill
    final bgPaint = Paint()..color = const Color(0xFFF3F4F6); // gray-100
    final bgRect = Rect.fromCenter(center: mid, width: 24, height: 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      bgPaint,
    );

    // Type text (FS/SS/FF/SE)
    final textPainter = TextPainter(
      text: TextSpan(
        text: type,
        style: const TextStyle(
          fontSize: 9,
          color: Color(0xFF6B7280), // gray-500
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      mid - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawLagLabel(
    Canvas canvas,
    Offset start,
    Offset end,
    int lagDays,
  ) {
    final mid = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2 + 12,
    );

    final label = lagDays > 0 ? '+${lagDays}d' : '${lagDays}d';
    final color = lagDays > 0
        ? const Color(0xFFEF4444) // red for lag (delay)
        : const Color(0xFF10B981); // green for lead (acceleration)

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      mid - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawGhostArrow(Canvas canvas, Offset start, Offset end) {
    final ghostPaint = Paint()
      ..color = const Color(0xFF9CA3AF) // gray-400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Simple dashed line effect by drawing multiple short segments
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length =
        math.sqrt(dx * dx + dy * dy);
    if (length == 0) return;

    const dashLen = 6.0;
    const gapLen = 4.0;
    final totalPattern = dashLen + gapLen;
    final segments = (length / totalPattern).floor();

    final nx = dx / length;
    final ny = dy / length;

    for (int i = 0; i < segments; i++) {
      final startOffset = i * totalPattern;
      final endOffset = startOffset + dashLen;
      canvas.drawLine(
        Offset(start.dx + nx * startOffset, start.dy + ny * startOffset),
        Offset(start.dx + nx * endOffset, start.dy + ny * endOffset),
        ghostPaint,
      );
    }

    // Draw arrowhead at end
    _drawArrowhead(canvas, start, end, ghostPaint);
  }

  @override
  bool shouldRepaint(DependencyArrowPainter oldDelegate) {
    return oldDelegate.dependencies != dependencies ||
        oldDelegate.taskBarRects != taskBarRects ||
        oldDelegate.cycleInvolvedIds != cycleInvolvedIds ||
        oldDelegate.dragStart != dragStart ||
        oldDelegate.dragEnd != dragEnd;
  }
}
