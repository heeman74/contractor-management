import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/annotation_schema.dart';

/// Full-screen photo annotation screen.
///
/// Displays a photo as the base layer (immutable). Annotations are drawn on
/// top as a separate [CustomPainter] layer — the original photo is never
/// modified ([annotationData] stored in TaskAttachment, not embedded in image).
///
/// **Modes:**
/// - View mode (default): [InteractiveViewer] allows pinch-to-zoom and pan.
/// - Draw mode: [GestureDetector] captures pan/tap gestures for the active tool.
///   InteractiveViewer is disabled in draw mode to prevent gesture conflicts.
///
/// **Tools (4):**
/// - Arrow: pan start → pan end creates a directional arrow annotation.
/// - Circle: pan start → pan end defines the bounding rect for an ellipse.
/// - Text: tap → AlertDialog with TextField → text label annotation.
/// - Measurement: pan start → pan end → showDialog for measurement input.
///
/// **Returns:** `Navigator.pop(context, String?)` — JSON string on save, null on discard.
///
/// Navigation:
///   Push via: `context.push(RouteNames.photoAnnotation, extra: {'localPath': ..., 'annotationData': ...})`
///   Result: `String?` — annotation JSON or null if discarded.
class PhotoAnnotationScreen extends ConsumerStatefulWidget {
  /// Absolute file path to the local photo image.
  final String localPath;

  /// Optional existing annotation JSON to pre-load (round-trip editing).
  final String? annotationData;

  const PhotoAnnotationScreen({
    required this.localPath, super.key,
    this.annotationData,
  });

  @override
  ConsumerState<PhotoAnnotationScreen> createState() =>
      _PhotoAnnotationScreenState();
}

class _PhotoAnnotationScreenState
    extends ConsumerState<PhotoAnnotationScreen> {
  // ── Annotation state ──────────────────────────────────────────────────────

  final List<Annotation> _annotations = [];
  final List<Annotation> _undoStack = [];

  // ── Tool state ────────────────────────────────────────────────────────────

  AnnotationTool _activeTool = AnnotationTool.arrow;
  Color _activeColor = const Color(0xFFD32F2F); // Red
  bool _isDrawMode = false;

  // ── Gesture tracking for in-progress annotation ───────────────────────────

  Offset? _panStart;
  Offset? _panCurrent;

  // ── Canvas size (set from LayoutBuilder) ─────────────────────────────────

  Size _canvasSize = Size.zero;

  // ── Color presets ─────────────────────────────────────────────────────────

  static const _colorPresets = [
    (Color(0xFFD32F2F), '#D32F2F'), // Red
    (Color(0xFFF57C00), '#F57C00'), // Orange
    (Color(0xFFFFC107), '#FFC107'), // Yellow
    (Color(0xFF1565C0), '#1565C0'), // Blue
    (Color(0xFF000000), '#000000'), // Black
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.annotationData != null) {
      try {
        final layer =
            AnnotationLayer.fromJsonString(widget.annotationData!);
        _annotations.addAll(layer.annotations);
      } catch (e, st) {
        debugPrint('[PhotoAnnotationScreen] Failed to parse annotationData: $e\n$st');
      }
    }
  }

  // ── Normalize / denormalize helpers ───────────────────────────────────────

  double _nx(double x) => _canvasSize.width > 0 ? x / _canvasSize.width : 0;
  double _ny(double y) => _canvasSize.height > 0 ? y / _canvasSize.height : 0;

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _panStart = details.localPosition;
      _panCurrent = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _panCurrent = details.localPosition;
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    final start = _panStart;
    final end = _panCurrent;
    if (start == null || end == null) return;

    setState(() {
      _panStart = null;
      _panCurrent = null;
    });

    switch (_activeTool) {
      case AnnotationTool.arrow:
        _commitArrow(start, end);
      case AnnotationTool.circle:
        _commitCircle(start, end);
      case AnnotationTool.measurement:
        await _commitMeasurement(start, end);
      case AnnotationTool.text:
        // Text uses tap, not pan.
        break;
    }
  }

  Future<void> _onTapDown(TapDownDetails details) async {
    if (_activeTool == AnnotationTool.text) {
      await _showTextDialog(details.localPosition);
    }
  }

  // ── Annotation creation ───────────────────────────────────────────────────

  void _commitArrow(Offset start, Offset end) {
    final ann = Annotation(
      tool: AnnotationTool.arrow,
      color: _colorHex(_activeColor),
      thickness: 3.0,
      startX: _nx(start.dx),
      startY: _ny(start.dy),
      endX: _nx(end.dx),
      endY: _ny(end.dy),
    );
    setState(() {
      _annotations.add(ann);
      _undoStack.clear();
    });
  }

  void _commitCircle(Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    final ann = Annotation(
      tool: AnnotationTool.circle,
      color: _colorHex(_activeColor),
      thickness: 3.0,
      x: _nx(rect.left),
      y: _ny(rect.top),
      width: _nx(rect.width),
      height: _ny(rect.height),
    );
    setState(() {
      _annotations.add(ann);
      _undoStack.clear();
    });
  }

  Future<void> _showTextDialog(Offset position) async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Text Label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter label text…',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (label == null || label.isEmpty) return;

    final ann = Annotation(
      tool: AnnotationTool.text,
      color: _colorHex(_activeColor),
      thickness: 1.0,
      x: _nx(position.dx),
      y: _ny(position.dy),
      label: label,
      fontSize: 16.0,
    );
    setState(() {
      _annotations.add(ann);
      _undoStack.clear();
    });
  }

  Future<void> _commitMeasurement(Offset start, Offset end) async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Measurement'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. 24 inches',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add Measurement'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (label == null || label.isEmpty) return;

    final ann = Annotation(
      tool: AnnotationTool.measurement,
      color: _colorHex(_activeColor),
      thickness: 2.0,
      startX: _nx(start.dx),
      startY: _ny(start.dy),
      endX: _nx(end.dx),
      endY: _ny(end.dy),
      label: label,
    );
    setState(() {
      _annotations.add(ann);
      _undoStack.clear();
    });
  }

  // ── Undo / clear ──────────────────────────────────────────────────────────

  void _undo() {
    if (_annotations.isEmpty) return;
    setState(() {
      _undoStack.add(_annotations.removeLast());
    });
  }

  Future<void> _clearAll() async {
    if (_annotations.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all annotations?'),
        content: const Text('All annotations will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _undoStack.addAll(_annotations.reversed);
        _annotations.clear();
      });
    }
  }

  // ── Save / discard ────────────────────────────────────────────────────────

  bool get _hasChanges {
    // Enable save if there are annotations or if original data was loaded.
    return _annotations.isNotEmpty || widget.annotationData != null;
  }

  void _saveAnnotation() {
    final layer = AnnotationLayer(
      canvasWidth: _canvasSize.width,
      canvasHeight: _canvasSize.height,
      annotations: _annotations,
    );
    Navigator.of(context).pop(layer.toJsonString());
  }

  // ── Color helper ──────────────────────────────────────────────────────────

  String _colorHex(Color color) {
    final argb = color.toARGB32();
    return '#${argb.toRadixString(16).substring(2).toUpperCase()}';
  }

  // ── Tool activation ───────────────────────────────────────────────────────

  void _selectTool(AnnotationTool tool) {
    setState(() {
      _activeTool = tool;
      _isDrawMode = true;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Image + annotation canvas ────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                // Record available canvas size for coordinate normalization.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_canvasSize != constraints.biggest) {
                    setState(() {
                      _canvasSize = constraints.biggest;
                    });
                  }
                });

                final photoAndPainter = Stack(
                  fit: StackFit.expand,
                  children: [
                    // Layer 0: Photo
                    Image.file(
                      File(widget.localPath),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white54, size: 64),
                      ),
                    ),
                    // Layer 1: Annotation overlay
                    CustomPaint(
                      painter: _AnnotationPainter(
                        annotations: _annotations,
                        inProgressTool: _isDrawMode ? _activeTool : null,
                        panStart: _panStart,
                        panCurrent: _panCurrent,
                        inProgressColor: _colorHex(_activeColor),
                      ),
                    ),
                  ],
                );

                if (_isDrawMode) {
                  return GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    onTapDown: _onTapDown,
                    child: photoAndPainter,
                  );
                }

                // View mode: pinch-to-zoom + pan.
                return InteractiveViewer(
                  child: photoAndPainter,
                );
              },
            ),

            // ── Top bar ──────────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Discard Changes',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    if (_isDrawMode)
                      ActionChip(
                        label: const Text('Done Drawing'),
                        onPressed: () => setState(() => _isDrawMode = false),
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                    TextButton(
                      onPressed: _hasChanges ? _saveAnnotation : null,
                      child: Text(
                        'Save Annotation',
                        style: TextStyle(
                          color: _hasChanges ? Colors.white : Colors.white30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom toolbar ────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _AnnotationToolbar(
                activeTool: _activeTool,
                activeColor: _activeColor,
                colorPresets: _colorPresets,
                isDrawMode: _isDrawMode,
                onToolSelected: _selectTool,
                onColorSelected: (color) =>
                    setState(() => _activeColor = color),
                onUndo: _undo,
                onClearAll: _clearAll,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Annotation painter ─────────────────────────────────────────────────────

/// Renders all committed annotations + the in-progress annotation preview.
class _AnnotationPainter extends CustomPainter {
  final List<Annotation> annotations;
  final AnnotationTool? inProgressTool;
  final Offset? panStart;
  final Offset? panCurrent;
  final String inProgressColor;

  const _AnnotationPainter({
    required this.annotations,
    this.inProgressTool,
    this.panStart,
    this.panCurrent,
    this.inProgressColor = '#D32F2F',
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw committed annotations.
    for (final ann in annotations) {
      _drawAnnotation(canvas, size, ann);
    }

    // Draw in-progress preview if dragging.
    if (inProgressTool != null &&
        panStart != null &&
        panCurrent != null &&
        size.width > 0 &&
        size.height > 0) {
      _drawPreview(canvas, size);
    }
  }

  void _drawAnnotation(Canvas canvas, Size size, Annotation ann) {
    final color = _parseColor(ann.color);
    final paint = Paint()
      ..color = color
      ..strokeWidth = ann.thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    switch (ann.tool) {
      case AnnotationTool.arrow:
        if (ann.startX != null &&
            ann.startY != null &&
            ann.endX != null &&
            ann.endY != null) {
          final from = Offset(ann.startX! * w, ann.startY! * h);
          final to = Offset(ann.endX! * w, ann.endY! * h);
          canvas.drawLine(from, to, paint);
          _drawArrowHead(canvas, from, to, paint);
        }

      case AnnotationTool.circle:
        if (ann.x != null &&
            ann.y != null &&
            ann.width != null &&
            ann.height != null) {
          final rect = Rect.fromLTWH(
            ann.x! * w,
            ann.y! * h,
            ann.width! * w,
            ann.height! * h,
          );
          canvas.drawOval(rect, paint);
        }

      case AnnotationTool.text:
        if (ann.x != null && ann.y != null && ann.label != null) {
          _drawText(canvas, size, ann, color);
        }

      case AnnotationTool.measurement:
        if (ann.startX != null &&
            ann.startY != null &&
            ann.endX != null &&
            ann.endY != null) {
          final from = Offset(ann.startX! * w, ann.startY! * h);
          final to = Offset(ann.endX! * w, ann.endY! * h);
          _drawMeasurement(canvas, from, to, ann.label ?? '', color, ann.thickness);
        }
    }
  }

  void _drawPreview(Canvas canvas, Size size) {
    final color = _parseColor(inProgressColor);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final start = panStart!;
    final end = panCurrent!;

    switch (inProgressTool!) {
      case AnnotationTool.arrow:
        canvas.drawLine(start, end, paint);
        _drawArrowHead(canvas, start, end, paint);
      case AnnotationTool.circle:
        final rect = Rect.fromPoints(start, end);
        canvas.drawOval(rect, paint);
      case AnnotationTool.measurement:
        _drawMeasurement(
            canvas, start, end, '...', color.withValues(alpha: 0.7), 2.0);
      case AnnotationTool.text:
        break;
    }
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    if ((to - from).distance < 8) return;
    const arrowSize = 14.0;
    final angle = (to - from).direction;
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - arrowSize * math.cos(angle - 0.5),
        to.dy - arrowSize * math.sin(angle - 0.5),
      )
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - arrowSize * math.cos(angle + 0.5),
        to.dy - arrowSize * math.sin(angle + 0.5),
      );
    canvas.drawPath(path, paint);
  }

  void _drawText(
      Canvas canvas, Size size, Annotation ann, Color color) {
    final fontSize = ann.fontSize ?? 16.0;
    final tp = TextPainter(
      text: TextSpan(
        text: ann.label,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(
              color: Colors.black54,
              blurRadius: 2,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(ann.x! * size.width, ann.y! * size.height));
  }

  void _drawMeasurement(
    Canvas canvas,
    Offset from,
    Offset to,
    String label,
    Color color,
    double thickness,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Main ruler line.
    canvas.drawLine(from, to, paint);

    // Tick marks (short perpendicular lines) at endpoints.
    _drawTickMark(canvas, from, to, paint);
    _drawTickMark(canvas, to, from, paint);

    // Label at midpoint.
    if (label.isNotEmpty) {
      final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 13.0,
            fontWeight: FontWeight.bold,
            shadows: const [
              Shadow(
                color: Colors.black87,
                blurRadius: 3,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      // Offset label slightly above the midpoint.
      tp.paint(
        canvas,
        Offset(mid.dx - tp.width / 2, mid.dy - tp.height - 4),
      );
    }
  }

  void _drawTickMark(Canvas canvas, Offset point, Offset other, Paint paint) {
    const tickLength = 8.0;
    final angle = (other - point).direction;
    // Perpendicular angle.
    final perp = angle + math.pi / 2;
    canvas.drawLine(
      Offset(
        point.dx + tickLength * math.cos(perp),
        point.dy + tickLength * math.sin(perp),
      ),
      Offset(
        point.dx - tickLength * math.cos(perp),
        point.dy - tickLength * math.sin(perp),
      ),
      paint,
    );
  }

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
      return Colors.red;
    } catch (_) {
      return Colors.red;
    }
  }

  @override
  bool shouldRepaint(_AnnotationPainter old) {
    return old.annotations != annotations ||
        old.panStart != panStart ||
        old.panCurrent != panCurrent ||
        old.inProgressTool != inProgressTool;
  }
}

// ─── Bottom toolbar ─────────────────────────────────────────────────────────

class _AnnotationToolbar extends StatelessWidget {
  final AnnotationTool activeTool;
  final Color activeColor;
  final List<(Color, String)> colorPresets;
  final bool isDrawMode;
  final void Function(AnnotationTool) onToolSelected;
  final void Function(Color) onColorSelected;
  final VoidCallback onUndo;
  final VoidCallback onClearAll;

  const _AnnotationToolbar({
    required this.activeTool,
    required this.activeColor,
    required this.colorPresets,
    required this.isDrawMode,
    required this.onToolSelected,
    required this.onColorSelected,
    required this.onUndo,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // ── Tool buttons ─────────────────────────────────────────────
            _ToolBtn(
              icon: Icons.arrow_forward,
              label: 'Arrow',
              tool: AnnotationTool.arrow,
              activeTool: activeTool,
              onTap: onToolSelected,
            ),
            const SizedBox(width: 4),
            _ToolBtn(
              icon: Icons.circle_outlined,
              label: 'Circle',
              tool: AnnotationTool.circle,
              activeTool: activeTool,
              onTap: onToolSelected,
            ),
            const SizedBox(width: 4),
            _ToolBtn(
              icon: Icons.text_fields,
              label: 'Text',
              tool: AnnotationTool.text,
              activeTool: activeTool,
              onTap: onToolSelected,
            ),
            const SizedBox(width: 4),
            _ToolBtn(
              icon: Icons.straighten,
              label: 'Measure',
              tool: AnnotationTool.measurement,
              activeTool: activeTool,
              onTap: onToolSelected,
            ),
            const SizedBox(width: 12),

            // ── Color swatches ────────────────────────────────────────────
            ...colorPresets.map(((Color, String) preset) {
              final isSelected =
                  preset.$1.toARGB32() == activeColor.toARGB32();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => onColorSelected(preset.$1),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: preset.$1,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            isSelected ? Colors.white : Colors.white30,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 12),

            // ── Undo ──────────────────────────────────────────────────────
            IconButton(
              icon: const Icon(Icons.undo, color: Colors.white),
              tooltip: 'Undo',
              onPressed: onUndo,
            ),

            // ── Clear all ─────────────────────────────────────────────────
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              tooltip: 'Clear all',
              onPressed: onClearAll,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final AnnotationTool tool;
  final AnnotationTool activeTool;
  final void Function(AnnotationTool) onTap;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.tool,
    required this.activeTool,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = tool == activeTool;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => onTap(tool),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive
                ? Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
