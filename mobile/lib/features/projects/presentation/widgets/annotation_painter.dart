import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/annotation_color.dart';
import '../../domain/annotation_schema.dart';

/// Renders all committed annotations plus the in-progress annotation preview
/// on top of a photo. Coordinates on [Annotation] are normalized 0–1 and are
/// denormalized against the painter [Size].
class AnnotationPainter extends CustomPainter {
  const AnnotationPainter({
    required this.annotations,
    this.inProgressTool,
    this.panStart,
    this.panCurrent,
    this.inProgressColor = '#D32F2F',
  });

  final List<Annotation> annotations;
  final AnnotationTool? inProgressTool;
  final Offset? panStart;
  final Offset? panCurrent;
  final String inProgressColor;

  static const double _arrowHeadSize = 14.0;
  static const double _arrowMinDistance = 8.0;
  static const double _arrowHeadAngle = 0.5;
  static const double _tickLength = 8.0;
  static const double _defaultFontSize = 16.0;
  static const double _measurementFontSize = 13.0;
  static const double _previewThickness = 2.0;
  static const double _previewAlpha = 0.7;

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in annotations) {
      _drawAnnotation(canvas, size, annotation);
    }
    if (_hasActivePreview(size)) {
      _drawPreview(canvas, size);
    }
  }

  bool _hasActivePreview(Size size) =>
      inProgressTool != null &&
      panStart != null &&
      panCurrent != null &&
      size.width > 0 &&
      size.height > 0;

  void _drawAnnotation(Canvas canvas, Size size, Annotation annotation) {
    final color = AnnotationColor.fromHex(annotation.color);
    final paint = _strokePaint(color, annotation.thickness);

    switch (annotation.tool) {
      case AnnotationTool.arrow:
        final line = _lineFor(annotation, size);
        if (line == null) return;
        canvas.drawLine(line.$1, line.$2, paint);
        _drawArrowHead(canvas, line.$1, line.$2, paint);
      case AnnotationTool.circle:
        final rect = _rectFor(annotation, size);
        if (rect != null) canvas.drawOval(rect, paint);
      case AnnotationTool.text:
        if (annotation.x != null &&
            annotation.y != null &&
            annotation.label != null) {
          _drawText(canvas, size, annotation, color);
        }
      case AnnotationTool.measurement:
        final line = _lineFor(annotation, size);
        if (line == null) return;
        _drawMeasurement(canvas, line.$1, line.$2, annotation.label ?? '',
            color, annotation.thickness);
    }
  }

  void _drawPreview(Canvas canvas, Size size) {
    final color = AnnotationColor.fromHex(inProgressColor)
        .withValues(alpha: _previewAlpha);
    final paint = _strokePaint(color, _previewThickness);
    final start = panStart!;
    final end = panCurrent!;

    switch (inProgressTool!) {
      case AnnotationTool.arrow:
        canvas.drawLine(start, end, paint);
        _drawArrowHead(canvas, start, end, paint);
      case AnnotationTool.circle:
        canvas.drawOval(Rect.fromPoints(start, end), paint);
      case AnnotationTool.measurement:
        _drawMeasurement(canvas, start, end, '...', color, _previewThickness);
      case AnnotationTool.text:
        break;
    }
  }

  Paint _strokePaint(Color color, double thickness) => Paint()
    ..color = color
    ..strokeWidth = thickness
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  (Offset, Offset)? _lineFor(Annotation annotation, Size size) {
    if (annotation.startX == null ||
        annotation.startY == null ||
        annotation.endX == null ||
        annotation.endY == null) {
      return null;
    }
    return (
      Offset(annotation.startX! * size.width, annotation.startY! * size.height),
      Offset(annotation.endX! * size.width, annotation.endY! * size.height),
    );
  }

  Rect? _rectFor(Annotation annotation, Size size) {
    if (annotation.x == null ||
        annotation.y == null ||
        annotation.width == null ||
        annotation.height == null) {
      return null;
    }
    return Rect.fromLTWH(
      annotation.x! * size.width,
      annotation.y! * size.height,
      annotation.width! * size.width,
      annotation.height! * size.height,
    );
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    if ((to - from).distance < _arrowMinDistance) return;
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

  void _drawText(Canvas canvas, Size size, Annotation annotation, Color color) {
    final painter = _labelPainter(
      annotation.label!,
      color,
      annotation.fontSize ?? _defaultFontSize,
    );
    painter.paint(
      canvas,
      Offset(annotation.x! * size.width, annotation.y! * size.height),
    );
  }

  void _drawMeasurement(
    Canvas canvas,
    Offset from,
    Offset to,
    String label,
    Color color,
    double thickness,
  ) {
    final paint = _strokePaint(color, thickness);
    canvas.drawLine(from, to, paint);
    _drawTickMark(canvas, from, to, paint);
    _drawTickMark(canvas, to, from, paint);
    if (label.isEmpty) return;

    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final painter = _labelPainter(label, color, _measurementFontSize);
    painter.paint(
      canvas,
      Offset(mid.dx - painter.width / 2, mid.dy - painter.height - 4),
    );
  }

  TextPainter _labelPainter(String text, Color color, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 2, offset: Offset(1, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    return painter;
  }

  void _drawTickMark(Canvas canvas, Offset point, Offset other, Paint paint) {
    final perpendicular = (other - point).direction + math.pi / 2;
    canvas.drawLine(
      Offset(
        point.dx + _tickLength * math.cos(perpendicular),
        point.dy + _tickLength * math.sin(perpendicular),
      ),
      Offset(
        point.dx - _tickLength * math.cos(perpendicular),
        point.dy - _tickLength * math.sin(perpendicular),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(AnnotationPainter old) {
    return old.annotations != annotations ||
        old.panStart != panStart ||
        old.panCurrent != panCurrent ||
        old.inProgressTool != inProgressTool;
  }
}
