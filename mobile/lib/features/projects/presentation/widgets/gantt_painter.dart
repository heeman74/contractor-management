import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart' show TradeScope, ProjectTask;

/// Converts a hex color string (e.g. '#3949AB' or '3949AB') to a [Color].
Color hexToColorGantt(String hex) {
  final sanitized = hex.replaceAll('#', '').padLeft(8, 'FF');
  return Color(int.parse(sanitized, radix: 16));
}

/// CustomPainter that renders the Gantt chart background, swim lanes,
/// trade lane headers, task bars with progress fills, and the today line.
///
/// Coordinate system:
/// - Y axis: one horizontal band per trade scope (height = [laneHeight])
/// - X axis: time axis with [dayWidth] pixels per day, origin = [startDate]
/// - Left side: [headerWidth] px column reserved for trade name labels
class GanttPainter extends CustomPainter {
  final List<TradeScope> scopes;
  final Map<String, List<ProjectTask>> tasksByScope;
  final DateTime startDate; // leftmost date on the time axis
  final double dayWidth; // pixels per day (varies with zoom)
  final double laneHeight; // 48px per lane (2xl spacing token)
  final Set<String> conflictTaskIds; // task IDs that have zone conflicts
  final Map<String, Rect> taskBarRectsOut; // output: filled during paint

  static const double headerWidth = 120.0;
  static const double timeAxisHeight = 40.0;

  GanttPainter({
    required this.scopes,
    required this.tasksByScope,
    required this.startDate,
    required this.dayWidth,
    this.laneHeight = 48.0,
    this.conflictTaskIds = const {},
    required this.taskBarRectsOut,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawTimeAxis(canvas, size);
    _drawSwimLanes(canvas, size);
    _drawTodayLine(canvas, size);
    _drawTaskBars(canvas, size);
  }

  void _drawTimeAxis(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF3F4F6); // gray-100
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, timeAxisHeight),
      bgPaint,
    );

    final textStyle = ui.TextStyle(
      color: const Color(0xFF6B7280), // gray-500
      fontSize: 11,
    );

    // Draw day labels starting from startDate
    final now = DateTime.now();
    final visibleDays = ((size.width - headerWidth) / dayWidth).ceil() + 1;

    DateTime current = startDate;
    for (int i = 0; i < visibleDays; i++) {
      final x = headerWidth + i * dayWidth;
      if (x > size.width) break;

      // Draw a subtle vertical grid line
      final gridPaint = Paint()
        ..color = const Color(0xFFE5E7EB) // gray-200
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(x, timeAxisHeight),
        Offset(x, size.height),
        gridPaint,
      );

      // Show day number label
      final isToday = current.year == now.year &&
          current.month == now.month &&
          current.day == now.day;

      final label = '${current.month}/${current.day}';
      final paraBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: 10,
        ),
      )
        ..pushStyle(
          isToday
              ? ui.TextStyle(
                  color: const Color(0xFF3B82F6), // blue-500 for today
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                )
              : textStyle,
        )
        ..addText(label);

      final para = paraBuilder.build();
      para.layout(ui.ParagraphConstraints(width: dayWidth));
      canvas.drawParagraph(para, Offset(x, (timeAxisHeight - 16) / 2));

      current = current.add(const Duration(days: 1));
    }

    // Separator line below time axis
    final separatorPaint = Paint()
      ..color = const Color(0xFFD1D5DB) // gray-300
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, timeAxisHeight),
      Offset(size.width, timeAxisHeight),
      separatorPaint,
    );

    // Header column separator
    canvas.drawLine(
      Offset(headerWidth, 0),
      Offset(headerWidth, size.height),
      separatorPaint,
    );
  }

  void _drawSwimLanes(Canvas canvas, Size size) {
    for (int i = 0; i < scopes.length; i++) {
      final scope = scopes[i];
      final y = timeAxisHeight + i * laneHeight;

      // Alternating row background
      final rowPaint = Paint()
        ..color = i.isEven
            ? Colors.white
            : const Color(0xFFF9FAFB); // gray-50
      canvas.drawRect(
        Rect.fromLTWH(headerWidth, y, size.width - headerWidth, laneHeight),
        rowPaint,
      );

      // Trade color header strip (left column)
      final tradeColor = _parseTradeColor(scope.tradeColor);
      final headerPaint = Paint()..color = tradeColor.withValues(alpha: 0.85);
      canvas.drawRect(
        Rect.fromLTWH(0, y, headerWidth, laneHeight),
        headerPaint,
      );

      // Trade name text in header
      _drawText(
        canvas,
        text: scope.tradeName,
        x: 8,
        y: y + (laneHeight - 16) / 2,
        width: headerWidth - 16,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _contrastColor(tradeColor),
      );

      // Bottom lane separator
      final linePaint = Paint()
        ..color = const Color(0xFFE5E7EB)
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(0, y + laneHeight),
        Offset(size.width, y + laneHeight),
        linePaint,
      );
    }
  }

  void _drawTodayLine(Canvas canvas, Size size) {
    final now = DateTime.now();
    final daysFromStart = now.difference(startDate).inDays.toDouble();
    final x = headerWidth + daysFromStart * dayWidth;

    if (x < headerWidth || x > size.width) return;

    final paint = Paint()
      ..color = const Color(0xFF6B7280) // gray-500
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(x, timeAxisHeight),
      Offset(x, size.height),
      paint,
    );

    // Today dot at top
    final dotPaint = Paint()
      ..color = const Color(0xFF3B82F6) // blue-500
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, timeAxisHeight + 4), 4, dotPaint);
  }

  void _drawTaskBars(Canvas canvas, Size size) {
    const double barPadding = 6.0;
    const double barRadius = 4.0;
    const double minBarWidth = 8.0;

    for (int i = 0; i < scopes.length; i++) {
      final scope = scopes[i];
      final tasks = tasksByScope[scope.id] ?? [];
      final laneY = timeAxisHeight + i * laneHeight;

      for (final task in tasks) {
        // Compute bar X position
        DateTime effectiveStart = task.startDate ?? task.dueDate ?? startDate;
        if (task.startDate == null && task.dueDate != null) {
          // Estimate start from estimated hours
          final hours = task.estimatedHours ?? 8;
          final days = (hours / 8).ceil();
          effectiveStart = task.dueDate!.subtract(Duration(days: days));
        }

        final barStartDays =
            effectiveStart.difference(startDate).inDays.toDouble();
        final barX = headerWidth + barStartDays * dayWidth;

        // Compute bar width
        double barWidthDays = 1.0;
        if (task.dueDate != null) {
          barWidthDays =
              task.dueDate!.difference(effectiveStart).inDays.toDouble();
          if (barWidthDays < 1) barWidthDays = 1;
        } else {
          final hours = task.estimatedHours ?? 8;
          barWidthDays = (hours / 8).toDouble();
          if (barWidthDays < 1) barWidthDays = 1;
        }

        final rawWidth = barWidthDays * dayWidth;
        final barWidth = rawWidth < minBarWidth ? minBarWidth : rawWidth;

        // Skip bars completely off-screen
        if (barX + barWidth < headerWidth || barX > size.width) continue;

        final barY = laneY + barPadding;
        final barH = laneHeight - barPadding * 2;
        final barRect =
            Rect.fromLTWH(barX, barY, barWidth, barH);

        // Record rect for hit testing and arrow rendering
        taskBarRectsOut[task.id] = barRect;

        final isConflict = conflictTaskIds.contains(task.id);
        final status = task.status;

        // Draw bar background
        if (status == 'blocked') {
          _drawBlockedBar(canvas, barRect, barRadius);
        } else {
          final (bgColor, fillColor, progress) =
              _barColors(status, task.estimatedHours);
          _drawProgressBar(canvas, barRect, barRadius, bgColor, fillColor,
              progress, isConflict);
        }

        // Draw task title
        canvas.save();
        canvas.clipRect(barRect);
        _drawText(
          canvas,
          text: task.title,
          x: barRect.left + 4,
          y: barRect.top + (barH - 12) / 2,
          width: barRect.width - 8,
          fontSize: 10,
          color: _labelColor(status),
        );
        canvas.restore();
      }
    }
  }

  void _drawBlockedBar(Canvas canvas, Rect rect, double radius) {
    // Red-200 background
    final bgPaint = Paint()..color = const Color(0xFFFECACA); // red-200
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      bgPaint,
    );

    // Dashed red border
    final borderPaint = Paint()
      ..color = const Color(0xFFF87171) // red-400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final dashPath = _dashedRectPath(rect, radius);
    canvas.drawPath(dashPath, borderPaint);

    // Lock icon indicator (small rectangle at left edge)
    final lockPaint = Paint()..color = const Color(0xFFEF4444); // red-500
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 2, rect.top + rect.height / 2 - 4, 3, 8),
      lockPaint,
    );
  }

  void _drawProgressBar(
    Canvas canvas,
    Rect rect,
    double radius,
    Color bgColor,
    Color fillColor,
    double progress,
    bool isConflict,
  ) {
    // Background
    final bgPaint = Paint()..color = bgColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      bgPaint,
    );

    // Progress fill (clipped to bar rect)
    if (progress > 0) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      final fillRect = Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width * progress.clamp(0.0, 1.0),
        rect.height,
      );
      final fillPaint = Paint()..color = fillColor;
      canvas.drawRect(fillRect, fillPaint);
      canvas.restore();
    }

    // Conflict orange border
    if (isConflict) {
      final conflictPaint = Paint()
        ..color = const Color(0xFFF97316) // orange-500
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        conflictPaint,
      );
    }
  }

  // Returns (backgroundColor, fillColor, progress fraction)
  (Color, Color, double) _barColors(String status, double? estimatedHours) {
    return switch (status) {
      'in_progress' => (
          const Color(0xFFFDE68A), // amber-200
          const Color(0xFFF59E0B), // amber-500
          0.5,
        ),
      'complete' => (
          const Color(0xFFBBF7D0), // green-200
          const Color(0xFF16A34A), // green-600
          1.0,
        ),
      _ => (
          const Color(0xFFE5E7EB), // gray-200 (not_started)
          const Color(0xFF9CA3AF), // gray-400
          0.0,
        ),
    };
  }

  Color _labelColor(String status) {
    return switch (status) {
      'blocked' => const Color(0xFF991B1B), // red-800
      'complete' => const Color(0xFF14532D), // green-900
      'in_progress' => const Color(0xFF78350F), // amber-900
      _ => const Color(0xFF374151), // gray-700
    };
  }

  Color _parseTradeColor(String hex) {
    try {
      return hexToColorGantt(hex);
    } catch (_) {
      return const Color(0xFF6366F1); // indigo-500 fallback
    }
  }

  /// Returns black or white depending on which contrasts better with [bg].
  Color _contrastColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? Colors.black : Colors.white;
  }

  void _drawText(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required double width,
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.normal,
    required Color color,
  }) {
    final paraBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        ellipsis: '…',
        maxLines: 1,
      ),
    )
      ..pushStyle(
        ui.TextStyle(color: color, fontSize: fontSize, fontWeight: fontWeight),
      )
      ..addText(text);

    final para = paraBuilder.build();
    para.layout(ui.ParagraphConstraints(width: width));
    canvas.drawParagraph(para, Offset(x, y));
  }

  /// Builds a rounded rectangle border path (used for blocked task borders).
  Path _dashedRectPath(Rect rect, double radius) {
    final path = Path();
    path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    return path;
  }

  @override
  bool shouldRepaint(GanttPainter oldDelegate) {
    return oldDelegate.scopes != scopes ||
        oldDelegate.tasksByScope != tasksByScope ||
        oldDelegate.startDate != startDate ||
        oldDelegate.dayWidth != dayWidth ||
        oldDelegate.conflictTaskIds != conflictTaskIds;
  }
}
