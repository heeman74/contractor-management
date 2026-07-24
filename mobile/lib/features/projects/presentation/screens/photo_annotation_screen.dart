import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/annotation_color.dart';
import '../../domain/annotation_schema.dart';
import '../widgets/annotation_painter.dart';
import '../widgets/annotation_toolbar.dart';

/// Full-screen photo annotation screen.
///
/// Displays a photo as the base layer (immutable). Annotations are drawn on
/// top as a separate [CustomPainter] layer — the original photo is never
/// modified ([annotationData] stored in TaskAttachment, not embedded in image).
///
/// **Modes:**
/// - View mode (default): [InteractiveViewer] allows pinch-to-zoom and pan.
/// - Draw mode: [GestureDetector] captures pan/tap gestures for the active tool.
///
/// **Returns:** `Navigator.pop(context, String?)` — JSON string on save, null
/// on discard.
class PhotoAnnotationScreen extends ConsumerStatefulWidget {
  const PhotoAnnotationScreen({
    required this.localPath,
    super.key,
    this.annotationData,
  });

  /// Absolute file path to the local photo image.
  final String localPath;

  /// Optional existing annotation JSON to pre-load (round-trip editing).
  final String? annotationData;

  @override
  ConsumerState<PhotoAnnotationScreen> createState() =>
      _PhotoAnnotationScreenState();
}

class _PhotoAnnotationScreenState extends ConsumerState<PhotoAnnotationScreen> {
  static const _colorPresets = [
    (Color(0xFFD32F2F), '#D32F2F'), // Red
    (Color(0xFFF57C00), '#F57C00'), // Orange
    (Color(0xFFFFC107), '#FFC107'), // Yellow
    (Color(0xFF1565C0), '#1565C0'), // Blue
    (Color(0xFF000000), '#000000'), // Black
  ];

  static const double _arrowThickness = 3.0;
  static const double _circleThickness = 3.0;
  static const double _textThickness = 1.0;
  static const double _measurementThickness = 2.0;
  static const double _textFontSize = 16.0;

  final List<Annotation> _annotations = [];
  final List<Annotation> _undoStack = [];

  AnnotationTool _activeTool = AnnotationTool.arrow;
  Color _activeColor = AnnotationColor.fallback;
  bool _isDrawMode = false;

  Offset? _panStart;
  Offset? _panCurrent;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _loadExistingAnnotations();
  }

  void _loadExistingAnnotations() {
    final data = widget.annotationData;
    if (data == null) return;
    try {
      _annotations.addAll(AnnotationLayer.fromJsonString(data).annotations);
    } catch (error, stackTrace) {
      debugPrint(
        '[PhotoAnnotationScreen] Failed to parse annotationData: '
        '$error\n$stackTrace',
      );
    }
  }

  double _normalizeX(double x) =>
      _canvasSize.width > 0 ? x / _canvasSize.width : 0;
  double _normalizeY(double y) =>
      _canvasSize.height > 0 ? y / _canvasSize.height : 0;

  String get _activeColorHex => AnnotationColor.toHex(_activeColor);

  void _addAnnotation(Annotation annotation) {
    setState(() {
      _annotations.add(annotation);
      _undoStack.clear();
    });
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _panStart = details.localPosition;
      _panCurrent = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _panCurrent = details.localPosition);
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    final start = _panStart;
    final end = _panCurrent;
    setState(() {
      _panStart = null;
      _panCurrent = null;
    });
    if (start == null || end == null) return;

    switch (_activeTool) {
      case AnnotationTool.arrow:
        _commitArrow(start, end);
      case AnnotationTool.circle:
        _commitCircle(start, end);
      case AnnotationTool.measurement:
        await _commitMeasurement(start, end);
      case AnnotationTool.text:
        break; // Text uses tap, not pan.
    }
  }

  Future<void> _onTapDown(TapDownDetails details) async {
    if (_activeTool == AnnotationTool.text) {
      await _commitText(details.localPosition);
    }
  }

  void _commitArrow(Offset start, Offset end) {
    _addAnnotation(Annotation(
      tool: AnnotationTool.arrow,
      color: _activeColorHex,
      thickness: _arrowThickness,
      startX: _normalizeX(start.dx),
      startY: _normalizeY(start.dy),
      endX: _normalizeX(end.dx),
      endY: _normalizeY(end.dy),
    ));
  }

  void _commitCircle(Offset start, Offset end) {
    final rect = Rect.fromPoints(start, end);
    _addAnnotation(Annotation(
      tool: AnnotationTool.circle,
      color: _activeColorHex,
      thickness: _circleThickness,
      x: _normalizeX(rect.left),
      y: _normalizeY(rect.top),
      width: _normalizeX(rect.width),
      height: _normalizeY(rect.height),
    ));
  }

  Future<void> _commitText(Offset position) async {
    final label = await _promptForLabel(
      title: 'Add Text Label',
      hint: 'Enter label text…',
      confirmLabel: 'Add',
    );
    if (label == null || label.isEmpty) return;

    _addAnnotation(Annotation(
      tool: AnnotationTool.text,
      color: _activeColorHex,
      thickness: _textThickness,
      x: _normalizeX(position.dx),
      y: _normalizeY(position.dy),
      label: label,
      fontSize: _textFontSize,
    ));
  }

  Future<void> _commitMeasurement(Offset start, Offset end) async {
    final label = await _promptForLabel(
      title: 'Add Measurement',
      hint: 'e.g. 24 inches',
      confirmLabel: 'Add Measurement',
    );
    if (label == null || label.isEmpty) return;

    _addAnnotation(Annotation(
      tool: AnnotationTool.measurement,
      color: _activeColorHex,
      thickness: _measurementThickness,
      startX: _normalizeX(start.dx),
      startY: _normalizeY(start.dy),
      endX: _normalizeX(end.dx),
      endY: _normalizeY(end.dy),
      label: label,
    ));
  }

  /// Shows a single-field dialog and returns the entered text (or null).
  Future<String?> _promptForLabel({
    required String title,
    required String hint,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (value) => Navigator.of(ctx).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _undo() {
    if (_annotations.isEmpty) return;
    setState(() => _undoStack.add(_annotations.removeLast()));
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
    if (confirmed != true) return;
    setState(() {
      _undoStack.addAll(_annotations.reversed);
      _annotations.clear();
    });
  }

  bool get _hasChanges =>
      _annotations.isNotEmpty || widget.annotationData != null;

  void _saveAnnotation() {
    final layer = AnnotationLayer(
      canvasWidth: _canvasSize.width,
      canvasHeight: _canvasSize.height,
      annotations: _annotations,
    );
    Navigator.of(context).pop(layer.toJsonString());
  }

  void _selectTool(AnnotationTool tool) {
    setState(() {
      _activeTool = tool;
      _isDrawMode = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCanvas(),
            _buildTopBar(),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnnotationToolbar(
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

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleCanvasSizeUpdate(constraints.biggest);
        final photoAndPainter = Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(widget.localPath),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image,
                    color: Colors.white54, size: 64),
              ),
            ),
            CustomPaint(
              painter: AnnotationPainter(
                annotations: _annotations,
                inProgressTool: _isDrawMode ? _activeTool : null,
                panStart: _panStart,
                panCurrent: _panCurrent,
                inProgressColor: _activeColorHex,
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
        return InteractiveViewer(child: photoAndPainter);
      },
    );
  }

  void _scheduleCanvasSizeUpdate(Size size) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canvasSize != size) {
        setState(() => _canvasSize = size);
      }
    });
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }
}
