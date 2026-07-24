import 'package:flutter/painting.dart';

/// Drawing tools available in the drawing pad.
enum DrawingTool { pen, eraser, text, line, rectangle, circle, arrow }

/// A single drawn stroke: an ordered list of points with a tool + style.
///
/// Freehand tools (pen/eraser) use all points; shape tools (line, rectangle,
/// circle, arrow) use only the first and last point as bounds.
class DrawingStroke {
  const DrawingStroke({
    required this.tool,
    required this.color,
    required this.thickness,
    required this.points,
  });

  final DrawingTool tool;
  final Color color;
  final double thickness;
  final List<Offset> points;

  /// Returns a copy with [point] appended — used while a drag is in progress.
  DrawingStroke addPoint(Offset point) => DrawingStroke(
        tool: tool,
        color: color,
        thickness: thickness,
        points: [...points, point],
      );
}
