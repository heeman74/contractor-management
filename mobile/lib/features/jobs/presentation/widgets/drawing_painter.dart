import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/drawing_models.dart';

/// Paints committed strokes plus the in-progress stroke onto the canvas.
class DrawingPainter extends CustomPainter {
  const DrawingPainter({
    required this.strokes,
    this.currentStroke,
  });

  final List<DrawingStroke> strokes;
  final DrawingStroke? currentStroke;

  static const double _arrowHeadSize = 12.0;
  static const double _arrowHeadAngle = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _paintStroke(canvas, stroke);
    }
    if (currentStroke != null) {
      _paintStroke(canvas, currentStroke!);
    }
  }

  void _paintStroke(Canvas canvas, DrawingStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.tool == DrawingTool.eraser) {
      paint.blendMode = BlendMode.src;
    }

    if (stroke.points.length == 1) {
      canvas.drawCircle(
        stroke.points.first,
        stroke.thickness / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    switch (stroke.tool) {
      case DrawingTool.rectangle:
        canvas.drawRect(_boundsOf(stroke), paint);
      case DrawingTool.circle:
        canvas.drawOval(_boundsOf(stroke), paint);
      case DrawingTool.line:
      case DrawingTool.arrow:
        canvas.drawLine(stroke.points.first, stroke.points.last, paint);
        if (stroke.tool == DrawingTool.arrow) {
          _drawArrowHead(canvas, stroke.points.first, stroke.points.last, paint);
        }
      case DrawingTool.pen:
      case DrawingTool.eraser:
      case DrawingTool.text:
        _drawFreehand(canvas, stroke, paint);
    }
  }

  Rect _boundsOf(DrawingStroke stroke) =>
      Rect.fromPoints(stroke.points.first, stroke.points.last);

  void _drawFreehand(Canvas canvas, DrawingStroke stroke, Paint paint) {
    final path = Path()
      ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (var i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final angle = (to - from).direction;
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - _arrowHeadSize * math.cos(angle - _arrowHeadAngle),
        to.dy - _arrowHeadSize * math.sin(angle - _arrowHeadAngle),
      )
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - _arrowHeadSize * math.cos(angle + _arrowHeadAngle),
        to.dy - _arrowHeadSize * math.sin(angle + _arrowHeadAngle),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}

/// Paints a thin gray grid over the canvas — excluded from PNG export.
class DrawingGridPainter extends CustomPainter {
  const DrawingGridPainter();

  static const double _spacing = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    for (double x = 0; x <= size.width; x += _spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += _spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(DrawingGridPainter oldDelegate) => false;
}
