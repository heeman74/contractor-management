import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../data/drawing_export_service.dart';
import '../../domain/drawing_models.dart';
import '../widgets/drawing_painter.dart';
import '../widgets/drawing_toolbar.dart';

/// Full-screen landscape drawing pad — accessible from the Add Note bottom sheet.
///
/// Opens in landscape orientation and restores portrait on exit. Provides pen,
/// eraser, text, line, rectangle, circle, and arrow tools with color/thickness
/// presets, optional grid overlay, and undo/redo.
///
/// On save: exports a PNG (via [DrawingExportService]) and pops with the file
/// path. The grid overlay is NOT included in the exported PNG.
class DrawingPadScreen extends StatefulWidget {
  const DrawingPadScreen({super.key});

  @override
  State<DrawingPadScreen> createState() => _DrawingPadScreenState();
}

class _DrawingPadScreenState extends State<DrawingPadScreen> {
  static const _colors = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.brown,
    Colors.white,
  ];
  static const _thicknessOptions = [1.0, 3.0, 6.0];
  static const _thicknessLabels = ['Thin', 'Med', 'Thick'];
  static const double _defaultThickness = 3.0;
  static const double _defaultFontSize = 16.0;
  static const double _eraserThicknessMultiplier = 4;

  final List<DrawingStroke> _strokes = [];
  final List<List<DrawingStroke>> _undoStack = [];
  final GlobalKey _canvasKey = GlobalKey();
  final DrawingExportService _exportService = DrawingExportService();

  DrawingStroke? _currentStroke;
  Color _selectedColor = Colors.black;
  double _selectedThickness = _defaultThickness;
  bool _showGrid = false;
  double _textFontSize = _defaultFontSize;
  DrawingTool _activeTool = DrawingTool.pen;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // CRITICAL: always restore portrait or the whole app stays in landscape.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  double get _effectiveThickness => _activeTool == DrawingTool.eraser
      ? _selectedThickness * _eraserThicknessMultiplier
      : _selectedThickness;

  Future<void> _saveDrawing() async {
    final boundary =
        _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || _strokes.isEmpty) {
      _showSnackBar('Nothing to save.');
      return;
    }

    try {
      final path = await _exportService.exportToPng(boundary);
      if (mounted) Navigator.of(context).pop(path);
    } on DrawingExportException catch (error) {
      if (mounted) _showSnackBar(error.message);
    } catch (error, stackTrace) {
      debugPrint('[DrawingPadScreen._saveDrawing] Error: $error\n$stackTrace');
      if (mounted) _showSnackBar('Failed to save: $error');
    }
  }

  Future<void> _handleClose() async {
    if (_strokes.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard drawing?'),
        content: const Text('Your drawing will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if ((discard ?? false) && mounted) Navigator.of(context).pop();
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _undoStack.add(List.from(_strokes));
      _strokes.removeLast();
    });
  }

  void _redo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      final previous = _undoStack.removeLast();
      _strokes
        ..clear()
        ..addAll(previous);
    });
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = DrawingStroke(
        tool: _activeTool,
        color: _activeTool == DrawingTool.eraser ? Colors.white : _selectedColor,
        thickness: _effectiveThickness,
        points: [details.localPosition],
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final stroke = _currentStroke;
    if (stroke == null) return;
    setState(() => _currentStroke = stroke.addPoint(details.localPosition));
  }

  void _onPanEnd(DragEndDetails details) {
    final stroke = _currentStroke;
    if (stroke == null) return;
    setState(() {
      _undoStack.clear();
      _strokes.add(stroke);
      _currentStroke = null;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: _handleClose,
        ),
        title: const Text('Drawing Pad'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
              onPressed: _saveDrawing,
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(child: _buildCanvas()),
          DrawingToolbar(
            activeTool: _activeTool,
            selectedColor: _selectedColor,
            selectedThickness: _selectedThickness,
            showGrid: _showGrid,
            textFontSize: _textFontSize,
            colors: _colors,
            thicknessOptions: _thicknessOptions,
            thicknessLabels: _thicknessLabels,
            onToolSelected: (tool) => setState(() => _activeTool = tool),
            onColorSelected: (color) => setState(() => _selectedColor = color),
            onThicknessSelected: (thickness) =>
                setState(() => _selectedThickness = thickness),
            onGridToggled: (value) => setState(() => _showGrid = value),
            onFontSizeChanged: (value) => setState(() => _textFontSize = value),
            onUndo: _undo,
            onRedo: _redo,
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return Stack(
      children: [
        if (_showGrid)
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: DrawingGridPainter()),
            ),
          ),
        Positioned.fill(
          child: RepaintBoundary(
            key: _canvasKey,
            child: Container(
              color: Colors.white,
              child: CustomPaint(
                painter: DrawingPainter(
                  strokes: _strokes,
                  currentStroke: _currentStroke,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
          ),
        ),
      ],
    );
  }
}
